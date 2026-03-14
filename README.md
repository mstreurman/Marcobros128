# MARCO BROS 128
### An original 8-bit platformer for ZX Spectrum 128K Toastrack
*Inspired by classic side-scrolling platformers of the 1980s.*

**Current version: v0.7.7**

---

## OVERVIEW

A complete 3-world × 3-level-per-world (9 levels total) side-scrolling platformer
for the ZX Spectrum 128K Toastrack. The last level of each world is a boss battle.
All assets (code, music, graphics) are original works — no Nintendo IP.

**Target hardware:** ZX Spectrum 128K Toastrack — no expansions, no interfaces.  
**Assembler:** sjasmplus (z00m fork, v1.22.0+)  
**Snapshot tool:** `make_szx.py` — builds a FUSE-compatible `.szx` snapshot from scratch (no template required)  
**Testing:** FUSE emulator with PC-sampling profiler output  

---

## GAMEPLAY

**Controls (keyboard only — no joystick):**
- **O** — move left
- **P** — move right
- **Space** — jump (hold for variable height)

**Objective:** Reach the exit flag at the end of each level within the time limit.

**Enemies:**
- **Walker** — marches left/right, stomp to defeat, awards 100 points
- **Sheller** — walks, shell slides when stomped, awards 200 points
- **Boss** — appears in level X-3, takes 3 stomps, awards 5000 points

**Powerups:**
- **Power-up mushroom** — makes Marco bigger (one extra hit before death)
- **Coin** — 10 points, collect 100 for extra life

**Scoring:**
- Stomp Walker: 100
- Stomp Sheller: 200
- Boss hit: 500
- Boss defeated: 5000
- Coin: 10
- Q-Block reveal: 50
- Level end: time_remaining × 50

---

## MEMORY MAP

```
$0000-$3FFF  ROM1 (48K BASIC ROM) — permanent via BANKM=$17
             Font at $3D00 (used by DrawCharXY_Real)
$4000-$7FFF  BANK 5 (fixed) — Screen ($4000-$57FF) + Attrs ($5800-$5AFF)
             Sysvars ($5B00+), IM2 vector table at $7E00 (257 × $BC)
$8000-$BFFF  BANK 2 (fixed) — Engine, HANDLER, music, SFX, BankSwitch
$C000-$FFFF  BANKABLE — Bank 7 always during play; Banks 0/1/3 during level load only
Stack: $BBFE downward (~15KB free gap $842E-$BBFE)
```

### Bank Layout

| Bank | Contents | Contended? |
|------|----------|-----------| 
| 0 | World 1 map + spawn tables | No |
| 1 | World 2 map + spawn tables | Yes (data only) |
| 2 | Main engine (FIXED) | No |
| 3 | World 3 map + spawn tables | No |
| 5 | Screen + sysvars + IM2 table (FIXED) | Yes |
| 7 | Game logic, UI, tile/sprite rendering | Yes (code) |

### Key Addresses — Bank 2 ($8000-$BFFF)

```
$8000  Entry stub (jp GAME_START)
$8375  GAME_START     di; ld sp,$BBFE; setup bankswitch; call ClearScreen;
                      call Setup_IM2; call AY_Silence; jp MainLoop
$83CB  DoLevelBanking Pages in level data bank, copies to level_map_cache, pages back
$BC00  HANDLER        IM2 interrupt: keyboard scan, timer, music, SFX, AY write
$BC76  AY_Silence     Silences all AY channels via port writes
$BCC0  AY_WriteBuffer Writes ay_buf shadow registers to AY hardware
$BCDB  Music_Init     Starts a music track
$BCEB  Music_Stop     Stops music, calls AY_Silence
$BCF3  Music_Tick     Advances music one frame (called from HANDLER)
$BD62  SFX_Play       Starts a sound effect
$BD7F  SFX_Tick       Advances SFX one frame (called from HANDLER)
$BF7B  BankSwitch     Safe bank switch via port $7FFD (guards on bankswitch_ok)
$BF9B  ClearScreen    di; zeros $4000-$57FF pixels; fills $5800-$5AFF with ATTR_SKY; ei
$BFFD  DrawCharXY     JP DrawCharXY_Real (PINNED — last 3 bytes of bank2)
```

### Key Addresses — Bank 7 ($C000-$FFFF, always paged during play)

