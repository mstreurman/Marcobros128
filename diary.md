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
