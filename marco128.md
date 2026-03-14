# MARCO BROS 128 — Project Reference
*Project-specific data: addresses, contracts, bugs, game state.*
*See architecture.md for ZX Spectrum 128K hardware reference.*
*See lessons.md for reusable Z80 coding rules and gotchas.*
*Last updated: v0.7.7*

---

## SECTION B — MARCO BROS 128 PROJECT SPECIFICS

## B1. HARDWARE TARGET (project instance)
- ZX Spectrum 128K Toastrack
- AY-3-8912 sound chip via ports $FFFD (register select) / $BFFD (register write)
- Display: Bank 5 at $4000–$57FF (pixel) + $5800–$5AFF (attr), 256×192, 15 colours
- No shadow screen (bit 3 of $7FFD = 0 always)
- No +2A/+3 features

---

## B2. MEMORY MAP (project)

```
$0000–$3FFF  ROM          ROM1 (48K BASIC) permanent via BANKM=$17
$4000–$7FFF  BANK 5 fixed Screen + sysvars + IM2 table
$8000–$BFFF  BANK 2 fixed Engine, physics, renderer, music, SFX, handler
$C000–$FFFF  BANKABLE     Bank 7 always during play; 0/1/3 paged during InitLevel only
```

### Bank 5 layout ($4000–$7FFF, fixed)
```
$4000–$57FF  Display file (pixels)
$5800–$5AFF  Attribute file
$5B5C        BANKM sysvar = $17 (initialised by make_szx.py and GAME_START)
$5B00–$7DFF  Sysvars (unused by game, present for 128K ROM compatibility)
$7E00–$7F00  IM2 vector table — 257 bytes, all $BC
             Written by make_szx.py at build time + verified by Setup_IM2 at runtime
```

### Bank 2 layout ($8000–$BFFF, fixed, always present)
```
DRIFT WARNING: Exact variable addresses below $8800 shift whenever any variable
is added or resized. Treat all addresses in the variables block as APPROXIMATE
(marked ~). Use label names in code, never hardcoded addresses. The three fixed
anchors that never drift are: $8000 (entry stub), $8800 (TILE_DATA, ORG-pinned),
and $8E00 (FONT_DATA, ORG-pinned). Everything between $8000 and $8800 is a
floating variable block — rely on labels, not addresses.

$8000        Entry stub:    ld a,2 / out($FE),a (red border) / JP GAME_START
~$8003+      [VARIABLE BLOCK — all addresses approximate, drift with every edit]
             PLAYER STATE:  plr_x(DW), plr_y(DW), plr_vx, plr_vy, plr_dir,
                            plr_anim, plr_anim_cnt, plr_on_ground, plr_jumping,
                            plr_dead, plr_dead_timer, plr_big, plr_inv_timer
             CAMERA:        cam_x(DW), cam_max(DW)
             GAME STATE:    game_state, score(DS4), lives, coins, world,
                            level_num, level_timer(DW), timer_cnt
             LEVEL:         cur_level_bank, cur_level_map(DW)
             ENTITIES:      ent_type(DS8), ent_xl(DS8), ent_xh(DS8),
                            ent_yl(DS8), ent_yh(DS8), ent_vx(DS8),
                            ent_state(DS8), ent_anim(DS8), ent_anim_cnt(DS8)
             POWERUP:       pwrup_xl, pwrup_xh, pwrup_yl, pwrup_active, pwrup_vy
             INPUT:         joy_held, joy_new, joy_prev
             SYSTEM:        frame_count(DW), ay_buf(DS14)
             SFX:           sfx_active, sfx_ptr(DW), sfx_frame
             MUSIC:         music_ptr(DW), music_note_ptr(DW), music_frame,
                            music_playing
             RENDER:        cam_tile_x, cam_sub_x, bankswitch_ok
$80A3        level_map_cache  DS 704 (MAP_W×MAP_H = 64×11) — v0.7.7 listing confirmed
                              Immediately follows variable block; drifts with it.
$8375        GAME_START     di; ld sp,$BBFE; ld a,$17; ld($5B5C),a;  — v0.7.7 listing
                            ld a,1; ld(bankswitch_ok),a;
                            call Setup_IM2; call ClearScreen; call AY_Silence; jp MainLoop
$838F        Setup_IM2      Fills $7E00 with $BC×257; writes JP $BC00 at $BCBC; ld i,$7E; im 2; ei; ret  — v0.6.5
$83CB        DoLevelBanking BankSwitch(cur_level_bank)→LoadLevelMap→LoadEnemySpawns→BankSwitch(7) — v0.6.5
$842E        [FREE GAP]     Stack headroom begins here (end of LoadEnemySpawns in v0.6.5)
                            SP=$BBFE grows DOWN toward this address. ~15KB headroom.

$8800        TILE_DATA      PINNED (ORG $8800). 10 tiles × 32 bytes (16×16 px, 2 bitplanes)
~$8940       SPRITE_DATA    Multiple sprites × 32 bytes each (13 sprites total)
$8E00        FONT_DATA      PINNED (ORG ENGINE_BASE+$0E00). Custom chars ASCII 128-255.
                            Fix41: ASCII 32-127 removed — ROM1 font at $3D00 used instead.

             [FREE GAP — between FONT_DATA end and HANDLER. Grows/shrinks with music/SFX data.]
~$BF??       MUSIC_TITLE    AY music data — title theme (original composition)
~$BF??       MUSIC_OVERWORLD
~$BF??       MUSIC_BOSS
~$BF??       SFX_DATA       SFX table (8 entries × 2 bytes) + SFX frame data

$BC00        HANDLER        PINNED (ORG HANDLER_ADDR). IM2 interrupt handler, ~50Hz.
$BCBC        IM2_JUMP       PINNED. C3 00 BC = JP $BC00 (pre-written by make_szx.py)
$BCC0        AY_WriteBuffer PINNED (DS pad before it). Writes ay_buf[0..13] via OUT
$BCDB        Music_Init     HL=music data ptr, sets music_ptr, music_playing=1
$BCEB        Music_Stop     Sets music_playing=0, calls AY_Silence
$BCF3        Music_Tick     Advances music by one frame (reads note, writes ay_buf)
$BD62        SFX_Play       A=sfx index; sets sfx_ptr, sfx_active=1
$BD7F        SFX_Tick       Advances SFX by one frame (overwrites ay_buf ch C)
$BFA5        BankSwitch     A=bank number; guards on bankswitch_ok; reads BANKM; OUT $7FFD
$BFC5        ClearScreen    di; clear pixels+attrs via LDIR×2; out blue; ei; ret
$BFFD        DrawCharXY     PINNED (ORG $BFFD). JP DrawCharXY_Real — last 3 bytes of bank2
```

