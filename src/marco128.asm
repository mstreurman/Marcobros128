; ============================================================
; MARCO BROS 128
; ZX Spectrum 128K Toastrack platformer
; Inspired by classic 8-bit platformers of the 1980s.
; Assembler: sjasmplus (z00m fork)
; Build:     sjasmplus --nologo --lst=build/marco128.lst marco128.asm
; Version:   0.2.0
; ============================================================

    DEVICE ZXSPECTRUM128

; ============================================================
; CONSTANTS
; ============================================================
PORT_ULA        EQU $FE
PORT_KEMPSTON   EQU $1F
PORT_PAGE       EQU $7FFD

BANKM           EQU $5B5C
ATTR_BASE       EQU $5800
SCREEN_BASE     EQU $4000
SCREEN_SIZE     EQU 6912

IM2_TABLE       EQU $7E00
IM2_JUMP        EQU $BCBC
HANDLER_ADDR    EQU $BC00
ENGINE_BASE     EQU $8000

TILE_AIR        EQU 0
TILE_GROUND     EQU 1
TILE_BRICK      EQU 2
TILE_QBLOCK     EQU 3
TILE_PIPE_T     EQU 4
TILE_PIPE_B     EQU 5
TILE_FLAG       EQU 6
TILE_SOLID      EQU 7
TILE_QUSED      EQU 8
TILE_CASTLE     EQU 9

ATTR_SKY        EQU $47     ; bright white ink, black paper
ATTR_GROUND_C   EQU $F0
ATTR_BRICK_C    EQU $16
ATTR_QBLOCK_C   EQU $F2
ATTR_PIPE_C     EQU $E0
ATTR_FLAG_C     EQU $E7
ATTR_CASTLE_C   EQU $F0
ATTR_USEDQ_C    EQU $38

MAP_W           EQU 64
MAP_H           EQU 11
SCREEN_TW       EQU 16
SCREEN_TH       EQU 11
TILE_PX         EQU 16

PLR_W           EQU 12
PLR_H           EQU 14
PLR_MAX_VX      EQU 2
GRAVITY         EQU 1

ENT_WALKER      EQU 1
ENT_SHELLER       EQU 2
ENT_BOSS        EQU 3
MAX_ENEMIES     EQU 8

STATE_TITLE     EQU 0
STATE_PLAYING   EQU 1
STATE_DEAD      EQU 2
STATE_LEVELEND  EQU 3
STATE_GAMEOVER  EQU 5
STATE_WIN       EQU 6

SFX_JUMP        EQU 0
SFX_COIN        EQU 1
SFX_BUMP        EQU 2
SFX_STOMP       EQU 3
SFX_DIE         EQU 4
SFX_POWERUP     EQU 5
SFX_BOSS_HIT    EQU 6
SFX_LEVELEND    EQU 7

AY_FINE_A       EQU 0
AY_COARSE_A     EQU 1
AY_FINE_B       EQU 2
AY_COARSE_B     EQU 3
AY_FINE_C       EQU 4
AY_COARSE_C     EQU 5
AY_NOISE        EQU 6
AY_MIXER        EQU 7
AY_VOL_A        EQU 8
AY_VOL_B        EQU 9
AY_VOL_C        EQU 10
AY_ENV_FINE     EQU 11
AY_ENV_COARSE   EQU 12
AY_ENV_SHAPE    EQU 13

NOTE_REST       EQU 0
NOTE_C4         EQU 424
NOTE_D4         EQU 377
NOTE_E4         EQU 336
NOTE_F4         EQU 317
NOTE_G4         EQU 283
NOTE_A4         EQU 252
NOTE_B4         EQU 224
NOTE_C5         EQU 212
NOTE_D5         EQU 189
NOTE_E5         EQU 168
NOTE_F5         EQU 159
NOTE_G5         EQU 141
NOTE_A5         EQU 126
NOTE_C6         EQU 106
NOTE_D6         EQU  94
NOTE_E6         EQU  84
NOTE_G6         EQU  71

; ============================================================
; BANK 2 — FIXED ENGINE ($8000–$BFFF)
; ============================================================
    PAGE 2
    ORG ENGINE_BASE

; $8000: entry stub — Z80 snapshot jumps here
; Border flashes: 2=red means CPU reached $8000
    ld a, 2
    out ($FE), a
    jp GAME_START
    DEFB "MB128 v0.2.0", 0   ; version tag in binary

; ============================================================
; GAME VARIABLES  ($8003 onwards)
; ============================================================
plr_x:          DW 32
plr_y:          DW 144
plr_vx:         DB 0
plr_vy:         DB 0
plr_dir:        DB 0
plr_anim:       DB 0
plr_anim_cnt:   DB 0
plr_on_ground:  DB 0
plr_jumping:    DB 0
plr_dead:       DB 0
plr_dead_timer: DB 0
plr_big:        DB 0
plr_inv_timer:  DB 0

cam_x:          DW 0
cam_max:        DW (MAP_W-SCREEN_TW)*TILE_PX

game_state:     DB STATE_TITLE
score:          DS 4, 0
lives:          DB 3
coins:          DB 0
world:          DB 0
level_num:      DB 0
level_timer:    DW 400
timer_cnt:      DB 0

cur_level_bank: DB 0
cur_level_map:  DW $C000

ent_type:       DS MAX_ENEMIES, 0
ent_xl:         DS MAX_ENEMIES, 0
ent_xh:         DS MAX_ENEMIES, 0
ent_yl:         DS MAX_ENEMIES, 0
ent_yh:         DS MAX_ENEMIES, 0
ent_vx:         DS MAX_ENEMIES, 0
ent_state:      DS MAX_ENEMIES, 0
ent_anim:       DS MAX_ENEMIES, 0
ent_anim_cnt:   DS MAX_ENEMIES, 0

pwrup_xl:       DB 0
pwrup_xh:       DB 0
pwrup_yl:       DB 0
pwrup_active:   DB 0
pwrup_vy:       DB 0

joy_held:       DB 0
joy_new:        DB 0
joy_prev:       DB 0

frame_count:    DW 0
ay_buf:         DS 14, 0

sfx_active:     DB 0
sfx_ptr:        DW 0
sfx_frame:      DB 0

music_ptr:      DW 0
music_note_ptr: DW 0
music_frame:    DB 0
music_playing:  DB 0

cam_tile_x:     DB 0
cam_sub_x:      DB 0
bankswitch_ok:  DB 0        ; set to 1 if 128K paging available

; Level map cache — filled at level load, read by GetTileAt
; Lives in fixed bank2 so no paging needed during rendering
level_map_cache: DS MAP_W * MAP_H, 0

; ============================================================
; ENTRY POINT  (address follows variables, after $8003)
; ============================================================
GAME_START:
    di
    ld sp, $BFF8
    ; Mark 128K paging as available (this is a 128K-only binary)
    ld a, 1
    ld (bankswitch_ok), a
    call ClearScreen
    call Setup_IM2
    call AY_Silence
    jp MainLoop

; ============================================================
; IM2 SETUP
; ============================================================
Setup_IM2:
    di
    ld hl, IM2_TABLE
    ld b, 0
    ld a, $BC
.fill:
    ld (hl), a
    inc hl
    djnz .fill
    ld (hl), a
    ld hl, IM2_JUMP
    ld (hl), $C3
    inc hl
    ld (hl), low HANDLER_ADDR
    inc hl
    ld (hl), high HANDLER_ADDR
    ld a, $7E
    ld i, a
    im 2
    ei
    ret

; ============================================================
; LEVEL LOAD HELPERS — must live in bank2 (fixed) because
; InitLevel calls BankSwitch which pages out bank7.
; If these were in bank7 they'd vanish mid-execution.
; ============================================================

SetLevelMapPtr:
    ; Returns HL = $C000 + level_num * MAP_W*MAP_H
    ld hl, $C000
    ld a, (level_num)
    or a
    ret z
    ld de, MAP_W * MAP_H
    add hl, de
    dec a
    ret z
    add hl, de
    ret

LoadLevelMap:
    ; Copy level map from paged bank ($C000) → level_map_cache (bank2)
    ; Level bank must already be paged in.
    call SetLevelMapPtr     ; HL = map start in paged bank
    ld de, level_map_cache
    ld bc, MAP_W * MAP_H
    ldir
    ret

LoadEnemySpawns:
    ; Spawn table base: $C000 + 3*MAP_W*MAP_H, then +32 per level
    ld hl, $C000 + 3 * MAP_W * MAP_H
    ld a, (level_num)
    or a
    jr z, .les_ready
    ld de, 32
.les_off:
    add hl, de
    dec a
    jr nz, .les_off
.les_ready:
    ld b, MAX_ENEMIES
    ld c, 0
.les_loop:
    ld a, (hl)
    cp $FF
    jr z, .les_done
    or a
    jr z, .les_done

    push hl
    ld hl, ent_type
    ld d, 0
    ld e, c
    add hl, de
    ld (hl), a
    pop hl

    inc hl
    ld a, (hl)
    add a, a
    add a, a
    add a, a
    add a, a
    push hl
    ld hl, ent_xl
    ld d, 0
    ld e, c
    add hl, de
    ld (hl), a
    pop hl

    inc hl
    ld a, (hl)
    add a, a
    add a, a
    add a, a
    add a, a
    push hl
    ld hl, ent_yl
    ld d, 0
    ld e, c
    add hl, de
    ld (hl), a

    ld hl, ent_vx
    add hl, de
    ld (hl), $FF

    ld hl, ent_state
    add hl, de
    ld (hl), 1
    pop hl

    inc hl
    inc c
    djnz .les_loop
.les_done:
    ret

; ============================================================
; INTERRUPT HANDLER
; ============================================================
    ORG HANDLER_ADDR

HANDLER:
    di
    push af
    push bc
    push de
    push hl
    push ix

    ld hl, frame_count
    inc (hl)
    jr nz, .no_hi
    inc hl
    inc (hl)
.no_hi:

    ld a, (game_state)
    cp STATE_PLAYING
    jr nz, .no_timer
    ld hl, timer_cnt
    inc (hl)
    ld a, (hl)
    cp 50
    jr c, .no_timer
    ld (hl), 0
    ld hl, level_timer
    ld a, (hl)
    or a
    jr z, .no_timer
    dec (hl)
.no_timer:

    ; Read Kempston joystick. Port $1F floats to $FF with no joystick,
    ; which would set all bits. Check keyboard row $7FFE (0-Space row)
    ; bit 0 = Caps, bit 1 = Z, bit 2 = X, bit 3 = C, bit 4 = V
    ; We use: up=$7FFE(V=b4), down/left/right from same, fire=Space($7FFE b0 of $BFFE)
    ; Simple approach: AND joy read with keyboard - if no joystick, kbd takes over.
    in a, ($1F)
    and $1F
    ; If all 5 bits set, likely no joystick (floating) - zero it out
    cp $1F
    jr nz, .joy_real
    xor a   ; no joystick connected, zero
