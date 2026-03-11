# MARCO BROS 128 — Architecture Blueprint
*Format: machine-readable reference for Claude. Update this file every time code changes.*
*Last updated: Fix 24 — Turbo loader removed (was overwriting SFX_Play/SFX_Tick). v0.2.0*

---

## HARDWARE TARGET

- ZX Spectrum 128K Toastrack (Motorola Z80A, 3.5 MHz)
- AY-3-8912 sound chip via ports $FFFD (register select) / $BFFD (register write)
- Display: Bank 5 at $4000–$57FF (pixel) + $5800–$5AFF (attr), 256×192, 15 colours
- No shadow screen (bit 3 of $7FFD = 0 always)
- No +2A/+3 features

---

## MEMORY MAP

```
$0000–$3FFF  ROM          128K ROM 0 (editor+menu) or ROM 1 (48K BASIC)
$4000–$7FFF  BANK 5 fixed Screen + sysvars + IM2 table
$8000–$BFFF  BANK 2 fixed Engine, physics, renderer, music, SFX, handler
$C000–$FFFF  BANKABLE     Bank 7 always during play; 0/1/3 paged during InitLevel only
```

### Bank 5 layout ($4000–$7FFF, fixed)
```
$4000–$57FF  Display file (pixels)
$5800–$5AFF  Attribute file
$5B00–$7DFF  Sysvars (unused by game, present for 128K ROM compatibility)
$7E00–$7F00  IM2 vector table — 257 bytes, all $BC
             Written by make_szx.py at build time + verified by Setup_IM2 at runtime
$7C00–$7DFF  OLD stack location — no longer used
```

### Bank 2 layout ($8000–$BFFF, fixed, always present)
```
$8000        Entry stub:    JP GAME_START
$8003–$8009  (gap)
$800A–$8074  Game variables (see Variables section)
$8075        pwrup_vy       DB
$8076        joy_held       DB   Joystick state this frame
$8077        joy_new        DB   Joystick edges (newly pressed)
$8078        joy_prev       DB
$807B        ay_buf         DS 14  AY shadow register buffer (regs 0–13)
$8089        sfx_active     DB   0=silent, 1=playing
$808A        sfx_ptr        DW   Pointer into current SFX data
$808D        music_ptr      DW   Pointer into current music data
$8091        music_note_ptr DW   Current position within note
$8092        music_playing  DB
$8093        music_speed    DB
$8094        sfx_frame      DB
$8095        bankswitch_ok  DB   1=BankSwitch enabled; 0=no-op guard
                                 WARNING: AY_Silence zeroes bytes $807B–$817A.
                                 bankswitch_ok MUST be re-set after AY_Silence.
                                 GAME_START sets it before calling AY_Silence
                                 — AY_Silence is called from GAME_START only,
                                 never from Music_Stop (Music_Stop is safe).
$8096–$81F5  level_map_cache DS 352  32×11 tile map, filled by LoadLevelMap
~$8356       GAME_START     di; ld sp,$BFF8; ld a,1; ld(bankswitch_ok),a;
                            call ClearScreen; call Setup_IM2; call AY_Silence;
                            jp MainLoop
             [note: AY_Silence zeros $807B–$817A which INCLUDES bankswitch_ok.
              GAME_START sets bankswitch_ok BEFORE calling ClearScreen and
              AY_Silence will zero it — this is acceptable because BankSwitch
              is not needed until InitLevel, which runs after Setup_IM2
              has restored the IM2 state. FIX NEEDED: move bankswitch_ok
              write to AFTER AY_Silence, or shrink AY_Silence loop to ld b,14]

$836B        Setup_IM2      Writes I=$7E, sets IM 2, writes JP $BC00 at $BCBC
$8800–$891F  TILE_DATA      10 tiles × 32 bytes (16×16 px, 2 bitplanes)
~$8940       SPRITE_DATA    Multiple sprites × 32 bytes each
~$8E00       FONT_DATA      96 chars × 8 bytes (ASCII 32–127)
~$BF4F       MUSIC_TITLE    AY music data — title theme
~$BF??       MUSIC_OVERWORLD
~$BF??       MUSIC_BOSS
~$BF??       SFX_DATA       SFX table (8 entries)

$BC00        HANDLER        IM2 interrupt handler (fired every frame, ~50Hz)
$BCBC        IM2_JUMP       C3 00 BC = JP $BC00  (pre-written by make_szx.py)
$BCC0        AY_WriteBuffer Writes ay_buf[0..13] to AY via OUT C instructions
$BCDB        Music_Init     HL=music data ptr, sets music_ptr, music_playing=1
$BCEB        Music_Stop     Sets music_playing=0, calls AY_Silence
$BCF3        Music_Tick     Advances music by one frame (reads note, writes ay_buf)
$BD62        SFX_Play       HL=sfx data ptr, sets sfx_ptr, sfx_active=1
$BD7F        SFX_Tick       Advances SFX by one frame (overwrites ay_buf ch C)
$BDD1–$BFA4  (misc engine routines)
$BFA5        BankSwitch     A=bank number; guards on bankswitch_ok; OUT $7FFD
$BFC5        ClearScreen    di; clear pixels+attrs via LDIR×2; out blue; ei; ret
                            CRITICAL: DI/EI wrap is mandatory — an interrupt
                            firing mid-LDIR corrupts the return address on stack.
                            GAME_START's own DI is not sufficient; ClearScreen
                            must guard itself because it's also called with
                            interrupts already enabled (TitleScreen, ShowLevelEntry).
$BFFD        DrawCharXY     JP DrawCharXY_Real   ← PINNED with ORG $BFFD
                            Must be last 3 bytes of bank2 ($BFFD–$BFFF).
                            If bank2 code grows past $BFFD, assembler will error.
```

