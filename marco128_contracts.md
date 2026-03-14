# Marco Bros 128 — Subroutine Contracts

> Full IN/OUT/CLOBBERS contracts for every routine.
> Consult when writing or modifying any subroutine.

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