.joy_real:
    ; Map keyboard to joystick bits: Space=$BFFE b0 = fire (bit 4 of joy)
    push af
    ld a, $BF
    in a, ($FE)
    bit 0, a         ; Space key (active low)
    jr nz, .no_space
    pop af
    or %00010000     ; set fire bit
    jr .joy_done
.no_space:
    pop af
.joy_done:
    ld (joy_held), a
    ld b, a
    ld a, (joy_prev)
    cpl
    and b
    ld (joy_new), a
    ld a, (joy_held)
    ld (joy_prev), a

    ld a, (music_playing)
    or a
    jr z, .no_music
    call Music_Tick
.no_music:

    ld a, (sfx_active)
    or a
    jr z, .no_sfx
    call SFX_Tick
.no_sfx:

    call AY_WriteBuffer

    pop ix
    pop hl
    pop de
    pop bc
    pop af
    ei
    reti

; ============================================================
; AY ROUTINES
; ============================================================

AY_Silence:
    ld bc, $FFFD
    ld a, AY_MIXER
    out (c), a
    ld bc, $BFFD
    ld a, $FF
    out (c), a
    ld bc, $FFFD
    ld a, AY_VOL_A
    out (c), a
    ld bc, $BFFD
    xor a
    out (c), a
    ld bc, $FFFD
    ld a, AY_VOL_B
    out (c), a
    ld bc, $BFFD
    xor a
    out (c), a
    ld bc, $FFFD
    ld a, AY_VOL_C
    out (c), a
    ld bc, $BFFD
    xor a
    out (c), a
    ld hl, ay_buf
    ld b, 14
    xor a
.clr:
    ld (hl), a
    inc hl
    djnz .clr
    ld a, $FF
    ld (ay_buf + AY_MIXER), a
    ret

    ; $BCB6-$BCBF: reserved gap for IM2 JP stub at $BCBC.
    ; Setup_IM2 and make_szx.py both write JP $BC00 at $BCBC-$BCBE.
    ; AY_WriteBuffer MUST start at $BCC0 so it is entirely past this stub.
    ; We pad here so the label naturally assembles at $BCC0.
    DS $BCC0 - $, 0

AY_WriteBuffer:
    ld hl, ay_buf
    ld b, 0
.wr:
    ld a, b
    push bc
    ld bc, $FFFD
    out (c), a
    ld a, (hl)
    ld bc, $BFFD
    out (c), a
    pop bc
    inc hl
    inc b
    ld a, b
    cp 14
    jr nz, .wr
    ret

; ============================================================
; MUSIC ENGINE
; Note entry (6 bytes): period_lo, period_hi, vol_a, vol_b, vol_c, duration
; Sequence ends with $FF, $FF
; ============================================================

Music_Init:
    ld (music_ptr), hl
    ld (music_note_ptr), hl
    xor a
    ld (music_frame), a
    ld a, 1
    ld (music_playing), a
    ret

Music_Stop:
    xor a
    ld (music_playing), a
    call AY_Silence
    ret

Music_Tick:
    push hl
    push bc
    push de

    ld hl, (music_note_ptr)

    ld a, (hl)
    cp $FF
    jr nz, .mt_check_dur
    inc hl
    ld a, (hl)
    cp $FF
    jr nz, .mt_check_dur
    ld hl, (music_ptr)
    ld (music_note_ptr), hl
    xor a
    ld (music_frame), a
    jr .mt_load

.mt_check_dur:
    push hl
    ld bc, 5
    add hl, bc
    ld b, (hl)              ; duration
    pop hl
    ld a, (music_frame)
    inc a
    ld (music_frame), a
    cp b
    jr c, .mt_still

    ld bc, 6
    add hl, bc
    ld (music_note_ptr), hl
    xor a
    ld (music_frame), a

    ld a, (hl)
    cp $FF
    jr nz, .mt_load
    inc hl
    ld a, (hl)
    cp $FF
    jr nz, .mt_load
    ld hl, (music_ptr)
    ld (music_note_ptr), hl
    xor a
    ld (music_frame), a

.mt_load:
    ld a, (hl)
    ld (ay_buf + AY_FINE_A), a
    inc hl
    ld a, (hl)
    ld (ay_buf + AY_COARSE_A), a
    inc hl
    ld a, (hl)
    ld (ay_buf + AY_VOL_A), a
    inc hl
    ld a, (hl)
    ld (ay_buf + AY_VOL_B), a
    inc hl
    ld a, (hl)
    ld (ay_buf + AY_VOL_C), a
    ld a, %11111110
    ld (ay_buf + AY_MIXER), a

.mt_still:
    pop de
    pop bc
    pop hl
    ret

; ============================================================
; SFX ENGINE (channel C)
; SFX entry (4 bytes): period_lo, period_hi, vol, duration
; Ends with $FF
; ============================================================

SFX_Play:
    ; A = SFX index
    push hl
    push de
    ld hl, SFX_TABLE
    ld d, 0
    ld e, a
    add hl, de
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (sfx_ptr), de
    xor a
    ld (sfx_frame), a
    ld a, 1
    ld (sfx_active), a
    pop de
    pop hl
    ret

SFX_Tick:
    push hl
    push de
    push bc

    ld hl, (sfx_ptr)
    ld a, (hl)
    cp $FF
    jr z, .st_done

    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    ld a, (hl)
    ld (ay_buf + AY_VOL_C), a
    inc hl
    ld b, (hl)

    ld hl, sfx_frame
    inc (hl)
    ld a, (hl)
    cp b
    jr c, .st_write

    ld hl, (sfx_ptr)
    ld bc, 4
    add hl, bc
    ld (sfx_ptr), hl
    xor a
    ld (sfx_frame), a

.st_write:
    ld a, e
    ld (ay_buf + AY_FINE_C), a
    ld a, d
    ld (ay_buf + AY_COARSE_C), a
    ld a, (ay_buf + AY_MIXER)
    and %11111011
    ld (ay_buf + AY_MIXER), a
    pop bc
    pop de
    pop hl
    ret

.st_done:
    xor a
    ld (sfx_active), a
    ld (ay_buf + AY_VOL_C), a
    ld a, (ay_buf + AY_MIXER)
    or %00000100
    ld (ay_buf + AY_MIXER), a
    pop bc
    pop de
    pop hl
    ret

SFX_TABLE:
    DW SFX_DATA_JUMP
    DW SFX_DATA_COIN
    DW SFX_DATA_BUMP
    DW SFX_DATA_STOMP
    DW SFX_DATA_DIE
    DW SFX_DATA_POWERUP
    DW SFX_DATA_BOSSHIT
    DW SFX_DATA_LVLEND

SFX_DATA_JUMP:
    DEFB low NOTE_E5, high NOTE_E5, 12, 3
    DEFB low NOTE_G5, high NOTE_G5, 10, 3
    DEFB low NOTE_C6, high NOTE_C6,  8, 4
    DEFB $FF

SFX_DATA_COIN:
    DEFB low NOTE_G5, high NOTE_G5, 14, 2
    DEFB low NOTE_C6, high NOTE_C6, 14, 4
    DEFB $FF

SFX_DATA_BUMP:
    DEFB low NOTE_C4, high NOTE_C4, 12, 3
    DEFB low NOTE_A4, high NOTE_A4, 10, 3
    DEFB $FF

SFX_DATA_STOMP:
    DEFB low NOTE_A4, high NOTE_A4, 12, 2
    DEFB low NOTE_E4, high NOTE_E4,  8, 3
    DEFB $FF

SFX_DATA_DIE:
    DEFB low NOTE_A5, high NOTE_A5, 15, 4
    DEFB low NOTE_G5, high NOTE_G5, 13, 3
    DEFB low NOTE_F5, high NOTE_F5, 11, 3
    DEFB low NOTE_E5, high NOTE_E5,  9, 4
    DEFB low NOTE_D5, high NOTE_D5,  7, 4
    DEFB low NOTE_C5, high NOTE_C5,  5, 6
    DEFB $FF

SFX_DATA_POWERUP:
    DEFB low NOTE_C5, high NOTE_C5, 12, 2
    DEFB low NOTE_E5, high NOTE_E5, 12, 2
    DEFB low NOTE_G5, high NOTE_G5, 12, 2
    DEFB low NOTE_C6, high NOTE_C6, 12, 6
    DEFB $FF

SFX_DATA_BOSSHIT:
    DEFB low NOTE_D4, high NOTE_D4, 15, 2
    DEFB low NOTE_A4, high NOTE_A4, 12, 3
    DEFB $FF

SFX_DATA_LVLEND:
    DEFB low NOTE_C5, high NOTE_C5, 14, 3
    DEFB low NOTE_E5, high NOTE_E5, 14, 3
    DEFB low NOTE_G5, high NOTE_G5, 14, 3
    DEFB low NOTE_C6, high NOTE_C6, 14, 8
    DEFB low NOTE_C6, high NOTE_C6,  0, 3
    DEFB low NOTE_C6, high NOTE_C6, 14,10
    DEFB $FF

; ============================================================
; MUSIC DATA
; ============================================================
MUSIC_OVERWORLD:
    DEFB low NOTE_E5,  high NOTE_E5,  12, 0, 0,  4
    DEFB low NOTE_REST,0,               0, 0, 0,  2
    DEFB low NOTE_E5,  high NOTE_E5,  12, 0, 0,  4
    DEFB low NOTE_REST,0,               0, 0, 0,  2
    DEFB low NOTE_C5,  high NOTE_C5,  12, 0, 0,  4
    DEFB low NOTE_E5,  high NOTE_E5,  12, 0, 0,  6
    DEFB low NOTE_G5,  high NOTE_G5,  12, 0, 0,  8
    DEFB low NOTE_G4,  high NOTE_G4,   8, 0, 0,  8
    DEFB low NOTE_C5,  high NOTE_C5,  12, 0, 0,  8
    DEFB low NOTE_G4,  high NOTE_G4,  10, 0, 0,  6
    DEFB low NOTE_REST,0,               0, 0, 0,  4
    DEFB low NOTE_E4,  high NOTE_E4,  10, 0, 0,  8
    DEFB low NOTE_A4,  high NOTE_A4,  12, 0, 0,  6
    DEFB low NOTE_B4,  high NOTE_B4,  12, 0, 0,  4
    DEFB low NOTE_A4,  high NOTE_A4,  11, 0, 0,  4
    DEFB low NOTE_A4,  high NOTE_A4,  12, 0, 0,  6
    DEFB low NOTE_G4,  high NOTE_G4,  11, 0, 0,  5
    DEFB low NOTE_E5,  high NOTE_E5,  12, 0, 0,  5
    DEFB low NOTE_G5,  high NOTE_G5,  12, 0, 0,  5
    DEFB low NOTE_A5,  high NOTE_A5,  12, 0, 0,  6
    DEFB low NOTE_F5,  high NOTE_F5,  11, 0, 0,  5
    DEFB low NOTE_G5,  high NOTE_G5,  10, 0, 0,  4
    DEFB low NOTE_REST,0,               0, 0, 0,  2
    DEFB low NOTE_E5,  high NOTE_E5,  12, 0, 0,  6
    DEFB low NOTE_C5,  high NOTE_C5,  12, 0, 0,  4
    DEFB low NOTE_D5,  high NOTE_D5,  11, 0, 0,  4
    DEFB low NOTE_B4,  high NOTE_B4,  10, 0, 0,  6
    DEFB $FF, $FF

