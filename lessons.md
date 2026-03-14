# Z80 ASSEMBLY LESSONS LEARNED
*Reusable rules, patterns and gotchas extracted from Marco Bros 128 development.*
*Apply these to any Z80/Spectrum project.*
*See marco128.md for project-specific pre-flight and code rules.*
*Last updated: v0.7.7*

---

## SECTION C — SELF-REFERENCE: HOW TO READ THE .LST AND PROFILER
## ══════════════════════════════════════════════════════════════
## For Claude only. Not human documentation.
## These are the exact patterns needed to extract information from
## build/marco128.lst and the FUSE profiler .txt file.
## ══════════════════════════════════════════════════════════════

## C1. LISTING FILE (build/marco128.lst) ─────────────────────

## C1.1 Column Layout

Every non-blank line follows one of these patterns:

PATTERN 1 — Assembled instruction or data:
  "  NNN  XXXX BB BB BB   source text"
  col 1-5:   line number (decimal, right-justified, 1-based)
  col 7-10:  assembled address (4 hex digits, uppercase, NO $ prefix)
  col 12+:   assembled bytes (1–4 hex byte pairs, space-separated)
  then:      original source (label, mnemonic, operands, comment)

PATTERN 2 — Label-only line or blank address line:
  "  NNN  XXXX              label:"
  Address present but no bytes — label definition, ORG result, comment line.

PATTERN 3 — EQU / constant definition:
  "  NNN  0000              NAME  EQU  value"
  Address always 0000 for EQU lines. Value NOT shown in address column.
  To find the value: read the source text, or search for "EQU" on that line.

PATTERN 4 — Multi-byte continuation (DEFB strings, DS blocks):
  Same line number repeated, address advances, bytes shown:
  " 129  8007 4D 42 31 32      DEFB \"MB128...\"
   129  800B 38 20 76 30
   129  800F 2E 36 2E 31
   129  8013 00"
  Only the first continuation has the source text. Subsequent lines: line number + address + bytes only.

PATTERN 5 — DS (define space) with many bytes:
  "  163  8036 00 00 00...  ent_type: DS MAX_ENEMIES, 0"
  Truncated with "..." when DS block is > 4 bytes. Address = start of block.
  END address = start + size (derive from constant or context).

PATTERN 6 — Directive lines (PAGE, ORG, DEVICE, SAVEBIN):
  "  121  0000                  PAGE 2"
  "  122  0000                  ORG ENGINE_BASE"
  Address stays 0000 until ORG takes effect. The NEXT line shows the resolved address.
  PAGE directive resets the active bank but does NOT change the address counter unless
  followed by ORG. The address in the PAGE line itself = address before the switch.

PATTERN 7 — Error/warning inline:
  "marco128.asm(NNNN): error: [JR] Target out of range (+NNN)"
  These appear in the listing interspersed between code lines, referencing the
  source file line number (not the listing line number). Source line = NNNN.
  The listing line number for the same code is close but not identical.

## C1.2 How to Look Up an Address

To find what code lives at a specific hex address XXXX:
  grep "^\s\+[0-9]\+\s\+XXXX" marco128.lst
  Example: grep "^\s\+[0-9]\+\s\+BC00" marco128.lst
  → Returns all lines where the assembled address = XXXX.
  → Multiple matches are normal: label line + instruction line(s).
  → Take the line with bytes in column 3 for the actual instruction.

To find where a LABEL is defined:
  grep "LABELNAME:" marco128.lst
  → Returns the label definition line. Address is in column 2.

To find all instructions at addresses in a range XXXX–YYYY:
  Use python3 — grep is unreliable for hex range comparison.
  Pattern:
    for line in lst:
      parts = line.split()
      if len(parts) >= 2 and len(parts[1]) == 4:
        try:
          addr = int(parts[1], 16)
          if 0xXXXX <= addr <= 0xYYYY:
            print(line)
        except: pass

