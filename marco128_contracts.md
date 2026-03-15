;;; MARCO128_CONTRACTS.MD — Claude-internal. Subroutine contracts. v0.7.9
;;; FORMAT: NAME addr bank | IN | OUT | CLOBBERS | GLOBALS | NOTES
;;; "Clobbers" = register differs on return vs entry. Unlisted = preserved (push/pop).
;;; Addresses approximate (~) unless marked exact. Update after every build that shifts them.

;;; ═══════════════ BANK 2 (fixed, $8000-$BFFF) ═══════════════

GAME_START         $8375  bank2
  IN: snapshot PC set here by make_szx.py
  SIDE-FX: di; ld sp,$BBFE; ld a,$17; ld ($5B5C),a; ld a,1; ld (bankswitch_ok),a
            call Setup_IM2; call ClearScreen; call AY_Silence; jp MainLoop

Setup_IM2          $838F  bank2
  IN: none | OUT: none | CLOBBERS: AF,BC,HL
  SIDE-FX: fills $7E00-$7F00 with $BC×257; writes JP $BC00 at $BCBC; ld i,$7E; im 2; ei

DoLevelBanking     $83CB  bank2
  IN: cur_level_bank set | OUT: none | CLOBBERS: AF,BC,DE,HL
  CALLS: BankSwitch→LoadLevelMap→LoadEnemySpawns→BankSwitch(7)
  NOTE: must stay in bank2. Called from InitLevel (bank7) which cannot touch $7FFD itself.

LoadEnemySpawns    ~$83DD  bank2  (called only from DoLevelBanking)
  IN: level bank paged | OUT: none | CLOBBERS: AF,BC,DE,HL (not push/pop balanced)
  GLOBALS: writes ent_type[8],ent_xl[8],ent_xh[8],ent_yl[8],ent_vx[8],ent_state[8]
  CRITICAL(Fix45): djnz loop with B=counter, C=entity_index.
    Any push/pop inside loop: wrap with outer push bc/pop bc.
    Fix45 root: pop bc inside loop retrieved pixel_x into B(counter),C(index) → B=0 → 255 extra iters
    → level data executed as Z80 code → CALL BankSwitch with random A → bank7 paged out.

GetTileAt          ~$C674  bank2  (called from many bank7 routines — safe, bank2 fixed)
  IN: HL=world_pixel_x(16-bit), B=world_pixel_y(8-bit)
  OUT: A=tile_id | CLOBBERS: AF | PRESERVES: BC,DE,HL (push/pop)
  NOTE: reads level_map_cache in bank2. No paging. B preserved (Fix 33).

IsSolid            ~bank2
  IN: A=tile_id | OUT: Z=passable(air/flag), NZ=solid; A preserved (Fix 37) | CLOBBERS: F only

BankSwitch         $BF7B  bank2  (v0.7.8+; was $BFA5 pre-v0.7.8)
  IN: A=bank(0-7) | OUT: none | CLOBBERS: nothing (push/pop AF,BC)
  SIDE-FX: DI on entry; EI on exit always; writes $5B5C+port $7FFD; guard: bankswitch_ok=0 → nop

ClearScreen        $BF9B  bank2  (v0.7.8+; was $BFC5 pre-v0.7.8)
  IN: none | OUT: A=1 (border colour, CAUTION Fix54: xor a after call if zeroing vars)
  CLOBBERS: AF,BC,DE,HL | SIDE-FX: DI/EI; sets border=blue; clears $4000-$5AFF (pixels+attrs=ATTR_SKY)

HANDLER            $BC00  bank2  ORG-pinned
  STACK: di/push af,bc,de,hl,ix,iy … pop iy,ix,hl,de,bc,af/ei/reti (perfectly balanced, Fix43)
  CALLS: Music_Tick(if playing), SFX_Tick(if active), AY_WriteBuffer — ALL bank2 only
  RULE: HANDLER must NEVER call bank7 routines.

AY_WriteBuffer     $BCC0  bank2  ORG-pinned (DS pad before it must stay positive)
  IN: none (reads ay_buf[0..13]) | CLOBBERS: AF,BC,HL | SIDE-FX: OUT to AY regs 0..13

Music_Init         $BCDB  bank2
  IN: HL=music data ptr | CLOBBERS: AF | GLOBALS: music_ptr, music_note_ptr, music_frame, music_playing=1

Music_Stop         $BCEB  bank2
  IN: none | CLOBBERS: AF,BC,HL (via AY_Silence) | GLOBALS: music_playing=0; calls AY_Silence

Music_Tick         $BCF3  bank2  (HANDLER only)
  IN: none | CLOBBERS: AF (push/pop BC,DE,HL) | GLOBALS: writes ay_buf[0,1,8,9,10,7]

SFX_Play           $BD62  bank2
  IN: A=sfx_index(0..7) | CLOBBERS: AF (push/pop DE,HL) | GLOBALS: sfx_ptr,sfx_frame,sfx_active=1

