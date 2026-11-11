#!/usr/bin/env bash
# Builds the Jungle Operative (the decision log's "Jungle Operative, a skin for CROSS") from CROSS's
# finished model: his texture repainted in jungle camo and face paint, into game/player/skins
# (jungle.glb, jungle.json). See build_jungle.py. Run again whenever CROSS is rebuilt.
# Usage (from anywhere): art_source/operative/tools/build_jungle.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
"$BLENDER" --background --factory-startup --python art_source/operative/tools/build_jungle.py -- \
  game/player/cross.glb game/player/skins/jungle.glb
