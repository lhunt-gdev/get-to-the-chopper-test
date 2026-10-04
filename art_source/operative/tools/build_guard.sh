#!/usr/bin/env bash
# Builds the guard for the game from his Meshy model (art_source/guard/guard-meshy.glb, made in a
# T-pose, so his arms are lowered to the A-pose first) into game/enemies/guard (guard.glb, guard.json).
# See build_character.sh for the stages.
# Usage (from the project root): art_source/operative/tools/build_guard.sh [tris=3000] [tex=512]
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec art_source/operative/tools/build_character.sh guard art_source/guard/guard-meshy.glb game/enemies/guard "${1:-3000}" "${2:-512}" apose