### Bank 7 layout ($C000–$FFFF, always paged during play)
```
$C000        DrawCharXY_Real  B=row, C=col, A=char. Draws 8×8 char to screen.
$C05E        DrawString       HL=string ptr (null-term), B=row, C=col
$C070        DrawDecimalN     Various decimal drawing routines
~$C200       DrawTile         Draws 16×16 tile to screen (B=tile_y, C=tile_x)
~$C400       DrawSprite       IX=sprite data, B=pixel_y, C=pixel_x
~$C500       UpdatePlayer     Reads joy, applies physics, moves player
~$C6A0       UpdateEnemies    Loops entity array, moves each enemy
~$C800       CheckCollisions  Coin, enemy-stomp, powerup collisions
~$C900       DrawPowerup      Draws active powerup if any
~$C98C       DrawHUD          Draws score, lives, coins, time
~$CBA0       InitGame         Resets lives=3, score=0, world=0, level=0
$CBBC        InitLevel        Sets game_state=PLAYING, calls DoLevelBanking,
                              calls Music_Init(MUSIC_OVERWORLD)
~$CBD0       DoLevelBanking   IN BANK2 (not bank7) — see bank2 notes below
$CC4E        MainLoop         Outer game loop:
                              1 → TitleScreen
                              2 → InitGame
                              3 → ShowLevelEntry
                              4 → InitLevel
                              5 → game frame loop (halt → update → render)
$CC4E–$CD25  MainLoop body    Debug border colours: blue=title, red=initgame,
                              magenta=showlevelentry, green=initlevel, cyan=playing
$CAF6        ShowGameOver
$CBA0        InitGame
```

### Banks 0, 1, 3 — Level Data ($C000–$FFFF, paged only during InitLevel)
```
$C000        W1L1_MAP / W2L1_MAP / W3L1_MAP    32×11 = 352 bytes
$C160        W1L2_MAP / ...                     352 bytes
$C2C0        W1L3_MAP / ...                     352 bytes
$C420        W1_SPAWNS / ...                    Enemy spawn table ($FF terminated)
```