### Bank 7 layout ($C000–$FFFF, always paged during play)
```
$C000        DrawCharXY_Real  B=col, C=row, A=char
                             Fix41: A<128→ROM1 font ($3D00+(A-32)*8); A>=128→FONT_DATA+((A-128)*8)
$C05E        DrawString       HL=null-terminated string, B=col, C=row
~$C200       DrawTile         16×16 tile blit
~$C400       DrawSprite       IX=sprite, B=pixel_y, C=pixel_x; mask+OR blit
~$C500       UpdatePlayer     Input→physics→position
~$C6A0       UpdateEnemies    Entity array walk
~$C800       CheckCollisions
~$C900       DrawPowerup
~$C98C       DrawHUD          Score(4 BCD digits), lives, coins, timer
~$CBA0       InitGame         lives=3, score=0, world=0, level=0
$CBBC        InitLevel        game_state=PLAYING; DoLevelBanking; Music_Init(OVERWORLD)
$CC4E        MainLoop         Title→InitGame→ShowLevelEntry→InitLevel→frame loop
```

### Banks 0, 1, 3 — Level Data (paged only during InitLevel)
```
$C000  WxL1_MAP    704 bytes (64×11 tile IDs)
$C2C0  WxL2_MAP    704 bytes
$C580  WxL3_MAP    704 bytes
$C840  Wx_SPAWNS   spawn table: ENT_TYPE(1), TILE_X(1), TILE_Y(1) per entry, $FF terminated
                   Each level slot = 32 bytes (padded with DS zeros)
```

---

## B3. INTERRUPT HANDLER — $BC00