SFX_Tick           $BD7F  bank2  (HANDLER only)
  IN: none | CLOBBERS: AF (push/pop BC,DE,HL) | GLOBALS: writes ay_buf[4,5,10,7] (ch C)

AY_Silence         ~bank2
  IN: none | CLOBBERS: AF,BC,HL | GLOBALS: zeros ay_buf; ay_buf[AY_MIXER]=$FF
  SIDE-FX: immediately silences AY (R7=$FF, vol=0)

DrawCharXY         $BFFD  bank2 trampoline → DrawCharXY_Real $C000 bank7
  IN: A=char(32-127→ROM1; 128-255→FONT_DATA), B=col(0..31), C=row(0..23)
  OUT: none | CLOBBERS: nothing (push/pop AF,IX,BC,DE,HL)
  ADDR FORMULA: correct since Fix 28. Screen addr computed with correct carry condition (jr c).

;;; ═══════════════ BANK 7 ($C000-$FFFF, always paged during play) ═══════════════

DrawCharXY_Real    $C000  bank7
  Same contract as DrawCharXY (trampoline passes through unchanged).
  ROW ADVANCE: jr c at $C05F (correct, Fix 28). SCREEN ADDR: no rrca on prow field.

DrawString         $C06E  bank7
  IN: HL=null-terminated string ptr, B=col, C=row
  OUT: none | CLOBBERS: HL (advanced past null) | PRESERVES: AF,BC (push/pop)

DrawTile           $C224  bank7
  IN: A=tile_id(0-9), B=screen_pixel_x(mult of 8), C=screen_pixel_y(mult of 8)
  OUT: none | CLOBBERS: nothing (push/pop AF,IY,IX,BC,DE,HL)
  ROW ADVANCE: jr c at $C27B (correct, Fix 27).
  ATTR WRITE: yes — writes 2×2 attr cells per tile. Required (unlike DrawSprite).

RenderLevel        $C2BA  bank7
  IN: none | OUT: none | CLOBBERS: nothing (push/pop IY,IX,BC,DE,HL)
  GLOBALS: writes cam_tile_x
  NOTE: reads level_map_cache (bank2). Calls DrawTile for non-AIR tiles.
        Draws tile rows 0-10. Row 1 (pixel_y 16-31) overlaps HUD COINS area → HUD flicker (cosmetic, accept).

DrawSprite         $C4A8  bank7
  IN: IX=sprite ptr(32 bytes: 16 rows × 2 bytes), B=screen_pixel_x, C=screen_pixel_y
  OUT: none | CLOBBERS: AF (push/pop IX,BC,DE,HL; IY never touched)
  ADDR FORMULA: correct since Fix 68 (removed 3 rrca from prow field).
  ROW ADVANCE: jr c at $C51A (correct, Fix 27 context).
  NO ATTR WRITE (removed Fix 65). ClearScreen sets ATTR_SKY; RenderLevel restores tile attrs.
  GUARD: callers must cp 176 / jp nc before calling. screen_y=176+ corrupts $5B00 (BANKM sysvar).
  ERASE ORDER: EraseSprite at prev_sy must run BEFORE the cp 176 guard (Fix 72).

EraseSprite        $C529  bank7
  IN: B=screen_pixel_x, C=screen_pixel_y (previous drawn position)
  OUT: none | CLOBBERS: AF,HL,D (push/pop BC)
  ADDR FORMULA: correct since Fix 68 (removed 3 rrca from prow field).
  ROW ADVANCE: jr c at $C55F (correct, Fix 71 — was jr nc until v0.7.9).
  SAFE RANGE: screen_y 0-175. 176+ → attr area. 255 → $5Fxx BANKM corruption (Fix 66).
  SENTINEL: callers check cp 255 / jr z before calling (Fix 66).
  CALL ORDER: must be called BEFORE screen_y guard in callers (Fix 72).

UpdatePlayer       $C56A  bank7
  IN: none (reads joy_held, joy_new, plr_* globals)
  OUT: none | CLOBBERS: DE (push/pop HL,BC,AF)
  GLOBALS: writes plr_x,plr_y,plr_vx,plr_vy,plr_on_ground,plr_jumping,
           plr_dir,plr_anim,plr_anim_cnt,plr_dead; calls UpdateCamera→cam_x
  JUMP TRIGGER: joy_new bit4 → plr_vy=-8, plr_jumping=1, SFX_JUMP.
  NOTE(Fix70): joy_held/new/prev flushed in InitLevel — first Space press always works.

UpdateCamera       $C7F6  bank7  (called only from UpdatePlayer)
  IN: none (reads plr_x, cam_x, cam_max) | OUT: none | CLOBBERS: AF (push/pop DE,HL, Fix50)
  GLOBALS: writes cam_x
  CRITICAL(Fix50): push de/push hl MUST be at entry. Previously missing → pop consumed
    return address and saved registers → PC jumped to random address every frame.

