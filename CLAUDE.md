;;; CLAUDE.MD — Marco Bros 128 session instructions. Claude-internal. v0.7.9
;;; Read this first. Follow exactly. No exceptions.

;;; ═══════════════════════════════════════════════════
;;; 1. STARTUP SEQUENCE (every session, every time)
;;; ═══════════════════════════════════════════════════
;;; RULE: understand first. code second. build only after a code change.

;;; STEP 1 — clone:
;;;   git clone https://TOKEN@github.com/mstreurman/Marcobros128.git repo

;;; STEP 2 — read in this exact order, no skipping:
;;;   1. CLAUDE.md              ← you are here, finish reading
;;;   2. marco128.md            ← version, addresses, sysvar layout, bug history (72 fixes)
;;;   3. lessons.md             ← [PRE] checklist, [SCR] formula, [PRF] profiler, [DRW] rules
;;;   4. changelog.chg          ← tail -20: what was last fixed
;;;   5. diary.md               ← tail -30: context of last session
;;;   6. build/marco128.lst     ← committed listing (no build needed at startup)
;;;   7. architecture.md        ← hardware reference (consult as needed only)
;;;   8. marco128_contracts.md  ← subroutine contracts (consult when writing code)
;;;   9. marco128_history.md    ← bug history (consult when debugging regressions)

;;; STEP 3 — verify listing is current:
;;;   grep "Version" src/marco128.asm   →  must match last entry in changelog.chg
;;;   If match: listing and SZX are trustworthy. DO NOT BUILD.
;;;   If mismatch: build now (see §2).

;;; STEP 4 — ask user background questions (mandatory, see §6), then ask what they need.

;;; ═══════════════════════════════════════════════════
;;; 2. BUILD RULES
;;; ═══════════════════════════════════════════════════
;;; DO NOT build at session start. DO build after every src/marco128.asm change.
;;;
;;; BUILD COMMAND:
;;;   cp tools/sjasmplus /usr/local/bin/sjasmplus && chmod +x /usr/local/bin/sjasmplus
;;;   cp src/marco128.asm .
;;;   sjasmplus --nologo --lst=build/marco128.lst marco128.asm
;;;   python3 tools/make_szx.py
;;;
;;; EXPECTED: "Pass 3 complete / Errors: 0, warnings: 0"
;;;           make_szx: PC=$8375  SP=$BBFE  machine=Spectrum 128K  $7FFD=$17
;;; Any warning = a bug. Fix before proceeding. Never guess addresses — read from listing.
;;;
;;; AFTER SUCCESSFUL BUILD:
;;;   1. Update marco128.md if any addresses shifted
;;;   2. cp marco128.asm src/marco128.asm
;;;   3. git add src/marco128.asm build/marco128.lst build/marco128.szx
;;;   4. Update changelog.chg + diary.md
;;;   5. git commit / tag / push (see §5)

;;; ═══════════════════════════════════════════════════
;;; 3. BEFORE WRITING ANY CODE — mandatory pre-flight
;;; ═══════════════════════════════════════════════════
;;; Full detail in lessons.md [PRE]. Summary:

;;; CHECK 1 — REGISTERS:
;;;   List every register touched. Each must be pushed/popped (balanced on ALL paths)
;;;   or documented clobber. For every djnz loop: trace B through every push/pop in loop.
;;;   Union clobber sets of all called subroutines (see marco128_contracts.md).

;;; CHECK 2 — BANK PAGING:
;;;   bank7→bank2: OK. bank2→bank7: NEVER. bank7→port $7FFD: NEVER (use BankSwitch).
;;;   HANDLER→bank7: NEVER.

;;; CHECK 3 — JUMP RANGE:
;;;   Every jr/djnz: distance = |target - (jr_addr+2)|. ≥100 bytes → use jp.
;;;   Check ALL branches in modified routine, not just the changed one.

;;; ═══════════════════════════════════════════════════
;;; 4. ARCHITECTURAL RULES — never violate
;;; ═══════════════════════════════════════════════════
;;; SoA only: ld hl,array_base / ld d,0 / ld e,C / add hl,de  (C=entity index 0-7)
;;; AoS (struct_base + index*size + offset) IS BANNED.
;;; Every push has exactly one matching pop on every code path.
;;; EraseSprite: cp 255 / jr z guard before every call (y=255 → $5Fxx attr/sysvar corruption)
;;; DrawSprite:  cp 176 / jp nc guard before every call (y≥176 → $5B00 BANKM corruption)
;;; EraseSprite MUST run before the cp 176 guard in DrawPlayer/DrawEnemies (Fix 72).
;;; DS $BCC0-$ pad must always be positive. Check after every HANDLER section edit.
;;; BANKM at $5B5C: only BankSwitch may write it. Nothing else.
;;; Screen address formula: no rrca on (screen_y & $07) prow field (Fix 68). See lessons.md [SCR].
;;; Row-advance carry condition: jr c (not jr nc) at character-boundary branch (Fix 27/28/71).