---

## INTERRUPT HANDLER — $BC00

Entry: hardware pushes PC+SP to stack.
```
Handler body:
  di
  push af, bc, de, hl, ix          ; 5 pushes = SP-10
  increment frame_count (16-bit)
  if game_state == STATE_PLAYING: tick level_timer (every 50 frames)
  read Kempston port $1F → AND $1F → if $1F (floating) zero it
  read keyboard Space ($BF / port $FE, bit 0) → OR fire bit
  compute joy_new (edge detect), update joy_held, joy_prev
  if music_playing: call Music_Tick ($BCF3)
  if sfx_active:   call SFX_Tick ($BD7F)
  call AY_WriteBuffer ($BCC0)
  pop ix, hl, de, bc, af           ; 5 pops = SP+10
  ei
  reti                             ; SP+2 → back to interrupted PC
```
**Stack balance: EXACTLY balanced. Any change breaks RET addresses.**
Keyboard row: $BF (row 7FFE) for Space. `in a,($FE)` with A=$BF loaded into C first.

---

## CLEARSCREEN — $BFC5

```
ClearScreen:
  di                        ; MANDATORY — see bug history Fix 23
  ld hl, $4000
  ld de, $4001
  ld bc, $1AFF              ; 6912 bytes = full pixel area
  ld (hl), 0
  ldir
  ld hl, $5800
  ld de, $5801
  ld bc, $02FF              ; 768 bytes = attribute area
  ld (hl), $47              ; ATTR_SKY = bright white on black
  ldir
  ld a, 1
  out ($FE), a              ; border = blue
  ei                        ; re-enable before returning
  ret
```

---

## BANKSWITCH SYSTEM

```
BankSwitch ($BFA5):
  ld a, (bankswitch_ok)
  or a
  ret z                     ; guard: if 0, skip entirely
  ; a = bank number (passed in A before call? No — see DoLevelBanking)
  ; Actually: call convention is A=bank number
  ld bc, $7FFD
  out (c), a
  ret

DoLevelBanking (in bank2, ~$CBD0 area):
  Reads world/level → computes bank number (0/1/3)
  Calls BankSwitch(level_bank) → pages in level data
  Calls LoadLevelMap → fills level_map_cache from $C000
  Calls LoadEnemySpawns → reads spawn table
  Calls BankSwitch(7) → restores bank7
  ret
  CRITICAL: This must be in BANK2, not bank7. Calling BankSwitch from bank7
  would page out bank7 and the return address would land in garbage.
```

---

## AY AUDIO SYSTEM

AY-3-8912 accessed via Z80 OUT only (no IN needed for playback).
```
Register select: ld bc, $FFFD : out (c), reg_number
Register write:  ld bc, $BFFD : out (c), value
```

Shadow buffer `ay_buf` ($807B, 14 bytes) maps to AY registers 0–13.
- Music_Tick writes to ay_buf (channels A+B)
- SFX_Tick writes channel C registers in ay_buf
- AY_WriteBuffer does single pass: 14 consecutive OUT pairs

AY register map:
```
R0  ch A period lo    R1  ch A period hi
R2  ch B period lo    R3  ch B period hi
R4  ch C period lo    R5  ch C period hi
R6  noise period
R7  mixer ($38 = tone A+B enabled, all noise off, all IO off)
R8  ch A volume       R9  ch B volume    R10 ch C volume
R11 envelope period lo  R12 envelope period hi  R13 envelope shape
```

Music format (custom, not PT3):
```
Each note: period_lo, period_hi, vol_A, vol_B, vol_C, duration_frames
End marker: $FF $FF
Loops to start automatically.
```

**AY_Silence warning:** The loop in AY_Silence clears `ld bc, (ay_buf)` for 14
iterations using HL walking from $807B. Historically the loop used `ld b,0`
(256 iterations) which zeroed `bankswitch_ok` at $8095 and `level_map_cache`.
Current status: **verify ld b,14 is used** — check listing at AY_Silence entry.

