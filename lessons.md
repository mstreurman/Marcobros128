;;; LESSONS.MD — Claude-internal reference. Not human docs. v0.7.9
;;; FORMAT: dense key→value / rule tables / code patterns.
;;; Prose stripped. Headers are grep anchors. Read top-to-bottom on first load,
;;; then grep-jump to section needed.

;;; SECTIONS
;;; [LST]  Listing file format & lookup patterns
;;; [PRF]  Profiler file format & diagnostic patterns
;;; [SCR]  Screen address formula — canonical correct version + known bugs
;;; [DRW]  Drawing routines — contracts, guards, call order
;;; [STK]  Stack / push-pop rules and known failure patterns
;;; [BNK]  Bank paging rules
;;; [JMP]  Jump range rules
;;; [PRE]  Pre-flight checklist (mandatory before any code write)
;;; [SOA]  SoA entity array rules
;;; [AMS]  sjasmplus assembly patterns

;;; ═══════════════════════════════════════════════════
;;; [LST] LISTING FILE (build/marco128.lst)
;;; ═══════════════════════════════════════════════════
;;; COLUMN LAYOUT:
;;;   "  NNN  XXXX BB BB BB   source text"
;;;   NNN  = src line number (1-based decimal, maps to marco128.asm:NNN)
;;;   XXXX = assembled address (4 hex, NO $ prefix)
;;;   BB   = assembled bytes (hex pairs, space-separated)
;;;   EQU lines: address=0000; value not in addr col, read source text.
;;;   PAGE lines: address=0000 until next ORG. Next line shows resolved address.
;;;   DS blocks: "..." when >4 bytes. End=start+size.
;;;   Error inline: "marco128.asm(NNN): error: [JR] Target out of range (+N)"

;;; ADDRESS LOOKUP:
;;;   label:  grep "LABELNAME:" build/marco128.lst
;;;   addr:   python3: parts=l.split(); int(parts[1],16) if len(parts)>=2 and len(parts[1])==4
;;;   range:  filter above by 0xXXXX<=addr<=0xYYYY

;;; ADDRESS SPACE:
;;;   $0000-$3FFF = ROM (EQU lines show 0000 — not our code)
;;;   $4000-$7FFF = bank5 (IM2 table at $7E00, sysvars, pixel/attr mem — no executable code)
;;;   $8000-$BFFF = bank2 (fixed engine, always present)
;;;   $C000-$FFFF = bankable:
;;;     PAGE 7  → bank7 game code (executable)
;;;     PAGE 0/1/3 → level data (data only, same logical addresses as bank7 code)
;;;     Find last PAGE N directive above any $C000 address to know which bank.

;;; PINNED ADDRESSES (verify after every build — must not shift):
;;;   $8375  GAME_START      "di / ld sp,$BBFE"
;;;   $8800  TILE_DATA       ORG-pinned
;;;   $8E00  FONT_DATA       ORG-pinned
;;;   $BC00  HANDLER         ORG HANDLER_ADDR
;;;   $BCBC  IM2_JUMP        "C3 00 BC" = JP $BC00
;;;   $BCC0  AY_WriteBuffer  DS pad before it — pad must stay positive
;;;   $BFFD  DrawCharXY      "jp DrawCharXY_Real" ($C3 00 C0)
;;;   $C000  DrawCharXY_Real

;;; ═══════════════════════════════════════════════════
;;; [PRF] PROFILER FILE (marco128.txt from FUSE)
;;; ═══════════════════════════════════════════════════
;;; FORMAT: "0xADDR,COUNT" CSV, no header, CRLF, sorted addr asc, only count>0.
;;; PARSE:  data={int(l.split(',')[0],16):int(l.split(',')[1]) for l in f if l.strip()}

;;; COUNT = opcode fetch cycles at that address ≈ instruction execution count.
;;;   HALT: re-fetches same addr each frame → HALT addr gets huge counts during wait screens.
;;;   LDIR: counts each re-fetch per iteration (inner loop of LDIR).

;;; PROFILER ADDRESS ALIASING (bank7 range $C000-$FFFF):
;;;   During InitLevel, banks 0/1/3 briefly paged. Profiler records their fetches
;;;   at same $C000+ addresses as bank7 code. This inflates counts during gameplay.
;;;   Symptom: DrawSprite djnz/entry ratio ~23-25 instead of 16.
;;;   Cause: level map DEFB bytes in bank0/1/3 executed as code during bank switch window.
;;;   NOT a code bug. Verify by checking if suspicious addresses correspond to level data.

