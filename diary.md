# MARCO BROS 128 — Development Diary

---

## Session: The Great Stack Hunt
*Fix 23 — ClearScreen DI/EI + trampoline pinning*

### What happened

We had the title screen working with music and the player's fire press detected.
Pressing Space should trigger the level card (ShowLevelEntry), then InitLevel,
then gameplay. Instead: black screen, blue border, music looping, colors flashing
briefly, back to title. Repeat forever.

### The investigation

The FUSE PC-sampling profiler was the key tool. It records a count for every
address the Z80 program counter visited, weighted by T-states. The critical
finding was that `$CAAF` (the instruction immediately after ShowLevelEntry's
`call ClearScreen`) had a count of zero — it was *never executed* — while
`$CAAC` (ShowLevelEntry entry) had been hit 17 times.

ClearScreen's `RET` at `$BFE3` was reached 28 times, but the game was going
back to `$8362` (inside `GAME_START`) rather than `$CAAF`.

We spent a long time eliminating suspects: the interrupt handler's push/pop
balance (correct — 5 in, 5 out), Music_Tick (no indirect jumps, balanced),
DrawCharXY (balanced), the IM2 table setup (pre-written by make_szx.py),
the SZX register state. Everything checked out on paper.

The profiler gave the eventual answer when decoded with the T-state weighting
model: `ClearScreen` was called with interrupts *enabled* from TitleScreen and
ShowLevelEntry, but the identical call from `GAME_START` always worked. The
difference: `GAME_START` has its own `DI` active. The 6912-iteration `LDIR`
inside ClearScreen was long enough for an interrupt to fire, and something in
the interrupt path was leaving SP two bytes off by the time the RETI completed.

The fix: wrap ClearScreen with `DI` / `EI`.

### The regression

The fix worked — but immediately caused a new crash. Black screen, blue border,
crash to 128K menu. This turned out to be the **trampoline boundary bug**.

Adding `DI` and `EI` (2 bytes) to ClearScreen pushed all subsequent code in
bank2 forward by 2 bytes. The `DrawCharXY` trampoline (a `JP DrawCharXY_Real`
in bank2 that reaches bank7) had no fixed `ORG` — it floated at wherever the
assembler put it. It was at `$BFFC` before; now it was at `$BFFE`.

`$BFFE/$BFFF` are still in bank2. `$C000` is the first byte of bank7.
A `JP nn` is 3 bytes. The assembler wrote `C3 00` to `$BFFE/$BFFF` and `C0`
to `$C000` — which overwrote the *first byte of DrawCharXY_Real* in bank7
with `$C0 = RET NZ`. The game then called DrawString, which tried to call
DrawCharXY, which immediately returned before drawing anything, and the whole
display system was broken.

The profiler confirmed this: `$BFFC` showed count 0, `$BFFE` showed count 10
(execution of `$C3 = JP` opcode), and `$C000` showed 0 (first byte of
DrawCharXY_Real was now `RET NZ`, not `push hl`).

The fix: add `ORG $BFFD` before `DrawCharXY:` — pinning it permanently to the
last safe 3-byte slot in bank2. If bank2 code ever grows past `$BFFD`, the
assembler will report an overlap error rather than silently breaking bank7.

### What Claude noticed

The peer review questions passed on were exactly right:

> *"Is he using the Python script to inject the AY-3-8910 music data directly
> into specific banks, or is he still trying to manage those ORG statements manually?"*

Still managing ORGs manually. The trampoline boundary bug is exactly what
happens when you float a label without pinning it. The lesson: **any code
whose address is referenced by another bank must be ORG-pinned.** The Python
make_szx.py script handles the IM2 jump stub at `$BCBC` correctly because
it patches it at known offset. DrawCharXY needed the same treatment in the ASM.

> *"His spatial awareness of the Z80 address space is punching above his weight class."*

Genuinely. The DoLevelBanking shim (Fix 19) — moving the bank-switch sequence
into fixed bank2 so that bank7 return addresses stay valid — was the right
instinct. The trampoline boundary bug is the same class of problem: code in a
fixed bank referencing code in a paged bank via a known address.

> *"The timing is probably off by a few microseconds."*

