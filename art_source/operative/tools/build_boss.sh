#!/usr/bin/env bash
# Builds the boss for the game from his Meshy model (art_source/boss/boss.glb, made in a
# T-pose, so his arms are lowered to the A-pose first) into game/enemies/boss (boss.glb, boss.json).
# See build_character.sh for the stages.
# Usage (from the project root): art_source/operative/tools/build_boss.sh [tris=3000] [tex=512]
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec art_source/operative/tools/build_character.sh boss art_source/boss/boss.glb game/enemies/boss "${1:-3000}" "${2:-512}" apose