```
di / push af,bc,de,hl,ix,iy (SP-12)  [Fix43: push iy added — RenderLevel uses IYH/IYL as row/col counters]
inc frame_count
if STATE_PLAYING: tick level_timer
read Kempston $1F; AND $1F; if $1F zero it
read Space: LD A,$7F / IN A,($FE); bit 0 → fire flag
compute joy_new/joy_held/joy_prev
if music_playing: Music_Tick
if sfx_active: SFX_Tick
AY_WriteBuffer
pop iy,ix,hl,de,bc,af (SP+12)
ei / reti
```
Stack: perfectly balanced. DI at entry zeros IFF2; EI before RETI restores it (Fix26a).
Fix43: missing push iy/pop iy caused RETI to clobber IYH/IYL on every frame interrupt,
resetting the RenderLevel row/col counters and preventing .rl_nextrow from being reached.

---

## B4. BANKSWITCH SYSTEM

```
BankSwitch(A=bank):
  ld a,(bankswitch_ok) / or a / ret z     ; guard
  ld b,a (save bank)
  ld a,($5B5C) / and $F8 / or b           ; preserve bits[7:3], set [2:0]
  ld ($5B5C),a / ld bc,$7FFD / out(c),a

DoLevelBanking (MUST be in bank2):
  BankSwitch(cur_level_bank) → LoadLevelMap → LoadEnemySpawns → BankSwitch(7)
  Returns to InitLevel in bank7 (now restored).
```

---

## B5. TILE AND SPRITE FORMATS

```
Tile:   16×16 pixels, 2 bitplanes, 32 bytes
        Plane 0: bytes 0–15  (pixel rows 0–15, 1 byte = 8 pixels, MSB=left)
        Plane 1: bytes 16–31 (same rows, second 8 pixels)
        → full 16 pixels per row across 2 bytes (big-endian pixel order)

Sprite: same 16×16×2 bitplane format
        Rendering: screen = (screen AND NOT mask) OR pixels
        mask = complement of pixels (1 where sprite transparent)
        Fix29: masking added — previously just OR'd, merged with background
```

---

## B6. GETTIILEAT INTERFACE (Fix33)

```
GetTileAt: HL=world_pixel_x (16-bit), B=world_pixel_y → A=tile_id
  Reads level_map_cache at $8096.
  tile_x = HL>>4 (= HL/16, 6-bit result for MAP_W=64)
  tile_y = B>>4  (= B/16,  4-bit result for MAP_H=11)
  offset = tile_y*64 + tile_x
  Returns: A = tile_id (0=AIR, 1=GND, 2=BRICK, 3=QBLOCK, 4=PIPE_T,
                        5=PIPE_B, 6=FLAG, 7=SOLID, 8=QUSED, 9=CASTLE)
  Pushes BC to preserve caller's B (pixel_y). Fix33.
  Called by: CheckGround, CheckCeiling, CheckLevelEnd, CheckWalls (Fix34)
```

---

## B7. SCORE SYSTEM

```
score: DS 3  (3 BCD bytes, 6 decimal digits total)
  score[0] = ones + tens     (BCD: $00–$99)
  score[1] = hundreds + thousands
  score[2] = ten-thousands + hundred-thousands

QBlockHit: ADD score[0],$50 / DAA; carry→ADD score[1],$01/DAA  (Fix39)
Stomp:     ADD score[1],$01 / DAA; carry→ADD score[2],$01/DAA  (Fix39)
DrawHUD:   Displays 4 digits: score[1] hi nibble, score[1] lo, score[0] hi, score[0] lo (Fix40)
```

---

## B8. BUILD PIPELINE

```
sjasmplus --nologo --lst=build/marco128.lst src/marco128.asm
  → build/bank{0,1,2,3,7}.bin  (SAVEBIN directives at end of each PAGE section)
  → build/marco128.lst

python3 tools/make_szx.py
  reads: tools/128k_power_on.szx (FUSE power-on snapshot template, machine type 2)
         build/bank{0,1,2,3,7}.bin
  writes: build/marco128.szx
  signature scan: F3 31 FE BB (DI + LD SP,$BBFE) in bank2 → PC = that address

Open build/marco128.szx in FUSE: File → Open
```

ZXST Z80R register offsets (Fix43 — corrected):
```
SP=[20-21]  PC=[22-23]  I=[24]  IFF1=[26]  IFF2=[27]  IM=[28]
```

---

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

## B10. DEBUG BORDER COLOURS

```
1 Blue    = TitleScreen
2 Red     = InitGame  (also: entry stub at $8000 flashes red to confirm bank2 reached)
3 Magenta = ShowLevelEntry
4 Green   = InitLevel
5 Cyan    = Game frame loop running
```

---

