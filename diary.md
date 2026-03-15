# MARCO BROS 128 — Development Diary

> **Showing last 3 sessions. Full history in .**

---

## 2026-03-14 — v0.6.7: The Invisible Wall at y=177 (Fix 49)

### Symptom

Level loads, player and enemy visible on the floor, music playing — then after
a moment: display corruption, crash to 48K BASIC, last AY note stuck forever.
This is the classic Spectrum attribute-area crash. Something wrote pixel data
into `$5800+` (the colour attribute / sysvar region), corrupted the machine
state, and the interrupt handler died mid-execution leaving `DI` set permanently
(hence the stuck note — AY chip keeps playing, Z80 never wakes up again).

### Root cause

The ZX Spectrum pixel address formula wraps at row 192. Pixel row 192 maps to
address `$5800` — the first byte of the attribute area. `DrawSprite` writes 2–3
bytes per pixel row, 16 rows total. If `screen_y >= 177`, then the final pixel
row lands at `screen_y + 15 >= 192`, straight into attributes and sysvars.

`DrawPlayer` passed `C = ld a,(plr_y)` directly to `DrawSprite` with the
comment "plr_y always fits in 8 bits: 0..175". That's true when everything
is working — but between a gravity step increasing `plr_y` and the
`CheckGround` snap correcting it on the NEXT frame, `plr_y` can pass through
177–191 for a single frame. One frame is all it takes.

`DrawEnemies` and `DrawPowerup` had the same unguarded pass-through.

### The fix

Three `cp 177 / jp nc` (or `ret nc` for DrawPowerup) guards added, one before
each `call DrawSprite`. If `screen_y >= 177`, the sprite is simply not drawn
that frame. The game continues; the entity is invisible for one frame at most.
The guard is 3 bytes (`cp 177`) + 3 bytes (`jp nc`) = 6 bytes per site.
All existing `jr` branches in the affected routines were verified to be
unaffected (the insertions are after the label targets, not before them).

### Why the stuck note?

When `DrawSprite` wrote pixel bytes into `$5C00+` (the sysvar area), it
corrupted `BANKM` at `$5B5C`, `ERR_SP` at `$5C3A`, and other Z80 state mirrors.
The ROM's error handler was triggered, which called `$0008` (PRINT-A-2) in
ROM1, which eventually executed a `DI` and entered the 48K BASIC editor.
`DI` never paired with `EI`, so the AY chip kept playing the last note the
music engine had written to the hardware registers before the crash.

---

## 2026-03-14 — v0.6.8: Two Pushes We Should Have Found Sooner (Fix 50)

### The crash that kept crashing

Fix 49 went in (screen_y clamp). Still crashed to 48K BASIC with stuck note.
Same profiler signature: ROM1 `$11DC` and `$0E5C` running for hundreds of
thousands of T-states. We went through everything — DrawTile, DrawSprite, 
DrawHUD, the AY engine, gravity overflow, BANKM corruption paths. Nothing.

Then I re-read architecture.md's B11 entry for `UpdateCamera`:

> *"Has unbalanced pop de/pop hl before ret. DO NOT call directly from new
> code outside of UpdatePlayer — stack behaviour is undefined."*

This was documented as a **usage warning**, not a bug. But it IS a bug.

### The stack trace

When `call UpdateCamera` fires inside UpdatePlayer, the stack looks like:

```
[SP+0,1]  UpdateCamera return address  ← pop de consumes this (WRONG)
[SP+2,3]  UpdatePlayer's saved AF      ← pop hl consumes this (WRONG)
[SP+4,5]  UpdatePlayer's saved BC      ← ret jumps HERE (CRASH)
[SP+6,7]  UpdatePlayer's saved HL
```

Every single frame the player was alive, `ret` from UpdateCamera jumped
to whatever **BC** held when UpdatePlayer's caller invoked it. Random
address. Non-deterministic destination. Every frame.

### The fix

```asm
UpdateCamera:
    push hl    ; ← new: matches pop hl at exit
    push de    ; ← new: matches pop de at exit
```

