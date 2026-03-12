#!/usr/bin/env python3
"""
make_szx.py  —  Build a FUSE-compatible 128K Spectrum snapshot (.szx)

Reads:
  tools/128k_power_on.szx  — FUSE power-on snapshot used as machine template
  build/bank2.bin          — fixed engine bank  ($8000-$BFFF)
  build/bank7.bin          — game code bank     ($C000-$FFFF, page 7)
  build/bank0.bin          — world 1 level data (page 0)
  build/bank1.bin          — world 2 level data (page 1)
  build/bank3.bin          — world 3 level data (page 3)

Writes:
  build/marco128.szx

Usage:
  python3 tools/make_szx.py

Place your 128k_power_on.szx in the tools/ folder.
To create it: open FUSE, select Spectrum 128, then File -> Save Snapshot.
"""

import struct, os, sys

BUILD  = "build"
TOOLS  = "tools"
OUT    = os.path.join(BUILD, "marco128.szx")
TMPL   = os.path.join(TOOLS, "128k_power_on.szx")

def load_bank(name, required=True):
    path = os.path.join(BUILD, name)
    if not os.path.exists(path):
        if required:
            print(f"ERROR: {path} not found")
            sys.exit(1)
        return bytes(16384)
    data = open(path, "rb").read()
    if len(data) != 16384:
        data = (data + bytes(16384))[:16384]
    return data

def find_game_start(bank2):
    idx = bank2.find(bytes([0xF3, 0x31, 0xFE, 0xBB]))
    if idx < 0:
        print("ERROR: GAME_START (DI+LD SP,$BBFE) not found in bank2.bin")
        sys.exit(1)
    addr = 0x8000 + idx
    print(f"  GAME_START: ${addr:04X}")
    return addr

def make_ramp(page_num, raw_data):
    """Uncompressed RAMP chunk."""
    assert len(raw_data) == 16384
    payload = struct.pack('<HB', 0, page_num) + raw_data
    return b'RAMP' + struct.pack('<I', len(payload)) + payload

def build_szx():
    if not os.path.exists(TMPL):
        print(f"ERROR: template not found: {TMPL}")
        print("Create it by saving a power-on snapshot from FUSE (File -> Save Snapshot)")
        print("and placing it at tools/128k_power_on.szx")
        sys.exit(1)

    tmpl = open(TMPL, "rb").read()

    # Verify it's a ZXST file for Spectrum 128
    if tmpl[:4] != b'ZXST':
        print("ERROR: template is not a ZXST file")
        sys.exit(1)
    machine = tmpl[6]
    if machine != 2:
        print(f"WARNING: template machine type = {machine}, expected 2 (Spectrum 128)")

    print("Loading banks...")
    bank2 = bytearray(load_bank("bank2.bin"))
    bank7 = load_bank("bank7.bin")
    bank0 = load_bank("bank0.bin")
    bank1 = load_bank("bank1.bin")
    bank3 = load_bank("bank3.bin")
    zeros = bytes(16384)

    # Pre-write the IM2 jump stub into bank2 at $BCBC
    # This ensures FUSE's pre-load interrupt fires through our handler
    # (Setup_IM2 will also write these at runtime, so this is idempotent)
    BCBC_OFFSET = 0xBCBC - 0x8000   # = 0x3CBC
    bank2[BCBC_OFFSET]     = 0xC3   # JP
    bank2[BCBC_OFFSET + 1] = 0x00   # $BC00 low
    bank2[BCBC_OFFSET + 2] = 0xBC   # $BC00 high
    bank2 = bytes(bank2)
    print(f"  Pre-wrote JP $BC00 at $BCBC in bank2")

    # Pre-fill IM2 vector table in bank5 at $7E00 (257 bytes of $BC)
    # bank5 maps $4000-$7FFF; offset of $7E00 = $7E00-$4000 = $3E00
    # ClearScreen only clears $4000-$5AFF so this is safe.
    bank5 = bytearray(16384)
    IM2_OFFSET = 0x7E00 - 0x4000    # = 0x3E00
    for j in range(257):
        bank5[IM2_OFFSET + j] = 0xBC
    bank5 = bytes(bank5)
    print(f"  Pre-filled IM2 table at $7E00 in bank5 (257 × $BC)")

    print(f"  bank2: {sum(1 for b in bank2 if b)} non-zero bytes")
    print(f"  bank7: {sum(1 for b in bank7 if b)} non-zero bytes, first byte=${bank7[0]:02X}")
    print(f"  bank0: {sum(1 for b in bank0 if b)} non-zero bytes")
    print(f"  bank1: {sum(1 for b in bank1 if b)} non-zero bytes")
    print(f"  bank3: {sum(1 for b in bank3 if b)} non-zero bytes")

    gs = find_game_start(bank2)

    bmap = {0:bank0, 1:bank1, 2:bank2, 3:bank3,
            4:zeros, 5:bank5, 6:zeros, 7:bank7}

    # Rebuild ZXST by patching the template chunks
    out = bytearray(tmpl[:8])  # keep ZXST header verbatim (magic+version+machine)

    i = 8
    while i < len(tmpl):
        cid  = tmpl[i:i+4]
        csz  = int.from_bytes(tmpl[i+4:i+8], 'little')
        cdata = bytearray(tmpl[i+8:i+8+csz])

        if cid == b'Z80R':
            # Clear all GP registers
            for j in range(10): cdata[j] = 0
            # PC at offsets 10-11, SP at 12-13
            cdata[10] = gs & 0xFF
            cdata[11] = gs >> 8
            cdata[12] = 0xFE        # SP = $BBFE (Fix 26d: free gap below HANDLER)
            cdata[13] = 0xBB        # SP high byte
            cdata[30] = 0x7E        # I = $7E (IM2 vector table prefix)
            cdata[31] = 0           # R
            cdata[32] = 1           # IFF = 1 (interrupts enabled — our IM2 handler handles them)
            cdata[33] = 2           # IM = 2
            cdata[34] = 0           # not halted
            out += cid + struct.pack('<I', len(cdata)) + bytes(cdata)

        elif cid == b'SPCR':
            cdata[0] = 0    # border = black
            cdata[1] = 7    # port $7FFD = 7 → bank 7 at $C000
            cdata[2] = 0    # port $FE
            cdata[3] = 7    # port $1FFD (mirror)
            out += cid + struct.pack('<I', len(cdata)) + bytes(cdata)

        elif cid == b'RAMP':
            page = cdata[2]
            out += make_ramp(page, bmap.get(page, zeros))

        elif cid == b'AY\x00\x00':
            # Silence all AY channels
            ay = bytearray(18)
            ay[9] = 0xFF   # mixer register = all off
            out += cid + struct.pack('<I', 18) + bytes(ay)

        else:
            # CRTR, JOY, KEYB, ZXPR — keep verbatim
            out += cid + struct.pack('<I', csz) + bytes(cdata)

        i += 8 + csz

    os.makedirs(BUILD, exist_ok=True)
    open(OUT, "wb").write(out)
    print(f"\nWrote {OUT}  ({len(out):,} bytes)")
    print(f"  Machine : Spectrum 128")
    print(f"  PC      : ${gs:04X}  (GAME_START)")
    print(f"  SP      : $BBFE")
    print(f"  $7FFD   : $07  (bank 7 at $C000)")
    print(f"  IFF     : 1   (IM2 pre-initialized — handler active from first instruction)")
    print(f"\nLoad in FUSE: File -> Open -> {OUT}")

build_szx()
