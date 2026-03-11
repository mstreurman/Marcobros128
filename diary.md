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