## B11. SUBROUTINE CONTRACTS (API TABLE)
## Ground truth extracted from marco128.asm v0.7.7.
## Format: IN / OUT / CLOBBERS / SIDE-EFFECTS / GLOBALS-WRITTEN
## "Clobbers" = register value on return differs from value on entry.
## Registers not listed = preserved (pushed/popped internally).
## ─────────────────────────────────────────────────────────────

DrawCharXY        (trampoline $BFFD → DrawCharXY_Real $C000, bank7)
  IN:       A=char_code (32-127 → ROM1 font; 128-255 → FONT_DATA)
            B=col (0..31)  C=row (0..23)
  OUT:      none
  CLOBBERS: nothing  (pushes/pops AF,IX,BC,DE,HL)

DrawString        ($C06E, bank7)
  IN:       HL=ptr to null-terminated string  B=col  C=row
  OUT:      none
  CLOBBERS: HL (advanced past null terminator)
  NOTE:     AF,BC preserved via push/pop. B on return = original B (restored).

DrawTile          ($C224, bank7)
  IN:       A=tile_id (0-9)  B=screen_pixel_x (must be mult of 8)
            C=screen_pixel_y (must be mult of 8)
  OUT:      none
  CLOBBERS: nothing  (pushes/pops AF,IY,IX,BC,DE,HL)

DrawSprite        ($C4A8, bank7)
  IN:       IX=sprite data ptr (32-byte block, 16 rows × 2 bytes)
            B=screen_pixel_x  C=screen_pixel_y
  OUT:      none
  CLOBBERS: AF  (pushes/pops IX,BC,DE,HL — balanced; IY never touched)
  NOTE:     OR-mask blit: (screen AND ~pixel) OR pixel. Transparent where pixel=0.
            Does NOT write attr cells — ClearScreen sets ATTR_SKY for all cells
            at level start; RenderLevel maintains solid tile attrs each frame.
            Guard callers with cp 176 / jp nc before calling (screen_y=176+ unsafe).

RenderLevel       ($C2BA, bank7)
  IN:       none
  OUT:      none
  CLOBBERS: nothing  (pushes/pops IY,IX,BC,DE,HL)
  GLOBALS:  writes cam_tile_x, cam_sub_x

GetTileAt         (bank2, addr from listing)
  IN:       HL=world_pixel_x (16-bit, 0..1023)
            B=world_pixel_y  (8-bit)
  OUT:      A=tile_id (TILE_GROUND returned for out-of-bounds coords)
  CLOBBERS: AF  (A=return value; pushes/pops BC,DE,HL — all preserved)
  NOTE:     Reads level_map_cache in bank2. No paging required.

IsSolid           (bank2)
  IN:       A=tile_id
  OUT:      Z=passable (AIR=0 or FLAG=6)  NZ=solid
            A preserved (Fix 37 — cp TILE_FLAG leaves A intact)
  CLOBBERS: F only

CheckGround       ($C6C5, bank7)
  IN:       none (reads plr_x, plr_y globals)
  OUT:      none
  CLOBBERS: AF  (pushes/pops BC,DE,HL)
  GLOBALS:  writes plr_y, plr_vy, plr_on_ground, plr_jumping

CheckCeiling      ($C710, bank7)
  IN:       none (reads plr_x, plr_y globals)
  OUT:      none
  CLOBBERS: AF, DE  (pushes/pops BC,HL only)
  GLOBALS:  writes plr_vy, plr_y; may call QBlockHit → writes score,coins; SFX_Play

CheckWalls        ($C75E, bank7)
  IN:       none (reads plr_vx, plr_x, plr_y globals)
  OUT:      none
  CLOBBERS: AF  (pushes HL, BC, DE on entry; pops DE, BC, HL on exit — all preserved)
  GLOBALS:  writes plr_x, plr_vx
  NOTE Fix42a/46: routine has multiple branches to .cw_done; ALL were measured and
    two required jp (not jr): entry jr z (+144) and right-probe jp z (+143).
    When adding any new branch to .cw_done, verify distance before using jr.

UpdatePlayer      ($C570, bank7)
  IN:       none (reads joy_held, joy_new, plr_* globals)
  OUT:      none
  CLOBBERS: DE  (pushes/pops HL,BC,AF)
  GLOBALS:  writes plr_x, plr_y, plr_vx, plr_vy, plr_on_ground, plr_jumping,
            plr_dir, plr_anim, plr_anim_cnt, plr_dead; calls UpdateCamera (cam_x)