;;; ═══════════════════════════════════════════════════
;;; 5. COMMITTING CHANGES
;;; ═══════════════════════════════════════════════════
;;; Every fix → changelog.chg entry. Every session → diary.md entry.
;;; Every file touched → version bump in that file's header.
;;;
;;; git add -A
;;; git commit -m "vX.Y.Z — brief summary"
;;; git tag -a vX.Y.Z -m "vX.Y.Z — brief summary"
;;; git push origin main --tags
;;;
;;; VERSION FORMAT: main.major.minor
;;;   minor = bug fix   major = new feature   main = milestone
;;; Current: v0.7.9

;;; ═══════════════════════════════════════════════════
;;; 6. USER CONTEXT
;;; ═══════════════════════════════════════════════════
;;; MANDATORY at session start — ask before starting work:
;;;   Q1: profession / day job?
;;;   Q2: programming experience in general?
;;;   Q3: Z80 assembly experience specifically?
;;; Then calibrate communication depth to their answers.
;;; Known (this user): IBM Lenovo server support tech, 25yr IT, ZX Spectrum 48K background,
;;;   no formal programming training, can follow C++/BASIC, cannot write Z80 unaided.
;;; Style: plain English explanations, hardware analogies, Z80 jargon in code/changelog only.
;;;
;;; USER PROVIDES EACH SESSION:
;;;   - Fresh GitHub PAT token (for git push)
;;;   - FUSE profiler .txt (after test runs — upload directly to chat)
;;;   - Description of what was seen in FUSE

;;; ═══════════════════════════════════════════════════
;;; 7. CRASH DIAGNOSIS
;;; ═══════════════════════════════════════════════════
;;; Full profiler workflow in lessons.md [PRF]. Summary:
;;;
;;; STEP 1: request profiler .txt from user (FUSE → run until crash → save profiler)
;;; STEP 2: parse with python3: data={int(l.split(',')[0],16):int(l.split(',')[1]) for l in f if l.strip()}
;;; STEP 3: quick checks:
;;;   $0038 hits > 0           → IM1 active (IM2 broke down)
;;;   $0296-$02AE hits >> 0    → stuck in IM1 keyboard scanner
;;;   $BC00 (HANDLER) hits = 0 → handler never ran; crash was immediate
;;;   $BC00 / 50               ≈ session seconds
;;; STEP 4: sort by count desc → top addresses → cross-ref listing → name hot routines
;;; STEP 5: check fragile areas below for root cause match

;;; FRAGILE AREAS (crash risk):
;;;   EraseSprite y=255       → $5Fxx attr corruption → BANKM corrupt → IM1 (Fix 66)
;;;   DrawSprite  y≥176       → $5B00 BANKM corrupt (Fix 49/60)
;;;   Screen addr rrca×3 bug  → writes IM2 table / game code (Fix 68 — RESOLVED v0.7.8)
;;;   EraseSprite jr nc       → wrong erase addresses for bottom 8 rows (Fix 71 — RESOLVED v0.7.9)
;;;   djnz loop + pop bc      → B corrupted → 255 extra iters → level data executed (Fix 45)
;;;   UpdateCamera no push    → return addr consumed → random PC (Fix 50 — RESOLVED v0.6.8)
;;;   DS $BCC0-$ negative     → "Negative BLOCK?" warning → AY_WriteBuffer displaced
;;;   HANDLER section growth  → pushes AY_Silence past $BCC0 → DS pad negative
;;;   jr range >127           → [JR] out of range error at pass 3 (Fix 42a,42b,44,46)

;;; ═══════════════════════════════════════════════════
;;; 8. REFERENCE FILE MAP
;;; ═══════════════════════════════════════════════════
;;; marco128.md        addresses, sysvar layout, memory map, state machine, SoA layout
;;; lessons.md         [PRE] preflight, [SCR] screen formula, [PRF] profiler, [DRW] draw rules,
;;;                    [STK] stack rules, [BNK] bank rules, [JMP] jump rules, [AMS] build
;;; architecture.md    ZX 128K hardware: ports, timing, keyboard matrix, ZXST format
;;; changelog.chg      append-only fix log
;;; diary.md           session reasoning and context
;;; marco128_contracts.md  IN/OUT/CLOBBERS for every subroutine
;;; marco128_history.md    bug history: symptom→cause→fix→risk, searchable by fix# or keyword
