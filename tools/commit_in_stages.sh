#!/usr/bin/env bash
# Commits the Gunarok midterm build to the repo one stage at a time.
#
# Usage (Git Bash on Windows, or any bash), from INSIDE your clone:
#   bash path/to/GAMDES1_GUNAROK/tools/commit_in_stages.sh path/to/GAMDES1_GUNAROK
# Then check `git log --oneline` and run `git push`.
set -euo pipefail

SRC="${1:?Give the path to the extracted GAMDES1_GUNAROK folder}"
SRC="$(cd "$SRC" && pwd)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Run this inside your git clone."; exit 1; }
[ "$(pwd)" != "$SRC" ] || { echo "Run it inside the clone, not inside the extracted folder."; exit 1; }
if [ -n "$(git status --porcelain)" ]; then echo "Your clone has uncommitted changes. Commit or stash them first."; exit 1; fi

# Copy a list of paths from the build into the clone, then commit them.
stage() {
  local message="$1"; shift
  for path in "$@"; do
    if [ -d "$SRC/$path" ]; then
      mkdir -p "$path"; cp -R "$SRC/$path/." "$path/"
    else
      mkdir -p "$(dirname "$path")"; cp "$SRC/$path" "$path"
    fi
    git add -- "$path"
  done
  if git diff --cached --quiet; then echo "skip: $message (nothing new)"; else git commit -q -m "$message"; echo "committed: $message"; fi
}

# 0. Keep the Lab 3 prototype reachable, then remove it from the root
if ! git rev-parse -q --verify refs/tags/lab3-core-loop >/dev/null; then git tag lab3-core-loop; fi
removed=0
for old in Fighter.gd Fighter.gd.uid Main.tscn Main.tscn.uid assets/ninja.png assets/ninja.png.import assets/samurai.png assets/samurai.png.import; do
  if git ls-files --error-unmatch "$old" >/dev/null 2>&1; then git rm -q "$old"; removed=1; fi
done
[ "$removed" = 1 ] && git commit -q -m "Remove Lab 3 prototype (kept in tag lab3-core-loop)" && echo "committed: remove Lab 3 prototype"

stage "Project setup: Godot 4 project, input map, folders, font" \
  project.godot icon.svg .gitignore .gitattributes .editorconfig assets/fonts
stage "Data: Balance constants, WarriorData and CpuTier resources (Tables B and C)" \
  scripts/resources data
stage "Fighter: state machine, hitbox and hurtbox, player input, CPU brain, placeholder rig" \
  scenes/fighter scenes/effects assets/audio/sfx/whoosh_punch.wav assets/audio/sfx/whoosh_kick.wav \
  assets/audio/sfx/whoosh_special.wav assets/audio/sfx/hit_light.wav assets/audio/sfx/hit_heavy.wav \
  assets/audio/sfx/hit_special.wav assets/audio/sfx/block.wav assets/audio/sfx/jump.wav \
  assets/audio/sfx/knockdown.wav assets/audio/sfx/thunder.wav assets/audio/sfx/rifle.wav
stage "Stage 1: Ancient Arena (M1, M2)" \
  scenes/stages/stage.gd scenes/stages/stage_1_ancient_arena.tscn \
  assets/sprites/stages/stage_1_ancient_arena.png assets/audio/music/ancient_arena.wav
stage "Stage 2: Battlefield (M3 to M5), sky darkens each match" \
  scenes/stages/stage_battlefield.gd scenes/stages/stage_2_battlefield.tscn \
  assets/sprites/stages/stage_2_battlefield.png assets/sprites/stages/stage_2_battlefield_sky.png \
  assets/audio/music/battlefield.wav
stage "Stage 3: Mythic Summit (M6, Zeus)" \
  scenes/stages/stage_3_mythic_summit.tscn assets/sprites/stages/stage_3_mythic_summit.png \
  assets/audio/music/mythic_summit.wav
stage "Match: round manager, round timer, camera rig, HUD" \
  scenes/match scenes/ui/hud assets/sprites/ui/bar_under.png assets/sprites/ui/bar_fill.png
stage "Game flow: GameState and AudioManager autoloads, menus, result, ending, game over, pause" \
  scripts/autoload scripts/ui scenes/main scenes/ui assets/sprites/ui assets/audio
stage "Tools, README, and revised GDD (Sections I to VIII)" \
  tools README.md GDD

echo
git log --oneline -n 12
echo
echo "Done. Open the project once in Godot 4.4+, commit the generated .uid and .import files, then: git push --follow-tags"
