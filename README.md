# Gunarok

A 2D one-on-one fighting game where history's greatest warriors fight up an arcade ladder to face Zeus.
GAMDES1 Game Design and Development, BSCS IAC1, University of Baguio. **BOPAA Team**: Acejo, Asas, Bulong, Osian, Puguon.

The design is in `GDD/` (Game Design Document, Sections I to VIII describe this build).

## Controls (Design Plan v3 Section 4)

| Action | Player 1 | Player 2 | Gamepad (each player) |
| --- | --- | --- | --- |
| Move / Dash | A / D (double-tap dash) | Left / Right (double-tap) | D-pad or left stick |
| Jump / Crouch | W / S | Up / Down | D-pad up / down |
| Light + Direction | `F`, `Fwd+F`, `Back+F`, `S+F`, `W+F` | `,` + direction | `X` + direction |
| Heavy + Direction | `G`, `Fwd+G`, `Back+G`, `S+G`, `W+G` | `.` + direction | `Y` + direction |
| Seize (grab / throw tech) | H | `/` (slash) | A |
| Block (hold) / Parry (tap) | J | Right Shift | LB |
| Skills (chord / startup-cancel) | `F+G`, `W+F+G`, `S+F+G` | `,+.`, `Up+,+.`, `Down+,+.` | `X+Y`, `Up+X+Y`, `Down+X+Y` |
| Ultimate (100 meter) | T | Enter | RB |
| Pause | Esc | Esc | Start |
| Menus | Arrows, Enter, Backspace | | D-pad, A, B |

Character select in Versus: each player moves with their own movement keys, confirms with Light or Heavy, and cancels with Block.
Gamepad 1 is Player 1 and gamepad 2 is Player 2. Every action is a named Input Map action (`p1_*`, `p2_*`, `pause`, `menu_back`), so keys can be changed in **Project > Project Settings > Input Map**.

## What is in the build

- 8 warriors with the shared v3 move template (Light, Heavy, Seize, Crouch Light/Heavy, Ground/Air/Low Skills, Parry, Ultimate) and a 9-point stat budget: Leonidas, Julius Caesar, Ragnar, Miyamoto Musashi, Lapu-Lapu, Crazy Horse, Simo Häyhä and Nai Khanom Tom.
- **Arcade**: a fixed six-match ladder over three stages. M1 and M2 are in the Ancient Arena, M3 to M5 on the Battlefield, and M6 is Zeus on the Mythic Summit. You have 3 continues and a score.
- **2-Player Versus** on one keyboard or two gamepads, with a stage choice.
- Fixed 60 Hz deterministic simulation (integer frame counters, per-tick input bit-fields, 3-frame chord buffer, simple box math, no wall-clock tiebreak or physics-node dependencies).
- Best of three rounds, 100 health (Zeus 150), 60-second timer, ultimate meter (fills from landed hits and parries only, costs 100, resets each round), parry system (tap Block to stagger attacker, mistimed tap locks block for 0.3 s), Seize throw-tech (`H` in first 0.15 s), 25% chip damage (50% on Ultimate), high/low/mid/grab heights, hitstun and knockdown.
- Nearest texture filtering and Section 14.2 animation hooks ready for 192×128 (2× scaled) pixel-art sprites.
- Opponent intro cards, round banners, pause menu, result, ending and game over screens, music on every screen and sound for every action.

## Project structure

Scenes and the scripts that belong to them sit together, following the Godot project organization guidelines. Files and folders use `snake_case`, and nodes use `PascalCase`.

```
project.godot
assets/                  art, audio and fonts (no scripts)
  audio/music/           menu and stage loops
  audio/sfx/             hits, blocks, whooshes, announcer, UI
  fonts/                 DejaVu Sans Condensed Bold + licence
  sprites/stages/        stage backgrounds
  sprites/ui/            HUD bar textures, menu background
data/
  warriors/*.tres        WarriorData: one file per warrior + zeus.tres (GDD Table C)
  cpu_tiers/*.tres       CpuTier: one file per ladder match (GDD Table B)
scenes/
  main/                  main.tscn: entry point, swaps screens, owns pausing
  match/                 match.tscn + round_manager, round_timer, camera_rig
  fighter/               fighter.tscn (reused for P1, P2, CPU and Zeus), state_machine, hitbox,
                         hurtbox, player_input, cpu_brain, placeholder_rig
  stages/                stage_1_ancient_arena, stage_2_battlefield, stage_3_mythic_summit
  effects/               hit_spark
  ui/                    main_menu, character_select, hud, result_screen, ending_screen,
                         game_over_screen, pause_menu
scripts/
  autoload/              game_state.gd (GameState), audio_manager.gd (AudioManager)
  resources/             balance.gd (all tuning numbers), warrior_data.gd, cpu_tier.gd
  ui/                    ui_style.gd (shared button look)
tools/                   Python scripts that generate the placeholder art and audio
GDD/                     the Game Design Document
```