To find the SOURCE LINE NUMBER for a given address (for cross-reference to .asm):
  From a listing line "  NNN  XXXX ...", NNN is the .asm line number.
  That line number maps directly to src/marco128.asm line NNN.
  sed -n 'NNNp' src/marco128.asm — retrieves the source line.

## C1.3 Address Space Interpretation

Address shown in listing = LOGICAL address within the DEVICE.
For ZXSPECTRUM128:
  $0000–$3FFF = ROM space (not our code — constants and EQU lines show 0000)
  $4000–$7FFF = bank5 (IM2 table, sysvars — only DS/DEFB here, not executable code)
  $8000–$BFFF = bank2 (fixed engine — always present)
  $C000–$FFFF = bankable slot — which bank depends on current PAGE directive context
                In PAGE 7: this is bank7 game code
                In PAGE 0/1/3: this is level data (not executable)

PAGE directive context affects which SAVEBIN captures the bytes.
The listing does NOT show which PAGE is active — it shows only logical addresses.
To know which physical bank a $C000 address belongs to, find the last PAGE N
directive above that address in the listing.

## C1.4 Key Addresses to Always Check After a Build

  $8000:  first instruction (entry stub) — should be "ld a,2"
  $8375:  GAME_START — should be "di" followed by "ld sp,$BBFE"
  $BFFD:  DrawCharXY trampoline — should be exactly "jp DrawCharXY_Real" ($C3 00 C0)
           If bank2 code grew past $BFFD, this will show overlap or assembler error.
  $BC00:  HANDLER — should be "di" / "push af"
  $BCBC:  IM2_JUMP — should be "C3 00 BC" (JP $BC00)
  $C000:  DrawCharXY_Real — should be "push hl" / "push de" / "push bc" / "push ix" / "push af"

  Check for SAVEBIN ranges at end of file — each bank's byte count confirms no overflow:
  bank2 = $8000–$BFFF = 16384 bytes. If code reaches past $BFFD before DrawCharXY pin, error.
  bank7 = $C000–$FFFF = 16384 bytes. Monitor growth of DrawCharXY_Real + all bank7 routines.

## C1.5 Detecting jr Range Errors Before Assembling

sjasmplus reports "[JR] Target out of range (+N)" at pass 3.
The +N value is the ACTUAL byte offset to the target, which exceeded ±127.
To pre-screen: for every "jr" instruction, estimate distance to its target label
by comparing the listing addresses. If |target_addr - jr_addr - 2| > 127: must be jp.
The -2 accounts for the jr instruction itself being 2 bytes.

CheckWalls and CheckEnemyPlayer were caught this way (Fix42a,b):
  jr z,.cw_done  at $8??? — target +143 bytes — FAIL
  jr nz,.cep_no  at $8??? — target +128 bytes — FAIL (exactly one byte over)

## C2. PROFILER FILE (build/marco128.txt) ──────────────────────

## C2.1 File Format

Plain CSV, no header, CRLF line endings:
  0xADDR,COUNT
  address = hex string with 0x prefix, lowercase
  count   = decimal integer, execution count (number of times PC = this address during a fetch)

Properties:
  - Sorted by address ascending
  - No duplicate addresses
  - Only addresses with count > 0 appear (unexecuted addresses absent)
  - No total/summary line at end

Parse with python3:
  entries = [(int(l.split(',')[0], 16), int(l.split(',')[1]))
             for l in open('marco128.txt') if l.strip()]

## C2.2 What "count" Means

Count = number of Z80 instruction fetch cycles at that address.
= number of times the CPU fetched an opcode byte from that address.
= approximately "number of times that instruction executed".

Nuance: multi-byte instructions (e.g. LDIR, CB-prefixed) only count ONE fetch
at the base address per execution. The prefix byte itself is not counted separately.
So count at an LDIR address = number of LDIR iterations is NOT correct —
LDIR's inner loop re-fetches the same address each iteration, so count ≈ iterations.

## C2.3 Diagnostic Patterns