;;; DIAGNOSTIC PATTERNS:
;;;   max(addr) <= $3FFF            → game code never ran
;;;   $0000 count > 0               → crash/reset count
;;;   $0038 count > 0               → IM1 firing instead of IM2
;;;     + no $8000+ addrs           → Setup_IM2 never called
;;;     + $8000+ addrs present      → IM2 table/I register corrupted mid-game
;;;   $0296-$02AE counts            → ROM1 keyboard scanner = stuck in IM1
;;;   $BC00 count / 50              ≈ session seconds
;;;   $BC00 count ~= 0              → HANDLER never fired
;;;   DrawPlayer guard ($CA7E) fires >50% → screen_y >= 176 almost always → plr_y bug
;;;   HALT addrs hottest            → user left game idling (not a bottleneck)
;;;     Known HALT addrs: TitleScreen.ts_wait, ShowLevelEntry.sle_wait,
;;;     MainLoop.mg_frame (gameplay HALT — this one IS the frame rate anchor)

;;; QUICK DIAGNOSIS SEQUENCE:
;;;   1. max addr <= $3FFF?  → snapshot broken
;;;   2. $0038 hits?         → IM1 active; check I register and IM2 table at $7E00
;;;   3. $BC00 count         → session length; if 0, HANDLER never ran
;;;   4. sort by count desc → top addrs → cross-ref listing → name routines
;;;      filter out known HALT wait-loop addrs first
;;;   5. screen_y guard hit rate in DrawPlayer/DrawEnemies → plr_y range check
;;;   6. ROM1 keyboard scanner hits → IM1 active during gameplay → crash pattern

;;; ═══════════════════════════════════════════════════
;;; [SCR] SCREEN ADDRESS FORMULA
;;; ═══════════════════════════════════════════════════
;;; CANONICAL CORRECT FORMULA (C=screen_y, B=screen_x → H:L):
;;;   third = (C & $C0) >> 3        → placed into H via rrca×3 from $C0 mask
;;;   prow  = (C & $07)             → placed into H DIRECTLY (no rrca) — OR into H
;;;   crow  = (C & $38) << 2        → placed into L via add a,a twice from $38 mask
;;;   col   = (B >> 3) & $1F        → placed into L via rrca×3 from B
;;;   H = third | prow | $40
;;;   L = crow | col
;;;
;;; Z80 CODE PATTERN (H:L target registers, C=screen_y, B=screen_x):
;;;   ld a,c / and $C0 / rrca / rrca / rrca / ld h,a   ; third
;;;   ld a,c / and $07 / or h / or $40 / ld h,a        ; prow — NO rrca after and $07
;;;   ld a,c / and $38 / add a,a / add a,a / ld l,a    ; crow
;;;   ld a,b / rrca / rrca / rrca / and $1F / or l / ld l,a ; col

;;; BUG THAT WAS PRESENT (FULLY FIXED v0.7.8/v0.7.9):
;;;   and $07 / rrca / rrca / rrca  — 3 rrcas on prow field.
;;;   Effect: prow $01→$20, $02→$40, $03→$60 etc. → bits in H[6:5] not H[2:0].
;;;   Corrupted addresses mapped to wrong screen third, attr area, IM2 table, or game code.
;;;   FIX: remove the 3 rrca after and $07. OR directly into H.
;;;   FIXED IN: DrawSprite (Fix 68), EraseSprite (Fix 68).
;;;   DrawTile and DrawCharXY formula was always correct (never had the 3 rrca).

;;; ROW ADVANCE (character boundary transition — identical in all 4 routines):
;;;   inc H (or inc D in DrawTile)
;;;   test H & $07 == 0 → character row boundary crossed
;;;   L += $20
;;;   carry set   → crossed into next screen third → H already correct, skip sub $08
;;;   carry clear → same third, H overshot by 8 → sub $08 from H
;;;   Z80: add a,$20 / ld l,a / jr c,.ok / ld a,h / sub $08 / ld h,a / .ok:

;;; CARRY CONDITION TABLE — MUST BE jr c (not jr nc):
;;;   DrawTile     $C27B  jr c, .dt_cont     CORRECT (Fix 27 — was jr nc)
;;;   DrawCharXY   $C05F  jr c, .dcxy_cont   CORRECT (Fix 28 — was jr nc)
;;;   DrawSprite   $C51A  jr c, .ds_rowok    CORRECT (Fix 27 context — was jr nc)
;;;   EraseSprite  $C55F  jr c, .er_ok       CORRECT (Fix 71 — was jr nc)
;;;   ALL FIXED v0.7.9. New drawing routines: MUST use jr c at this branch point.

;;; SCREEN SAFETY LIMITS:
;;;   Valid pixel rows: 0-191. Rows 192+ = attr area $5800+.
;;;   Max safe screen_y for 16px sprite: 175 (175+15=190 <= 191).
;;;   Guard: cp 176 / jp nc (skip draw if screen_y >= 176).
;;;   screen_y=255: EraseSprite computes $5Fxx → attr area → BANKM corruption (Fix 66).
;;;   Erase sentinel: cp 255 / jr z .skip_erase in DrawPlayer and DrawEnemies.

;;; ═══════════════════════════════════════════════════
;;; [DRW] DRAWING ROUTINES — GUARDS AND CALL ORDER
;;; ═══════════════════════════════════════════════════
;;; ERASE-BEFORE-GUARD RULE (Fix 72 — critical):
;;;   EraseSprite at OLD position MUST run BEFORE the screen_y guard.
;;;   WRONG (pre-Fix 72): guard fires → erase skipped → old pixels persist → jump trail.
;;;   CORRECT ORDER:
;;;     1. cp 255 / jr z .skip_erase    (sentinel: never drawn yet → skip erase)
;;;     2. load prev_sx → B, prev_sy → C
;;;     3. call EraseSprite
;;;     .skip_erase:
;;;     4. compute new screen_x → B, screen_y → C
;;;     5. cp 176 / jp nc .done         (screen_y guard for new position)
;;;     6. call DrawSprite
;;;     7. store new B → prev_sx, C → prev_sy
;;;   If guard fires at step 5 (player off-screen): erase still happened at step 3. Clean.
;;;   Applied in: DrawPlayer (Fix 72), DrawEnemies (Fix 72).

;;; FRAME DRAW ORDER (STATE_PLAYING):
;;;   RenderLevel → DrawPowerup → DrawEnemies → DrawPlayer → DrawHUD
;;;   Sprites draw after tiles (correct: sprites on top of tiles).
;;;   HUD draws last (correct: HUD on top of everything).

;;; HUD FLICKER (architectural — not a bug, do not attempt to fix):
;;;   RenderLevel draws tile row 1 (pixel_y 16-31) every frame.
;;;   DrawHUD immediately follows and overwrites the COINS/SCORE area with text.
;;;   CRT beam catches the gap between the two calls → brief tile pixels visible as flicker.
;;;   Cannot fix without: restricting RenderLevel to rows 2-10 (loses ceiling)
;;;   OR running HUD from HANDLER (HANDLER cannot call bank7 DrawCharXY). Accept.

;;; ═══════════════════════════════════════════════════
;;; [STK] STACK / PUSH-POP RULES
;;; ═══════════════════════════════════════════════════
;;; RULE: every push has exactly one matching pop on every code path (all branches).

;;; DJNZ LOOP COUNTER CORRUPTION (Fix 45 root cause pattern):
;;;   Trigger: pop bc inside djnz loop retrieves data value into B (loop counter).
;;;   Effect: B set to data value (often 0) → djnz 0→255 → 255 extra iterations.
;;;   Detection: trace B through every push/pop inside each djnz loop body.
;;;   Fix: wrap risky push/pop with outer push bc / pop bc around the block.
;;;   Historic: LoadEnemySpawns — pop bc got pixel_x bytes → B=0 → 255 extra loops
;;;             → byte sequence in level data executed as CALL BankSwitch → bank7 paged out.

;;; HANDLER STACK (perfectly balanced, do not modify):
;;;   Entry: di / push af,bc,de,hl,ix,iy  (SP-12)
;;;   Exit:  pop iy,ix,hl,de,bc,af / ei / reti
;;;   HANDLER must NEVER call bank7 routines.

;;; ═══════════════════════════════════════════════════
;;; [BNK] BANK PAGING RULES
;;; ═══════════════════════════════════════════════════
;;; Rule 1: bank7 → bank2: ALWAYS SAFE
;;; Rule 2: bank2 → bank7: NEVER (bank7 may not be present)
;;; Rule 3: bank7 → port $7FFD: NEVER (use BankSwitch in bank2 instead)
;;; Rule 4: HANDLER → bank7: NEVER
;;; Rule 5: level banks 0/1/3: read-only, transient (only during DoLevelBanking)
;;;          Gameplay reads level data via level_map_cache (bank2), never by paging.