MUSIC_BOSS:
    DEFB low NOTE_A4,  high NOTE_A4,  13, 0, 0,  3
    DEFB low NOTE_REST,0,               0, 0, 0,  1
    DEFB low NOTE_A4,  high NOTE_A4,  13, 0, 0,  3
    DEFB low NOTE_REST,0,               0, 0, 0,  1
    DEFB low NOTE_A4,  high NOTE_A4,  13, 0, 0,  3
    DEFB low NOTE_A5,  high NOTE_A5,  14, 0, 0,  3
    DEFB low NOTE_G5,  high NOTE_G5,  12, 0, 0,  4
    DEFB low NOTE_F5,  high NOTE_F5,  11, 0, 0,  4
    DEFB low NOTE_E5,  high NOTE_E5,  13, 0, 0,  4
    DEFB low NOTE_REST,0,               0, 0, 0,  2
    DEFB low NOTE_C5,  high NOTE_C5,  12, 0, 0,  3
    DEFB low NOTE_E5,  high NOTE_E5,  13, 0, 0,  4
    DEFB low NOTE_D5,  high NOTE_D5,  12, 0, 0,  3
    DEFB low NOTE_D5,  high NOTE_D5,  13, 0, 0,  5
    DEFB $FF, $FF

MUSIC_TITLE:
    DEFB low NOTE_C5,  high NOTE_C5,  13, 0, 0,  4
    DEFB low NOTE_C5,  high NOTE_C5,  13, 0, 0,  4
    DEFB low NOTE_C5,  high NOTE_C5,  13, 0, 0,  4
    DEFB low NOTE_C5,  high NOTE_C5,   0, 0, 0,  2
    DEFB low NOTE_G4,  high NOTE_G4,  12, 0, 0,  4
    DEFB low NOTE_G4,  high NOTE_G4,   0, 0, 0,  2
    DEFB low NOTE_G4,  high NOTE_G4,  13, 0, 0,  8
    DEFB low NOTE_REST,0,               0, 0, 0,  4
    DEFB low NOTE_E5,  high NOTE_E5,  13, 0, 0,  4
    DEFB low NOTE_E5,  high NOTE_E5,   0, 0, 0,  2
    DEFB low NOTE_E5,  high NOTE_E5,  13, 0, 0,  4
    DEFB low NOTE_C5,  high NOTE_C5,  12, 0, 0,  4
    DEFB low NOTE_E5,  high NOTE_E5,  13, 0, 0,  6
    DEFB low NOTE_G5,  high NOTE_G5,  14, 0, 0, 10
    DEFB $FF, $FF

; ============================================================
; BANK SWITCH — A = bank number 0-7
; Skips the port write if bankswitch_ok=0 (48K/SNA mode)
; ============================================================
BankSwitch:
    di
    push bc
    push af
    ld b, a
    ld a, (bankswitch_ok)
    or a
    jr z, .bs_skip          ; 48K mode: skip port write
    ld a, b
    and $07
    ld b, a
    ld a, ($5B5C)
    and $F8
    or b
    ld ($5B5C), a
    ld bc, $7FFD
    out (c), a
.bs_skip:
    pop af
    pop bc
    ei
    ret

; ============================================================
; CLEAR SCREEN
; ============================================================
ClearScreen:
    di                      ; disable interrupts — an interrupt firing mid-ldir
                            ; corrupts the return address on the stack
    ld hl, SCREEN_BASE
    ld de, SCREEN_BASE+1
    ld bc, SCREEN_SIZE-1
    ld (hl), 0
    ldir
    ld hl, ATTR_BASE
    ld de, ATTR_BASE+1
    ld bc, 767
    ld (hl), ATTR_SKY
    ldir
    ld a, 1
    out (PORT_ULA), a
    ei                      ; re-enable interrupts before returning
    ret

; ============================================================
; PIXEL ADDRESS — B=pixel row → HL=screen address (col 0)
; ============================================================
PixelAddr:
    ld a, b
    and $C0
    rrca
    rrca
    rrca
    ld h, a
    ld a, b
    and $07
    rrca
    rrca
    rrca
    or h
    or $40
    ld h, a
    ld a, b
    and $38
    add a, a
    add a, a
    ld l, a
    ret

; ============================================================
; DrawCharXY trampoline — PINNED at $BFFD.
; JP nn is 3 bytes: $BFFD/$BFFE/$BFFF — the last safe slot
; entirely within bank2. Adding code above? Check for overlap.
; ============================================================
    ORG $BFFD
DrawCharXY:
    jp DrawCharXY_Real

; ============================================================
; BANK 7 — CODE OVERFLOW ($C000-$FFFF when bank 7 paged)
; Always paged during gameplay. Bank2 ($8000-$BFFF) is fixed.
; DrawCharXY trampoline in bank2 jumps here.
; ============================================================
    PAGE 7
    ORG $C000

DrawCharXY_Real:
    push hl
    push de
    push bc
    push ix
    push af

    sub 32
    jp c, .dcxy_skip
    cp 96
    jp nc, .dcxy_skip

    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, FONT_DATA
    add hl, de
    push hl
    pop ix

    ld a, c
    add a, a
    add a, a
    add a, a
    ld e, a
    and $C0
    rrca
    rrca
    rrca
    ld d, a
    ld a, e
    and $07
    rrca
    rrca
    rrca
    or d
    or $40
    ld d, a
    ld a, e
    and $38
    add a, a
    add a, a
    ld e, a
    ld a, b
    and $1F
    or e
    ld e, a

    ld b, 8
.dcxy_row:
    ld a, (ix+0)
    ld (de), a
    inc ix
    inc d
    ld a, d
    and $07
    jr nz, .dcxy_cont
    ld a, e
    add a, $20
    ld e, a
    jr nc, .dcxy_cont
    ld a, d
    sub $08
    ld d, a
.dcxy_cont:
    djnz .dcxy_row

.dcxy_skip:
    pop af
    pop ix
    pop bc
    pop de
    pop hl
    ret

DrawString:
    push af
    push bc
.dstr_loop:
    ld a, (hl)
    or a
    jr z, .dstr_done
    call DrawCharXY
    inc hl
    inc b
    jr .dstr_loop
.dstr_done:
    pop bc
    pop af
    ret

DrawDigit:
    ; A=0-9, B=col, C=row
    add a, '0'
    jp DrawCharXY

DrawDecimal2:
    ; A=0-99, B=col, C=row
    push af
    push bc
    ld d, 0
.dd2_tens:
    cp 10
    jr c, .dd2_got
    sub 10
    inc d
    jr .dd2_tens
.dd2_got:
    push af
    ld a, d
    add a, '0'
    call DrawCharXY
    inc b
    pop af
    add a, '0'
    call DrawCharXY
    pop bc
    pop af
    ret

DrawDecimal3:
    ; A=0-199, B=col, C=row  (used for level timer display)
    push af
    push bc
    ; hundreds digit
    ld d, 0
    cp 100
    jr c, .dd3_u
    sub 100
    inc d
.dd3_u:
    push af
    ld a, d
    add a, '0'
    call DrawCharXY
    inc b
    pop af
    ; tens digit
    ld d, 0
.dd3_tens:
    cp 10
    jr c, .dd3_got
    sub 10
    inc d
    jr .dd3_tens
.dd3_got:
    push af
    ld a, d
    add a, '0'
    call DrawCharXY
    inc b
    pop af
    add a, '0'
    call DrawCharXY
    pop bc
    pop af
    ret

; ============================================================
; TILE ATTRIBUTE TABLE
; ============================================================
TILE_ATTR_TAB:
    DEFB ATTR_SKY       ; 0 air
    DEFB ATTR_GROUND_C  ; 1 ground
    DEFB ATTR_BRICK_C   ; 2 brick
    DEFB ATTR_QBLOCK_C  ; 3 Q-block
    DEFB ATTR_PIPE_C    ; 4 pipe top
    DEFB ATTR_PIPE_C    ; 5 pipe body
    DEFB ATTR_FLAG_C    ; 6 flag
    DEFB ATTR_SKY       ; 7 solid invisible
    DEFB ATTR_USEDQ_C   ; 8 used Q-block
    DEFB ATTR_CASTLE_C  ; 9 castle

GetTileAttr:
    ; A = tile ID → returns A = attribute byte
    ld hl, TILE_ATTR_TAB
    ld d, 0
    ld e, a
    add hl, de
    ld a, (hl)
    ret

; ============================================================
; TILE PIXEL DATA — 10 tiles × 32 bytes each
; ============================================================
TILE_DATA:

; 0: Air
    DS 32, 0

; 1: Ground
    DEFB %11111111,%11111111
    DEFB %10000010,%00001000
    DEFB %10010010,%01001001
    DEFB %11111111,%11111111
    DEFB %11001100,%11001100
    DEFB %11001100,%11001100
    DEFB %11111111,%11111111
    DEFB %10000010,%00001000
    DEFB %10010010,%01001001
    DEFB %11111111,%11111111
    DEFB %11001100,%11001100
    DEFB %11001100,%11001100
    DEFB %11111111,%11111111
    DEFB %10000010,%00001000
    DEFB %10010010,%01001001
    DEFB %11111111,%11111111

; 2: Brick
    DEFB %11111111,%11111110
    DEFB %10010010,%01001010
    DEFB %10010010,%01001010
    DEFB %11111111,%11111110
    DEFB %11001001,%00100110
    DEFB %11001001,%00100110
    DEFB %11111111,%11111110
    DEFB %10010010,%01001010
    DEFB %10010010,%01001010
    DEFB %11111111,%11111110
    DEFB %11001001,%00100110
    DEFB %11001001,%00100110
    DEFB %11111111,%11111110
    DEFB %10010010,%01001010
    DEFB %10010010,%01001010
    DEFB %11111111,%11111110

; 3: Q-Block
    DEFB %11111111,%11111100
    DEFB %11000011,%00000100
    DEFB %10100010,%10001100
    DEFB %10010010,%01001100
    DEFB %11111111,%11111100
    DEFB %10011001,%00110100
    DEFB %10101001,%01010100
    DEFB %11001001,%10010100
    DEFB %11111111,%11111100
    DEFB %10010010,%01001100
    DEFB %10100010,%10001100
    DEFB %10010010,%01001100
    DEFB %11111111,%11111100
    DEFB %10000000,%00000100
    DEFB %10111111,%11110100
    DEFB %11111111,%11111100

; 4: Pipe Top
    DEFB %00011111,%11110000
    DEFB %00111111,%11111000
    DEFB %01111111,%11111100
    DEFB %01111111,%11111100
    DEFB %00111111,%11111000
    DEFB %00011111,%11110000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000

; 5: Pipe Body
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000
    DEFB %00001111,%11100000