Push order matters. `push hl / push de` puts HL at SP+2 and DE at SP+0.
Then `pop de / pop hl / ret` correctly restores DE first (from SP+0), then
HL (from SP+2), then pops the real return address into PC. Symmetric.

An earlier draft had the pushes in the wrong order (`push de / push hl`),
which would have cross-restored the registers. Harmless in this case since
UpdateCamera clobbers both and UpdatePlayer overwrites HL immediately after
the call — but wrong is wrong.

### Lesson

Architecture.md's B11 warning existed but framed the imbalance as a caller
restriction. It should have been a bug report. The B11 contract for
UpdateCamera has been updated to reflect the correct balanced state and
document the push order explicitly.

---

## 2026-03-14 — v0.7.7: Two Bugs We Introduced (Fixes 66-67)

### Fix 66 — The sentinel that ate the sysvars

Fix 62 was meant to stop EraseSprite from flashing the top-left corner
of the screen by initialising `prev_sy` to 255 instead of 0.

The problem: `EraseSprite` with `screen_y=255` calculates:
```
H = $40 | (255 & $C0)>>3 | (255 & 7) = $40 | $18 | $07 = $5F
```
`$5F00` is in the attribute area. All 16 erase rows write to
`$5Fxx`, `$58xx`, `$59xx`... including `$5B20`, `$5B40` which
contain BANKM at `$5B5C`. The very first draw frame corrupts paging,
the CPU drops to IM1 mode, and the game freezes with the floor flashing.

Fix: add `cp 255 / jr z` sentinel check before EraseSprite in both
DrawPlayer and DrawEnemies. If prev_sy is 255, skip the erase.
The first actual draw stores the real screen position as prev, so
erasing works correctly from frame 2 onwards.

### Fix 67 — Reading Y and U instead of O and P

The Spectrum keyboard matrix for port `$DFFE` (A[15:8]=`$DF`):

```
bit4=Y   bit3=U   bit2=I   bit1=O   bit0=P
```

Our code had `bit 4,a` for P and `bit 3,a` for O. We were reading
Y and U — two keys nobody would ever press while playing a platformer.
O and P never triggered. No left/right movement ever worked.

The profiler showed `set 0,d` (P detected) and `set 1,d` (O detected)
with zero hits across the entire session — completely invisible until
we checked the matrix layout.

Fixed: `bit 0,a` for P, `bit 1,a` for O. Space (`$7F` row `bit0`)
was already correct and unchanged.

## 2026-03-15 — v0.7.8: The address formula, the backwards stomp, and the stolen jump

### Fix 68 — Six rotations that broke everything

This one was subtle and took the full profiler trace to confirm. DrawSprite
and EraseSprite both compute a Spectrum screen address from (screen_x, screen_y).
The formula splits screen_y into three fields:

- bits[7:6] → which screen third (top/middle/bottom)
- bits[5:3] → which character row within the third (goes into L)
- bits[2:0] → which pixel row within the character (goes into H)

The bug: bits[2:0] were being processed with three `rrca` instructions before
OR-ing into H. On the Z80, `rrca` rotates right through the carry. Three rrcas
on a value like $02 produce $40 — the bits end up in bit6 of H instead of
bits[1:0]. For screen_y=130 (low 3 bits = $02) this shifted H from the correct
$50 to $50|$40 = $50... actually the corruption was subtler — the OR'd value
displaced the correct third/char bits entirely.

The practical effect: for any screen_y not on an 8-pixel boundary, the sprite
rows were written to wrong addresses. For some Y values this meant writing into
$7Exx (the IM2 vector table), $5Bxx (sysvars including BANKM), or $C0xx–$FFxx
(bank7 game code). The first enemy contact produced a screen_y value with
non-zero low bits, wrote to the IM2 table, broke the interrupt chain, and the
CPU fell into IM1 mode. The last AY note played forever.

The profiler confirmed it: $0038 (IM1 vector) got 1,606 hits, ROM keyboard
scanner $0296–$02AE got 68,182 hits. Classic crash signature.

Fix: remove the 3 rrca from both DrawSprite and EraseSprite. The low 3 bits
of screen_y go directly into H via OR. Six bytes removed, both routines fixed.