```
$C000  DrawCharXY_Real  Draws ASCII char using ROM1 font at $3D00
$C06E  DrawString       Draws null-terminated string via DrawCharXY
$C224  DrawTile         Draws 16×16 tile (skips AIR tiles — Fix 47)
$C2BA  RenderLevel      Draws visible tile columns from level_map_cache
$C4A8  DrawSprite       Draws 16×16 masked sprite (OR-mask, no attr write)
$C52C  EraseSprite      Zeros 16×16 pixel area (3 bytes × 16 rows)
$C570  UpdatePlayer     Physics, input, CheckGround/Walls/Ceiling
$C6C5  CheckGround      Snaps player to tile boundary on landing
$C710  CheckCeiling     Bounces player off ceiling tiles
$C75E  CheckWalls       Prevents player walking through solid tiles
$C7FC  UpdateCamera     Smooth horizontal scroll toward player
$C847  UpdateEnemies    Moves enemies, bounces at edges, CheckEnemyPlayer
$C984  DrawEnemies      Erase-at-prev + draw enemies with sprite selection
$CA35  DrawPlayer       Erase-at-prev + draw player with animation
$CB08  DrawPowerup      Draws active powerup sprite
$CB2F  DrawHUD          Score, world, timer, lives display
$CC03  TitleScreen      Title loop, waits for Space
$CC68  ShowLevelEntry   Level card (world/level/lives), 2-second pause
$CCB2  ShowGameOver     Game Over screen, waits for Space to continue
$CCD0  ShowVictory      Victory screen with fanfare music
$CD1C  PlayerDie        Sets STATE_DEAD, plays SFX, stops music
$CD3D  CheckLevelEnd    Detects TILE_FLAG contact → STATE_LEVELEND
$CD5C  InitGame         Resets score/lives/world/level
$CD78  InitLevel        ClearScreen, resets player/camera/timer/enemies/prev positions
$CE21  MainLoop         Title → game loop → death/respawn → game over
$CE41  mg_frame HALT    Main game loop HALT (50Hz sync point)
```

### Sysvar Block ($8014-$80B4, bank2 fixed)

```
$8014  plr_x          DW  player world X (16-bit)
$8016  plr_y          DW  player world Y (16-bit)
$8018  plr_vx         DB  player horizontal velocity (signed)
$8019  plr_vy         DB  player vertical velocity (signed)
$801A  plr_dir        DB  facing direction (0=right, 1=left)
$801B  plr_anim       DB  animation frame counter
$801F  plr_dead       DB  death flag (1=dead)
$8021  plr_big        DB  powerup state (1=big)
$8022  plr_inv_timer  DB  invincibility frames remaining
$8023  plr_prev_sx    DB  previous drawn screen_x (for EraseSprite)
$8024  plr_prev_sy    DB  previous drawn screen_y (255=not yet drawn)
$8025  ent_prev_sx    DS 8  entity previous screen_x[0..7]
$802D  ent_prev_sy    DS 8  entity previous screen_y[0..7] (255=not drawn)
$8035  cam_x          DW  camera world X scroll position
$8037  cam_max        DW  maximum camera scroll (map width - screen width)
$8039  game_state     DB  STATE_TITLE/PLAYING/DEAD/LEVELEND/GAMEOVER/WIN
$803A  score          DS 4  BCD score (4 digits packed)
$803E  lives          DB
$8040  world          DB  (0-2)
$8041  level_num      DB  (0-2)
$8042  level_timer    DW  countdown (199 → 0 at 1Hz)
$8048  ent_type       DS 8  entity type per slot
$8050  ent_xl         DS 8  entity world X low byte
$8058  ent_xh         DS 8  entity world X high byte
$8060  ent_yl         DS 8  entity world Y (screen_y, no vert scroll)
$8078  ent_state      DS 8  0=inactive, 1=active
$8095  joy_held       DB  current frame keys (bit0=right,bit1=left,bit4=fire)
$8096  joy_new        DB  newly-pressed keys this frame (edge detect)
$80B4  bankswitch_ok  DB  1 if 128K paging available
$80B5  level_map_cache DS 352  32×11 tile cache (filled by DoLevelBanking)
```

---

## ARCHITECTURE SUMMARY