---

## IM2 SETUP

```
I register = $7E → vector table at $7E00–$7EFF (and $7F00 for the 257th byte)
All 257 bytes = $BC
When interrupt fires: Z80 reads I ($7E) + data bus byte → forms address $BCXX
$BCBC contains JP $BC00 (pre-written by make_szx.py, confirmed by Setup_IM2)
So all IM2 vectors point to HANDLER at $BC00.
```

---

## STACK

```
SP = $BFF8 (set by GAME_START, stays here as base)
Stack grows DOWN into bank2 ($8000–$BFFF, fixed, uncontended)

Typical call depth during ShowLevelEntry→ClearScreen:
  [BFF8] = base (nothing here during normal flow)
  [BFF6] = return addr from mg_level CALL ShowLevelEntry ($CC63)
  [BFF4] = return addr from ShowLevelEntry CALL ClearScreen ($CAAF)
  [BFF2] = interrupt PC pushed by hardware (while ClearScreen runs)
  [BFEC] = handler saves: af,bc,de,hl,ix (SP-10)
  ...handler runs, restores, RETI pops [BFF2], SP→$BFF4
  ClearScreen RET pops [BFF4]=$CAAF → ShowLevelEntry continues ✓
```

---

## ENTITY SYSTEM

Entity IDs (ENT_*):
```
ENT_WALKER  = 1  (walks left, stomp to kill)
ENT_SHELLER = 2  (walks, shell slides when stomped)
ENT_BOSS    = 3  (boss, 3 stomps required)
```

Sprite IDs referenced in DrawEntities:
```
SPR_WALKER1, SPR_WALKER2, SPR_WALKER_FLAT  (Walker enemy)
SPR_SHELLER1                                (Sheller enemy)
SPR_BOSS1, SPR_BOSS2                        (Boss)
SPR_PWRUP                                   (Power-up item)
SPR_MARCO_STAND, SPR_MARCO_WALK1, SPR_MARCO_WALK2, SPR_MARCO_JUMP
```

---

## KNOWN BUGS / PENDING FIXES

| # | Status | Description |
|---|--------|-------------|
| 22 | FIXED | Space key row: $7FFE not $BFFE |
| 23 | FIXED | ClearScreen DI/EI — interrupt mid-LDIR corrupted stack |
| 23b | FIXED | DrawCharXY trampoline not pinned — grew past $BFFC into bank boundary |
| P1 | FIXED | AY_Silence loop: confirmed ld b,14 in listing (BCA9). Clears only $807B-$8088, bankswitch_ok ($8095) unaffected. |
| 24 | FIXED | Turbo loader (ORG $BD00) overwrote SFX_Play (BD62) and SFX_Tick (BD7F) in bank2. Removed entirely. |
| P2 | PENDING | Game crashes to 128K menu after one frame — root cause TBD after Fix 24 retest. |
| P3 | PENDING | Gameplay verification: player movement, enemy AI, collision, music/SFX |

---

## BUILD ARTEFACTS

```
marco128.asm       → sjasmplus → build/marco128.lst + build/bank{0,1,2,3,7}.bin
build/bank*.bin    → tools/make_szx.py → build/marco128.szx
build/marco128.szx → FUSE (File → Open) for testing
```

make_szx.py detection signature: `$F3 $31 $F8 $BF` = `DI; LD SP,$BFF8` at GAME_START.
Version string in binary: `DEFB "MB128 v0.2.0", 0` immediately after JP GAME_START at $8006.

---

## DEBUG BORDER COLOURS (MainLoop)

```
Blue    (1) = TitleScreen running
Red     (2) = InitGame running
Magenta (3) = ShowLevelEntry running
Green   (4) = InitLevel running
Cyan    (5) = Game frame loop running
```

---
*End of architecture.md — update every time code is changed.*
