# Marco Bros 128 — Session Startup Checklist

Quick reference for Claude at the start of each session.

## Step 1 — Clone and build

```bash
git clone https://TOKEN@github.com/mstreurman/Marcobros128.git repo
cd repo
cp src/marco128.asm .
mkdir -p build tools
sjasmplus --nologo --lst=build/marco128.lst marco128.asm
python3 make_szx.py
snapdump build/marco128.szx | head -5
```

Expected output:
```
Pass 3 complete
Errors: 0, warnings: 0
GAME_START: $8375
machine: Spectrum 128K
PC: 0x8375  SP: 0xBBFE
```

## Step 2 — Orient yourself

```bash
tail -30 changelog.chg          # what was last fixed
grep "Version" src/marco128.asm # current version  
grep "open issues" README.md -A 10  # known problems
```

## Step 3 — sjasmplus not installed?

```bash
# Clone and build (one-time)
cd /tmp && git clone https://github.com/z00m128/sjasmplus.git
cd sjasmplus

# Fix the Lua stub issue
cat >> sjasm/lua_sjasm.cpp << 'STUBS'
#ifndef USE_LUA
void dirLUA() {}
void dirENDLUA() {}
void dirINCLUDELUA() {}
#endif
STUBS

make USE_LUA=0 -j4
cp build/release/sjasmplus /usr/local/bin/
```

## Step 4 — Tools available

| Tool | Command | Purpose |
|------|---------|---------|
| Assembler | `sjasmplus` | Assemble .asm → .bin + .lst |
| Snapshot builder | `python3 make_szx.py` | Build .szx for FUSE |
| Snapshot verifier | `snapdump build/marco128.szx` | Verify .szx integrity |
| Disassembler | `z80dasm --origin=0xC000 build/bank7.bin` | Disassemble banks |
| Z80 emulator | `python3 -c "import z80; ..."` | Trace registers/stack |

## What the user provides each session

- Fresh GitHub PAT (for `git push` at end)
- FUSE profiler `.txt` file (after test runs)
- Description of what they saw in FUSE

## Current version: v0.7.7
