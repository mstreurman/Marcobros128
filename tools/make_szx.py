#!/usr/bin/env python3
"""
make_szx.py  —  Build a FUSE-compatible 128K Spectrum snapshot (.szx)
                Built from scratch using the ZXST v1.5 spec.
                No template file required.

Reads:
  build/bank2.bin   — fixed engine bank  ($8000-$BFFF)
  build/bank7.bin   — game code bank     ($C000-$FFFF, page 7)
  build/bank0.bin   — world 1 level data (page 0)
  build/bank1.bin   — world 2 level data (page 1)
  build/bank3.bin   — world 3 level data (page 3)

Writes:
  build/marco128.szx

ZXST format notes:
  Header : ZXST(4) + major(1) + minor(1) + machine(1) + flags(1) = 8 bytes
  machine: 2 = Spectrum 128K
  Chunks : ID(4) + size(4 LE) + data(size bytes)
  CRTR   : name(32, null-padded) + major(2 LE) + minor(2 LE) = 36 bytes min
  Z80R   : 37 bytes (registers)
  SPCR   : 8 bytes (hardware state)
  AY     : 18 bytes (sound chip state)
  RAMP   : flags(2 LE) + page(1) + data(16384) per bank
"""

import struct, os, sys

BUILD = "build"
OUT   = os.path.join(BUILD, "marco128.szx")

# ---------------------------------------------------------------------------
# ZXST chunk helpers
# ---------------------------------------------------------------------------

def chunk(cid, data):
    """Pack a ZXST chunk: ID(4) + size(4 LE) + data."""
    assert len(cid) == 4
    return cid + struct.pack('<I', len(data)) + data

def make_crtr():
    """CRTR: name(32 bytes null-padded) + major(2) + minor(2) = 36 bytes."""
    name = b'make_szx.py / Marco Bros 128'
    name = name[:32].ljust(32, b'\x00')
    return chunk(b'CRTR', name + struct.pack('<HH', 1, 0))

def make_z80r(pc, sp=0xBBFE):
    """Z80R: 37 bytes of Z80 register state."""
    data = struct.pack('<HHHHHHHHHHHHBBBBBIBBh',
        0, 0, 0, 0,     # AF BC DE HL
        0, 0, 0, 0,     # AF' BC' DE' HL'
        0, 0,           # IX IY
        sp, pc,         # SP PC
        0x3F, 0x00,     # I  R   (Setup_IM2 sets I=$7E at runtime)
        0, 0,           # IFF1 IFF2 (disabled; GAME_START starts with DI)
        1,              # IM = 1 (Setup_IM2 switches to IM2)
        0, 0, 0, 0)     # dwCyclesStart chHoldIntReqCycles chFlags wMemPtr
    assert len(data) == 37, f"Z80R is {len(data)} bytes, expected 37"
    return chunk(b'Z80R', data)

def make_spcr(port7ffd=0x17):
    """SPCR: 8 bytes of Spectrum hardware state.
    port7ffd=$17: bits[2:0]=7 (bank7 at $C000), bit4=1 (ROM1/48K BASIC active).
    """
    return chunk(b'SPCR',
        struct.pack('<BBBBBBBB', 0, port7ffd, 0, port7ffd, 0, 0, 0, 0))

def make_ay():
    """AY: 18 bytes — currentReg(1) + registers(16) + flags(1). All silenced."""
    regs = bytearray(16)
    regs[7] = 0xFF  # mixer register = all channels off
    return chunk(b'AY\x00\x00', bytes([0]) + bytes(regs) + bytes([0]))

def make_ramp(page_num, raw_data):
    """RAMP: flags(2 LE) + page(1) + data(16384). Uncompressed (flags=0)."""
    assert len(raw_data) == 16384
    return chunk(b'RAMP', struct.pack('<HB', 0, page_num) + raw_data)

# ---------------------------------------------------------------------------
# Bank loading
# ---------------------------------------------------------------------------

