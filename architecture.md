# MARCO BROS 128 — Architecture Blueprint
*Format: machine-readable reference for Claude. Update this file every time code changes.*
*Last updated: v0.7.7 — 67 fixes. Full build pipeline runs natively (sjasmplus + make_szx.py, no template). Keyboard matrix corrected ($DF row: P=bit0, O=bit1). EraseSprite sentinel guard (prev_sy=255 skip). DrawSprite attr write removed (redundant+crashing). Fix62-67 all applied. B2/B11 contracts fully updated.*

---

## ══════════════════════════════════════════════════════════════
## SECTION A — ZX SPECTRUM 128K TOASTRACK: COMPLETE HARDWARE MAP
## ══════════════════════════════════════════════════════════════
## Machine-readable target reference. No human-readability required.
## Source: ZX Spectrum 128K technical manual, FUSE source, ZXST spec v1.5,
##         The ZX Spectrum ULA (Wilkie), World Of Spectrum techinfo pages.
## ══════════════════════════════════════════════════════════════

## A1. CPU ─────────────────────────────────────────────────────

CPU          Zilog Z80A (NMOS)
CLOCK        3.5469 MHz (PAL); 1 T-state = 281.9 ns
             Exact: 3,546,900 Hz (17,734,500 / 5)
FRAME        69,888 T-states per frame (50.08 Hz)
             = 312 lines × 224 T-states/line
CONTENDED    Banks 1, 3, 5, 7 contended by ULA (see A8)
             Banks 0, 2, 4, 6 = uncontended (no wait states from ULA)
             NOTE: Banks 1 and 3 ARE contended while paged at $C000 during InitLevel.
             ROM is UNCONTENDED — wait states apply only to RAM banks shared with ULA.

