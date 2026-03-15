# ZX SPECTRUM 128K TOASTRACK — Hardware Reference
*Machine-readable hardware reference for Z80/Spectrum development.*
*Reusable across any ZX Spectrum 128K Toastrack project.*
*Last updated: v0.7.9 (Marco Bros 128 project)**

---

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