UpdateCamera      (~$C7FC, bank7) — INTERNAL, called only from UpdatePlayer
  IN:       none (reads plr_x, cam_x, cam_max)
  OUT:      none
  CLOBBERS: AF  (push de / push hl at entry; pop de / pop hl / ret at exit — balanced Fix50)
  GLOBALS:  writes cam_x
  NOTE Fix50: Previously missing push de / push hl at entry. The unmatched pop de / pop hl
            consumed UpdateCamera's own return address and UpdatePlayer's saved AF from the
            stack; ret then jumped to UpdatePlayer's saved BC as the program counter — a
            random address every frame. Fixed v0.6.8 by adding push de / push hl at entry.

UpdateEnemies     (~$C6A0, bank7)
  IN:       none
  OUT:      none
  CLOBBERS: AF, DE, IX  (pushes/pops BC,HL)
  GLOBALS:  writes ent_xl,ent_xh,ent_yl,ent_vx,ent_state,ent_anim,ent_anim_cnt

CheckEnemyPlayer  (bank7) — called from within UpdateEnemies loop only
  IN:       C=entity index (set by UpdateEnemies; must not be changed before call)
  OUT:      none
  CLOBBERS: AF, DE  (pushes/pops BC,HL)
  GLOBALS:  may write ent_state[c]=0, plr_vy, score, plr_big, plr_inv_timer;
            may call PlayerDie, SFX_Play

DrawEnemies       (~$C??? bank7)
  IN:       none (reads ent_* arrays, cam_x)
  OUT:      none
  CLOBBERS: AF, DE, HL  (pushes/pops BC,IX,IY)

DrawPlayer        (~$C860, bank7)
  IN:       none (reads plr_*, cam_x)
  OUT:      none
  CLOBBERS: AF, DE, HL  (pushes/pops IX,BC)

BankSwitch        ($BFA5, bank2)
  IN:       A=bank number (0-7)
  OUT:      none
  CLOBBERS: nothing  (pushes/pops BC,AF)
  SIDE-FX:  DI on entry; EI on exit ALWAYS regardless of IFF state on entry.
            Writes $5B5C (BANKM) and port $7FFD.
  GUARD:    if bankswitch_ok=0, skips port write (no-op in 48K mode).

Music_Init        ($BCDB, bank2)
  IN:       HL=music data pointer
  OUT:      none
  CLOBBERS: AF
  GLOBALS:  writes music_ptr, music_note_ptr, music_frame, music_playing=1

Music_Stop        ($BCEB, bank2)
  IN:       none
  OUT:      none
  CLOBBERS: AF, BC, HL  (via AY_Silence)
  GLOBALS:  writes music_playing=0; calls AY_Silence (zeros ay_buf, silences AY)

Music_Tick        ($BCF3, bank2) — called from HANDLER only
  IN:       none (reads music_note_ptr, music_frame, music_ptr)
  OUT:      none
  CLOBBERS: AF  (pushes/pops BC,DE,HL)
  GLOBALS:  writes ay_buf[0..1,8..10,7] (tone, vol, mixer for ch A)

SFX_Play          ($BD62, bank2)
  IN:       A=SFX index (SFX_JUMP=0..SFX_LEVELEND=7)
  OUT:      none
  CLOBBERS: AF  (pushes/pops DE,HL)
  GLOBALS:  writes sfx_ptr, sfx_frame, sfx_active=1

SFX_Tick          ($BD7F, bank2) — called from HANDLER only
  IN:       none (reads sfx_ptr, sfx_frame)
  OUT:      none
  CLOBBERS: AF  (pushes/pops BC,DE,HL)
  GLOBALS:  writes ay_buf[4,5,10,7] (ch C tone, vol, mixer)

AY_WriteBuffer    ($BCC0, bank2)
  IN:       none (reads ay_buf[0..13])
  OUT:      none
  CLOBBERS: AF, BC, HL  (uses push bc/pop bc inside loop only)
  SIDE-FX:  writes AY registers 0..13 via OUT

AY_Silence        (bank2)
  IN:       none
  OUT:      none
  CLOBBERS: AF, BC, HL
  GLOBALS:  zeros ay_buf[0..13]; sets ay_buf[AY_MIXER]=$FF
  SIDE-FX:  immediately silences AY via OUT (R7=$FF, vol A/B/C=0)