; 6: Flag
    DEFB %00000010,%00000000
    DEFB %00000011,%00000000
    DEFB %00000011,%10000000
    DEFB %00000011,%11000000
    DEFB %00000011,%10000000
    DEFB %00000011,%00000000
    DEFB %00000010,%00000000
    DEFB %00000010,%00000000
    DEFB %00000010,%00000000
    DEFB %00000010,%00000000
    DEFB %00000010,%00000000
    DEFB %00000010,%00000000
    DEFB %00000010,%00000000
    DEFB %00000011,%00000000
    DEFB %00000011,%00000000
    DEFB %00001111,%10000000

; 7: Solid invisible
    DS 32, 0

; 8: Used Q-block
    DEFB %11111111,%11111100
    DEFB %11000000,%00000100
    DEFB %10000000,%00001100
    DEFB %10000000,%00001100
    DEFB %11111111,%11111100
    DEFB %10000000,%00000100
    DEFB %10000000,%00000100
    DEFB %10000000,%00000100
    DEFB %11111111,%11111100
    DEFB %10000000,%00000100
    DEFB %10000000,%00000100
    DEFB %10000000,%00000100
    DEFB %11111111,%11111100
    DEFB %10000000,%00000100
    DEFB %10111111,%11110100
    DEFB %11111111,%11111100

; 9: Castle
    DEFB %01010101,%01010100
    DEFB %01010101,%01010100
    DEFB %01111111,%11111100
    DEFB %01111111,%11111100
    DEFB %01100110,%01100100
    DEFB %01100110,%01100100
    DEFB %01111111,%11111100
    DEFB %01111111,%11111100
    DEFB %01100110,%01100100
    DEFB %01100110,%01100100
    DEFB %01111111,%11111100
    DEFB %01111111,%11111100
    DEFB %01100110,%01100100
    DEFB %01100110,%01100100
    DEFB %01111111,%11111100
    DEFB %01111111,%11111100

; ============================================================
; DRAW TILE — A=tile_id, B=screen_pixel_x, C=screen_pixel_y
; Both B and C must be multiples of 8
; Uses IY to preserve pixel coords across attr write
; ============================================================
DrawTile:
    push hl
    push de
    push bc
    push ix
    push iy
    push af

    ; Tile data into IX
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, TILE_DATA
    add hl, de
    push hl
    pop ix

    ; Save pixel coords in IY
    ld iyh, b
    ld iyl, c

    ; Screen address from B (pixel x), C (pixel y) into DE
    ld a, c
    and $C0
    rrca
    rrca
    rrca
    ld d, a
    ld a, c
    and $07
    rrca
    rrca
    rrca
    or d
    or $40
    ld d, a
    ld a, c
    and $38
    add a, a
    add a, a
    ld e, a
    ld a, b
    rrca
    rrca
    rrca
    and $1F
    or e
    ld e, a

    ; Draw 16 rows × 2 bytes
    ld b, 16
.dt_row:
    ld a, (ix+0)
    ld (de), a
    inc de
    ld a, (ix+1)
    ld (de), a
    dec de
    push bc
    ld bc, 2
    add ix, bc
    pop bc
    inc d
    ld a, d
    and $07
    jr nz, .dt_cont
    ld a, e
    add a, $20
    ld e, a
    jr nc, .dt_cont
    ld a, d
    sub $08
    ld d, a
.dt_cont:
    djnz .dt_row

    ; Write 2×2 attribute cells
    pop af
    push af
    call GetTileAttr
    ld d, a             ; attr in D

    ld a, iyl           ; pixel_y
    rrca
    rrca
    rrca
    and $1F
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld bc, ATTR_BASE
    add hl, bc
    ld a, iyh           ; pixel_x
    rrca
    rrca
    rrca
    and $1F
    ld c, a
    ld b, 0
    add hl, bc

    ld (hl), d
    inc hl
    ld (hl), d
    ld bc, 31
    add hl, bc
    ld (hl), d
    inc hl
    ld (hl), d

    pop af
    pop iy
    pop ix
    pop bc
    pop de
    pop hl
    ret

; ============================================================
; RENDER LEVEL — draws 16×11 tile viewport
; Level bank must already be paged in
; ============================================================
RenderLevel:
    push hl
    push de
    push bc
    push ix
    push iy

    ; cam_tile_x = cam_x / 16
    ld hl, (cam_x)
    ld b, 4
.rl_camdiv:
    srl h
    rr l
    djnz .rl_camdiv
    ld a, l
    ld (cam_tile_x), a

    ld iyh, 0               ; tile row 0..MAP_H-1

.rl_rowloop:
    ld a, iyh
    cp MAP_H
    jp nc, .rl_done

    ld iyl, 0               ; tile col 0..SCREEN_TW-1