PATTERN: All addresses in $0000–$3FFF, none in $8000+
  → CPU never left ROM. Our code never ran.
  → Cause: PC in snapshot wrong, or bank2 not loaded, or crash at first instruction.
  → Fix43 was exactly this: PC stayed at $0038 (template default).

PATTERN: $0000 has count > 0
  → CPU executed the Z80 reset vector. Count = number of hard resets/crashes.
  → Even count=1 means the game crashed and reset at least once.

PATTERN: $0038 has count > 0 AND bank2 addresses absent
  → IM1 mode active and firing. Our IM2 handler never installed.
  → CPU is in ROM running the standard IM1 interrupt handler.
  → Causes: IM register not set (see Fix43), Setup_IM2 never called, or bank5 IM2 table wrong.

PATTERN: $0038 has count > 0 BUT bank2 addresses also present
  → Our code ran but IM2 wasn't set up before first interrupt.
  → Usually means Setup_IM2 called too late (after first EI).

PATTERN: $BC00 (HANDLER) has count N
  → N ÷ ~50 ≈ seconds of emulated time the game ran under our IM2 handler.
  → If N = 0: handler never fired (IM2 not active, or game crashed before first interrupt).
  → If N is very low (< 50): game ran briefly then crashed.

PATTERN: addresses clustered tightly with very high counts
  → Tight loop. Identify by looking up the address range in the listing.
  → Count on the loop-back branch ≈ total loop iterations.
  → Count on the first instruction of the loop body ≈ total iterations.
  → Compare adjacent address counts to find loop entry/exit.

PATTERN: address X has count C1, address X+1 has count C2, C2 << C1
  → A conditional branch at X is taken (C1-C2) times and falls through C2 times.
  → Useful for branch frequency analysis.

PATTERN: address present in listing but absent from profiler
  → That code path was never reached during the profiling session.
  → Could be: dead code, a branch always taken/never taken, error handler, etc.

## C2.4 Mapping Profiler Addresses to Code

Step 1: python3 to extract hot addresses sorted by count desc:
  entries.sort(key=lambda x: -x[1])
  for addr, count in entries[:20]: print(hex(addr), count)

Step 2: for each hot address, look up in listing:
  grep "^\s\+[0-9]\+\s\+{ADDR:04X}" marco128.lst
  where ADDR is the integer address zero-padded to 4 uppercase hex digits.

Step 3: check address range to determine which bank/section:
  $0000–$3FFF → ROM (see A4 for ROM1 routine map)
  $4000–$7FFF → bank5 (should never be executing here in our game)
  $8000–$BFFF → bank2 engine (expected hot zone)
  $C000–$FFFF → bank7 game code (expected hot zone)

Step 4: if address is in ROM, identify the ROM routine:
  Cross-reference with A4 (ROM contents section) for known addresses.
  Key ROM1 diagnostic addresses:
    $0000  reset/startup sequence
    $0005  PRINT-A (character output)
    $0038  IM1 interrupt handler → reti
    $0066  NMI handler
    $028E  CHAN-OPEN
    $03B4–$04C3  LD-BYTES (tape loader)
    $0D6B  Token tables (data, not code)
    $10A8  SA-BYTES / output routines
    $11DC–$11ED  tight loop in output or copy routine
    $15DE–$162C  BASIC interpreter evaluation loop
    $3D00–$3EFF  CHARACTER FONT DATA (data, not code — if PC here = serious crash)

## C2.5 Quick Diagnosis Checklist (use every time profiler data is received)

