# Marco Bros 128 — Bug History

> Full fix history (67 fixes). See B9 in this file.
> Consult when debugging a crash pattern or investigating a regression.

## B9. KNOWN BUGS / PENDING FIXES

| # | Status | Description |
|---|--------|-------------|
| 67 | FIXED | Keyboard bit assignments wrong ($DF row): code read bit4=Y as P (right) and bit3=U as O (left). Correct: bit0=P, bit1=O. No left/right input ever worked since Fix 55. |
| 66 | FIXED | `EraseSprite` with `prev_sy=255` (Fix 62 sentinel for "not yet drawn") computes screen address `$5F00` (attr area). All 16 erase rows write through `$5B00-$5F00` including BANKM at `$5B5C`, corrupting paging on first draw frame → CPU drops to IM1, game freezes. Fixed by `cp 255 / jr z` guard before EraseSprite in DrawPlayer and DrawEnemies. |
| 65 | FIXED | DrawSprite attr write (Fix 56, extended Fix 63) caused crashes. Fix 63's 3-column write overflowed into the next attr row when sprite char col >= 30. Also redundant: ClearScreen sets ATTR_SKY for all 768 attr cells at level start; RenderLevel restores solid tile attrs every frame. Attr write removed entirely from DrawSprite. |
| 64 | FIXED | `.mg_drender` (death animation) did not call DrawEnemies. Enemy sprites left permanent pixel trails for 60 frames. Added call DrawEnemies. |
| 63 | FIXED | **CAUSED CRASH** see Fix 65. |
| 62 | FIXED | InitLevel did not reset prev screen positions. `prev_sy=0` → EraseSprite cleared top-left screen corner (HUD flicker). Changed to `prev_sy=255` sentinel. See Fix 66 for the follow-on issue. |
| 61 | FIXED | DrawSprite push/pop mismatch (Fix 56 added IY without updating pop order). Replaced IY coord storage with `ds_save_x/ds_save_y` memory vars, then in Fix 65 the attr write was removed entirely making those vars unnecessary too. |
| 60 | FIXED | `cp 177 / jp nc` guards in DrawPlayer/DrawEnemies/DrawPowerup allowed `screen_y=176`, causing DrawSprite attr write (row+1 base `$5AE0` + 32 = `$5B00`) to hit sysvars. Changed to `cp 176`. |
| 59 | FIXED | DrawSprite missing `push iy / pop iy`. Fix 56 used IYH/IYL for coord storage without preserving caller's IY. DrawEnemies stored entity index in IYL — corrupted after every DrawSprite call. |
| 58 | FIXED | `AY_Silence` had redundant 14-byte ay_buf zeroing loop. AY_WriteBuffer rewrites all 14 registers every HANDLER call. Removed loop to shrink AY_Silence and keep DS pad positive. |
| 57 | FIXED | `DS $BCC0 - $` went negative (Negative BLOCK? warning) after Fix 55 added bytes to HANDLER input section, pushing AY_Silence past $BCC0. Fixed by shrinking Fix 55 keyboard code (D accumulator) and removing AY_Silence loop (Fix 58). |
| 56 | FIXED | **LATER REMOVED (Fix 65)** DrawSprite attr write added to fix black boxes around sprites. Later found redundant (ClearScreen already sets ATTR_SKY) and caused crashes via col overflow. |
| 55 | FIXED | Kempston joystick port $1F removed (stock 128K Toastrack has no joystick port). Pure keyboard: O=left (port $DFFE bit1), P=right (bit0), Space=fire (port $7FFE bit0). Note: original Fix 55 had wrong bits (bit3/4); corrected in Fix 67. |
| 54 | FIXED | `InitLevel`: `call ClearScreen` added (Fix 51) returns A=1 (blue border). All subsequent `ld (var),a` stored 1 instead of 0 — corrupting plr_dead, plr_vx, plr_vy, plr_on_ground, plr_jumping, plr_big. Added `xor a` immediately after `call ClearScreen`. |
| 53 | FIXED | No sprite erase before redraw. Added EraseSprite calls in DrawPlayer and DrawEnemies with prev_sx/sy tracking arrays. |
| 52 | FIXED | level_timer initialised to 200 but DrawDecimal3 handles 0-199 only; 200 displayed as "100". Changed to 199. |
| 51 | FIXED | InitLevel had no ClearScreen. ShowLevelEntry text persisted on screen during gameplay. Added `call ClearScreen` at InitLevel entry. |
| 50 | FIXED | **SEVERE** `UpdateCamera` missing `push de` / `push hl` at entry. `pop de / pop hl / ret` consumed UpdateCamera's own return address (→DE), UpdatePlayer's saved AF (→HL), then jumped to UpdatePlayer's saved BC as PC. Every frame the player existed, execution jumped to a random address. Caused all observed crashes. |
| 49 | FIXED | DrawPlayer/DrawEnemies/DrawPowerup: no `screen_y` bounds check before DrawSprite. `screen_y ≥ 176` (was 177 before Fix 60) hits attr/sysvar area. Added `cp 176 / jp nc` guards. |
| 50 | FIXED | **SEVERE** `UpdateCamera` missing `push de` / `push hl` at entry. `pop de / pop hl / ret` at exit consumed UpdateCamera's own return address (→DE), UpdatePlayer's saved AF (→HL), then jumped to UpdatePlayer's saved BC as PC. Every frame the player existed, execution jumped to a random address. Caused all crashes: display corruption, ROM1 execution, 48K BASIC reset, stuck AY note. Fix: add `push de` / `push hl` at entry. |
| 49 | FIXED | `DrawPlayer`, `DrawEnemies`, `DrawPowerup`: no `screen_y` bounds check before `call DrawSprite`. `screen_y ≥ 177` causes sprite row 15 (y+15 ≥ 192) to map to `$5800` (attr/sysvar area), corrupting memory. Added `cp 177 / jp nc` guard before each `call DrawSprite`. |
| 48 | FIXED | `LoadEnemySpawns`: `ent_yl = tile_y * 16` placed enemy body-top at tile-top, body fully inside the ground row. Fixed with `sub PLR_H` after the multiply so feet sit at the tile row top. |
| 47 | FIXED | `RenderLevel` called `DrawTile` for every tile including AIR (tile_id=0, ~120/176 tiles per frame). AIR = all-zero pixels + SKY attr already set by `ClearScreen`. Added `or a / jp z, .rl_air_skip` — saves ~108K T-states/frame, bringing the game loop inside the 69,888 T-state budget. |
| 46 | FIXED | CheckWalls entry `jr z,.cw_done` offset +144 > ±127. Changed to `jp z`. Identical class of bug to Fix42a — in the same routine, three lines earlier. Fixing one out-of-range branch does NOT guarantee the rest of the routine is safe. |
| 45 | FIXED | **SEVERE** `LoadEnemySpawns`: `pop bc` inside `djnz` loop overwrote `B` (loop counter, should be 8) and `C` (entity index) with `pixel_x_high` and `pixel_x_low`. For any enemy at tile_x<16 (`pixel_x_high=0`), `djnz` decremented 0→255, running 255 extra iterations. Runaway loop executed level bank data as Z80 code; byte sequence `$CD $BC $83` in level data fired a spurious `CALL BankSwitch` with random `A`, paging out bank7 permanently. `RenderLevel` then ran in the wrong bank every frame. Fix: `push bc`/`pop bc` around the pixel_x store block to save and restore loop state. |
| 44 | FIXED | CheckWalls entry `jr z` grew to +144 bytes after Fix43 added 4 bytes to bank7. Changed to `jp z`. |
| 43 | FIXED | HANDLER missing `push iy`/`pop iy`. RenderLevel uses IYH/IYL as tile row/col counters; every RETI clobbered IY, resetting the counters and preventing `.rl_nextrow` from ever being reached. |
| 42a | FIXED | CheckWalls jr z,.cw_done offset +143 > ±127. Changed to jp z. |
| 42b | FIXED | CheckEnemyPlayer jr nz,.cep_no offset +128 > ±127. Changed to jp nz. |
| 41 | FIXED | FONT_DATA had 520 bytes of ROM-duplicate ASCII 32-127. Replaced with ROM1 font at $3D00; BANKM=$17 permanent. |
| 40 | FIXED | DrawHUD only showed 2 BCD digits. Extended to 4. |
| 39 | FIXED | Score BCD carry not propagated between bytes. Fixed in QBlockHit and stomp. |
| 38 | FIXED | DrawPowerup used 8-bit cam_x. Fixed to 16-bit sbc. |
| 37 | FIXED | IsSolid clobbered A with ld a,1. QBlock detection always failed. |
| 36 | FIXED | mg_respawn called InitLevel then jp .mg_level → double InitLevel. |
| 35 | FIXED | DrawEnemies djnz loop > 127 bytes. Changed to dec b / jp nz. |
| 34 | FIXED | No horizontal wall collision. CheckWalls added. |
| 33 | FIXED | GetTileAt took C=pixel_x (8-bit). Wrong for x>255. Now HL=pixel_x (16-bit). |
| 32 | FIXED | DrawPlayer used 8-bit plr_x/cam_x. Sprite teleported at x>255. |
| 31 | FIXED | GetTileAt ld de,level_map_cache clobbered E. All tile reads 161 bytes off. |
| 30 | FIXED | Copyright music replaced with original AY compositions. |
| 29 | FIXED | DrawSprite no mask — ORed pixels into background. Added AND-NOT-OR. |
| 28 | FIXED | DrawCharXY jr nc→jr c (inverted). Chars at row≥128 → attr area. |
| 27 | FIXED | DrawTile/DrawSprite jr nc→jr c. 3rd+ tiles to attr/sysvar area. |
| 26a-d | FIXED | EI/RETI, Space key row, 16-bit enemy X, SP $BF00→$BBFE. |
| 25a-f | FIXED | Nested interrupt, boot order, DoLevelBanking shim, map padding. |
| 23-24 | FIXED | ClearScreen DI/EI, DrawCharXY pin, turbo loader collision. |
| P3 | PENDING | Full gameplay verification: movement, AI, collision, audio |
| P4 | PENDING | pwrup_xl is DB (8-bit); powerups past tile 16 won't place correctly |

---