;;; ═══════════════════════════════════════════════════
;;; [JMP] JUMP RANGE RULES
;;; ═══════════════════════════════════════════════════
;;; jr / djnz: ±127 bytes. Threshold for using jp instead: ≥ 100 bytes.
;;; Distance = |target_addr - (jr_addr + 2)|
;;; Error only at pass 3 → pre-check for every jr in routines > 100 bytes total.
;;; CHECK ALL BRANCHES IN ROUTINE after any edit (not just the modified one).
;;;   Fix 42a fixed one jr in CheckWalls (+143). Missed entry jr (+142). Fix 46 caught it next session.
;;;   Adding 1 byte to any routine can push a previously-safe jr over 127.
;;; Known forced-jp branches:
;;;   CheckWalls entry: jp z, .cw_done (was jr, Fix 42a, 46)
;;;   CheckEnemyPlayer .cep_no target: jp nz (Fix 42b)

;;; ═══════════════════════════════════════════════════
;;; [PRE] PRE-FLIGHT CHECKLIST (run before writing any Z80 assembly)
;;; ═══════════════════════════════════════════════════
;;; CHECK 1 — REGISTERS:
;;;   List every register touched (read or write) including called subroutine clobbers.
;;;   Each register must be either: pushed/popped (balanced on ALL paths) OR documented clobber.
;;;   For every djnz loop: trace B through every push/pop inside loop body.
;;;   If any pop bc gets non-counter data: add outer push bc / pop bc.

;;; CHECK 2 — BANK PAGING:
;;;   Q1: which bank does this routine live in?
;;;   Q2: does it call (directly or transitively) anything in the opposite bank?
;;;   bank7→bank2: OK. bank2→bank7: STOP. bank7→$7FFD: STOP. HANDLER→bank7: STOP.

;;; CHECK 3 — JUMP RANGE:
;;;   For every jr and djnz: distance = |target_addr - (jr_addr + 2)|
;;;   ≥ 100 bytes → use jp. Check ALL branches in the modified routine.

;;; ═══════════════════════════════════════════════════
;;; [SOA] ENTITY SoA RULES
;;; ═══════════════════════════════════════════════════
;;; AoS (C-style struct array) IS BANNED. SoA only.
;;; CORRECT PATTERN (C = entity index, 0..MAX_ENEMIES-1):
;;;   ld hl, ent_FIELDNAME / ld d,0 / ld e,c / add hl,de / ld a,(hl)
;;; ld ixl,(hl) is ILLEGAL Z80 — use: ld a,(hl) / ld ixl,a

;;; ENTITY ARRAYS (bank2, fixed):
;;;   ent_type[8]   ent_xl[8]   ent_xh[8]   ent_yl[8]   ent_vx[8]
;;;   ent_state[8]  ent_anim[8] ent_anim_cnt[8]
;;;   ent_prev_sx[8]  ent_prev_sy[8]  (255 = never drawn sentinel, Fix 62)
;;; ent_state: 0=dead/inactive, 1=active. No other values.

;;; ═══════════════════════════════════════════════════
;;; [AMS] SJASMPLUS ASSEMBLY PATTERNS
;;; ═══════════════════════════════════════════════════
;;; BUILD:
;;;   cp src/marco128.asm . && sjasmplus --nologo --lst=build/marco128.lst marco128.asm
;;;   Any warning = bug. Fix before proceeding. Then: python3 tools/make_szx.py

;;; ILLEGAL Z80 (assembler may accept but hardware rejects):
;;;   ld ixl,(hl) → ld a,(hl) / ld ixl,a
;;;   ld (hl),ixl → ld a,ixl / ld (hl),a
;;;   ld ixh,ixl  → ld a,ixl / ld ixh,a

;;; VERSION: main.major.minor. Bump every session touching source.
;;; Update: asm header + DEFB version tag + marco128.md + changelog + diary.

;;; OUTPUT RULES:
;;;   Full subroutine only (entry label to ret). No placeholders.
;;;   Changed lines: "; CHANGED: Fix NN — reason"
;;;   Local labels: .routineabbrev_name (no collision across routines in same PAGE)
;;;   Comment column: ~40