See **`architecture.md`** for ZX Spectrum 128K hardware reference.
See **`marco128.md`** for project-specific data including:
- Hardware specs and memory paging rules
- Cross-bank calling rules (bank7 may call bank2; not the reverse)
- Subroutine contracts (IN/OUT/CLOBBERS for every routine)
- Complete bug history (67 fixes)
- Pre-flight checklist for all code changes

---

## BUILD INSTRUCTIONS

### Prerequisites

```bash
# sjasmplus (z00m fork) — Linux native build included in repo
# https://github.com/z00m128/sjasmplus
sjasmplus --nologo --lst=build/marco128.lst src/marco128.asm

# Python 3.8+
python3 make_szx.py
# → produces build/marco128.szx
```

Load `build/marco128.szx` in FUSE: **File → Open**.  
Select machine: **Spectrum 128K**.

### make_szx.py behaviour

Built from scratch against the ZXST v1.5 spec — no template `.szx` required.

- Reads `build/bank0.bin`, `bank1.bin`, `bank2.bin`, `bank3.bin`, `bank7.bin`
- Finds GAME_START by locating `DI + LD SP,$BBFE` signature in bank2
- Pre-writes `JP $BC00` at `$BCBC` in bank2 (IM2 jump stub)
- Pre-fills IM2 vector table at `$7E00` in bank5 (257 × `$BC`)
- Sets BANKM sysvar at `$5B5C` = `$17` (bank7 at `$C000`, ROM1 active)
- Builds valid ZXST chunks: CRTR, Z80R, SPCR, AY, RAMP×8
- Writes `build/marco128.szx`

---

## ASSET NOTES

All assets are original works created for Marco Bros 128.

**Sprites:** Original 16×16 pixel art, ZX Spectrum attribute-safe.

**Music:** Original AY-3-8912 compositions (frame-sequenced custom player):
- Title theme: C-major fanfare
- Overworld: D-major driving loop  
- Underground: A-minor phrase

**Sound Effects:** Original AY tone sweep sequences for jump, stomp, die, coin, bump.

---

## LICENCE

Source code and all original assets released under **CC0 1.0 Universal**
(Public Domain Dedication).

https://creativecommons.org/publicdomain/zero/1.0/

---

## SESSION STARTUP (for Claude)

At the start of each new session, run these steps before doing anything else:

```bash
# 1. Clone the repo
git clone https://TOKEN@github.com/mstreurman/Marcobros128.git repo
cd repo

# 2. Install sjasmplus if not already built
# (see build instructions in sjasmplus README — requires fixing Lua stubs)
# Quick fix: append stub functions to sjasm/lua_sjasm.cpp then make USE_LUA=0

# 3. Verify clean build
cp src/marco128.asm .
mkdir -p build tools
sjasmplus --nologo --lst=build/marco128.lst marco128.asm
# Expect: Errors: 0, warnings: 0

# 4. Build snapshot
python3 make_szx.py
# Expect: Wrote build/marco128.szx

# 5. Verify snapshot
snapdump build/marco128.szx | head -8
# Expect: machine: Spectrum 128K, PC: 0x8375, SP: 0xBBFE

# 6. Check current state
tail -20 changelog.chg        # latest fixes
grep "Version" src/marco128.asm | head -1  # current version
```

### What you need from the user each session:
- Fresh GitHub PAT token (for git push at end of session)
- FUSE profiler output (`.txt`) after test runs — upload directly to chat
- Description of what was observed in FUSE

### Key tools available in this environment:
- `sjasmplus` — Z80 assembler (build from source once, then persistent)
- `python3 make_szx.py` — builds `.szx` snapshot from scratch (no template)
- `snapdump` — verifies `.szx` file integrity (from fuse-emulator-utils)
- `z80dasm` — Z80 disassembler
- `python3 -c "import z80; ..."` — Z80 CPU emulator for stack/register tracing

### Architecture notes:
- Full technical reference: `architecture.md`
- Bug history (67 fixes): Section B9 of `architecture.md`
- Subroutine contracts: Section B11 of `architecture.md`
- Pre-flight checklist for all code changes: Section C3.6 of `architecture.md`

### Current open issues (as of v0.7.7):
- Sprite ghosting during transitions (cosmetic)
- HUD attribute overlap with tile row 0-1 (cosmetic)
- Game performance ~7fps (acceptable but improvable)
- Enemy contact crash — may be resolved in v0.7.7, needs profiler run to confirm
