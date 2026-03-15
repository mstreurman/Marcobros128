;;; MARCO128_HISTORY.MD — Claude-internal. Bug history. v0.7.9
;;; FORMAT: #fix | class | symptom→cause→fix | regression_risk
;;; Classes: CRASH SEVERE DRAW INPUT AUDIO PHYSICS LOGIC PERF PENDING
;;; Search by fix number, class, or symptom keyword.

;;; ═══════════════ FIXES 68-72 (v0.7.8-0.7.9, 2026-03-15) ═══════════════

72 | DRAW | SYMPTOM: ghost sprite pixels trail along jump path.
   | CAUSE: DrawPlayer/DrawEnemies had EraseSprite inside screen_y guard block.
   |        When guard fired (player near screen edge), erase skipped → old pixels persisted.
   | FIX: moved EraseSprite call to BEFORE screen_y guard. Erase always runs at prev_sy.
   |      255 sentinel (Fix 62/66) still guards the erase itself.
   | RISK: any new drawable entity must follow erase-before-guard pattern.

71 | DRAW | SYMPTOM: sprite bottom half flickers in/out, random pixel debris during motion.
   | CAUSE: EraseSprite row-advance had "jr nc, .er_ok" (was: sub $08 fires on carry).
   |        Correct condition is jr c. Same class as Fix 27 (DrawTile), Fix 28 (DrawCharXY).
   |        EraseSprite was the last routine with the inverted carry condition.
   |        Effect: sub $08 H-correction fired ~2% instead of ~50% of boundary crossings.
   |        Bottom 8 rows of every erase wrote to garbage addresses.
   | FIX: jr nc → jr c at EraseSprite row-advance boundary branch.
   | RISK: if new drawing routine added, MUST use jr c at this branch (see [SCR] in lessons.md).

70 | INPUT | SYMPTOM: Space/jump does not work on first press after level start.
   | CAUSE: TitleScreen exits on Space press → joy_prev bit4 set → edge-detect produces
   |        joy_new bit4=0 for first frames of gameplay → jump trigger never fires.
   | FIX: InitLevel zeroes joy_held, joy_new, joy_prev after timer_cnt reset.
   | RISK: any new screen that exits on a key press should be followed by joy flush.

69 | LOGIC | SYMPTOM: touching enemy kills player regardless of direction; stomp doesn't kill enemy.
   | CAUSE: "bit 7,a / jr nz,.cep_stomp" — nz fires when bit7 IS set (vy negative = moving up).
   |        Stomp triggered when player moving UP; hurt triggered when falling DOWN. Inverted.
   | FIX: jr nz → jr z at .cep_hit in CheckEnemyPlayer.

68 | CRASH,DRAW | SYMPTOM: crash to 48K BASIC with stuck AY note on any enemy contact.
   |              Bottom half of sprites at wrong position or in wrong screen third.
   | CAUSE: DrawSprite and EraseSprite: "and $07 / rrca / rrca / rrca" on screen_y prow field.
   |        3 rrcas on value $02 → $40, placing prow bits in H[6] not H[1:0].
   |        Sprite rows written to wrong addresses including $7Exx (IM2 table), $5Bxx (BANKM).
   |        Corrupted I register / IM2 table → CPU dropped to IM1 → stuck AY note.
   | FIX: removed 3 rrca after "and $07" in DrawSprite and EraseSprite.
   |      prow bits now OR'd directly into H (no rotation needed).
   | PROFILER: $0038 hits=1606, $0296-$02AE hits=68182 → IM1 active signature.
   | RISK: any new screen address formula must NOT apply rrca to the prow field.

;;; ═══════════════ FIXES 62-67 (v0.7.7, 2026-03-14) ═══════════════

67 | INPUT | O/P keys: wrong bits read ($DF row bit4=Y as P, bit3=U as O). No movement ever worked.
   | FIX: bit 0,a for P (right); bit 1,a for O (left). Space $7F row bit0 was correct.

66 | CRASH | EraseSprite with prev_sy=255 sentinel computes H=$5F → attr/sysvar area.
   |        Corrupts BANKM at $5B5C → IM1 mode → game freezes.
   | FIX: cp 255 / jr z skip-erase guard before EraseSprite in DrawPlayer and DrawEnemies.

65 | CRASH | DrawSprite attr write (Fix 56, 63): 3-col write overflowed into adjacent rows at col≥30.
   |         Also redundant: ClearScreen sets ATTR_SKY; RenderLevel restores tile attrs.
   | FIX: attr write removed entirely from DrawSprite.

64 | DRAW | .mg_drender (death animation) skipped DrawEnemies → 60-frame enemy pixel trails.
   | FIX: added call DrawEnemies to .mg_drender.

63 | CRASH | Caused crash — see Fix 65. |

62 | DRAW | InitLevel prev_sy=0 → EraseSprite cleared top-left corner on first draw frame (HUD flicker).
   | FIX: prev_sy initialised to 255 (off-screen sentinel). CAUTION: see Fix 66.

61 | CRASH | DrawSprite push/pop mismatch after Fix 56 added IY. Fixed with ds_save vars; later
   |         removed in Fix 65 when attr write was eliminated entirely.

60 | CRASH | cp 177 guard allowed screen_y=176. DrawSprite attr write hit $5B00 (BANKM sysvar).
   | FIX: cp 176 (screen_y=176 → jp nc skip).

59 | CRASH | DrawSprite missing push iy/pop iy. DrawEnemies stored entity index in IYL → corrupted.
   | FIX: push iy/pop iy added to DrawSprite.

58 | PERF | AY_Silence had redundant 14-byte ay_buf clear loop. Removed; AY_WriteBuffer does it.