REGISTERS
  AF BC DE HL   — general purpose (8/16-bit)
  AF' BC' DE' HL' — shadow (EXX/EX AF,AF' to swap)
  IX IY         — index (slow; 2-byte prefix DD/FD adds 4 T-states)
  SP            — stack pointer (grows DOWN)
  PC            — program counter
  I             — interrupt vector high byte (IM2: vector = I<<8 | data_bus)
  R             — DRAM refresh counter (7-bit, auto-incremented each M1 cycle)
  IFF1 IFF2     — interrupt flip-flops (DI→both 0; EI→both 1; NMI→IFF1=0; RETI→IFF1=IFF2)

INSTRUCTION TIMING (T-states, key instructions)
  NOP           4
  LD r,r        4      LD r,(HL)   7     LD r,n       7
  LD (HL),r     7      LD (HL),n  10     LD rr,nn    10
  LD (nn),A    13      LD A,(nn)  13     LD (nn),rr  20
  LD (IX+d),r  19      LD r,(IX+d) 19
  PUSH rr      11      POP rr     10
  CALL nn      17      RET        10     RETI        14
  JP nn        10      JP cc,nn  10/10   JR e        12     JR cc,e  12/7
  DJNZ e       13/8    HALT        4+4n (waits for interrupt)
  IN A,(n)     11      IN r,(C)   12     OUT (n),A   11     OUT (C),r 12
  ADD HL,rr    11      ADC HL,rr  15     SBC HL,rr   15
  EX DE,HL      4      EXX         4
  DI            4      EI          4     IM 0/1/2    8
  LDIR    (BC≠0): 21 per iteration; (BC=0) final: 16
  LDDR    same as LDIR
  DAA             4    (BCD adjust after ADD/SUB)

INTERRUPT MODES
  IM 0  — data bus value = instruction (RST on Spectrum = RST $38)
  IM 1  — always jumps to $0038 (ROM handler); used at power-on
  IM 2  — jumps to address stored at (I<<8 | data_bus_byte)
          data bus on Spectrum floats to $FF when no device drives it
          → safest: fill table so ALL $1XX addresses point to handler
          → Our setup: I=$7E, table at $7E00 all=$BC → vector=$BCBC → JP $BC00

NMI          jumps to $0066 (ROM NMI handler); IFF1→0; used for /NMI pin
             Toastrack has no accessible NMI button (unlike +2A)

RESET        Z80 sets PC=0, IFF=0, IM=0; does NOT clear RAM or registers
             → $0000 in ROM = LD B,$10 / LD A,$7F / ... 128K init sequence

## A2. MEMORY MAP ─────────────────────────────────────────────

PHYSICAL RAM    8 banks × 16 KiB = 128 KiB (on-board)
PHYSICAL ROM    2 banks × 16 KiB = 32 KiB

LOGICAL MAP (at any instant)
  $0000–$3FFF  ROM (16K)  — ROM0 or ROM1 selected by bit4 of $7FFD
  $4000–$7FFF  RAM bank 5 FIXED (always, non-switchable on Toastrack)
  $8000–$BFFF  RAM bank 2 FIXED (always, non-switchable on Toastrack)
  $C000–$FFFF  RAM SWITCHABLE — default bank 0; switched via $7FFD bits[2:0]

BANK NUMBERING   0–7 (3-bit field in $7FFD)
CONTENDED BANKS  1, 3, 5, 7 (ULA shares address bus with these banks)
                 Banks 0, 2, 4, 6 = uncontended (no wait states)
                 NOTE: Banks 1 and 3 are contended even when paged to $C000.
                 ROM is UNCONTENDED regardless of which ROM is selected.

ROM SELECTION
  ROM 0  (bit4=0) = 128K editor / menu ROM (16K)
  ROM 1  (bit4=1) = 48K BASIC ROM (16K) — contains character font, BASIC interpreter
  Both ROMs are UNCONTENDED — no wait states regardless of display state.

## A3. PAGING PORT $7FFD ──────────────────────────────────────

PORT    $7FFD  (write only; fully decoded: A15=0,A1=0 → matches many addresses)
               Reliable writes: ld bc,$7FFD / out (c),a

BIT FIELD
  bits[2:0]  RAM bank at $C000 (0–7)
  bit 3      Screen select: 0=bank5 (normal), 1=bank7 (shadow screen)
  bit 4      ROM select:    0=ROM0 (128K editor), 1=ROM1 (48K BASIC)
  bit 5      LOCK bit:      1=disable all further paging; latches until hard reset
             CRITICAL: once bit5=1, port $7FFD writes are ignored permanently
  bits[7:6]  ignored

SYSVAR SHADOW  $5B5C = BANKM — mirrors the last value written to $7FFD
               BankSwitch routine reads this, masks bits[2:0], ORs new bank, writes back
               → bit4 (ROM select) automatically preserved across every bank switch
               → bit5 MUST remain 0 (lock); never set it

OUR STARTUP VALUE  $17 = 0b0001_0111
  bit4=1 (ROM1), bits[2:0]=7 (bank7 at $C000), bits3,5=0

## A4. ROM CONTENTS ──────────────────────────────────────────

ROM 0 — 128K EDITOR ($0000–$3FFF when bit4=0)
  $0000  128K startup / main ROM init
  $0005  PRINT character routine (128K version)
  $0038  IM1 interrupt handler (returns via RETI)
  $0066  NMI handler
  $03A4  Paging code (writes $7FFD)
  $13BE  128K BASIC (extended commands)
  $3C00  128K Editor entry point

ROM 1 — 48K BASIC ($0000–$3FFF when bit4=1)
  SAME LOGICAL ADDRESSES as ROM0 but different content:

  $0000  48K startup sequence (LD B,$10 etc.)
  $0005  PRINT-A — print char in A to current stream
  $0008  PRINT-A-2 — print char, advance cursor
  $0010  PRINT-A-1
  $0038  IM1 maskable interrupt handler
  $0066  NMI handler
  $028E  CHAN-OPEN — opens a channel
  $0296  Print-Out — main output dispatcher
  $0D6B  TOKEN tables
  $1391  SYNTAX tables
  $3D00  ──────────────────────────────────────────────────────
         CHARACTER FONT — 96 characters × 8 bytes = 768 bytes
         Range: ASCII 32 (space) → ASCII 127 (©)
         Format: 8 rows × 8 pixels, MSB=leftmost pixel, 1=ink
         Address formula: $3D00 + (char - 32) × 8
         $3D00  space ($20)   $3D08  !      $3D10  "  ...
         $3E00  A ($41)       $3E08  B      ...
         $3EC0  a ($61)       ...
         $3EF8  z ($7A)
         $3F00  { ...  $3F78  DEL ($7F, shown as © on Spectrum)
         ──────────────────────────────────────────────────────

## A5. DISPLAY SYSTEM (ULA) ──────────────────────────────────

PIXEL AREA      $4000–$57FF  (6144 bytes, 256×192 pixels)
ATTR AREA       $5800–$5AFF  (768 bytes,  32×24 chars)
TOTAL           6912 bytes (SCREEN_SIZE constant)

PIXEL ADDRESSING (complex — non-linear!)
  Given pixel (px, py) where px=0..255, py=0..191:
  py split:  Y2Y1Y0 = py[2:0] (pixel row within char)
             Y7Y6   = py[7:6] (third = 0..2, each third = 64 lines)
             Y5Y4Y3 = py[5:3] (char row within third)

  Address = 0100_Y7Y6_Y2Y1Y0_Y5Y4Y3_px7..px3
  = $4000 | (py & $C0) << 5  (bits 12-11)
           | (py & $07) << 8  (bits 10-8)
           | (py & $38) << 2  (bits 7-5)
           | (px >> 3)        (bits 4-0)

  In Z80 assembly (standard pattern):
    ld a, py          ; A = pixel_y
    ld e, a           ; save
    and $C0           ; bits 7-6 → D high bits
    rrca : rrca : rrca ; shift right 3 → bits 4-3
    ld d, a           ; D[4:3] set
    ld a, e
    and $07           ; bits 2-0 of py → D[2:0]
    rrca : rrca : rrca ; → bits 7-5
    or d : or $40     ; combine + set $40 base → D done
    ld d, a
    ld a, e
    and $38           ; bits 5-3 → E[7:5]
    add a, a : add a, a ; << 2 → bits 7-5
    ld e, a
    ld a, px
    and $1F           ; low 5 bits of px → E[4:0]
    or e
    ld e, a           ; DE = screen address

  For DrawCharXY (tile=8px aligned): simplified using char coords
    B=col (0..31), C=row (0..23)
    D = $40 | (row & $18) << 2 | (row & $07) << 5   [base from row]
      actually: A=row*8 → three-stage encode as above

ADVANCING DOWN ONE PIXEL ROW (in DrawTile/DrawSprite inner loop)
  inc D                         ; next pixel row
  (D & $07) != 0: simple case (same char-row block)
  (D & $07) == 0: crossed a 8-row boundary → need to adjust
    E += $20 (next char column block)
    if carry: D -= $08          (wrapped into next third)
  Fix27/28: the carry test was inverted (jr nc → jr c). Now correctly jr c.

ATTRIBUTE ADDRESSING
  Given char position (col, row): addr = $5800 + row*32 + col
  = $5800 | (row << 5) | col
  In code: after computing D/E for pixel, attr addr = $5800 + ... (see DrawTile)

ATTRIBUTE BYTE FORMAT
  bit 7   FLASH (alternates ink/paper every 16 frames)
  bit 6   BRIGHT (intensifies ink and paper colours)
  bits[5:3]  PAPER colour (0–7)
  bits[2:0]  INK colour (0–7)

COLOUR TABLE (0–7)
  0=Black  1=Blue  2=Red  3=Magenta  4=Green  5=Cyan  6=Yellow  7=White
  +8 = bright variant (bit6=1 doubles intensity)

BORDER PORT $FE (write)
  bits[2:0] = border colour (0–7, same as above)
  bit3 = MIC output (tape)
  bit4 = EAR output (beeper)

ULA TIMING (PAL 50Hz)
  Frame = 312 lines × 224 T-states = 69,888 T-states
  Top border:    16 lines
  Display area: 192 lines (each: 128 T-states display + 96 T-states border/retrace)
  Bottom border: 56 lines
  Vertical blank: 8 lines
  Interrupt fires at start of vertical blank (~line 248)
  Interrupt duration: 32 T-states (Z80 must RETI within this window)
                      On Toastrack: longer than 48K (longer blanking pulse)

CONTENTION (ULA memory access conflicts)
  Affects: bank1 ($C000 if paged), bank3 ($C000 if paged),
           bank5 ($4000, always fixed), bank7 ($C000 if paged)
  ROM is UNCONTENDED — reads from $0000–$3FFF have no ULA wait states.
  Pattern (per line, T-states 1–128):
    6,5,4,3,2,1,0,0 repeated 16 times per display line = up to 6 T-states added
  Uncontended access: occurs T-states 128–223 (right border + hblank)
  Impact on our game: minor — engine in bank2 (uncontended); level data in banks
    1/3 paged briefly during InitLevel (contended but only runs once per level load)

## A6. I/O PORT MAP ──────────────────────────────────────────

PORT    DIR  DESCRIPTION
$FE    W    ULA: border[2:0], MIC(3), EAR(4); partially decoded (A0=0)
$FE    R    Keyboard + EAR input: see A7 keyboard matrix
$7FFD  W    Memory paging (see A3); fully decoded A15=0,A1=0
$FFFD  W/R  AY register select (write) / AY register read
$BFFD  W    AY register data write
$1F    R    Kempston joystick: bits[4:0]=URDLF (Up,Right,Down,Left,Fire)
             Returns $00 if no joystick present (bus float may give $FF on some hardware)
             Reliable test: read twice; if both same and != $FF, likely valid
             Our code: read; AND $1F; if == $1F (all bits set), treat as $00

KEMPSTON BIT FIELD ($1F read)
  bit 0  Right
  bit 1  Left
  bit 2  Down
  bit 3  Up
  bit 4  Fire
  bits[7:5]  undefined (float)

NOTE: Port $7FFE (A15=0, A0=0) aliases $FE for keyboard but $7FFD paging conflicts.
Use explicit LD A, $7F / IN A, ($FE) pattern for keyboard, not IN r,(C) with $7FFD.

## A7. KEYBOARD MATRIX ───────────────────────────────────────

8 half-rows, addressed by A[15:8] in IN A,($FE).
Active-low: 0=key pressed, 1=key released. Bits[4:0] of result.

A[15:8]  Port    Bit4    Bit3    Bit2    Bit1    Bit0
$F7     $F7FE   1       2       3       4       5
$FB     $FBFE   Q       W       E       R       T
$FD     $FDFE   A       S       D       F       G
$FE     $FEFE   CAPS    Z       X       C       V
$EF     $EFFE   0       9       8       7       6
$DF     $DFFE   P       O       I       U       Y
$BF     $BFFE   ENTER   L       K       J       H
$7F     $7FFE   SPACE   SS      M       N       B

Reading: LD A, $7F / IN A, ($FE) → bit0=0 if SPACE pressed
         LD A, $FE / IN A, ($FE) → bit0=0 if CAPS SHIFT pressed
         LD A, $BF / IN A, ($FE) → bit0=0 if ENTER pressed

Combined scan (any key): LD A,$00 / IN A,($FE) reads ALL rows ORed together — not useful
Correct: read each half-row separately with the half-row in A before IN.

## A8. AY-3-8912 SOUND ───────────────────────────────────────

IC location: piggybacked on ULA board (Toastrack), not on main PCB
Clock:       1.7734 MHz = 3.5469 / 2 (derived from ULA clock)

ACCESS PATTERN (Z80 side)
  Select register:  LD BC,$FFFD / OUT (C), reg_num   (reg 0–15)
  Write register:   LD BC,$BFFD / OUT (C), value
  Read register:    LD BC,$FFFD / IN A,(C)            (useful for envelopes)
  IMPORTANT: $FFFD and $BFFD are decoded by A15+A14+A1: ($FFFD: A15=1,A14=1,A1=0)

AY REGISTER MAP (16 registers, R0–R15; R14,R15 unused on -8912)
  R0   Channel A tone period LOW   (8 bits)
  R1   Channel A tone period HIGH  (bits[3:0] only, bits[7:4] ignored)
  R2   Channel B tone period LOW
  R3   Channel B tone period HIGH  (bits[3:0])
  R4   Channel C tone period LOW
  R5   Channel C tone period HIGH  (bits[3:0])
  R6   Noise period                (bits[4:0]; period = value × 2 / AY_clock)
  R7   Mixer control register:
         bit0  Tone A enable  (0=ON)    bit3  Noise A enable (0=ON)
         bit1  Tone B enable  (0=ON)    bit4  Noise B enable (0=ON)
         bit2  Tone C enable  (0=ON)    bit5  Noise C enable (0=ON)
         bit6  I/O A direction (1=output on -8912)
         bit7  I/O B direction (unused on -8912)
         Value $38 = tones A+B enabled, no noise, no I/O
         Value $FF = all silent
  R8   Channel A amplitude:  bits[3:0]=volume (0–15); bit4=1 use envelope
  R9   Channel B amplitude:  same format
  R10  Channel C amplitude:  same format
  R11  Envelope period LOW   (8 bits)
  R12  Envelope period HIGH  (8 bits)
  R13  Envelope shape:
         bit3  CONT (0=one-shot, 1=continuous)
         bit2  ATT  (0=decay, 1=attack — sets direction of first segment)
         bit1  ALT  (0=no alternate, 1=alternate direction each period)
         bit0  HOLD (0=continue, 1=hold final value)
         Common shapes: $08=\_ (fall once)  $0E=// (rise loop)  $0A=/\ (rise/fall loop)
  R14  I/O Port A (output: write value; input: read value) — not used on Spectrum
  R15  I/O Port B — not present on AY-3-8912

TONE FREQUENCY  f = AY_clock / (16 × period)
  AY_clock = 1,773,400 Hz
  Middle C (~262 Hz): period ≈ 424 ($01A8)
  period = round(1773400 / (16 × freq))

ENVELOPE FREQUENCY  f = AY_clock / (256 × envelope_period)

AY SILENCE SEQUENCE (reliable)
  LD BC,$FFFD / LD A,7 / OUT (C),A    ; select R7
  LD BC,$BFFD / LD A,$FF / OUT (C),A  ; mixer = all off
  ; then zero volumes R8,R9,R10

## A9. ZXST SNAPSHOT FORMAT (v1.5) ───────────────────────────

File header (8 bytes):
  [0-3]  "ZXST"  (magic)
  [4]    major version (1)
  [5]    minor version (5)
  [6]    machine type: 0=48K, 1=48K+IF1, 2=128K, 3=+2, 4=+2A/+3
  [7]    flags

Chunk format: 4-byte ID + 4-byte LE size + <size> bytes data
Chunks follow header sequentially.

Z80R chunk (ID "Z80R", size 37):
  [0-1]   AF      (LE word)
  [2-3]   BC
  [4-5]   DE
  [6-7]   HL
  [8-9]   AF'
  [10-11] BC'
  [12-13] DE'
  [14-15] HL'
  [16-17] IX
  [18-19] IY
  [20-21] SP      ← was wrong in make_szx.py (Fix 43)
  [22-23] PC      ← was wrong in make_szx.py (Fix 43)
  [24]    I       ← was wrong in make_szx.py (Fix 43)
  [25]    R
  [26]    IFF1    ← was wrong in make_szx.py (Fix 43)
  [27]    IFF2    ← was wrong in make_szx.py (Fix 43)
  [28]    IM      ← was wrong in make_szx.py (Fix 43)
  [29-32] dwCyclesStart (DWORD, T-states into current frame)
  [33]    chHoldIntReqCycles
  [34]    chFlags
  [35-36] wMemPtr (WORD)

SPCR chunk (ID "SPCR", size 8):
  [0]    last border colour (OUT $FE value)
  [1]    last value written to port $7FFD
  [2]    last value written to port $FE (EAR/MIC bits)
  [3]    last value written to port $1FFD (+3 only; ignored on 128K)
  [4-7]  unused

RAMP chunk (ID "RAMP", size = 3 + data_size):
  [0-1]  compression flags (0 = uncompressed)
  [2]    page number (0–7 for RAM; 5=bank5 etc.)
         page numbers map directly to 128K bank numbers
  [3+]   16384 bytes of page data

AY chunk (ID "AY\x00\x00", size 18):
  [0]    current register selected (0–15)
  [1-17] values of registers R0–R16 (17 bytes)
  Write R7=$FF on load to ensure silence

CRTR chunk (ID "CRTR") — creator string, ignore
JOY  chunk — joystick config, ignore
KEYB chunk — keyboard map, ignore

MACHINE TYPE 2 = Spectrum 128K (Toastrack or +2 grey)
Pages in a 128K snapshot: 0,1,2,3,4,5,6,7 (all 8 RAM banks) plus optional ROM pages

## A10. SYSTEM VARIABLES (SYSVARS) ──────────────────────────
## Selected sysvars in bank5 ($4000 map, addresses $5C00–$5CFF and beyond)

$5B5C  BANKM    DB  Mirror of port $7FFD (last paging value written)
                    BankSwitch reads/modifies/writes this.
$5C00  KSTATE   DS8  Keyboard state (used by ROM; we don't use)
$5C08  LASTK    DB  Last key pressed (ROM managed)
$5C3A  ERR_SP   DW  Error stack pointer (ROM; points into ROM error handler)
$5C3B  MEMBOT   DW  Calculator stack bottom (ROM)
$5C3C  NMIADD   DW  NMI handler address (if using ROM NMI)
$5C3D  RAMTOP   DW  Top of BASIC RAM (set by ROM; we don't use)
$5C41  CHANS    DW  Channel data start
$5CB0  PROG     DW  BASIC program start
$5CB2  VARS     DW  BASIC variables
$5CB4  E_LINE   DW  Edit line
$5C57  ATTR_T   DB  Temporary attributes
$5C8D  P_FLAG   DB  Print flags (OVER, INVERSE etc)

## A11. ROM1 FONT DETAIL ─────────────────────────────────────
## Required for DrawCharXY_Real hybrid font dispatch (Fix 41)

Base:     $3D00
Range:    ASCII 32 (space) → ASCII 127 (©/DEL graphic)
Count:    96 characters × 8 bytes = 768 bytes ($3D00–$3FFF boundary is $3FFF = last byte = $3D00+767)
Actual:   $3D00–$3EFF (768 bytes fits exactly, $3F00 is next area)
Formula:  address = $3D00 + (char_code - 32) × 8

Selected font addresses:
  $3D00  ' ' (32)    $3D08  '!' (33)    $3D10  '"' (34)    $3D18  '#' (35)
  $3D40  '0' (48)    $3D48  '1' (49)    ...
  $3D80  '@' (64)    $3D88  'A' (65)    $3D90  'B' (66)    ...
  $3DC0  '`' (96)    $3DC8  'a' (97)    $3DD0  'b' (98)    ...
  $3DF8  'z' (122)   $3E00  '{' (123)   ...   $3EF8  DEL(127)

Pixel format: 8 bytes, [0]=top row, [7]=bottom row
  Each byte: bit7=leftmost, bit0=rightmost; 1=ink, 0=paper
  Example 'A' ($3D88): 00010000 00101000 01000100 01111100 01000100 01000100 01000100 00000000

ROM1 font is permanently available when bit4 of $7FFD = 1 (ROM1 selected).
Access: simply read (HL) where HL = computed address. No port operations needed.
CRITICAL: ROM is NOT contended — reads are full speed.

## A12. STACK AND FREE MEMORY MAP ──────────────────────────

Bank2 free gap (used for stack):
  DRIFT WARNING: The gap start address ($842E in v0.6.5) drifts with every
  variable or code addition in bank2. Do NOT hardcode the gap start address.
  What is stable: SP=$BBFE (hardcoded in GAME_START and ZXST template).
  What drifts: the bottom of the gap (= end of LoadEnemySpawns).

  Gap = DS-zeroed space between end of LoadEnemySpawns and HANDLER ($BC00).
  SP = $BBFE (hardcoded; grows DOWN toward the gap bottom).
  The gap is currently ~15KB. Stack grows from $BBFE downward.
  Maximum safe stack depth: ~500 frames × worst-case 16 bytes = 8KB
    → stack bottom under max load ≈ $B9FE; gap bottom $842E → ~8.5KB headroom.
  Practical max depth (deepest call chain observed): ~13 frames = 26 bytes
    → stack reaches ~$BBE6; HANDLER's 6 push (Fix43 added IY) = 12 more bytes → ~$BBDA.
  MONITOR: if bank2 code grows past ~$BB00, stack headroom shrinks. Check listing.

ROM stack (at startup, before our SP is set):
  SP = $5BF9 (template value from FUSE power-on snapshot) — in bank5 sysvar area.
  Harmless: GAME_START sets SP=$BBFE before any stack operation.

## A13. TIMING REFERENCE ─────────────────────────────────────

Frames per second:         50.08 Hz (PAL)
T-states per frame:        69,888
T-states per scanline:     224
Active display lines:      192
Border+blank lines:        120
Interrupt pulse width:     ~32 T-states (Z80 samples INT line)
Interrupt to handler:      min 13 T-states (completion of current instruction + response)
  Worst case (LDIR mid-loop): 21+2 T-states before handler can start
  
Our frame budget:          ~69,888 T-states total
  HANDLER overhead:        ~200 T-states (music+sfx+AY+input)
  LDIR ClearScreen:        6912 × 5 + 7 × 6912 ≈ ~40K T-states (called once per scene change only)
  RenderLevel (per frame): estimated ~15,000–25,000 T-states (dominant cost)
  
HALT instruction:          waits until next interrupt (typically used for frame sync)
  ld a,(game_state) / halt → frame-synced game loop at ~50fps

## A14. COMMON Z80 PATTERNS (SPECTRUM-SPECIFIC) ─────────────

BANK SWITCH (safe pattern):
  di                        ; MUST DI — paging mid-instruction is dangerous
  ld a, (BANKM)             ; read current value
  and $F8                   ; clear bank bits[2:0]
  or bank_number            ; set new bank (preserves ROM select bit4, lock bit5)
  ld (BANKM), a             ; update shadow
  ld bc, $7FFD
  out (c), a
  ei                        ; re-enable after paging complete

DETECT CONTENTION (avoid if possible):
  Place time-critical loops in bank2 ($8000–$BFFF) or bank6 ($C000 if paged)
  Avoid long LDIR/LDDR in bank5 range ($4000–$7FFF) during display active area

SCREEN BYTE ADDRESS from tile position (col 0..31, row 0..23):
  pixel_y = row * 8
  D = $40 | ((pixel_y & $C0) >> 3) | (pixel_y & $07)
  E = ((pixel_y & $38) << 2) | col
  → DE = screen address of top-left pixel of character cell

ATTR ADDRESS from char position (col 0..31, row 0..23):
  = $5800 + (row << 5) + col
  In Z80: ld hl,$5800 / ld d,0 / ld e,row / add hl,hl/add hl,hl/add hl,hl/add hl,hl/add hl,hl / ld e,col / add hl,de
  Faster: multiply by hand — row*32 = row<<5, add to $5800.

KEMPSTON READ:
  in a, ($1F)       ; read joystick
  and $1F           ; mask valid bits
KEYBOARD READ (Fix 55 + Fix 67 — pure keyboard, no joystick):
  Port $DFFE (A[15:8]=$DF): bit4=Y  bit3=U  bit2=I  bit1=O  bit0=P
  Port $7FFE (A[15:8]=$7F): bit4=B  bit3=N  bit2=M  bit1=Sym bit0=Space

  ld d, 0              ; accumulate joy_held bits in D
  ld a, $DF            ; select $DFFE row
  in a, ($FE)
  bit 0, a             ; P = right (bit0, active-low)
  jr nz, .no_p
  set 0, d             ; joy bit0 = right
  bit 1, a             ; O = left (bit1, active-low)
  jr nz, .no_o
  set 1, d             ; joy bit1 = left
  ld a, $7F            ; select $7FFE row
  in a, ($FE)
  bit 0, a             ; Space = fire/jump (bit0, active-low)
  jr nz, .no_space
  set 4, d             ; joy bit4 = fire
  ld a, d
  ld (joy_held), a     ; store result

## A15. TOASTRACK-SPECIFIC NOTES ────────────────────────────

"Toastrack" nickname: from the distinctive heatsink fins on the RF modulator.
Board: Issue 3A (most common), some Issue 3B variants.
Differences from +2 (grey):
  - Physical PSU connector different
  - +2 has built-in tape deck (no external needed)
  - +2 has slightly different ULA timing
  - +2 does NOT have the AY chip on the same PCB (separate daughter board on Toastrack)
  - Both share same paging architecture; code compatible

Differences from +2A/+3:
  - +2A/+3 have secondary paging port $1FFD (extra ROM banks, all-RAM mode)
  - $1FFD must NOT be written on Toastrack (undefined behaviour)
  - Our SPCR byte[3] ($1FFD mirror) is harmless as metadata only

Known Toastrack hardware quirks:
  - AY data bus occasionally glitches if written too rapidly; AY_WriteBuffer
    sequential OUT pairs are fine at Z80 speed
  - $7FFD lock bit (bit5): once set, absolutely cannot be cleared until hard reset
    → never set bit5 in normal operation
  - Floating bus on data lines: when no device drives data bus, value ≈ $FF
    (useful: IM2 with I=$FE and table all $FF → vector $FFFF = ROM if ROM1 active)
    (our approach: I=$7E, table all $BC → explicit, not reliant on float)
  - RESET line: soft reset (CAPS SHIFT + SPACE) resets Z80 but does NOT clear $7FFD
    → page lock survives soft reset; only power cycle clears it

## ══════════════════════════════════════════════════════════════
## END SECTION A — HARDWARE TARGET REFERENCE
## ══════════════════════════════════════════════════════════════

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
$80A3        level_map_cache  DS 704 (MAP_W×MAP_H = 64×11) — v0.6.5 listing confirmed
                              Immediately follows variable block; drifts with it.
$8375        GAME_START     di; ld sp,$BBFE; ld a,$17; ld($5B5C),a;  — v0.6.5 listing
                            ld a,1; ld(bankswitch_ok),a;
                            call Setup_IM2; call ClearScreen; call AY_Silence; jp MainLoop
$837D        Setup_IM2      Fills $7E00 with $BC×257; writes JP $BC00 at $BCBC; ld i,$7E; im 2; ei; ret  — v0.6.5
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
## Ground truth extracted from marco128.asm v0.6.2.
## Format: IN / OUT / CLOBBERS / SIDE-EFFECTS / GLOBALS-WRITTEN
## "Clobbers" = register value on return differs from value on entry.
## Registers not listed = preserved (pushed/popped internally).
## ─────────────────────────────────────────────────────────────

DrawCharXY        (trampoline $BFFD → DrawCharXY_Real $C000, bank7)
  IN:       A=char_code (32-127 → ROM1 font; 128-255 → FONT_DATA)
            B=col (0..31)  C=row (0..23)
  OUT:      none
  CLOBBERS: nothing  (pushes/pops AF,IX,BC,DE,HL)

DrawString        ($C05E, bank7)
  IN:       HL=ptr to null-terminated string  B=col  C=row
  OUT:      none
  CLOBBERS: HL (advanced past null terminator)
  NOTE:     AF,BC preserved via push/pop. B on return = original B (restored).

DrawTile          (~$C200, bank7)
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

RenderLevel       (~$C000 area, bank7)
  IN:       none
  OUT:      none
  CLOBBERS: nothing  (pushes/pops IY,IX,BC,DE,HL)
  GLOBALS:  writes cam_tile_x, cam_sub_x

GetTileAt         ($8??? bank2)
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

CheckGround       (bank2)
  IN:       none (reads plr_x, plr_y globals)
  OUT:      none
  CLOBBERS: AF  (pushes/pops BC,DE,HL)
  GLOBALS:  writes plr_y, plr_vy, plr_on_ground, plr_jumping

CheckCeiling      (bank2)
  IN:       none (reads plr_x, plr_y globals)
  OUT:      none
  CLOBBERS: AF, DE  (pushes/pops BC,HL only)
  GLOBALS:  writes plr_vy, plr_y; may call QBlockHit → writes score,coins; SFX_Play

CheckWalls        (bank2)
  IN:       none (reads plr_vx, plr_x, plr_y globals)
  OUT:      none
  CLOBBERS: AF  (pushes HL, BC, DE on entry; pops DE, BC, HL on exit — all preserved)
  GLOBALS:  writes plr_x, plr_vx
  NOTE Fix42a/46: routine has multiple branches to .cw_done; ALL were measured and
    two required jp (not jr): entry jr z (+144) and right-probe jp z (+143).
    When adding any new branch to .cw_done, verify distance before using jr.

UpdatePlayer      (bank7)
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

LoadEnemySpawns   ($83CB, bank2) — called only from DoLevelBanking
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

Setup_IM2         ($837D, bank2)
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
