#!/usr/bin/env bash
# Builds CROSS for the game from his Meshy model (art_source/operative/ernest-cross.glb) into
# game/player (cross.glb, cross.json). See build_character.sh for the stages.
# Usage (from the project root): art_source/operative/tools/build_cross.sh [tris=3000] [tex=512]
set -euo pipefail
cd "$(dirname "$0")/../../.."
exec art_source/operative/tools/build_character.sh cross art_source/operative/ernest-cross.glb game/player "${1:-3000}" "${2:-512}"