This also explains why tiles rendered correctly — DrawTile uses a different
register (D not H) and the address formula there was written without the
erroneous rotations.

### Fix 69 — Backwards stomp

The comment even said "Stomp if player moving down" but the code did the
opposite. `bit 7,a` on plr_vy sets Z=0 when the bit IS set (vy negative =
moving up). `jr nz,.cep_stomp` therefore jumped to stomp when going UP.
When the player jumped onto an enemy, the upward vy triggered the stomp
correctly — but that also means landing on enemies from above (vy positive,
bit7 clear, Z=1) was taking the hurt-player path instead.

One character: `nz` → `z`.

### Fix 70 — The title screen stole the first jump

When you press Space on the title screen, the HANDLER sets joy_prev bit4.
On the next interrupt, joy_new = joy_held AND NOT joy_prev = 0 (Space is still
held but it's no longer a new press). ShowLevelEntry runs for 100 frames — by
then joy_prev has been set for 100 frames. When gameplay starts, the first
Space press fires joy_new correctly... except by then the player has probably
already released it and re-pressed, producing exactly one jump. But if they
held Space through the level-entry screen, joy_new bit4 never fired at all.

Fix: zero joy_held, joy_new, joy_prev in InitLevel. Three extra stores, no
other changes.

### Session notes

This was a three-bug session diagnosed entirely from one profiler upload and
source reading. The IM1 hits in the profiler pointed straight at the crash.
The half-sprite report pointed at the address formula. The no-jump report
pointed at the edge-detect state machine. All three diagnosed before any code
was written, all three fixed cleanly, build passed first time.

## 2026-03-15 — v0.7.9: The last inverted carry and the jump trail

### Fix 71 — EraseSprite: the one that got away

Fix 27 corrected the inverted carry condition in DrawTile. Fix 28 caught the
same bug in DrawCharXY. Fix 68 (this session, previous build) caught it in
the address formula. But the row-advance logic in EraseSprite was never
touched — it still had `jr nc` where it should be `jr c`.

The consequence: the `sub $08` H-correction that keeps the screen address
within the correct screen third was firing almost never (1.8% of boundary
crossings vs the correct ~50%). For every sprite at a Y position where the
bottom 8 rows cross a character-row boundary, EraseSprite was zeroing pixels
at whatever garbage address H happened to hold — which could be anywhere in
the top two thirds of the screen. This caused the bottom half of sprites to
flicker in and out, and left random zeroed pixels scattered around the screen
during motion.

One character: `nc` → `c` at source line 1955.

### Fix 72 — EraseSprite must happen before the screen_y guard

When the player jumps, plr_y briefly exceeds 175 (bottom guard) or goes
negative (top of screen during a high jump). The screen_y guard fires and
the entire erase+draw block is skipped. On the next frame the player is back
in the drawable zone — DrawSprite draws at the new position, but the pixels
from the last drawn frame (before the guard fired) were never erased.
Result: a trail of ghost sprites marking every frame where the player was
near the screen edge.

Fix: separate the erase from the draw. Erase always runs at prev_sy (with
the 255 sentinel from Fix 66), then the guard decides whether to call
DrawSprite. If the guard fires, we still erase the old position cleanly.
Applied to both DrawPlayer and DrawEnemies.

### HUD flicker (not fixed — cosmetic, inherent to architecture)

RenderLevel draws tile pixels into character rows 0–10 every frame. Tile
row 1 (pixel_y=16–31) overlaps with the COINS line of the HUD. DrawHUD
runs after RenderLevel and redraws the text on top. The flicker is the CRT
beam catching the tile pixels in the gap between the two calls. This is
standard Spectrum display behaviour and cannot be eliminated without either
restricting RenderLevel to rows 2–10 (losing the ceiling row) or moving
HUD drawing into the HANDLER (which cannot call bank7 code). Left for now.

### Session notes

Second profiler of the session. No crash, scrolling working, movement good.
Three specific visual artefacts reported: bottom half disappearing, jump
trail, HUD flicker. Profiler confirmed Fix 71 (EraseSprite row advance) and
Fix 72 (erase before guard). HUD flicker documented as architectural.
