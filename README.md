# Gunarok

A 2D one-on-one fighting game where history's greatest warriors fight up an arcade ladder to face Zeus.
GAMDES1 Game Design and Development, BSCS IAC1, University of Baguio. **BOPAA Team**: Acejo, Asas, Bulong, Osian, Puguon.

The design is in `GDD/` (Game Design Document, Sections I to VIII describe this build).

## Controls (GDD Section 8.3)

| Action             | Player 1                 | Player 2     | Gamepad (each player) |
| ------------------ | ------------------------ | ------------ | --------------------- |
| Move               | A / D                    | Left / Right | D-pad or left stick   |
| Jump               | W                        | Up           | D-pad up              |
| Crouch             | S                        | Down         | D-pad down            |
| Punch (high)       | F                        | Numpad 1     | X                     |
| Kick (low)         | G                        | Numpad 2     | A                     |
| Block (hold)       | H                        | Numpad 3     | LB                    |
| Special (50 meter) | T                        | Numpad 5     | Y                     |
| Pause              | Esc                      |              | Start                 |
| Menus              | Arrows, Enter, Backspace |              | D-pad, A, B           |

Character select in Versus: each player moves with their own movement keys, confirms with Punch or Kick, and cancels with Block.
Gamepad 1 is Player 1 and gamepad 2 is Player 2. Every action is a named Input Map action (`p1_*`, `p2_*`, `pause`, `menu_back`), so keys can be changed in **Project > Project Settings > Input Map**.

## What is in the build

- 8 warriors with the shared move template (punch, kick, block, special) and a 9-point stat budget: Leonidas, Julius Caesar, Ragnar, Miyamoto Musashi, Lapu-Lapu, Crazy Horse, Simo Häyhä and Nai Khanom Tom.
- **Arcade**: a fixed six-match ladder over three stages. M1 and M2 are in the Ancient Arena, M3 to M5 on the Battlefield, and M6 is Zeus on the Mythic Summit. You have 3 continues and a score.
- **2-Player Versus** on one keyboard or two gamepads, with a stage choice.
- Best of three rounds, 100 health (Zeus 150), a 60-second timer, a special meter (+1 per damage taken, +0.5 per damage dealt, special costs 50), 25% chip damage, high/low/mid attack heights, hitstun and knockdown.
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