.rl_colloop:
    ld a, iyl
    cp SCREEN_TW
    jp nc, .rl_nextrow

    ; Map address = $C000 + row*64 + (cam_tile_x + col) & 63
    ld a, iyh           ; tile row (can't ld l,iyh directly, go via A)
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, level_map_cache
    add hl, de
    ld a, (cam_tile_x)
    add a, iyl
    and 63
    ld c, a
    ld b, 0
    add hl, bc
    ld a, (hl)              ; tile ID

    ; Screen pixel X = col * 16
    push af
    ld a, iyl
    add a, a
    add a, a
    add a, a
    add a, a
    ld b, a

    ; Screen pixel Y = row * 16
    ld a, iyh
    add a, a
    add a, a
    add a, a
    add a, a
    ld c, a

    pop af
    call DrawTile

    inc iyl
    jp .rl_colloop

.rl_nextrow:
    inc iyh
    jp .rl_rowloop

.rl_done:
    pop iy
    pop ix
    pop bc
    pop de
    pop hl
    ret

; ============================================================
; SPRITE DATA — 13 sprites × 32 bytes (16 rows × 2 bytes)
; ============================================================
SPRITE_DATA:

SPR_MARCO_STAND:
    DEFB %00000000,%00111100
    DEFB %00000000,%01111111
    DEFB %00000000,%01101011
    DEFB %00000000,%01111111
    DEFB %00000000,%00111100
    DEFB %00000000,%00011100
    DEFB %00000000,%01111110
    DEFB %00000000,%11111111
    DEFB %00000000,%10011010
    DEFB %00000000,%10111110
    DEFB %00000000,%01111100
    DEFB %00000000,%00111000
    DEFB %00000000,%00111000
    DEFB %00000000,%01111100
    DEFB %00000000,%11000110
    DEFB %00000000,%11000110

SPR_MARCO_WALK1:
    DEFB %00000000,%00111100
    DEFB %00000000,%01111111
    DEFB %00000000,%01101011
    DEFB %00000000,%01111111
    DEFB %00000000,%00111100
    DEFB %00000000,%00111100
    DEFB %00000000,%01111111
    DEFB %00000000,%11111111
    DEFB %00000000,%10111110
    DEFB %00000000,%10111100
    DEFB %00000000,%00111100
    DEFB %00000000,%00011100
    DEFB %00000000,%01101000
    DEFB %00000000,%11111100
    DEFB %00000000,%11000100
    DEFB %00000000,%00001100

SPR_MARCO_WALK2:
    DEFB %00000000,%00111100
    DEFB %00000000,%01111111
    DEFB %00000000,%01101011
    DEFB %00000000,%01111111
    DEFB %00000000,%00111100
    DEFB %00000000,%01110100
    DEFB %00000000,%11111100
    DEFB %00000001,%11111100
    DEFB %00000001,%01111100
    DEFB %00000000,%01111110
    DEFB %00000000,%00111110
    DEFB %00000000,%01110000
    DEFB %00000001,%00100000
    DEFB %00000001,%11000000
    DEFB %00000001,%10000000
    DEFB %00000001,%00000000

SPR_MARCO_JUMP:
    DEFB %00000000,%00111100
    DEFB %00000000,%01111111
    DEFB %00000000,%01101011
    DEFB %00000000,%01111111
    DEFB %00000000,%00111100
    DEFB %00000000,%00110111
    DEFB %00000000,%01111111
    DEFB %00000000,%11011111
    DEFB %00000000,%10111100
    DEFB %00000000,%10111111
    DEFB %00000000,%01111111
    DEFB %00000000,%00011110
    DEFB %00000000,%00011000
    DEFB %00000000,%00011000
    DEFB %00000000,%00011000
    DEFB %00000000,%00000000

SPR_WALKER1:
    DEFB %00000000,%00111111
    DEFB %00000000,%01111111
    DEFB %00000000,%11010010
    DEFB %00000000,%11111111
    DEFB %00000001,%11111111
    DEFB %00000001,%11110011
    DEFB %00000001,%11101110
    DEFB %00000001,%01111111
    DEFB %00000000,%00111111
    DEFB %00000001,%01111111
    DEFB %00000001,%11111111
    DEFB %00000001,%00111110
    DEFB %00000001,%00000000
    DEFB %00000001,%11000011
    DEFB %00000001,%11000011
    DEFB %00000000,%10000001

SPR_WALKER2:
    DEFB %00000000,%00111111
    DEFB %00000000,%01111111
    DEFB %00000000,%11010010
    DEFB %00000000,%11111111
    DEFB %00000001,%11111111
    DEFB %00000001,%11110011
    DEFB %00000001,%11101110
    DEFB %00000001,%01111111
    DEFB %00000000,%00111111
    DEFB %00000001,%01111111
    DEFB %00000001,%11111111
    DEFB %00000001,%00111110
    DEFB %00000001,%00000000
    DEFB %00000001,%10000111
    DEFB %00000001,%10000111
    DEFB %00000001,%00000010

SPR_WALKER_FLAT:
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000
    DEFB %00000001,%10011001
    DEFB %00000011,%11111111
    DEFB %00000011,%11111111
    DEFB %00000001,%11111111
    DEFB %00000000,%11111110
    DEFB %00000000,%00111100

SPR_SHELLER1:
    DEFB %00000000,%01111110
    DEFB %00000000,%11111111
    DEFB %00000001,%10011001
    DEFB %00000001,%11111111
    DEFB %00000001,%01100110
    DEFB %00000001,%11111111
    DEFB %00000001,%01100110
    DEFB %00000000,%11111110
    DEFB %00000000,%01111100
    DEFB %00000000,%00111000
    DEFB %00000000,%01111100
    DEFB %00000000,%11111110
    DEFB %00000001,%10000001
    DEFB %00000001,%10000001
    DEFB %00000000,%11000011
    DEFB %00000000,%01000010

SPR_COIN:
    DEFB %00000000,%00000110
    DEFB %00000000,%00001111
    DEFB %00000000,%00011111
    DEFB %00000000,%00111111
    DEFB %00000000,%00111111
    DEFB %00000000,%00111111
    DEFB %00000000,%00101011
    DEFB %00000000,%00101011
    DEFB %00000000,%00111111
    DEFB %00000000,%00111111
    DEFB %00000000,%00111111
    DEFB %00000000,%00011111
    DEFB %00000000,%00001111
    DEFB %00000000,%00000110
    DEFB %00000000,%00000000
    DEFB %00000000,%00000000

SPR_PWRUP:
    DEFB %00000000,%00111100
    DEFB %00000000,%01111110
    DEFB %00000000,%11011011
    DEFB %00000001,%10110110
    DEFB %00000001,%11111110
    DEFB %00000001,%11111110
    DEFB %00000001,%11111110
    DEFB %00000000,%11111100
    DEFB %00000000,%01111110
    DEFB %00000000,%01111110
    DEFB %00000000,%01100110
    DEFB %00000000,%01100110
    DEFB %00000000,%01111110
    DEFB %00000000,%01111110
    DEFB %00000000,%00111100
    DEFB %00000000,%00000000

SPR_BOSS1:
    DEFB %00000001,%11111110
    DEFB %00000011,%11111111
    DEFB %00000111,%01101111
    DEFB %00001111,%11111111
    DEFB %00001111,%11111111
    DEFB %00001111,%01101111
    DEFB %00001111,%11111111
    DEFB %00000111,%11111110
    DEFB %00000111,%11111110
    DEFB %00001111,%11111111
    DEFB %00011111,%11111111
    DEFB %00011001,%10011001
    DEFB %00011000,%00011001
    DEFB %00011111,%11111001
    DEFB %00001110,%01110000
    DEFB %00001110,%01110000

SPR_BOSS2:
    DEFB %00000001,%11111110
    DEFB %00000011,%11111111
    DEFB %00000111,%11011111
    DEFB %00001111,%11111111
    DEFB %00001110,%11110111
    DEFB %00001111,%11111111
    DEFB %00001111,%11111111
    DEFB %00000111,%11111110
    DEFB %00000011,%11111100
    DEFB %00000111,%11111110
    DEFB %00001111,%11111111
    DEFB %00011001,%10011001
    DEFB %00011000,%00011001
    DEFB %00011111,%11111001
    DEFB %00001110,%01110000
    DEFB %00001110,%01110000

; ============================================================
; DRAW SPRITE — IX=data, B=screen_x, C=screen_y
; OR-draws 16×16 pixels with sub-byte X shift
; ============================================================
DrawSprite:
    push hl
    push de
    push bc
    push ix

    ; Shift = B & 7
    ld a, b
    and $07
    ld e, a             ; shift amount in E

    ; Screen address into HL
    ld a, b
    rrca
    rrca
    rrca
    and $1F
    ld d, a             ; char column

    ld a, c
    and $C0
    rrca
    rrca
    rrca
    ld h, a
    ld a, c
    and $07
    rrca
    rrca
    rrca
    or h
    or $40
    ld h, a
    ld a, c
    and $38
    add a, a
    add a, a
    ld l, a
    ld a, d
    and $1F
    or l
    ld l, a

    ld b, 16
.ds_row:
    push bc
    push hl

    ld b, (ix+0)
    ld c, (ix+1)
    push bc
    ld bc, 2
    add ix, bc
    pop bc

    ld a, e
    or a
    jr z, .ds_no_shift

    ld d, 0
.ds_shift:
    srl b
    rr c
    rr d
    dec a
    jr nz, .ds_shift

    ld a, (hl)
    or b
    ld (hl), a
    inc hl
    ld a, (hl)
    or c
    ld (hl), a
    inc hl
    ld a, (hl)
    or d
    ld (hl), a
    jr .ds_next

.ds_no_shift:
    ld a, (hl)
    or b
    ld (hl), a
    inc hl
    ld a, (hl)
    or c
    ld (hl), a

.ds_next:
    pop hl
    inc h
    ld a, h
    and $07
    jr nz, .ds_rowok
    ld a, l
    add a, $20
    ld l, a
    jr nc, .ds_rowok
    ld a, h
    sub $08
    ld h, a
.ds_rowok:
    pop bc
    djnz .ds_row

    pop ix
    pop bc
    pop de
    pop hl
    ret

; Erase 16×16 sprite area (zero 3 bytes × 16 rows)
EraseSprite:
    push hl
    push bc

    ld a, b
    rrca
    rrca
    rrca
    and $1F
    ld d, a

    ld a, c
    and $C0
    rrca
    rrca
    rrca
    ld h, a
    ld a, c
    and $07
    rrca
    rrca
    rrca
    or h
    or $40
    ld h, a
    ld a, c
    and $38
    add a, a
    add a, a
    ld l, a
    ld a, d
    or l
    ld l, a

    ld b, 16
.er_row:
    ld (hl), 0
    inc hl
    ld (hl), 0
    inc hl
    ld (hl), 0
    dec hl
    dec hl
    inc h
    ld a, h
    and $07
    jr nz, .er_ok
    ld a, l
    add a, $20
    ld l, a
    jr nc, .er_ok
    ld a, h
    sub $08
    ld h, a
.er_ok:
    djnz .er_row

    pop bc
    pop hl
    ret

; ============================================================
; PLAYER UPDATE
; ============================================================
UpdatePlayer:
    push hl
    push bc
    push af

    ; Decrement invincibility timer if active
    ld a, (plr_inv_timer)
    or a
    jr z, .up_inv_done
    dec a
    ld (plr_inv_timer), a
.up_inv_done:

    ld a, (joy_held)

    bit 1, a                ; left
    jr z, .up_not_left
    ld hl, plr_vx
    ld a, (hl)
    cp 256 - PLR_MAX_VX
    jr z, .up_not_left
    dec (hl)
    ld a, 1
    ld (plr_dir), a
.up_not_left:

    ld a, (joy_held)
    bit 0, a                ; right
    jr z, .up_not_right
    ld hl, plr_vx
    ld a, (hl)
    cp PLR_MAX_VX
    jr z, .up_not_right
    inc (hl)
    xor a
    ld (plr_dir), a
.up_not_right:

    ; Friction when no horizontal key
    ld a, (joy_held)
    and $03
    jr nz, .up_no_friction
    ld hl, plr_vx
    ld a, (hl)
    or a
    jr z, .up_no_friction
    jp m, .up_fric_neg
    dec (hl)
    jr .up_no_friction
.up_fric_neg:
    inc (hl)
.up_no_friction:

    ; Jump on fire (bit 4 = Kempston fire)
    ld a, (joy_new)
    bit 4, a
    jr z, .up_no_jump
    ld a, (plr_on_ground)
    or a
    jr z, .up_no_jump
    ld a, 256 - 8
    ld (plr_vy), a
    xor a
    ld (plr_on_ground), a
    ld a, 1
    ld (plr_jumping), a
    ld a, SFX_JUMP
    call SFX_Play
.up_no_jump:

    ; Variable jump height
    ld a, (joy_held)
    bit 4, a
    jr z, .up_do_gravity
    ld a, (plr_jumping)
    or a
    jr z, .up_do_gravity
    ld a, (plr_vy)
    cp 252                  ; -4 as unsigned
    jr nc, .up_stop_varjump
    jr .up_skip_gravity
.up_stop_varjump:
    xor a
    ld (plr_jumping), a
.up_do_gravity:
    ld hl, plr_vy
    ld a, (hl)
    add a, GRAVITY
    cp 9
    jr c, .up_grav_ok
    ld a, 8
.up_grav_ok:
    ld (hl), a
.up_skip_gravity:

    ; Apply vx to plr_x
    ld hl, (plr_x)
    ld a, (plr_vx)
    ld c, a
    ld b, 0
    bit 7, c
    jr z, .up_vx_pos
    ld b, $FF
.up_vx_pos:
    add hl, bc
    ; Clamp X >= 8
    bit 7, h
    jr z, .up_xpos_ok
    ld hl, 8
    xor a
    ld (plr_vx), a
    jr .up_x_done
.up_xpos_ok:
    ld a, h
    or a
    jr nz, .up_x_done
    ld a, l
    cp 8
    jr nc, .up_x_done
    ld hl, 8
    xor a
    ld (plr_vx), a
.up_x_done:
    ld (plr_x), hl

    ; Apply vy to plr_y
    ld hl, (plr_y)
    ld a, (plr_vy)
    ld c, a
    ld b, 0
    bit 7, c
    jr z, .up_vy_pos
    ld b, $FF
.up_vy_pos:
    add hl, bc
    ld (plr_y), hl

    call CheckGround

    ld a, (plr_vy)
    bit 7, a
    jr z, .up_no_ceiling
    call CheckCeiling
.up_no_ceiling:

    call UpdateCamera

    ; Animation counter
    ld hl, plr_anim_cnt
    inc (hl)
    ld a, (hl)
    cp 8
    jr c, .up_no_anim
    ld (hl), 0
    ld hl, plr_anim
    inc (hl)
    ld a, (hl)
    and $03
    ld (hl), a
.up_no_anim:

    ; Pit death (Y > 511)
    ld hl, (plr_y)
    ld a, h
    cp 2
    jr c, .up_no_pit
    call PlayerDie
.up_no_pit:

    pop af
    pop bc
    pop hl
    ret

; ============================================================
; TILE COLLISION HELPERS
; ============================================================

; GetTileAt: C=world_pixel_x, B=world_pixel_y → A=tile_id
; Level bank must be paged in
GetTileAt:
    ; Reads from level_map_cache in bank2 — no paging needed
    push hl
    push de

    ld a, c
    rrca
    rrca
    rrca
    rrca
    and $3F
    ld e, a             ; tile_x (0..63)

    ld a, b
    rrca
    rrca
    rrca
    rrca
    and $0F
    ld d, a             ; tile_y (0..10)

    cp MAP_H
    jp nc, .gta_solid
    ld a, e
    cp MAP_W
    jp nc, .gta_solid

    ; offset = tile_y * MAP_W + tile_x
    ld h, 0
    ld l, d
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl             ; hl = tile_y * 64  (MAP_W=64)
    ld de, level_map_cache
    add hl, de
    ld b, 0
    ld c, e
    add hl, bc
    ld a, (hl)
    jr .gta_done

.gta_solid:
    ld a, TILE_GROUND
.gta_done:
    pop de
    pop hl
    ret

; IsSolid — A=tile_id, NZ=solid Z=passable
IsSolid:
    or a
    ret z
    cp TILE_FLAG
    ret z
    ld a, 1
    or a
    ret

CheckGround:
    push hl
    push bc
    push de

    ; Player bottom = plr_y + PLR_H
    ld hl, (plr_y)
    ld a, l
    add a, PLR_H
    ld b, a

    ; Left foot
    ld hl, (plr_x)
    ld a, l
    add a, 4
    ld c, a
    call GetTileAt
    call IsSolid
    jp nz, .cg_snap

    ; Right foot
    ld hl, (plr_x)
    ld a, l
    add a, PLR_W - 4
    ld c, a
    call GetTileAt
    call IsSolid
    jr z, .cg_no_ground

.cg_snap:
    ld a, b
    and $F0
    sub PLR_H
    ld l, a
    ld h, 0
    ld (plr_y), hl
    xor a
    ld (plr_vy), a
    ld a, 1
    ld (plr_on_ground), a
    xor a
    ld (plr_jumping), a
    jr .cg_done

.cg_no_ground:
    xor a
    ld (plr_on_ground), a

.cg_done:
    pop de
    pop bc
    pop hl
    ret

CheckCeiling:
    push hl
    push bc

    ld hl, (plr_y)
    ld b, l

    ld hl, (plr_x)
    ld a, l
    add a, 8
    ld c, a
    call GetTileAt
    call IsSolid
    jr z, .cc_done

    cp TILE_QBLOCK
    call z, QBlockHit

    xor a
    ld (plr_vy), a
    ld hl, (plr_y)
    ld a, l
    and $F0
    add a, 16
    ld l, a
    ld (plr_y), hl
    ld a, SFX_BUMP
    call SFX_Play

.cc_done:
    pop bc
    pop hl
    ret

QBlockHit:
    push hl
    ld hl, coins
    inc (hl)
    ld hl, score
    ld a, (hl)
    add a, $50
    daa
    ld (hl), a
    ld a, SFX_COIN
    call SFX_Play
    pop hl
    ret

UpdateCamera:
    push hl
    push de

    ; Target = plr_x - 80
    ld hl, (plr_x)
    ld a, l
    sub 80
    ld l, a
    ld a, h
    sbc a, 0
    ld h, a

    bit 7, h
    jr z, .uc_pos
    ld hl, 0
.uc_pos:
    ld de, (cam_max)
    ld a, h
    cp d
    jp c, .uc_clamp_ok
    jr nz, .uc_clamp
    ld a, l
    cp e
    jr c, .uc_clamp_ok
.uc_clamp:
    ld hl, (cam_max)
.uc_clamp_ok:

    ; Smooth scroll toward HL
    ld de, (cam_x)
    ld a, h
    cp d
    jr c, .uc_retreat
    jr nz, .uc_advance
    ld a, l
    cp e
    jr nc, .uc_advance

.uc_retreat:
    ld a, e
    sub 2
    ld e, a
    jr nc, .uc_set
    dec d
    jr .uc_set

.uc_advance:
    ld a, e
    add a, 2
    ld e, a
    jr nc, .uc_set
    inc d

.uc_set:
    ld (cam_x), de

    pop de
    pop hl
    ret

; ============================================================
; ENEMY UPDATE & DRAW
; ============================================================
UpdateEnemies:
    push bc
    push hl

    ld b, MAX_ENEMIES
    ld c, 0

.uen_loop:
    push bc

    ld hl, ent_state
    ld d, 0
    ld e, c
    add hl, de
    ld a, (hl)
    or a
    jp z, .uen_skip

    ; Move by vx
    ld hl, ent_vx
    add hl, de
    ld a, (hl)
    or a
    jr nz, .uen_has_vx
    ld (hl), $FF            ; default: move left
.uen_has_vx:
    ld b, a             ; vx (signed: $FF = -1, $01 = +1)

    ld hl, ent_xl
    ld d, 0
    ld e, c
    add hl, de
    ld a, (hl)
    add a, b
    ld (hl), a          ; new ent_xl

    ; Bounce at left/right map pixel limits (tile 0 / tile MAP_W-1)
    cp 8                ; near left edge?
    jr nc, .uen_chk_right
    ld b, 1             ; reverse to rightward
    ld hl, ent_vx
    ld d, 0
    ld e, c
    add hl, de
    ld (hl), b
    jr .uen_post_move
.uen_chk_right:
    cp 240              ; right screen edge (8-bit limit: 15*16=240)
    jr c, .uen_post_move
    ld b, $FF           ; reverse to leftward
    ld hl, ent_vx
    ld d, 0
    ld e, c
    add hl, de
    ld (hl), b

.uen_post_move:
    ; Animate
    ld hl, ent_anim_cnt
    ld d, 0
    ld e, c
    add hl, de
    inc (hl)
    ld a, (hl)
    cp 8
    jr c, .uen_no_anim
    ld (hl), 0
    ld hl, ent_anim
    add hl, de
    ld a, (hl)
    xor 1
    ld (hl), a
.uen_no_anim:

    ; AABB vs player
    call CheckEnemyPlayer

.uen_skip:
    pop bc
    inc c
    djnz .uen_loop

    pop hl
    pop bc
    ret

; Check entity C against player
CheckEnemyPlayer:
    push hl
    push bc

    ld hl, ent_xl
    ld d, 0
    ld e, c
    add hl, de
    ld a, (hl)
    ld b, a             ; entity x

    ld a, (plr_x)       ; player world x lo
    sub b
    jp m, .cep_neg
    cp PLR_W + 16
    jp nc, .cep_no
    jr .cep_y
.cep_neg:
    neg
    cp 16
    jp nc, .cep_no
.cep_y:
    ld hl, ent_yl
    ld d, 0
    ld e, c
    add hl, de
    ld a, (hl)
    ld b, a

    ld a, (plr_y)
    sub b
    jp m, .cep_above
    cp PLR_H + 16
    jp nc, .cep_no
    jr .cep_hit
.cep_above:
    neg
    cp 16
    jp nc, .cep_no
.cep_hit:
    ; Stomp if player moving down
    ld a, (plr_vy)
    bit 7, a
    jr nz, .cep_stomp

    ; Player hurt — if big, lose powerup and go invincible; if small, die
    ld a, (plr_inv_timer)
    or a
    jr nz, .cep_no          ; already invincible
    ld a, (plr_big)
    or a
    jr z, .cep_die
    ; Big → lose powerup, gain 60-frame invincibility
    xor a
    ld (plr_big), a
    ld a, 60
    ld (plr_inv_timer), a
    jr .cep_no
.cep_die:
    call PlayerDie
    jr .cep_no

.cep_stomp:
    ; Kill enemy
    ld hl, ent_state
    ld d, 0
    ld e, c
    add hl, de
    ld (hl), 0
    ; Bounce player
    ld a, 256 - 5
    ld (plr_vy), a
    ; Score +100 (BCD)
    ld hl, score + 1
    ld a, (hl)
    add a, $01
    daa
    ld (hl), a
    ld a, SFX_STOMP
    call SFX_Play

.cep_no:
    pop bc
    pop hl
    ret

DrawEnemies:
    push bc
    push ix
    push iy

    ld b, MAX_ENEMIES
    ld c, 0             ; C = entity index (0..MAX_ENEMIES-1)

.den_loop:
    push bc

    ; Save entity index in IYL so C can be reused for screen_y
    ld iyl, c

    ; DE = {0, entity_index} for array addressing
    ld d, 0
    ld e, c

    ; Check entity active
    ld hl, ent_state
    add hl, de
    ld a, (hl)
    or a
    jp z, .den_skip

    ; screen_x = ent_xl[idx] - cam_x_lo
    ld hl, ent_xl
    add hl, de
    ld a, (hl)          ; ent_xl
    ld b, a
    ld a, (cam_x)       ; cam_x low byte
    sub b               ; cam_x - ent_xl
    neg                 ; ent_xl - cam_x  (screen x)
    cp 240
    jp nc, .den_skip    ; off screen (negative or > 239)

    ld iyh, a           ; save screen_x in IYH

    ; screen_y = ent_yl[idx]  (no vertical scroll)
    ld hl, ent_yl
    add hl, de
    ld a, (hl)
    push af             ; save screen_y

    ; Entity type → choose sprite
    ld hl, ent_type
    add hl, de
    ld a, (hl)

    cp ENT_WALKER
    jr nz, .den_sheller
    ; Use ent_anim to alternate between WALKER1 and WALKER2
    ld hl, ent_anim
    add hl, de
    ld a, (hl)
    or a
    jr z, .den_g1
    ld ix, SPR_WALKER2
    jr .den_draw
.den_g1:
    ld ix, SPR_WALKER1
    jr .den_draw
.den_sheller:
    cp ENT_SHELLER
    jr nz, .den_boss
    ld ix, SPR_SHELLER1
    jr .den_draw
.den_boss:
    ld ix, SPR_BOSS1

.den_draw:
    pop af
    ld c, a             ; screen_y
    ld b, iyh           ; screen_x
    call DrawSprite

.den_skip:
    pop bc
    ; Restore entity index from IYL for inc/djnz
    ld a, iyl
    ld c, a
    inc c
    djnz .den_loop

    pop iy
    pop ix
    pop bc
    ret

; ============================================================
; DRAW PLAYER
; ============================================================
DrawPlayer:
    push ix
    push bc

    ld a, (plr_dead)
    or a
    jr nz, .dp_dead

    ld a, (plr_on_ground)
    or a
    jr z, .dp_jumping

    ld a, (plr_vx)
    or a
    jr z, .dp_standing

    ld a, (plr_anim)
    and $01
    jr z, .dp_walk1
    ld ix, SPR_MARCO_WALK2
    jr .dp_draw
.dp_walk1:
    ld ix, SPR_MARCO_WALK1
    jr .dp_draw
.dp_standing:
    ld ix, SPR_MARCO_STAND
    jr .dp_draw
.dp_jumping:
    ld ix, SPR_MARCO_JUMP
    jr .dp_draw
.dp_dead:
    ld ix, SPR_MARCO_JUMP

.dp_draw:
    ld a, (plr_x)
    ld b, a
    ld a, (cam_x)
    ld c, a
    ld a, b
    sub c
    ld b, a             ; screen X

    ld a, (plr_y)
    ld c, a             ; screen Y

    call DrawSprite

    pop bc
    pop ix
    ret

; ============================================================
; POWERUP
; ============================================================
UpdatePowerup:
    ld a, (pwrup_active)
    or a
    ret z

    ld a, (pwrup_vy)
    inc a
    cp 5
    jr c, .upw_ok
    ld a, 4
.upw_ok:
    ld (pwrup_vy), a
    ld hl, pwrup_yl
    add a, (hl)
    ld (hl), a

    ; Check overlap with player
    ld a, (pwrup_xl)
    ld b, a
    ld a, (plr_x)
    sub b
    jp m, .upw_xneg
    cp PLR_W + 16
    jp nc, .upw_no
    jr .upw_y
.upw_xneg:
    neg
    cp 16
    jp nc, .upw_no
.upw_y:
    ld a, (pwrup_yl)
    ld b, a
    ld a, (plr_y)
    sub b
    jp m, .upw_yneg
    cp PLR_H + 16
    jp nc, .upw_no
    jr .upw_collect
.upw_yneg:
    neg
    cp 16
    jp nc, .upw_no
.upw_collect:
    xor a
    ld (pwrup_active), a
    ld a, 1
    ld (plr_big), a
    ld a, SFX_POWERUP
    call SFX_Play
.upw_no:
    ret

DrawPowerup:
    ld a, (pwrup_active)
    or a
    ret z
    ld ix, SPR_PWRUP
    ld a, (pwrup_xl)
    ld b, a
    ld a, (cam_x)
    sub b
    neg                 ; screen_x = pwrup_xl - cam_x
    ld b, a
    ld a, (pwrup_yl)
    ld c, a
    call DrawSprite
    ret

; ============================================================
; HUD
; ============================================================
DrawHUD:
    push hl
    push bc

    ld hl, ATTR_BASE
    ld b, 64
.hud_clr:
    ld (hl), $07
    inc hl
    djnz .hud_clr

    ld hl, STR_SCORE
    ld b, 0
    ld c, 0
    call DrawString

    ld a, (score+1)
    push af
    rrca
    rrca
    rrca
    rrca
    and $0F
    add a, '0'
    ld b, 6
    ld c, 0
    call DrawCharXY
    inc b
    pop af
    and $0F
    add a, '0'
    call DrawCharXY

    ld hl, STR_WORLD
    ld b, 16
    ld c, 0
    call DrawString
    ld a, (world)
    inc a
    add a, '0'
    ld b, 22
    ld c, 0
    call DrawCharXY
    ld a, '-'
    ld b, 23
    ld c, 0
    call DrawCharXY
    ld a, (level_num)
    inc a
    add a, '0'
    ld b, 24
    ld c, 0
    call DrawCharXY

    ld hl, STR_LIVES
    ld b, 0
    ld c, 1
    call DrawString
    ld a, (lives)
    ld b, 6
    ld c, 1
    call DrawDigit

    ld hl, STR_TIME
    ld b, 20
    ld c, 1
    call DrawString
    ld a, (level_timer)     ; low byte (0-199)
    ld b, 25
    ld c, 1
    call DrawDecimal3

    ld hl, STR_COINS
    ld b, 0
    ld c, 2
    call DrawString
    ld a, (coins)
    ld b, 6
    ld c, 2
    call DrawDecimal2

    pop bc
    pop hl
    ret

STR_SCORE:  DEFB "SCORE", 0
STR_WORLD:  DEFB "WORLD", 0
STR_LIVES:  DEFB "LIVES", 0
STR_TIME:   DEFB "TIME", 0
STR_COINS:  DEFB "COINS", 0

; ============================================================
; TITLE SCREEN
; ============================================================
TitleScreen:
    call ClearScreen
    ld a, 1
    out (PORT_ULA), a

    ld hl, STR_TITLE1
    ld b, 9
    ld c, 8
    call DrawString

    ld hl, STR_TITLE2
    ld b, 7
    ld c, 10
    call DrawString

    ld hl, STR_TITLE3
    ld b, 4
    ld c, 18
    call DrawString

    ld hl, MUSIC_TITLE
    call Music_Init

.ts_wait:
    halt
    ld a, (joy_new)
    bit 4, a
    jr z, .ts_wait

    call Music_Stop
    ret

STR_TITLE1: DEFB "MARCO BROS 128", 0
STR_TITLE2: DEFB "ZX SPECTRUM 128K", 0
STR_TITLE3: DEFB "FIRE TO START", 0

ShowLevelEntry:
    call ClearScreen
    ld hl, STR_WORLD
    ld b, 10
    ld c, 10
    call DrawString
    ld a, (world)
    inc a
    add a, '0'
    ld b, 16
    ld c, 10
    call DrawCharXY
    ld a, '-'
    ld b, 17
    ld c, 10
    call DrawCharXY
    ld a, (level_num)
    inc a
    add a, '0'
    ld b, 18
    ld c, 10
    call DrawCharXY
    ld hl, STR_LIVES
    ld b, 9
    ld c, 14
    call DrawString
    ld a, (lives)
    ld b, 16
    ld c, 14
    call DrawDigit
    ld b, 100
.sle_wait:
    halt
    djnz .sle_wait
    ret

ShowGameOver:
    call Music_Stop
    call ClearScreen
    ld hl, STR_GAMEOVER
    ld b, 8
    ld c, 11
    call DrawString
    ld b, 120
.sgo_wait:
    halt
    djnz .sgo_wait
.sgo_fire:
    halt
    ld a, (joy_new)
    bit 4, a
    jr z, .sgo_fire
    ret

ShowVictory:
    call Music_Stop
    call ClearScreen
    ld hl, STR_WIN1
    ld b, 7
    ld c, 9
    call DrawString
    ld hl, STR_WIN2
    ld b, 6
    ld c, 12
    call DrawString
    ld hl, MUSIC_TITLE
    call Music_Init
    ld b, 0
.sv_wait:
    halt
    djnz .sv_wait
    call Music_Stop
    ret

STR_GAMEOVER: DEFB "GAME OVER", 0
STR_WIN1:     DEFB "YOU WIN!", 0
STR_WIN2:     DEFB "CONGRATULATIONS", 0

PlayerDie:
    ld a, (plr_dead)
    or a
    ret nz
    ld a, 1
    ld (plr_dead), a
    xor a
    ld (plr_dead_timer), a
    ld a, 256 - 8
    ld (plr_vy), a
    ld a, STATE_DEAD
    ld (game_state), a
    ld a, SFX_DIE
    call SFX_Play
    call Music_Stop
    ret

CheckLevelEnd:
    ld hl, (plr_x)
    ld a, l
    add a, 8
    ld c, a
    ld hl, (plr_y)
    ld a, l
    add a, 8
    ld b, a
    call GetTileAt
    cp TILE_FLAG
    ret nz
    ld a, STATE_LEVELEND
    ld (game_state), a
    ld a, SFX_LEVELEND
    call SFX_Play
    ret

; ============================================================
; INIT
; ============================================================
InitGame:
    ld a, 3
    ld (lives), a
    xor a
    ld (score), a
    ld (score+1), a
    ld (score+2), a
    ld (score+3), a
    ld (coins), a
    ld (world), a
    ld (level_num), a
    ret

InitLevel:
    xor a
    ld (plr_dead), a
    ld (plr_dead_timer), a
    ld (plr_vx), a
    ld (plr_vy), a
    ld (plr_on_ground), a
    ld (plr_jumping), a
    ld (plr_big), a
    ld hl, 32
    ld (plr_x), hl
    ld hl, 144
    ld (plr_y), hl
    ld hl, 0
    ld (cam_x), hl
    ld hl, 200
    ld (level_timer), hl
    xor a
    ld (timer_cnt), a

    ld hl, ent_state
    ld de, ent_state+1
    ld bc, MAX_ENEMIES-1
    ld (hl), 0
    ldir
    ld hl, ent_type
    ld de, ent_type+1
    ld bc, MAX_ENEMIES-1
    ld (hl), 0
    ldir

    ld a, (world)
    or a
    jr nz, .il_w1
    ld a, 0
    jr .il_setbank
.il_w1:
    cp 1
    jr nz, .il_w2
    ld a, 1
    jr .il_setbank
.il_w2:
    ld a, 3
.il_setbank:
    ld (cur_level_bank), a

    call SetLevelMapPtr

    ; Page in level bank, copy map + spawns to bank2 caches, restore bank7
    ld a, (cur_level_bank)
    call BankSwitch
    call LoadLevelMap        ; copy map to level_map_cache
    call LoadEnemySpawns     ; copy spawns to ent arrays
    ld a, 7
    call BankSwitch          ; restore bank7

    ld a, (level_num)
    cp 2
    jr z, .il_boss_music
    ld hl, MUSIC_OVERWORLD
    call Music_Init
    jr .il_music_done
.il_boss_music:
    ld hl, MUSIC_BOSS
    call Music_Init
.il_music_done:

    ld a, STATE_PLAYING
    ld (game_state), a
    ret

; SetLevelMapPtr / LoadLevelMap / LoadEnemySpawns are in bank2 (fixed)
; so they survive BankSwitch calls during InitLevel.

; ============================================================
; MAIN GAME LOOP
; ============================================================
MainLoop:
    ld a, 1 : out ($FE), a   ; blue = entering TitleScreen
    call TitleScreen

.mg_restart:
    ld a, 2 : out ($FE), a   ; red = entering InitGame
    call InitGame

.mg_level:
    ld a, 3 : out ($FE), a   ; magenta = ShowLevelEntry
    call ShowLevelEntry
    ld a, 4 : out ($FE), a   ; green = InitLevel
    call InitLevel
    ld a, 5 : out ($FE), a   ; cyan = entering game loop

.mg_frame:
    halt

    ld a, (game_state)
    cp STATE_PLAYING
    jp nz, .mg_other

    ; All map data is in level_map_cache (fixed bank2). Bank7 must stay paged
    ; for DrawCharXY_Real. We never need to page the level bank during gameplay.

    call UpdatePlayer
    call UpdateEnemies
    call UpdatePowerup
    call CheckLevelEnd

    ; Check level timer expiry
    ld hl, (level_timer)
    ld a, h
    or l
    jr nz, .mg_timer_ok
    call PlayerDie
.mg_timer_ok:

    call RenderLevel
    call DrawPowerup
    call DrawEnemies
    call DrawPlayer
    call DrawHUD

    jp .mg_frame

.mg_other:
    cp STATE_DEAD
    jp z, .mg_dead
    cp STATE_LEVELEND
    jp z, .mg_levelend
    cp STATE_GAMEOVER
    jp z, .mg_gameover
    cp STATE_WIN
    jp z, .mg_win
    jp .mg_frame

.mg_dead:
    ld hl, plr_dead_timer
    inc (hl)
    ld a, (hl)
    cp 60
    jp nc, .mg_respawn

    ; Death bounce
    cp 25
    jr nc, .mg_dfalling
    ld hl, (plr_y)
    ld a, l
    sub 3
    ld l, a
    ld (plr_y), hl
    jr .mg_drender
.mg_dfalling:
    ld hl, (plr_y)
    ld a, l
    add a, 4
    ld l, a
    ld (plr_y), hl

.mg_drender:
    call RenderLevel
    call DrawPlayer
    call DrawHUD
    jp .mg_frame

.mg_respawn:
    ld hl, lives
    dec (hl)
    ld a, (hl)
    or a
    jp z, .mg_gameover
    ld a, STATE_PLAYING
    ld (game_state), a
    call InitLevel
    jp .mg_level

.mg_levelend:
    ld b, 100
.mg_le_wait:
    halt
    djnz .mg_le_wait

    ld hl, level_num
    inc (hl)
    ld a, (hl)
    cp 3
    jr nz, .mg_nextlevel
    ld (hl), 0
    ld hl, world
    inc (hl)
    ld a, (hl)
    cp 3
    jp nc, .mg_win
.mg_nextlevel:
    ld a, STATE_PLAYING
    ld (game_state), a
    jp .mg_level

.mg_gameover:
    call ShowGameOver
    jp .mg_restart

.mg_win:
    call ShowVictory
    jp .mg_restart

; ============================================================
; IM2 VECTOR TABLE
; ============================================================
    ORG IM2_TABLE
    DS 257, $BC

; ============================================================
; FONT DATA ($8E00 in Bank 2) — ASCII 32-127, 8 bytes each
; ============================================================
    ORG ENGINE_BASE + $0E00

FONT_DATA:
    DEFB $00,$00,$00,$00,$00,$00,$00,$00  ; 32 space
    DEFB $10,$10,$10,$10,$10,$00,$10,$00  ; 33 !
    DEFB $28,$28,$00,$00,$00,$00,$00,$00  ; 34 "
    DEFB $28,$7C,$28,$28,$7C,$28,$00,$00  ; 35 #
    DEFB $10,$7C,$90,$7C,$12,$7C,$10,$00  ; 36 $
    DEFB $C2,$C4,$08,$10,$26,$46,$00,$00  ; 37 %
    DEFB $30,$48,$48,$30,$4A,$44,$3A,$00  ; 38 &
    DEFB $10,$10,$00,$00,$00,$00,$00,$00  ; 39 '
    DEFB $08,$10,$20,$20,$20,$10,$08,$00  ; 40 (
    DEFB $20,$10,$08,$08,$08,$10,$20,$00  ; 41 )
    DEFB $00,$10,$54,$38,$54,$10,$00,$00  ; 42 *
    DEFB $00,$10,$10,$7C,$10,$10,$00,$00  ; 43 +
    DEFB $00,$00,$00,$00,$00,$10,$10,$20  ; 44 ,
    DEFB $00,$00,$00,$7C,$00,$00,$00,$00  ; 45 -
    DEFB $00,$00,$00,$00,$00,$30,$30,$00  ; 46 .
    DEFB $02,$04,$08,$10,$20,$40,$80,$00  ; 47 /
    DEFB $38,$44,$4C,$54,$64,$44,$38,$00  ; 48 0
    DEFB $10,$30,$10,$10,$10,$10,$38,$00  ; 49 1
    DEFB $38,$44,$04,$08,$10,$20,$7C,$00  ; 50 2
    DEFB $38,$44,$04,$18,$04,$44,$38,$00  ; 51 3
    DEFB $08,$18,$28,$48,$7C,$08,$08,$00  ; 52 4
    DEFB $7C,$40,$78,$04,$04,$44,$38,$00  ; 53 5
    DEFB $38,$40,$78,$44,$44,$44,$38,$00  ; 54 6
    DEFB $7C,$04,$08,$10,$20,$20,$20,$00  ; 55 7
    DEFB $38,$44,$44,$38,$44,$44,$38,$00  ; 56 8
    DEFB $38,$44,$44,$3C,$04,$04,$38,$00  ; 57 9
    DEFB $00,$30,$30,$00,$30,$30,$00,$00  ; 58 :
    DEFB $00,$30,$30,$00,$30,$10,$20,$00  ; 59 ;
    DEFB $08,$10,$20,$40,$20,$10,$08,$00  ; 60 <
    DEFB $00,$00,$7C,$00,$7C,$00,$00,$00  ; 61 =
    DEFB $20,$10,$08,$04,$08,$10,$20,$00  ; 62 >
    DEFB $38,$44,$04,$08,$10,$00,$10,$00  ; 63 ?
    DEFB $38,$44,$5C,$54,$5C,$40,$38,$00  ; 64 @
    DEFB $10,$28,$44,$7C,$44,$44,$44,$00  ; 65 A
    DEFB $78,$44,$44,$78,$44,$44,$78,$00  ; 66 B
    DEFB $38,$44,$40,$40,$40,$44,$38,$00  ; 67 C
    DEFB $78,$44,$44,$44,$44,$44,$78,$00  ; 68 D
    DEFB $7C,$40,$40,$78,$40,$40,$7C,$00  ; 69 E
    DEFB $7C,$40,$40,$78,$40,$40,$40,$00  ; 70 F
    DEFB $38,$44,$40,$5C,$44,$44,$38,$00  ; 71 G
    DEFB $44,$44,$44,$7C,$44,$44,$44,$00  ; 72 H
    DEFB $38,$10,$10,$10,$10,$10,$38,$00  ; 73 I
    DEFB $04,$04,$04,$04,$04,$44,$38,$00  ; 74 J
    DEFB $44,$48,$50,$60,$50,$48,$44,$00  ; 75 K
    DEFB $40,$40,$40,$40,$40,$40,$7C,$00  ; 76 L
    DEFB $44,$6C,$54,$54,$44,$44,$44,$00  ; 77 M
    DEFB $44,$64,$54,$4C,$44,$44,$44,$00  ; 78 N
    DEFB $38,$44,$44,$44,$44,$44,$38,$00  ; 79 O
    DEFB $78,$44,$44,$78,$40,$40,$40,$00  ; 80 P
    DEFB $38,$44,$44,$44,$54,$48,$34,$00  ; 81 Q
    DEFB $78,$44,$44,$78,$50,$48,$44,$00  ; 82 R
    DEFB $38,$44,$40,$38,$04,$44,$38,$00  ; 83 S
    DEFB $7C,$10,$10,$10,$10,$10,$10,$00  ; 84 T
    DEFB $44,$44,$44,$44,$44,$44,$38,$00  ; 85 U
    DEFB $44,$44,$44,$44,$44,$28,$10,$00  ; 86 V
    DEFB $44,$44,$44,$54,$54,$6C,$44,$00  ; 87 W
    DEFB $44,$44,$28,$10,$28,$44,$44,$00  ; 88 X
    DEFB $44,$44,$28,$10,$10,$10,$10,$00  ; 89 Y
    DEFB $7C,$04,$08,$10,$20,$40,$7C,$00  ; 90 Z
    DEFB $38,$20,$20,$20,$20,$20,$38,$00  ; 91 [
    DEFB $80,$40,$20,$10,$08,$04,$02,$00  ; 92 backslash
    DEFB $38,$08,$08,$08,$08,$08,$38,$00  ; 93 ]
    DEFB $10,$28,$44,$00,$00,$00,$00,$00  ; 94 ^
    DEFB $00,$00,$00,$00,$00,$00,$FE,$00  ; 95 _
    DEFB $20,$10,$00,$00,$00,$00,$00,$00  ; 96 `

; ============================================================
; BANK 0 — WORLD 1 DATA ($C000 when bank 0 paged)
; ============================================================
    PAGE 0
    ORG $C000

W1L1_MAP:
    ; Row 0 sky
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 1 elevated bricks + Q-blocks
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,2,3,0,0,0,0,0,2,2,0,0,0,0,0,0,0,3
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 2 sky
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 3 mid platform
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,2,2,2,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 4 sky
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 5 pipes + platform + flag
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,4,0,0,0,0,0,0,0,2,2,2,2
    DEFB 0,0,0,0,0,0,0,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6
    ; Row 6 pipe bodies
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 7 pipe bodies
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 8 sky
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Row 9 ground with pit at cols 32-34
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DEFB 0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    ; Row 10 solid base
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

W1L2_MAP:
    ; Ceiling
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    ; Hidden blocks
    DEFB 7,7,7,7,7,7,7,7,7,7,7,7,3,7,7,7,3,7,7,7,7,7,7,7,3,7,7,7,7,7,7,7
    DEFB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,3,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
    ; Open interior
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Mid platforms
    DEFB 0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0,2,2,6,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    ; Floor
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

W1L3_MAP:
    ; Castle boss arena
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,6,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DS (MAP_W*MAP_H - ($-W1L3_MAP)), 9

W1_SPAWNS:
    DEFB ENT_WALKER, 6, 9
    DEFB ENT_WALKER,16, 9
    DEFB ENT_WALKER,24, 9
    DEFB ENT_WALKER,36, 9
    DEFB ENT_SHELLER, 44, 9
    DEFB $FF
    DS 26, 0
    DEFB ENT_WALKER, 8, 9
    DEFB ENT_WALKER,14, 9
    DEFB ENT_SHELLER, 20, 9
    DEFB ENT_WALKER,30, 9
    DEFB $FF
    DS 28, 0
    DEFB ENT_BOSS, 48, 7
    DEFB $FF
    DS 30, 0

; ============================================================
; BANK 1 — WORLD 2 DATA
; ============================================================
    PAGE 1
    ORG $C000

W2L1_MAP:
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,2,2,2,0,0,0,0,0,3,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0,0,3,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,6,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DS (MAP_W*MAP_H - ($-W2L1_MAP)), 0

W2L2_MAP:
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,2,3,2,0,0,0,0,0,0,0,0,0,2,3,2,0,0,0,0,0,0,0,0,0,0,0,2,3,2,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,4,4,0,0,0,0,0,0,0,4,4,0,0,0,0,0,0,0,4,4,0,0,0,0,0,0,0
    DEFB 1,1,1,1,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,1,1,0,0,0,0,0,0,1,1,6,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DS (MAP_W*MAP_H - ($-W2L2_MAP)), 0

W2L3_MAP:
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,6,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DS (MAP_W*MAP_H - ($-W2L3_MAP)), 9

W2_SPAWNS:
    DEFB ENT_WALKER, 8, 9 : DEFB ENT_SHELLER,14, 9 : DEFB ENT_WALKER,20, 9
    DEFB ENT_SHELLER, 28, 9 : DEFB ENT_WALKER,36, 9 : DEFB $FF
    DS 26, 0
    DEFB ENT_SHELLER,  4, 9 : DEFB ENT_WALKER,10, 9 : DEFB ENT_SHELLER,18, 9
    DEFB ENT_WALKER,22, 9 : DEFB ENT_SHELLER, 30, 9 : DEFB $FF
    DS 26, 0
    DEFB ENT_BOSS, 48, 7 : DEFB $FF
    DS 30, 0

; ============================================================
; BANK 3 — WORLD 3 DATA
; ============================================================
    PAGE 3
    ORG $C000

W3L1_MAP:
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,2,2,2,3,2,2,2,0,0,0,0,0,0,0,0,0,0,2,3,2,2,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,2,3,2,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,4,4,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0,0,0,5,5,0,0,0,0,0,0
    DEFB 1,1,1,1,0,0,1,1,1,1,0,0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0,0,1,1,6,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DS (MAP_W*MAP_H - ($-W3L1_MAP)), 0

W3L2_MAP:
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,3,0,0,0,0,0,3,0,0,0,0,0,3,0,0,0,0,0,3,0,0,0,0,0,3,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    DEFB 1,1,1,0,0,1,1,1,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,0,1,1,0,0,0,0,6,1
    DEFB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DS (MAP_W*MAP_H - ($-W3L2_MAP)), 0

W3L3_MAP:
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,2,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,6,9
    DEFB 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
    DS (MAP_W*MAP_H - ($-W3L3_MAP)), 9

W3_SPAWNS:
    DEFB ENT_WALKER, 4, 9 : DEFB ENT_SHELLER, 8, 9 : DEFB ENT_WALKER,14, 9
    DEFB ENT_SHELLER, 20, 9 : DEFB ENT_WALKER,26, 9 : DEFB ENT_SHELLER,32, 9
    DEFB $FF
    DS 25, 0
    DEFB ENT_SHELLER,  4, 9 : DEFB ENT_SHELLER,10, 9 : DEFB ENT_WALKER,16, 9
    DEFB ENT_SHELLER, 22, 9 : DEFB ENT_WALKER,28, 9 : DEFB $FF
    DS 26, 0
    DEFB ENT_BOSS, 50, 8 : DEFB $FF
    DS 30, 0

    ; Output raw bank binaries for the Python Z80 snapshot builder
    PAGE 2
    SAVEBIN "build/bank2.bin", $8000, $4000

    PAGE 7
    SAVEBIN "build/bank7.bin", $C000, $4000

    PAGE 0
    SAVEBIN "build/bank0.bin", $C000, $4000

    PAGE 1
    SAVEBIN "build/bank1.bin", $C000, $4000

    PAGE 3
    SAVEBIN "build/bank3.bin", $C000, $4000