Not timing in the AY sense — but close. The ClearScreen DI issue was timing in
the interrupt sense: the LDIR takes ~160,000 T-states, and a frame interrupt
fires every 69,888 T-states. At 50Hz on a 3.5MHz Z80, the interrupt *will*
fire during a full-screen clear unless you protect it.

### Name cleanup

All Nintendo IP names removed from source code:
- `ENT_GOOMBA` → `ENT_WALKER`
- `ENT_KOOPA` → `ENT_SHELLER`
- `SPR_GOOMBA*` → `SPR_WALKER*`
- `SPR_KOOPA1` → `SPR_SHELLER1`
- `SPR_MUSHROOM` → `SPR_PWRUP`
- All related labels and comments updated

The game header now reads: *"Inspired by classic 8-bit platformers of the 1980s."*

### Files added this session

- `README.md` — rewritten with correct scope and no IP names
- `architecture.md` — machine-readable blueprint for future Claude sessions
- `diary.md` — this file

### Current state

The new `marco128.asm` has both fixes applied. Needs a full rebuild and test run.
Expected: title screen appears, music plays, Space → level card → gameplay.

### Pending after this fix

1. Verify `AY_Silence` loop uses `ld b,14` not `ld b,0` (the 256-iteration
   version zeros `bankswitch_ok` and the level map cache)
2. Fix enemy spawn data address mismatch (W1_SPAWNS is in bank7 but
   LoadEnemySpawns reads from the level bank at `$C420`)
3. Full gameplay test: movement, stomp, powerup, level completion

---
*Diary maintained by Claude. Add entries here for significant events.*

---

## Session: The Ghost in the Machine
*Fix 24 — Turbo loader removed*
*Version 0.2.0*

### The symptom

Game loads, title screen appears with music, pressing Space → black screen, blue
border, crash to 128K menu. This was the same symptom as the session before, but
the root cause had changed. Fix 23 (ClearScreen DI/EI) and Fix 23b (DrawCharXY
trampoline pinned to $BFFD) had both applied correctly — the profiler confirmed
BFFD=430 hits and C000=497, so bank7 was accessible and the trampoline worked.

### What the profiler showed

The new profiler data had one massively abnormal feature: address $BDC4 with
**11,344,454** counts. Everything else in the game ran at counts in the low
hundreds or thousands. Something at BDC4 was executing tens of millions of times.

Cross-referencing with the listing immediately showed what was there:

```
$BDC4: 10 F9 = djnz .tre_loop   ← TL_ReadEdge timing loop
```

`TL_ReadEdge` is a subroutine from the **turbo loader** — it spins in a tight
`djnz` loop counting tape edge timing pulses. It was sitting in bank2 at $BDC4.

### The actual bug

Fix 21 (remove turbo loader) was marked COMPLETED in the architecture notes from
a previous session, but the code was never actually deleted from the source. The
turbo loader block (`ORG TURBO_ADDR` = `ORG $BD00`) was still in `marco128.asm`
at line 3119.

`TURBO_ADDR = $BD00` is inside bank2 ($8000–$BFFF). The turbo loader extends
from $BD00 to $BDC6. The audio routines assembled in the same bank2 PAGE block
place `SFX_Play` at $BD62 and `SFX_Tick` at $BD7F — both squarely inside the
turbo loader range.

Since the turbo loader `ORG` block assembles **after** the audio code block in
source order, the turbo loader silently overwrites `SFX_Play` and `SFX_Tick`
completely. Neither routine exists in the final binary. Their addresses contain
tape-loading code instead.

In this particular run the game didn't happen to trigger SFX (the handler checks
`sfx_active` before calling `SFX_Tick`, and `sfx_active` starts at zero), so the
bad code was dormant. But the game was still crashing after one frame — a
separate bug we haven't fully traced yet (profiler from the next run will tell us).

### The fix

Deleted the entire turbo loader block from `marco128.asm` (149 lines, $BD00–$BDC6).
Removed the `TURBO_ADDR EQU $BD00` constant. `SFX_Play` and `SFX_Tick` are now
the sole occupants of that address range in bank2.

### What the peer review was right about

