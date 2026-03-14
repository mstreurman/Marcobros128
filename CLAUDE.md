# Marco Bros 128 — Instructions for Claude

This file tells Claude exactly how to work on this project.
Read this before reading anything else.

---

## 1. STARTUP SEQUENCE — do this every time, no exceptions

**Order matters. Understand first. Build second. Code third.**

### Step 1 — Clone the repo. Do not touch anything yet.

```bash
git clone https://TOKEN@github.com/mstreurman/Marcobros128.git repo
cd repo
```

### Step 2 — Read these files in this exact order before doing anything else.

```
1. CLAUDE.md          ← you are here. Finish reading it.
2. marco128.md        ← current project state: version, open issues,
                         addresses, sysvar layout, bug history (all 67 fixes),
                         subroutine contracts
3. lessons.md         ← pre-flight checklist, Z80 gotchas, coding rules,
                         listing/profiler reading guide
4. changelog.chg      ← tail: what was last fixed and why
5. diary.md           ← tail: context and mood of last session
6. architecture.md    ← hardware reference: consult as needed,
                         do NOT front-load the whole thing
```

Do not skip this reading step. The most expensive bugs in this project
came from acting before understanding the current state.

### Step 3 — Build to get a fresh listing.

```bash
cp src/marco128.asm .
mkdir -p build tools
sjasmplus --nologo --lst=build/marco128.lst marco128.asm
python3 make_szx.py
snapdump build/marco128.szx | head -5
```

If sjasmplus is not installed, build it first — see SESSION_START.md.

Expected output:
```
Pass 3 complete
Errors: 0, warnings: 0
GAME_START: $XXXX
machine: Spectrum 128K
PC: 0xXXXX  SP: 0xBBFE
```

**Verify that key addresses in the listing match marco128.md.**
**If they don't match, marco128.md is out of date — update it before proceeding.**

**Do not write a single line of code until you have a clean build.**
**Do not guess at addresses — read them from the listing.**

### Step 4 — Ask the user what they need.

Only now are you ready to work.

---

## 2. REFERENCE FILES — quick lookup guide

| File | Use it for |
|------|-----------|
| `marco128.md` | Addresses, sysvar layout, bug history, subroutine contracts |
| `lessons.md` | Pre-flight checklist, Z80 rules, known crash patterns |
| `architecture.md` | Port addresses, timing, keyboard matrix, ZXST format |
| `changelog.chg` | What changed and when |
| `diary.md` | Why it changed and what the context was |

---

## 3. BEFORE WRITING ANY CODE

Run the mandatory pre-flight from `lessons.md` Section C3.6:

- **Check 1 (Registers):** List every register the routine reads or writes.
  Verify against the B11 contract table in `marco128.md`.
  Explicitly trace every push and pop — count them, match them.
  For every `djnz` loop: trace B register through every push/pop inside the loop.

- **Check 2 (Paging):** State which bank the routine lives in.
  Bank7 may call bank2. Bank2 must never call bank7.
  Bank7 must never write port $7FFD directly — route through BankSwitch.
  HANDLER ($BC00) must never call bank7 code.

- **Check 3 (Jump range):** Estimate byte distance for every `jr` and `djnz`.
  If estimated distance >= 100 bytes, change to `jp` immediately.
  Check ALL branches in the routine, not just the one you edited.

**Do not skip the pre-flight. The most expensive bugs in this project
came from skipping it.**

---

## 4. AFTER WRITING CODE

```bash
# Always assemble immediately after every change
sjasmplus --nologo --lst=build/marco128.lst marco128.asm

# Must be: Errors: 0, warnings: 0
# Any warning is a bug. Fix it before proceeding.

# Then verify the snapshot
python3 make_szx.py
snapdump build/marco128.szx | grep -E "machine|PC|SP"

# For register/stack verification use the Z80 emulator:
python3 -c "
import z80, re
machine = z80.Z80Machine()
# ... load banks, set up state, trace execution
"
```

---

## 5. STRICT ARCHITECTURAL RULES — never violate these

- **SoA only.** Array-of-Structs pointer math is banned.
  Only valid pattern: `ld hl, array_base / ld d,0 / ld e,C / add hl,de`
  where C is the entity index (0-7).