57 | BUILD | DS $BCC0-$ went negative after Fix 55 grew HANDLER section past $BCC0.
   | FIX: shrink Fix 55 kbd code + remove AY_Silence loop (Fix 58).

56 | DRAW | Added DrawSprite attr write → later caused crash (Fix 65). |

55 | INPUT | Kempston port $1F removed (no joystick on 128K Toastrack). Pure O/P/Space keyboard.
   |         Note: original bit assignments wrong; corrected Fix 67.

54 | LOGIC | InitLevel ClearScreen returns A=1. Subsequent ld (var),a stored 1 not 0.
   |         Corrupted plr_dead, plr_vx, plr_vy, plr_on_ground, plr_jumping, plr_big.
   | FIX: xor a immediately after call ClearScreen.

;;; ═══════════════ FIXES 47-53 (v0.6.x) ═══════════════

53 | DRAW | No sprite erase before redraw → permanent pixel trails. Added EraseSprite with prev_sx/sy.
52 | LOGIC | level_timer=200 but DrawDecimal3 handles 0-199; 200 shows as "100". Changed to 199.
51 | DRAW | InitLevel no ClearScreen → ShowLevelEntry text persisted during gameplay.
50 | CRASH,SEVERE | UpdateCamera missing push de/push hl. Pop consumed return address → random PC.
   |               All crashes traced to this: display corruption, ROM1 exec, 48K BASIC, stuck AY.
49 | CRASH | No screen_y bounds before DrawSprite. screen_y≥177 → attr area. Added cp 176/jp nc.
48 | DRAW | LoadEnemySpawns: ent_yl=tile_y*16 placed enemy body inside ground. Fixed: sub PLR_H.
47 | PERF | RenderLevel called DrawTile for all tiles including AIR (120/frame). Added or a/jp z skip.
   |        Saves ~108K T-states/frame (>50% of frame budget recovered).

;;; ═══════════════ FIXES 40-46 (v0.5.x-0.6.x) ═══════════════

46 | BUILD | CheckWalls entry jr z offset +144 > ±127. Changed to jp z. Same routine as Fix 42a.
   |         FIX 42A DID NOT FIX THIS. Adding bytes to routine can push safe jr over limit.
45 | CRASH,SEVERE | LoadEnemySpawns pop bc inside djnz → B=pixel_x_high (often 0) → 255 extra iters.
   |               Executed level data as Z80 code; $CD $BC $83 = CALL BankSwitch → bank7 paged out.
   | FIX: push bc/pop bc wrapper around pixel_x store block inside loop.
44 | BUILD | CheckWalls entry jr z grew to +144 after Fix 43 added bytes. Changed to jp z.
43 | CRASH | HANDLER missing push iy/pop iy. RenderLevel uses IYH/IYL for tile row/col.
   |         Every RETI clobbered IY → row/col reset every frame → .rl_nextrow unreachable.
42a| BUILD | CheckWalls jr z,.cw_done +143 → jp z.
42b| BUILD | CheckEnemyPlayer jr nz,.cep_no +128 → jp nz.
41 | PERF | FONT_DATA had 520 bytes of ROM-duplicate ASCII 32-127. Removed; ROM1 font at $3D00 used.
40 | DRAW | DrawHUD showed only 2 BCD digits. Extended to 4.

;;; ═══════════════ FIXES 27-39 (v0.4.x-0.5.x) ═══════════════

39 | LOGIC | Score BCD carry not propagated between bytes in QBlockHit and stomp.
38 | DRAW | DrawPowerup used 8-bit cam_x. Fixed to 16-bit sbc.
37 | LOGIC | IsSolid clobbered A with ld a,1 → QBlock detection always failed.
36 | LOGIC | mg_respawn called InitLevel then jp .mg_level → double InitLevel.
35 | BUILD | DrawEnemies djnz loop >127 bytes. Changed to dec b / jp nz pattern.
34 | PHYSICS | No horizontal wall collision. CheckWalls added.
33 | PHYSICS | GetTileAt took C=pixel_x (8-bit). Wrong for x>255. Changed to HL=pixel_x (16-bit).
32 | DRAW | DrawPlayer used 8-bit plr_x/cam_x. Sprite teleported at x>255.
31 | DRAW | GetTileAt ld de,level_map_cache clobbered E → all tile reads 161 bytes off.
30 | AUDIO | Copyright music replaced with original AY compositions.
29 | DRAW | DrawSprite no mask: ORed pixels into background (black boxes). Added AND-NOT-OR.
28 | DRAW | DrawCharXY jr nc→jr c (inverted carry). Chars at row≥128 → attr area.
27 | DRAW | DrawTile/DrawSprite jr nc→jr c. Bottom 8 rows of any tile/sprite → attr/sysvar.
   |        ROOT CLASS: inverted carry condition at character-row-boundary branch.
   |        FULLY RESOLVED v0.7.9: DrawTile(27), DrawCharXY(28), DrawSprite(27ctx), EraseSprite(71).

;;; ═══════════════ FIXES 23-26 (v0.3.x-0.4.x) ═══════════════

26a-d| MISC | EI/RETI sequence, Space key row correction, 16-bit enemy X, SP $BF00→$BBFE.
25a-f| MISC | Nested interrupt, boot order, DoLevelBanking shim, bank2 CALL shim, map padding.
23-24| MISC | ClearScreen DI/EI wrap, DrawCharXY pin at $BFFD, turbo loader collision.

;;; ═══════════════ PENDING ═══════════════

P3 | PENDING | Full gameplay verification: all levels, enemy types, powerup, audio, HUD accuracy.
P4 | PENDING | pwrup_xl is DB (8-bit); powerups past tile 16 won't place correctly (>255 world_x).
