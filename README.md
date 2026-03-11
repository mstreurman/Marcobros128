# MARCO BROS 128
### An original 8-bit platformer for ZX Spectrum 128K Toastrack
*Inspired by classic side-scrolling platformers of the 1980s.*

---

## OVERVIEW

A complete 3-world × 3-level-per-world (9 levels total) side-scrolling platformer
for the ZX Spectrum 128K Toastrack. The last level of each world is a boss battle.

**Target hardware:** ZX Spectrum 128K Toastrack — no expansions, no interfaces.
**Assembler:** sjasmplus (z00m fork)
**Snapshot tool:** `tools/make_szx.py` — builds a FUSE-compatible `.szx` snapshot
**Testing:** FUSE emulator with PC-sampling profiler output

---

## GAMEPLAY

**Controls (Kempston Joystick / Keyboard Fire = Space):**
- Left/Right — move
- Up / Fire — jump (hold for higher jump)

**Objective:** Reach the exit at the end of each level within the time limit.

**Enemies:**
- **Walker** — marches left, stomp to defeat, awards 100 points
- **Sheller** — walks, shell slides when stomped, awards 200 points
- **Boss** — appears in level X-3, takes 3 stomps, awards 5000 points

**Powerups:**
- **Power-up** — makes Marco bigger (one extra hit)
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
$0000-$3FFF  ROM (48K ROM or 128K ROM 0/1)
$4000-$7FFF  BANK 5 (fixed) — Screen ($4000-$5AFF) + Sysvars ($5B00-$7FFF)
             IM2 vector table at $7E00 (257 × $BC)
             Stack: $7C00-$7DFF (old) → moved to $BFF8 in bank2
$8000-$BFFF  BANK 2 (fixed) — Main engine, physics, renderer, music, SFX
$C000-$FFFF  BANKABLE — Bank 7 always during play; Banks 0,1,3 paged briefly
             during InitLevel only (via DoLevelBanking shim in bank2)
```

### Bank Layout

| Bank | Contents | Contended? |
|------|----------|-----------|
| 0 | World 1 map + spawn tables | No |
| 1 | World 2 map + spawn tables | Yes (data only) |
| 2 | Main engine (FIXED) | No |
| 3 | World 3 map + spawn tables | No |
| 5 | Screen + sysvars (FIXED) | Yes |
| 7 | Game logic, DrawCharXY, UI, levels | Yes (code) |

### Key Addresses — Bank 2 ($8000-$BFFF)

```
$8000  Entry stub (jp GAME_START)
$8356  GAME_START: di; ld sp,$BFF8; set bankswitch_ok; call ClearScreen;
                   call Setup_IM2; call AY_Silence; jp MainLoop
$807B  ay_buf           DS 14 (AY shadow register buffer)
$8089  sfx_active       DB
$808A  sfx_ptr          DW
$808D  music_ptr        DW
$8092  music_playing    DB
$8095  bankswitch_ok    DB  (guard: 0 = BankSwitch is a no-op)
$8096  level_map_cache  DS 352 (32×11 tile cache, filled by LoadLevelMap)
$BC00  HANDLER          IM2 interrupt handler
$BCBC  IM2_JUMP         JP $BC00 (written by make_szx.py + Setup_IM2)
$BCC0  AY_WriteBuffer   Writes ay_buf to AY hardware
$BCDB  Music_Init
$BCEB  Music_Stop
$BCF3  Music_Tick
$BD62  SFX_Play
$BD7F  SFX_Tick
$BFA5  BankSwitch       Guards on bankswitch_ok; writes port $7FFD
$BFC5  ClearScreen      di; ldir×2; ei; ret  (DI/EI protect stack from IM2)
$BFFD  DrawCharXY       JP DrawCharXY_Real  (PINNED — last 3 bytes of bank2)
```

### Key Addresses — Bank 7 ($C000-$FFFF, always paged during play)

```
$C000  DrawCharXY_Real  Character renderer
$C05E  DrawString
$CA47  TitleScreen
$CAAC  ShowLevelEntry
$CAF6  ShowGameOver
$CBA0  InitGame
$CBBC  InitLevel        Calls DoLevelBanking (in bank2) to safely page level data
$CC4E  MainLoop
$CC52  call TitleScreen
$CC55  .mg_restart
$CC5C  .mg_level
$CC60  call ShowLevelEntry
$CC67  call InitLevel
```

---

## ARCHITECTURE SUMMARY

See **`architecture.md`** for the full technical blueprint.

---

## BUILD INSTRUCTIONS

### Prerequisites

```bash
# sjasmplus (z00m fork) — Windows / Linux / macOS
# https://github.com/z00m128/sjasmplus
sjasmplus --nologo --lst=build/marco128.lst marco128.asm

# Python 3 (any recent version)
python3 tools/make_szx.py
# → produces build/marco128.szx
```

Load `build/marco128.szx` in FUSE: **File → Open**.
Select machine: **Spectrum 128**.

### Quick build sequence

```cmd
.\sjasmplus --nologo --lst=build\marco128.lst marco128.asm
python3-64.exe tools\make_szx.py
```

### make_szx.py behaviour

- Reads `build/bank2.bin`, `bank7.bin`, `bank0.bin`, `bank1.bin`, `bank3.bin`
- Searches bank2 for `DI + LD SP,$BFF8` (`$F3 $31 $F8 $BF`) → GAME_START entry
- Pre-writes `JP $BC00` at `$BCBC` in bank2 (IM2 jump stub)
- Pre-fills IM2 vector table at `$7E00` in bank5 (257 × `$BC`)
- Patches Z80R: PC=GAME_START, SP=$BFF8, I=$7E, IFF=1, IM=2
- Patches SPCR: border=black, port $7FFD=$07 (bank 7 at $C000)
- Writes `build/marco128.szx`

---

## ASSET NOTES

All assets are original works created for Marco Bros 128.

**Sprites:** Original 16×16 pixel art, ZX Spectrum attribute-safe.
All sprites stay within 2×2 attribute cells to minimise colour clash.

**Music:** Original AY-3-8912 compositions, frame-sequenced custom player.
Not derived from any copyrighted work.

**Sound Effects:** Original AY tone sweep sequences.

---

## LICENCE

Source code and all original assets released under **CC0 1.0 Universal**
(Public Domain Dedication).

https://creativecommons.org/publicdomain/zero/1.0/