def load_bank(name, required=True):
    path = os.path.join(BUILD, name)
    if not os.path.exists(path):
        if required:
            print(f"ERROR: {path} not found"); sys.exit(1)
        return bytes(16384)
    data = open(path, 'rb').read()
    return (data + bytes(16384))[:16384]

def find_game_start(bank2):
    """Locate GAME_START by finding DI + LD SP,$BBFE in bank2."""
    needle = bytes([0xF3, 0x31, 0xFE, 0xBB])
    idx = bank2.find(needle)
    if idx < 0:
        print("ERROR: GAME_START (DI + LD SP,$BBFE) not found in bank2.bin")
        sys.exit(1)
    addr = 0x8000 + idx
    print(f"  GAME_START: ${addr:04X}")
    return addr

# ---------------------------------------------------------------------------
# Main build
# ---------------------------------------------------------------------------

def build_szx():
    print("Loading banks...")
    bank2 = bytearray(load_bank("bank2.bin"))
    bank7 = load_bank("bank7.bin")
    bank0 = load_bank("bank0.bin")
    bank1 = load_bank("bank1.bin")
    bank3 = load_bank("bank3.bin")
    zeros = bytes(16384)

    # Pre-write IM2 jump stub at $BCBC in bank2: JP $BC00
    off = 0xBCBC - 0x8000
    bank2[off], bank2[off+1], bank2[off+2] = 0xC3, 0x00, 0xBC
    bank2 = bytes(bank2)
    print("  Pre-wrote JP $BC00 at $BCBC in bank2")

    # Build bank5: IM2 vector table at $7E00 + BANKM sysvar at $5B5C
    bank5 = bytearray(16384)
    for j in range(257):
        bank5[0x7E00 - 0x4000 + j] = 0xBC   # 257 × $BC for IM2 table
    bank5[0x5B5C - 0x4000] = 0x17            # BANKM = $17 (bank7 + ROM1)
    bank5 = bytes(bank5)
    print("  Pre-filled IM2 table at $7E00 in bank5 (257 × $BC)")

    print(f"  bank2: {sum(1 for b in bank2 if b)} non-zero bytes")
    print(f"  bank7: {sum(1 for b in bank7 if b)} non-zero bytes, first byte=${bank7[0]:02X}")
    print(f"  bank0: {sum(1 for b in bank0 if b)} non-zero bytes")
    print(f"  bank1: {sum(1 for b in bank1 if b)} non-zero bytes")
    print(f"  bank3: {sum(1 for b in bank3 if b)} non-zero bytes")

    gs = find_game_start(bank2)

    bmap = {0:bank0, 1:bank1, 2:bank2, 3:bank3,
            4:zeros, 5:bank5, 6:zeros,  7:bank7}

    # ZXST header: 8 bytes (magic + v1.5 + machine=2 + flags=0)
    out  = b'ZXST' + bytes([1, 5, 2, 0])
    out += make_crtr()
    out += make_z80r(pc=gs, sp=0xBBFE)
    out += make_spcr(port7ffd=0x17)
    out += make_ay()
    for page in range(8):
        out += make_ramp(page, bmap[page])

    os.makedirs(BUILD, exist_ok=True)
    open(OUT, 'wb').write(out)

    print(f"\nWrote {OUT}  ({len(out):,} bytes)")
    print(f"  Machine : Spectrum 128K")
    print(f"  PC      : ${gs:04X}  (GAME_START)")
    print(f"  SP      : $BBFE")
    print(f"  I       : $3F  (Setup_IM2 sets $7E at runtime)")
    print(f"  IFF     : 0    (GAME_START starts with DI)")
    print(f"  IM      : 1    (Setup_IM2 switches to IM2)")
    print(f"  $7FFD   : $17  (bank7 at $C000, ROM1 active)")
    print(f"\nLoad in FUSE: File -> Open -> {OUT}")

build_szx()