IDLE SPIKE WARNING — read before interpreting counts:
  HALT loops accumulate enormous fetch counts during any wait screen.
  TitleScreen, ShowLevelEntry, ShowGameOver, ShowVictory, death animation,
  and the level-end 100-frame wait all spin on HALT. If the user let the game
  idle on a title or entry screen, the HALT address in that screen will be the
  single hottest address in the entire profiler file — often 10-100× higher
  than any gameplay address. THIS IS NOT A BOTTLENECK. It means the user waited.
  Rule: do not treat any HALT-spinning wait-loop address as a performance problem.
  To measure true gameplay performance, compare counts only from sessions where
  the user played at least one full level without pausing.
  To identify which HALT is which: cross-reference with the listing. Each wait
  loop has a unique address (TitleScreen .ts_wait, ShowLevelEntry .sle_wait, etc.).
  Gameplay HALT is in MainLoop .mg_frame; its address is the true frame-rate anchor.

  1. python3: max address? if <= $3FFF → game code never ran (Fix43 class bug)
  2. python3: any address >= $8000? if none → bank2 not executing
  3. grep $0000 → count > 0? → crash/reset count
  4. grep $0038 → count > 0? → IM1 active instead of IM2; check Setup_IM2
  5. grep $BC00 → count? → frames of gameplay under our handler
  6. sort by count desc → top 5 addresses → look up in listing → name the hot routines
     (filter out HALT addresses in known wait loops before calling anything a bottleneck)
  7. find addresses in listing with count=0 (absent from profiler) → unreached code paths
  8. look for count spikes on specific addresses → branch frequency / loop analysis

## C2.6 Profiler Limitations

- The profiler counts fetches, NOT wall-clock time or T-states.
  To convert to T-states: multiply count × instruction_T_states (approximate).
- HALT instruction: profiler counts each HALT re-fetch (4 T-states each).
  A HALT waiting for interrupt will show very high count at the HALT address.
  Our frame loop uses HALT → expect $CC?? (MainLoop halt address) to be hottest bank7 addr.
- Contended memory: profiler doesn't distinguish contended vs uncontended execution.
- FUSE profiler exports only addresses that were actually fetched as opcodes.
  Data reads (LD A,(HL) etc.) targeting an address do NOT add to that address's count.
- The profiler file represents the ENTIRE session from snapshot load to when profiling stopped.
  Counts accumulate. Ratio analysis (addr A count vs addr B count) is more useful than raw counts.

## C3. CODE OUTPUT FORMAT ──────────────────────────────────────
## Rules Claude MUST follow when producing Z80 assembly fixes.

## C3.1 Subroutine Output Rule
When providing a fix or new routine, output the ENTIRE subroutine from its
entry label to its final `ret` (or `reti`). No placeholders. No `; ... rest
of code unchanged`. The human will paste the entire block verbatim.

## C3.2 Comment Alignment
Target column 40 for inline comments (count from column 1).
Use the existing source style: tab-stop operand field, then `;` at ~col 40.
Example (col positions approximate):
  ld hl, ent_state            ; base of ent_state SoA array
  ld d, 0                     ; D = 0 for 16-bit index
  ld e, c                     ; E = entity index
  add hl, de                  ; HL = &ent_state[c]

## C3.3 Diff Presentation
For a one-liner change buried in a large routine: show the FULL routine anyway.
Also note the specific changed line with an inline comment: `; CHANGED: reason`.
Never use unified diff format (--- +++ @@) — paste-friendly assembly only.

## C3.4 Label Conventions
Local labels: prefix with `.` and a routine abbreviation, e.g. `.cg_snap`.
Do NOT reuse local label names from other routines in the same PAGE section —
sjasmplus scopes locals to the next non-local label, but collisions cause errors.

## C3.5 Register Usage Warning
Always state which registers are clobbered before writing new code.
Cross-check against B11 contracts table. If a new routine calls subroutines,
union their clobber sets. Never assume a register is safe without checking B11.

LOOP COUNTER PROTECTION RULE (Fix45 lesson):
  Whenever push/pop is used INSIDE a djnz loop:
    (a) Explicitly trace the state of register B at every pop instruction.
    (b) If any pop lands in BC (i.e. the instruction is "pop bc"), confirm
        that the value being popped is the original loop counter / entity index —
        NOT coordinate data, pixel values, or any other transient calculation.
    (c) If the pop retrieves coordinate data, wrap the entire push/pop block
        with an outer push bc / pop bc to save and restore the loop state.
  Fix45 root cause: pop bc inside .les_loop retrieved pixel_x bytes into BC,
  overwriting B=8 (loop counter) with 0 and C=entity_index with pixel_x_low.
  djnz then decremented B=0→255 and looped 255 extra times through level bank
  data, eventually executing $CD $BC $83 as CALL BankSwitch with random A.