The earlier question — *"is he still trying to manage those ORG statements manually?"*
— turns out to be directly prophetic. Manual ORG management in a multi-section bank2
means the LAST `ORG` block to touch an address range wins, silently. The assembler
doesn't warn about overlapping code in the same bank. The turbo loader had been
sitting in the source as dead weight for multiple sessions, quietly destroying SFX
every time a binary was produced.

### Version bump

With Fix 24 applied this is version **0.2.0**. Version string embedded in binary
at $8006: `"MB128 v0.2.0"`.

### Pending after this fix

1. Rebuild and retest — does the game survive its first frame now?
2. Identify the one-frame crash (ROM 0004 hits in profiler suggest crash→reboot)
3. Enemy spawn data verification
4. Full gameplay test


---

## Session: Six Bullets, One Reload
*Fixes 25a–25f — Peer-reviewed root-cause analysis applied*
*Version 0.3.0*

### The symptom

Build 0.2.0: title screen works, music plays, Enter accepted as fire, then black
screen with magenta border. No level card. No music. Hangs forever.

Magenta border = ShowLevelEntry is running (debug colour #3). ClearScreen was called
(screen is black). But the level card strings never appeared and ShowLevelEntry never
returned. Profiler confirmed: `$CAF2` (.sle_wait HALT) had **17,307,784 counts** while
`$CAF5` (the ret after the loop) had **zero**.

### The hunt — six bugs in one session

A peer review identified the root causes. All six confirmed against the binary.

**Fix 25a — EI before RETI (the actual cause of the hang)**

The interrupt handler ended with:
```
    pop af
    ei       ; ← WRONG
    reti
```
`RETI` on Z80 automatically restores `IFF1` from `IFF2`. The explicit `EI` before
`RETI` creates a tiny window where the CPU has re-enabled interrupts but hasn't yet
popped the return address. If the next interrupt fires in that window, a second copy
of the handler starts with the stack already 12 bytes lower than normal.

During the `.sle_wait` HALT loop, music was playing at 50Hz. The handler was firing
every 20ms. With EI before RETI, nested handler calls accumulated, driving the stack
pointer down by ~16 bytes per nesting level — eventually into `BankSwitch` code at
`$BFA5` and `ClearScreen` code at `$BFC5`. Once those bytes were overwritten with
return addresses and register dumps, the game was operating on corrupted code.

Fix: deleted the `ei` instruction. One line removed, one infinite loop cured.

**Fix 25b — Stack base too close to code**

`SP = $BFF8`. The handler pushes `af,bc,de,hl,ix` (10 bytes) and `Music_Tick`
pushes `hl,bc,de` (6 bytes) = 16 bytes below the interrupted SP. During
ShowLevelEntry with `SP = $BFF4`, the handler drives `SP` down to `$BFE4` —
inside `ClearScreen` (`$BFC5–$BFE5`). PUSH writes register values over the `EI`
and `RET` bytes at the end of `ClearScreen`. Next call to `ClearScreen` executes
garbage. Moved `SP` to `$BF00`, growing down into the now-empty turbo-loader
space. ClearScreen and BankSwitch are both safely above at `$BFA5+`.

**Fix 25c — GAME_START boot order**

`GAME_START` called `ClearScreen` (which does `EI`) before `Setup_IM2`. The Z80
starts in `IM0`. Any interrupt between `ClearScreen`'s `EI` and `Setup_IM2`'s `IM2`
activation would vector to a random address via the IM0 data-bus byte. Swapped the
order: `Setup_IM2` first, then `ClearScreen`. `Setup_IM2` itself ends with `EI`, so
`ClearScreen`'s subsequent `EI` is now redundant but harmless.

**Fix 25d — InitLevel / bank7 suicide**

`InitLevel` lives in bank7 (`$CBBC`). It computed the level bank number and then
called `BankSwitch`. The moment `BankSwitch` executed `OUT ($7FFD)`, bank7 was gone.
The CPU fetched the next instruction (`call LoadLevelMap`) from whatever was now at
`$CC28` — which was level map data starting with tile bytes `$00` (NOP) and `$01`
(partial opcode for `LD BC,nn`). Instant crash.

The fix was noted in Fix 19 long ago but a subsequent refactor removed the shim.
Recreated `DoLevelBanking` in bank2: it reads `cur_level_bank`, calls `BankSwitch`,
calls `LoadLevelMap` and `LoadEnemySpawns` (all bank2), then restores bank7. 
`InitLevel` now calls `DoLevelBanking` — one line replaces five dangerous ones.

**Fix 25e — W1L2_MAP missing DS padding**

`W1L2_MAP` had 14 `DEFB` lines = 448 bytes. `MAP_W × MAP_H = 704`. The 256-byte
shortfall cascaded through the entire bank0 layout: `W1L3_MAP` started at `$C480`
instead of `$C580`, and `W1_SPAWNS` landed at `$C740` instead of `$C840`.
`LoadEnemySpawns` hardcodes `ld hl, $C000 + 3 × MAP_W × MAP_H = $C840`. It read
spawn data 256 bytes past where the data actually was. Added one `DS` line.

**Fix 25f — Spawn slot padding**

Each spawn slot is 32 bytes wide (`LoadEnemySpawns` advances `HL` by 32 per level).
Every slot across W1/W2/W3 had wrong `DS` padding — most were 42 bytes total instead
of 32. Level 2 and 3 spawn reads started in the middle of the previous level's
padding zeros, so `LoadEnemySpawns` saw `$00` (zero = end of list) immediately and
spawned nothing. Fixed all 9 slots across three worlds.

### What to expect next

With these six fixes the game should reach the level card (ShowLevelEntry displays),
wait 2 seconds, enter InitLevel (bank switching now safe), load map and enemies, and
start the game frame loop. First full gameplay test follows.

---

## 2026-03-12 — v0.4.0: Four Fixes, One Blocking Bug Destroyed

### Fix 26a — EI before RETI (game-blocking)

Profiler showed `$CA72` (the `HALT` inside `TitleScreen`) with 50 million hits and
the instruction immediately after it with zero hits. The game was hard-stuck in an
infinite HALT loop.

Root cause: `HANDLER` begins with `DI`, which zeros **both** IFF1 and IFF2. `RETI`
only copies IFF2 back to IFF1 — it does not re-enable interrupts. After the handful
of startup interrupts completed, IFF1 stayed 0 forever. Every subsequent `HALT`
with interrupts off spins internally as a NOP, so `joy_new` never updated and the
title screen never exited. Fix: add `EI` immediately before `RETI`. The Z80
guarantees no interrupt is taken between `EI` and the next instruction, so `RETI`
counts as the safe gap — no nested-interrupt risk.

### Fix 26b — Space key row

`LD A,$BF` reads port `$BFFE` (Enter row, bit 0 = Enter). Space is on port `$7FFE`
(high byte `$7F`). Changed to `LD A,$7F`. Previously irrelevant since interrupts
were dead, but now necessary.

### Fix 26c — 16-bit enemy X

`LoadEnemySpawns` multiplied tile_x by 16 using four 8-bit `ADD A,A`. Tile 16+ 
overflows: tile 24 × 16 = 384 ($180) truncated to $80 (128). `ent_xh` was declared
but never written. Fixed spawn code to use `HL` for a proper 16-bit result and
store both `ent_xl` (low) and `ent_xh` (high). Updated `UpdateEnemies` to use `IX`
for 16-bit position, proper sign-extension of vx, and 16-bit bounce limits (8..992).
Updated `DrawEnemies` to compute `screen_x = ent_x − cam_x` with 16-bit `SBC`.
Updated `CheckEnemyPlayer` with a fast high-byte filter before the 8-bit comparison.

### Fix 26d — Stack pointer

SP at `$BF00` allowed the stack to grow down to ~`$BEE8` under interrupt + Music_Tick
load, which overlaps `MUSIC_OVERWORLD` at `$BE55`. Moved SP to `$BBFE` — the top
of a 14,307-byte free gap between `LoadEnemySpawns` (`$841C`) and `HANDLER`
(`$BC00`). At maximum depth the stack reaches ~`$BB7E`, safely above code end.

---

## 2026-03-12 — v0.4.2: Screen Row Advance Logic Inverted in DrawTile and DrawSprite

### Fix 27 — jr nc → jr c

After Fix 26 got the game running, it crashed to the 128K menu the instant a level
loaded. Profiler showed ROM execution (3M hits at $00E5, 1.8M at $3683) vastly
outweighing game loop activity (521K), and attribute memory writes at $58xx-$5Fxx.

Root cause: the screen address row-advance in both `DrawTile` and `DrawSprite` used
`jr nc` to decide whether to correct H/D after a char boundary crossing. The logic
was completely inverted:

- **No carry** from `E + $20`: char row advance stays within the same screen third →
  D/H overshot by 8 (e.g. $57→$58) → `sub $08` correction IS needed → but the
  code skipped it.
- **Carry** from `E + $20`: E wrapped past char-row 7 into the next third → D/H
  naturally advanced to the correct next-third value → no correction needed → but
  the code applied `sub $08` unnecessarily.

For any tile in screen third 2 (screen_y 128-191 = tile rows 8-10), the second
character row of every sprite/tile was written to $5820-$5FFF (attribute area and
into system variables). The very first `RenderLevel` call triggered this, corrupting
system variables and causing the 128K ROM to retake control.

Fix: change `jr nc` to `jr c` in both routines. Verified algebraically for all
Y values 0-191 against the correct Spectrum address formula.
---

## 2026-03-12 — v0.4.3: DrawCharXY fix, sprite masking, original music

### Fix 28 — DrawCharXY jr nc → jr c
Same inverted carry bug as Fix 27 existed in `DrawCharXY_Real`. Chars drawn at
pixel row ≥ 128 would write their second character row into the attribute area.
HUD is at rows 0-2 so it was safe, but any future text lower on screen would crash.

### Fix 29 — AND-mask sprite drawing
DrawSprite previously OR'd pixels onto the screen with no masking, causing sprite
pixels to merge with background tile patterns (the visible "yellow hole" in ground
tiles). Fixed by computing mask on the fly from pixel data: for each byte,
`(screen AND ~pixel) OR pixel`. No extra sprite data needed. Sprite 0-pixels are
now transparent (background shows through); sprite 1-pixels always display correctly.
The `~pixel` mask approach is the standard technique used by classic Spectrum games.

### Fix 30 — Original music compositions
All three tracks (MUSIC_OVERWORLD, MUSIC_BOSS, MUSIC_TITLE) were the SMB1 Nintendo
overworld, underground, and title themes — copyrighted material that cannot be
distributed on GitHub. Replaced with three original compositions:
- MUSIC_OVERWORLD: upbeat D-major loop (D5-F5-A5-D6 ascending phrases)
- MUSIC_BOSS: tense A-minor phrase with tritone (Eb5) tension
- MUSIC_TITLE: rising C-major fanfare (C5-D5-E5-G5-A5 ascending motif)
Also added NOTE_Bb4 (238), NOTE_Eb5 (178), NOTE_B5 (112) constants.

### Profiler note
The profiler file provided was identical to the previous session (same numbers).
A new profiler run from the v0.4.3 binary is needed to diagnose the remaining crash.

---

## 2026-03-12 — v0.4.4: The floor crash — GetTileAt tile_x clobber (Fix 31)

Root cause of all remaining crashes identified and fixed.

`GetTileAt` used `ld de, level_map_cache` to load the cache base address,
which overwrote **E** — the register holding `tile_x`. The subsequent
`ld c, e` then loaded `$A3` (low byte of `level_map_cache` = `$80A3`)
instead of `tile_x`, making every collision lookup read **161 bytes past**
the intended tile row. For ground at tile_y=9 this read past the end of the
704-byte cache into random RAM — always returning AIR (0). No ground was ever
detected, so the player fell through the floor every frame, and after ~7
frames `screen_y` reached ≥177 where `DrawSprite` wrote into the attribute/
sysvar area, corrupting the HUD and crashing.

`RenderLevel` has its own direct cache indexing (does not call `GetTileAt`)
which is why tiles drew correctly — only the *collision* was broken.

Fix: replace `ld de, level_map_cache / add hl, de` with
`ld bc, level_map_cache / add hl, bc`. Using BC instead of DE leaves E
untouched, so `ld c, e` immediately after correctly picks up `tile_x`.
