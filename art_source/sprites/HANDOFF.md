# Sprite art hand-off (v2 champions)

Generated 2026-11-27 from `prompts/Gunarok_Sprite_Prompts.txt` (based on Combat and Content
Design Plan v2, Section 10). This folder is **source art only**: raw AI-generated sheets,
not yet cut into game frames. A `.gdignore` keeps Godot from importing it.

The resource side is finished. Turning these sheets into game frames, and the game code that
plays them, is the next owner's work (see "What is not done").

## What is here

| folder | contents | count |
|---|---|---|
| `references/` | one approved reference per champion, `<id>_ref.png`, 896x1200 | 11 |
| `sheets/<id>/` | every animation sheet, `<animation>.png`, plus `cutin.png` | 11 x 27 = 297 |
| `fx/` | separate effect sprites (travelling and screen-sized effects, auras, hit sparks) | 30 |
| `prompts/` | the source prompt file and the exact prompts sent, including fix notes | |
| `manifest.csv` | one row per file: frames, layout, background, effects drawn in | |

Champions: leonidas, caesar, ragnar, musashi, lapulapu, simo, naikhanomtom, zeus, thor,
susanoo, anubis. Not generated yet: **crazyhorse** and **bathala** (draft looks waiting for
team review) and **kabunian** (waiting for the respectful design review). The optional
**jump_light** and **intro** (Open Decision 8) were skipped for every champion.

## Sheet conventions

- **Style:** chunky 16-bit pixel art (large hard-edged pixel blocks), side view, facing right,
  matching the champion's reference.
- **Layout** (as the prompt file's commands expect): 2-3 frames one row; 4 frames 2x2; 5 frames
  3 on top and 2 below; 6 frames 3x2. The ultimate is `ultimate_1` + `ultimate_2` (5 + 5).
  Frames are spaced unevenly by the generator, so cut by finding the figures, not by an
  even grid split.
- **Image size:** 16:9 for rows and 3-wide grids, 4:3 for 2x2 and the cut-in. Sheets are
  generator resolution (about 1376x768 or 1200x896), not game resolution.
- **Background:** flat light gray, except **simo** and **zeus**, which are flat dark green
  (#1E5A32) because their white clothing is too close to gray.
- **Game target** (prompt file SETTINGS): body about 84 px tall on a 192x128 canvas, 4 px
  padding, feet at bottom centre, up to 16 colours plus a dark outline, Nearest filtering,
  shown at 2x.

## Effects: what is drawn in and what is separate

Decision made during generation, after a cut-out test showed drawn-in effects survive
background removal and do not change the character's size:

- **Drawn into the sheets** (67 sheets, flagged in `manifest.csv`): slash/weapon trails on
  light, heavy, crouch attacks, skills and ultimates for leonidas, caesar, ragnar, musashi,
  lapulapu, susanoo and anubis; muzzle flash and smoke on simo's firing sheets; charge
  lightning on thor's and zeus's `ultimate_1`.
- **Separate in `fx/`** (travel or outgrow the frame): `caesar_legionary`, `ragnar_axe_spin`,
  `musashi_slash`, `lapulapu_arc`, `simo_muzzle_flash`, `simo_tracer`, `zeus_lightning_burst`,
  `zeus_bolt_flight`, `zeus_ground_electricity`, `zeus_sky_bolt`, `thor_hammer_spin`,
  `thor_shockwave`, `susanoo_sword_wave`, `susanoo_serpent_wave`, `anubis_scale_glyph`,
  `anubis_spirit_hand`, `hit_spark_light`, `hit_spark_heavy`, `block_spark`, and one
  `aura_<id>` per champion (a pair of flame columns to draw behind the fighter during the
  ultimate charge). All effects are on **pure black**: draw them with additive blending
  (CanvasItemMaterial, Blend Mode Add) so black disappears, or key black out.
- The prompt file's "do not draw" notes for travelling effects still hold: the bullet, thrown
  axe/hammer/bolt, sword wave, serpent, spirit hand, scale glyph and legionaries are only in `fx/`.

## Review status

Every sheet was checked by eye, frame by frame, and redone where wrong (wrong or missing
weapons, weapons through the face, frames that barely change, wrong frame count, stray
effects). Seize and seize_throw rows contain only the champion. Known leftovers:

- `ragnar/skill_ground`: his battle axe drops out of a few frames during the throw.
- `musashi/heavy` frame 4 draws a large X across his body (the X-cut); kept on purpose.
- A few of thor's sheets (`walk`, `victory`, `seize`) have a slightly bluish gray
  background; it is flat, so keying should still work. Check for a halo.
- Light-gray edge pixels appear where figures meet the background; tune the key tolerance.
- Hand-drawn polish (frame timing, hit-frame alignment, small cleanups) has not been done.

## What is not done (next owner)

1. **The sheet-processing tool does not exist.** The prompt file's commands call
   `gunarok_sprites.py` (`palette`, `process`, `build`); no such script is in this repo or
   on the generating machine. It needs to: key out the background (gray or green), find each
   figure (uneven spacing), scale all frames of a sheet by one factor so the body is ~84 px,
   place feet at bottom centre on 192x128, reduce to 16 colours + outline, write a preview GIF,
   append `ultimate_2` to `ultimate_1`, and build one `SpriteFrames` `.tres` per champion.
2. **The game still uses the v1 move set.** `scripts/resources/warrior_data.gd` expects
   `idle, walk, jump, crouch, block, crouch_block, punch, kick, special, hitstun, knockdown,
   getup, ko, victory`. The v2 sheets add `light, heavy, crouch_light, crouch_heavy, parry,
   parry_fail, parried, grabbed, seize, seize_throw, skill_ground, skill_air, skill_low,
   ultimate`. `scenes/fighter/fighter.gd` needs updating to v2 before these can play.
3. **Roster and ids.** `data/warriors/` has no thor, susanoo or anubis, and its file names
   differ from the art ids (`julius_caesar` vs `caesar`, `lapu_lapu` vs `lapulapu`,
   `simo_hayha` vs `simo`, `nai_khanom_tom` vs `naikhanomtom`).
4. **Pending team decisions:** crazyhorse and bathala looks, kabunian design review,
   jump_light and intro.

## How these were made

Generated with Google Flow (Nano Banana 2.1) through an automated image pipeline, one image
per prompt, with the champion's approved reference attached to every animation prompt and a
style line appended for the chunky pixel look. The exact prompts are in `prompts/`
(`anim_prompts.json` base prompts, `fx_redo_prompts.json` for the 65 sheets regenerated with
effects drawn in, `redo_fixes.json` for per-sheet corrections, `fx_prompts.json` for `fx/`).
Earlier versions and review contact sheets were kept on the generating machine, not committed.