CheckGround        $C6BF  bank7
  IN: none (reads plr_x,plr_y) | OUT: none | CLOBBERS: AF (push/pop BC,DE,HL)
  GLOBALS: writes plr_y,plr_vy,plr_on_ground,plr_jumping

CheckCeiling       $C6B9? bank7
  IN: none (reads plr_x,plr_y) | OUT: none | CLOBBERS: AF,DE (push/pop BC,HL)
  GLOBALS: writes plr_vy,plr_y; may call QBlockHit→score,coins; SFX_Play

CheckWalls         $C758  bank7
  IN: none (reads plr_vx,plr_x,plr_y) | OUT: none | CLOBBERS: AF (push/pop HL,BC,DE)
  GLOBALS: writes plr_x,plr_vx
  RANGE NOTE(Fix42a,46): two branches to .cw_done required jp (not jr): entry and right-probe.
    Any new branch to .cw_done: verify distance before using jr.

UpdateEnemies      $C841  bank7
  IN: none | OUT: none | CLOBBERS: AF,DE,IX (push/pop BC,HL)
  GLOBALS: writes ent_xl,ent_xh,ent_vx,ent_state,ent_anim,ent_anim_cnt
  CALLS: CheckEnemyPlayer per active entity.

CheckEnemyPlayer   $C8EA  bank7  (called from UpdateEnemies loop only)
  IN: C=entity_index (must not change before call) | OUT: none | CLOBBERS: AF,DE (push/pop BC,HL)
  GLOBALS: may write ent_state[c]=0, plr_vy, score, plr_big, plr_inv_timer; may call PlayerDie,SFX_Play
  STOMP: plr_vy bit7 clear (falling down, vy≥0) → stomp → ent_state=0, plr_vy=-5 (Fix69: was inverted)
  HURT:  plr_vy bit7 set (moving up) → hurt → plr_big check → PlayerDie or invincibility

DrawEnemies        $C97E  bank7
  IN: none (reads ent_* arrays, cam_x) | OUT: none | CLOBBERS: AF,DE,HL (push/pop BC,IX,IY)
  IYL=entity index during loop. IYH=screen_x temp.
  ERASE ORDER: EraseSprite at ent_prev_sy BEFORE screen_y guard (Fix72).

DrawPlayer         $CA3B  bank7
  IN: none (reads plr_*, cam_x) | OUT: none | CLOBBERS: AF,DE,HL (push/pop IX,BC)
  ERASE ORDER: EraseSprite at plr_prev_sy BEFORE screen_y guard (Fix72).

PlayerDie          $CD16  bank7
  IN: none | OUT: none | CLOBBERS: AF | GUARD: returns immediately if plr_dead already set
  GLOBALS: plr_dead=1, plr_dead_timer=0, plr_vy=-8, game_state=STATE_DEAD; SFX_Play(DIE), Music_Stop

CheckLevelEnd      $CD37  bank7
  IN: none | OUT: none | CLOBBERS: AF,BC,DE,HL
  READS: plr_x,plr_y → GetTileAt(plr_x+8,plr_y+8) → if TILE_FLAG → game_state=STATE_LEVELEND

InitLevel          $CD56? bank7  (address approximate — shifted post-Fix 70)
  IN: none | OUT: none | CLOBBERS: AF,BC,DE,HL
  GLOBALS: zeroes plr_*, cam_x; sets plr_x=32,plr_y=144; level_timer=199; timer_cnt=0
           zeroes joy_held,joy_new,joy_prev (Fix70); inits prev_sx/sy=255 (Fix62)
           calls DoLevelBanking,Music_Init; sets game_state=STATE_PLAYING

DrawHUD            $CB29  bank7
  IN: none (reads score,lives,coins,world,level_num,level_timer)
  OUT: none | CLOBBERS: AF,DE (push/pop HL,BC)
  WRITES: first 64 attr cells ($5800-$583F) with $07 (white on black) each call.
          Then draws score/world/lives/timer/coins via DrawCharXY.

MainLoop           $CE24  bank7
  FLOW: TitleScreen → InitGame → .mg_level loop
  .mg_level: ShowLevelEntry → InitLevel → .mg_frame (halt per frame)
  .mg_frame dispatches on game_state:
    STATE_PLAYING(1): UpdatePlayer→UpdateEnemies→UpdatePowerup→CheckLevelEnd→timer→RenderLevel→DrawPowerup→DrawEnemies→DrawPlayer→DrawHUD
    STATE_DEAD(2):    inc plr_dead_timer→bounce→RenderLevel→DrawEnemies→DrawPlayer→DrawHUD→respawn@60
    STATE_LEVELEND(3): 100-frame wait→inc level_num→next level or world
    STATE_GAMEOVER(5): ShowGameOver→restart
    STATE_WIN(6):     ShowVictory→restart