## C3.6 Pre-Flight Checklist — MANDATORY before outputting any Z80 assembly

Before writing a single line of new or modified Z80 assembly, Claude MUST
explicitly work through the following three checks. Output a reasoning block
(using <think> tags or equivalent) that addresses all three points. Do NOT
skip this step even for trivial-looking changes — the most common regressions
(Fix42a, Fix42b, Fix27, Fix28) came from "obvious" one-liner edits.

CHECK 1 — REGISTER CLOBBER:
  List every register this routine will touch (read or write), including
  registers touched inside any subroutine it calls (union of clobber sets
  per B11). Confirm each one is either:
    (a) pushed on entry and popped before return, OR
    (b) explicitly documented as clobbered in B11 for this routine's contract.
  If calling a subroutine that clobbers AF and you need AF after the call,
  push AF before the call. Never assume a callee preserves a register
  without verifying it in B11.

  ADDITIONAL — DJNZ LOOP COUNTER CHECK (mandatory if routine contains djnz):
  For every djnz loop, explicitly trace the value of B at EVERY pop instruction
  inside the loop body. If any pop bc is present, confirm the popped value is
  the original loop counter — NOT coordinate, pixel, or temporary data.
  If uncertain: wrap the risky push/pop pair with outer push bc / pop bc.
  Reference: Fix45 — pop bc inside djnz loop retrieved pixel_x bytes into BC,
  corrupting B=loop_counter(8)→0 → djnz looped 255 extra times.

CHECK 2 — BANK PAGING:
  Answer both questions:
    Q1: Does this routine live in bank2 or bank7?
    Q2: Does it call any subroutine — directly or transitively — that is in
        the opposite bank, or that writes to port $7FFD?
  If Q2 is yes for bank7 code calling bank2: OK (Rule 1).
  If Q2 is yes for bank2 code calling bank7: STOP — violates Rule 2.
  If Q2 involves any direct OUT to $7FFD from bank7: STOP — violates Rule 3.
  If the routine runs inside HANDLER ($BC00): it must call ONLY bank2 routines.

CHECK 3 — JUMP RANGE:
  For every `jr` or `djnz` instruction in the new code, estimate the byte
  distance to its target label. Use the listing addresses of nearby instructions
  as anchors, or count instruction bytes manually.
  jr / djnz range limit: ±127 bytes (signed offset).
  Rule: if the estimated distance from the jr instruction to its target
  is >= 100 bytes, use `jp` instead. The ±127 ceiling leaves no margin for
  error and the assembler's error message only appears at pass 3.
  Example calculation:
    jr at address $8400, target at $8483 → distance = $83 = 131 bytes → USE jp.
    jr at address $8400, target at $8450 → distance = $50 = 80 bytes → jr is safe.

  CRITICAL RULE — CHECK ALL BRANCHES, NOT JUST THE ONE YOU EDITED:
  When modifying a routine, scan EVERY jr and djnz in the entire routine,
  not just the line you changed. Adding or removing even 1–2 bytes can push
  a previously safe jr over the ±127 limit. A routine may also have multiple
  branches to the same label — fixing one does not guarantee the others are safe.
  Reference: Fix42a fixed right-probe jr z in CheckWalls (+143 bytes), but the
  entry jr z (+142 bytes at the time) was missed. Fix46 was required the very
  next session when Fix45's +1 byte pushed it to +144 bytes.
  Workflow: after writing any fix, grep the modified routine for ALL `jr` and
  `djnz` instructions and verify each one individually against the listing.

## ══════════════════════════════════════════════════════════════
## END SECTION C
## ══════════════════════════════════════════════════════════════