- **No direct $7FFD writes** from bank7. Route through BankSwitch in bank2.

- **Bank2 never calls bank7.** Bank7 always paged during play, bank2 is fixed,
  but bank2 must not depend on bank7 being there.

- **HANDLER never calls bank7 code.** HANDLER is in bank2 and fires at any time.

- **Every push has a matching pop on every code path.**
  Use the Z80 emulator to verify before committing if in any doubt.

- **EraseSprite is dangerous with y=255** (computes addr $5Fxx = attr/sysvar area).
  Always guard with `cp 255 / jr z` before calling EraseSprite.

- **cp 176 / jp nc** before every DrawSprite call.
  screen_y >= 176 causes attr/sysvar corruption.

---

## 6. DIAGNOSING A CRASH

When the user reports a crash (48K BASIC, stuck AY note, floor flashing):

1. **Get the profiler.** Ask the user to run FUSE, reproduce the crash,
   save the profiler output, and upload the `.txt` file.

2. **Check ROM1 hits first.**
   ```python
   rom1 = [(a,c) for a,c in d.items() if 0x0000<=a<=0x3FFF]
   ```
   - Hits at $11DC = tape loader = corrupted stack return
   - Hits at $0038 = IM1 vector = IM2 broke down (paging corrupted)
   - Hits at $0296-$02AE = ROM1 keyboard scanner = game stuck in IM1 mode

3. **Check HANDLER count vs game frame count.**
   HANDLER should fire ~50x per second. If HANDLER count is far lower than
   expected, something killed the interrupt chain.

4. **Check for impossible hit counts.**
   A routine hit N times when it should be hit M times = wrong address in
   listing, or something jumping into the middle of the routine.

5. **The DS pad warning** (`Negative BLOCK?`) means code grew past $BCC0.
   Check AY_Silence end address. Shrink something or add an ORG pin.

---

## 7. KNOWN FRAGILE AREAS

These have caused crashes before. Be extra careful:

| Area | Risk | Guard |
|------|------|-------|
| EraseSprite with prev_sy=255 | Writes to attr/sysvar area | cp 255 / jr z before call |
| DrawSprite screen_y >= 176 | Attr write hits $5B00 (BANKM) | cp 176 / jp nc before call |
| djnz loop with push/pop inside | B register corrupted = 255 extra iters | Trace B through every push/pop |
| UpdateCamera push/pop order | Fixed (Fix 50) but pattern recurs | Always count pushes = pops |
| DS $BCC0 - $ pad | Goes negative if HANDLER section grows | Check AY_Silence/$BCC0 gap after every HANDLER edit |
| AY_WriteBuffer at $BCC0 | Must stay pinned | DS pad must always be positive |
| IM2 table at $7E00 | 257 bytes of $BC | make_szx.py handles this |
| BANKM at $5B5C | Written by BankSwitch only | Nothing else should touch this |

---

## 8. COMMITTING CHANGES

At the end of each session:

```bash
cd repo

# Copy updated files back
cp marco128.asm src/marco128.asm

# Update version in source: main.major.minor
# Update changelog.chg with one-line entry per fix including date
# Update diary.md with session entry
# Update marco128.md if addresses shifted

git add -A
git commit -m "vX.Y.Z — brief summary of fixes"
git tag -a vX.Y.Z -m "vX.Y.Z — brief summary"
git push origin main --tags
```

**Every file you touch gets a version bump.**
**Every fix gets a changelog entry.**
**Every session gets a diary entry.**

---

## 9. VERSION NUMBERING

Format: `main.major.minor`

- `minor` — bug fix, no new feature
- `major` — new feature or significant behaviour change
- `main` — milestone (complete world, major gameplay feature)

Current: **v0.7.7**

---

## 10. WHAT THE USER PROVIDES

- Fresh GitHub PAT token at the start of each session (for git push)
- FUSE profiler `.txt` output after test runs
- Description of what was seen in FUSE

**Before starting work, ask the user:**
1. What is your profession / day job?
2. What is your experience with programming in general?
3. What is your experience with Z80 assembly specifically?

Then calibrate your communication style accordingly.
Keep technical jargon in the code and changelog.
Match the explanation depth to the user's background.