LoadEnemySpawns   ($83DD, bank2) — called only from DoLevelBanking
  IN:       none (reads cur_level_bank's data at $C000+ while level bank paged)
  OUT:      none
  CLOBBERS: AF, BC, DE, HL (all consumed internally; not push/pop balanced — caller must not rely on them)
  GLOBALS:  writes ent_type[0..7], ent_xl[0..7], ent_xh[0..7], ent_yl[0..7],
            ent_vx[0..7], ent_state[0..7]
  CRITICAL Fix45: This routine uses a djnz loop with B=loop_counter and C=entity_index.
    Any push/pop pair inside the loop MUST NOT allow a pop to land in BC if the
    popped value is pixel or coordinate data. The Fix45 regression: pop bc retrieved
    pixel_x bytes into B and C, corrupting the loop counter (B=0→djnz ran 255 extra
    times) and entity index (C=garbage). Rule: ALWAYS wrap push/pop for coordinate
    temporaries with an outer push bc / pop bc to preserve the loop state.

ClearScreen       ($BFC5, bank2)
  IN:       none
  OUT:      none
  CLOBBERS: AF, BC, DE, HL
  SIDE-FX:  DI on entry; EI on exit; sets border=blue (colour 1)
  GLOBALS:  clears $4000-$57FF (pixels) and $5800-$5AFF (attrs, all=ATTR_SKY)

Setup_IM2         ($838F, bank2)
  IN:       none
  OUT:      none
  CLOBBERS: AF, BC, HL
  SIDE-FX:  DI then EI; sets I=$7E; switches to IM2
  GLOBALS:  fills $7E00-$7F00 with $BC; writes JP $BC00 at $BCBC

DrawHUD           (~$C98C, bank7)
  IN:       none (reads score, lives, coins, world, level_num, level_timer)
  OUT:      none
  CLOBBERS: AF, DE  (pushes/pops HL,BC)

---

## B12. ENTITY SOA (STRUCTURE OF ARRAYS) LAYOUT

## ══════════════════════════════════════════════════════════════
## CRITICAL: AoS POINTER MATH IS BANNED. ALWAYS USE SoA INDEXING.
## ══════════════════════════════════════════════════════════════
## AI models are heavily biased toward C-style Array-of-Structs (AoS) because
## nearly all training data uses it. This game uses Structure-of-Arrays (SoA).
## These are INCOMPATIBLE. AoS math will corrupt unrelated entity fields silently.
##
## AoS math looks like:  ld hl, entity_base
##                        ld de, ENTITY_STRUCT_SIZE   ; e.g. 9 bytes per entity
##                        ld b, index
##                        (multiply or loop to offset into struct)
##                        ld a, (hl + FIELD_OFFSET)
## THIS IS WRONG. There is no entity struct. There is no ENTITY_STRUCT_SIZE.
## Do NOT multiply an entity index by any struct size. EVER.
##
## SoA math looks like:  ld hl, ent_state    ; choose the array for the field you want
##                        ld d, 0
##                        ld e, c             ; C = entity index (0..MAX_ENEMIES-1)
##                        add hl, de          ; HL = &ent_state[c]
##                        ld a, (hl)
## THIS IS THE ONLY CORRECT PATTERN. Use it for every entity field access.
## ══════════════════════════════════════════════════════════════

MAX_ENEMIES = 8  (indices 0..7)
Entity index C (0..7) is the ONLY indexing key. All arrays are MAX_ENEMIES bytes.

SoA ARRAYS (all in bank2, fixed):
  ent_type[MAX_ENEMIES]      ENT_WALKER=1, ENT_SHELLER=2, ENT_BOSS=3; 0=unused
  ent_xl[MAX_ENEMIES]        world_x low byte (pixel x, low 8 bits)
  ent_xh[MAX_ENEMIES]        world_x high byte (pixel x >> 8; normally 0 or 1-3)
  ent_yl[MAX_ENEMIES]        world_y (pixel y, always fits 8 bits; no ent_yh)
  ent_vx[MAX_ENEMIES]        velocity x: $FF=-1 (left), $01=+1 (right), 0=uninit
  ent_state[MAX_ENEMIES]     0=dead/inactive, 1=active. No other values.
  ent_anim[MAX_ENEMIES]      animation frame index (0 or 1; toggles every 8 frames)
  ent_anim_cnt[MAX_ENEMIES]  animation frame counter (0..7; incremented each frame)

STANDARD INDEXING PATTERN (C = entity index, preserved across the pattern):
  ld d, 0             ; D = 0 for 16-bit DE offset
  ld e, c             ; E = entity index
  ld hl, ent_state    ; (or any other SoA array base)
  add hl, de          ; HL = &ent_state[c]
  ld a, (hl)          ; read ent_state[c]

16-BIT X POSITION (ent_xh:ent_xl):
  Always load/store both bytes. ld ixh/ixl via A (direct ld ixl,(hl) is illegal Z80):
  ld hl, ent_xl / add hl, de / ld a, (hl) / ld ixl, a
  ld hl, ent_xh / add hl, de / ld a, (hl) / ld ixh, a

ENT_STATE VALUES:
  0 = dead / inactive — entity is skipped by UpdateEnemies and DrawEnemies.
      LoadEnemySpawns zeros all slots before filling. Stomped enemies set to 0.
  1 = active — entity updates and draws normally. LoadEnemySpawns sets this.
  No other state values exist. There is no "stunned", "dying", or "spawning" state.

CLEARING ALL ENTITIES (as in InitLevel):
  ld hl, ent_state / ld de, ent_state+1 / ld bc, MAX_ENEMIES-1 / ld (hl),0 / ldir
  Repeat for ent_type. Other arrays (xl,xh,yl,vx,anim,anim_cnt) are overwritten
  by LoadEnemySpawns so need not be explicitly cleared.

ENT_TYPE VALUES:
  0 = empty (slot unused)
  ENT_WALKER=1   two-frame walk animation, bounces left/right at map edges
  ENT_SHELLER=2  shell enemy, same movement as walker, different sprite
  ENT_BOSS=3     boss enemy, same movement; SPR_BOSS1/SPR_BOSS2

---

## B13. CROSS-BANK CALL GRAPH — RULES OF ENGAGEMENT
## Paging crashes are the most common 128K pitfall. Follow these rules exactly.

RULE 1 — BANK 7 MAY FREELY CALL BANK 2:
  Code at $C000-$FFFF may call any routine at $8000-$BFFD.
  Bank 2 is always present (fixed). These calls are always safe.
  Examples: DrawCharXY (trampoline in bank2 → DrawCharXY_Real in bank7 is special),
            CheckGround, GetTileAt, BankSwitch, Music_Init, SFX_Play, AY_Silence.

RULE 2 — BANK 2 MUST NOT ASSUME BANK 7 IS PAGED IN:
  Code in bank2 ($8000-$BFFF) executes during BankSwitch when bank7 is NOT present.
  DoLevelBanking, LoadLevelMap, LoadEnemySpawns, SetLevelMapPtr all run in bank2
  specifically because they execute while the level data bank (0/1/3) is paged,
  meaning bank7 is absent.
  → Never add calls from bank2 to bank7 routines unless bank7 is guaranteed present.
  → The interrupt handler HANDLER ($BC00, bank2) runs at any time — it must NEVER
     call bank7 code.

RULE 3 — BANK 7 CODE MUST NEVER WRITE TO PORT $7FFD:
  All paging MUST go through BankSwitch (bank2, $BFA5).
  If bank7 code writes to $7FFD directly it pages out itself mid-execution → crash.
  The only legitimate bank switch during gameplay is DoLevelBanking, called from
  InitLevel (bank7) which immediately calls BankSwitch (bank2) → safe shim.

RULE 4 — INTERRUPT HANDLER IS BANK-AGNOSTIC:
  HANDLER at $BC00 (bank2) fires regardless of which bank is paged at $C000.
  It calls only bank2 routines: Music_Tick, SFX_Tick, AY_WriteBuffer.
  NEVER add calls to bank7 routines inside HANDLER.

RULE 5 — LEVEL DATA BANKS (0,1,3) ARE READ-ONLY AND TRANSIENT:
  Banks 0,1,3 are paged in only during DoLevelBanking (inside InitLevel).
  After DoLevelBanking returns, bank7 is always restored.
  Level data is copied to level_map_cache (bank2) — access it via GetTileAt,
  NEVER by paging in the level bank during gameplay.

QUICK REFERENCE:
  Bank7 → Bank2:  always safe (call directly)
  Bank2 → Bank7:  NEVER (bank7 may not be present)
  Bank7 → $7FFD:  NEVER (use BankSwitch in bank2)
  HANDLER → Bank7: NEVER

---

## B14. GAME STATE MACHINE
## game_state (DB, bank2 variable) holds current state.
## The main frame loop (MainLoop/.mg_frame) dispatches on game_state each HALT.

STATE VALUES:
  STATE_TITLE    = 0   (initial value at boot; not used for frame dispatch)
  STATE_PLAYING  = 1
  STATE_DEAD     = 2
  STATE_LEVELEND = 3
  STATE_GAMEOVER = 5   (note: 4 is unused)
  STATE_WIN      = 6

FLOW GRAPH:
  [BOOT] → GAME_START → Setup_IM2 → ClearScreen → AY_Silence → MainLoop

  MainLoop:
    → TitleScreen (unconditional; halts until Fire pressed; plays MUSIC_TITLE)
    → InitGame (lives=3, score=0, coins=0, world=0, level_num=0)
    → .mg_level:
        → ShowLevelEntry (100-frame splash, border=magenta)
        → InitLevel (resets player, loads map+spawns via DoLevelBanking,
                     starts music, sets STATE_PLAYING, border=green)
        → .mg_frame: [HALT each frame]

  STATE_PLAYING (normal gameplay):
    Each frame: UpdatePlayer → UpdateEnemies → UpdatePowerup → CheckLevelEnd
                → timer check → RenderLevel → DrawPowerup → DrawEnemies
                → DrawPlayer → DrawHUD
    Transition triggers:
      PlayerDie()     → STATE_DEAD   (plr_dead=1, plr_dead_timer=0, SFX_DIE,
                                      Music_Stop, plr_vy=-8)
      CheckLevelEnd() → STATE_LEVELEND (player touches TILE_FLAG, SFX_LEVELEND)
      level_timer==0  → PlayerDie() → STATE_DEAD

  STATE_DEAD:
    Each frame: inc plr_dead_timer; death bounce animation; RenderLevel+DrawPlayer+DrawHUD
    Frames 0-24:  plr_y -= 3  (bounce up)
    Frames 25-59: plr_y += 4  (fall)
    Frame 60+:    → .mg_respawn
      dec lives
      lives == 0 → STATE_GAMEOVER → ShowGameOver → jp .mg_restart (→ TitleScreen)
      lives > 0  → STATE_PLAYING; jp .mg_level (→ ShowLevelEntry → InitLevel)

  STATE_LEVELEND:
    100-frame wait (djnz with halt), then:
    inc level_num
    level_num == 3 → level_num=0; inc world
      world >= 3 → STATE_WIN → ShowVictory → jp .mg_restart (→ TitleScreen)
      world < 3  → STATE_PLAYING; jp .mg_level
    level_num < 3  → STATE_PLAYING; jp .mg_level

  STATE_GAMEOVER:
    ShowGameOver: 120-frame wait then halt until Fire pressed
    → jp .mg_restart → TitleScreen (full restart, score/lives NOT reset here —
      InitGame is called after TitleScreen exits)

  STATE_WIN:
    ShowVictory: 256-frame halt loop + MUSIC_TITLE, then Music_Stop
    → jp .mg_restart → TitleScreen

NOTES:
  - STATE_TITLE (0) is NOT dispatched in the frame loop. The title screen is
    entered via unconditional call from MainLoop, not via game_state check.
    If game_state ever reads 0 inside .mg_frame (e.g. after boot before first
    InitLevel), the frame loop falls through to jp .mg_frame (nop-loops).
  - ShowLevelEntry is a screen/wait function, NOT a state. It has no STATE_* value.
  - There is no PAUSE state.
  - Adding a new state: add EQU constant, add cp STATE_NEW/jp .mg_newstate branch
    in .mg_other, add handler code, set game_state = STATE_NEW at transition point.

---

## B15. DEBUG BORDER COLOUR MAP (expanded)
## (Previously B10 — unchanged, retained here for completeness)
```
1 Blue    = TitleScreen (MainLoop entry + ClearScreen + GAME_START $8000 stub omits this)
2 Red     = InitGame (.mg_restart)
3 Magenta = ShowLevelEntry (.mg_level)
4 Green   = InitLevel (.mg_level, after ShowLevelEntry)
5 Cyan    = Game frame loop running (.mg_frame entry)
```
Entry stub at $8000: flashes border=2 (red) to confirm CPU reached bank2.
ClearScreen: sets border=1 (blue) on exit.

---
*End of architecture.md — update every time code changes.*

---

## ══════════════════════════════════════════════════════════════
