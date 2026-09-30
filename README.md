# Get to the Chopper!

PS1-style mobile escape action game (Godot 4.7). This repo is the **proof of concept**: it exists to find out whether the 20–30 seconds between route choices is fun.

- Design baseline: [`docs/design/handover.md`](docs/design/handover.md)
- What's locked, proposed or open: [`docs/design/decision-log.md`](docs/design/decision-log.md)

## Play it on your iPhone

Every push to `main` runs the tests, exports a web build and publishes it to GitHub Pages (`.github/workflows/web-deploy.yml`).

1. Open `https://<your-username>.github.io/<repo-name>/` in **Safari** on the iPhone.
2. For fullscreen: Share → **Add to Home Screen**, then launch it from the icon.
3. After a new push, wait for the Action to go green (~2–3 min), then reload.

Controls: swipe left/right to change lane, up to jump, down to slide; hold FIRE (bottom right) to shoot. Run into cover to take it; swipe left/right to break cover. At a fork, the far-left or far-right lane takes that side exit (corridor, stairs or ladder); the middle 3 lanes carry straight on. Tap to start and to retry. On desktop: arrow keys, Enter.

## Run it on your computer

1. Install [Godot 4.7.x](https://godotengine.org/download) (standard build, not .NET).
2. Godot → Import → pick `project.godot` → Run (F5).
3. Tweak feel in `game/config/default_tuning.tres` (Inspector): lane count, speeds, swipe threshold, junction slowdown, targeting mode.

## Current state: walking skeleton

| Works | Not built yet |
|---|---|
| Mission intro: start in an office room, GoldenEye-style camera pan round the player, tap to start, bash through the door; auto-run, 5 lanes, swipe dodge/jump/slide | Enemies beyond the Rifle Trooper (Rusher, Heavy, Sniper, Security) |
| Authored branching route from `route.json` | Real damage model and weapons (placeholders: 3 hits, unlimited-ammo rifle) |
| Junction prompt + brief slowdown (never a pause); stairs are narrow one-lane stairwells with a door you burst through at each end, seen through a CCTV security camera; a halfway marker wall across the main floor and the service tunnel with a double door in the middle to burst through (office doors / barred gates; the outer lanes funnel in); the road physically splits (turns, stairs, end-of-level ladders) and straight on stays open until the split; lockdown doors on alert-closed branches; authored bends; routes head back to the centre; sign over the fork (UP / DOWN for stairs) | Ambient lighting pass |
| Alert level: 2 tripwires on the main route (up to Alert 3), each followed by an alarm box that lowers it; TUNNEL (off BUILDING MAIN FLOOR) sealed above Alert 1; troopers tiered by alert on every route | Other alert triggers (e.g. the Security Trooper) |
| Stumbles (running into a jump/slide obstacle stuns, slows and costs 1 HP), death at 0 HP, capture (missed the ladder), extraction, route summary, discovery saved between sessions | Real route-map screen, art, audio |
| PS1 look: low-res, vertex wobble, affine textures, fog; placeholder textures generated in code, one look per area (BUILDING MAIN FLOOR is an MGS-style office: panelled walls, tiled floor, ceiling lights, filing cabinets and door-and-chair blockades to jump, sparking live wires to slide under, cabinets and desks for cover); ROOFTOPS are open night sky: stars, city skyline, neighbouring roofs and towers, gravel roofing, vent shafts to jump, double pipes to slide under (running over the edge and down the building), steaming vents and air-con units for cover, no tripwires; tripwires with wall emitters, pipes plumbed into walls or the floor | Distinct obstacle looks for the other areas (proposed in the decision log) |
| FIRE button (hold) with auto-targeting / tap-to-target; Rifle Trooper that aims at your lane (dodge or hide); contextual cover: solid walls (1–2 lanes, stand) and metal/wood boxes (crouch), never a trooper hidden right behind a wall; alarm box that lowers alert and can lift a lockdown door | |
| Chopper countdown: analog dial top centre, CHOPPER INBOUND → LANDED → LIFTING OFF under it, THE CHOPPER LEFT if you're too slow | |

## Layout

```
game/
  autoload/     GameState (alert, run lifecycle), RunLog (route travelled, discovery)
  config/       Tuning resource: every number worth playtesting
  input/        SwipeInput: swipes + taps (+ keyboard on desktop)
  player/       Player scene + auto-run movement
  enemies/      one folder per enemy (rifle_trooper/, rusher_dog/, ...)
  route/        RouteGraph (data) + RouteRunner (walks it, commits choices)
  systems/      alert/, targeting/, extraction/
  rendering/    shared PS1 materials
  ui/           hud/, route_map/
  levels/       one folder per mission: scene + route.json
assets/         shaders/psx, textures, models, audio, fonts
docs/           design/ (handover, decision log), dev/
tests/          unit tests + bot playthroughs (run in CI)
```

Conventions: snake_case files, PascalCase `class_name`s, one feature per folder (scene + script together). Numbers go in `Tuning`, not in code. Routes are data, never hard-coded.

## Tests

```
GODOT=/path/to/godot tests/run_all.sh
```
- Unit tests: route validity, alert gating, lane→exit rule, route geometry rules, swipe direction, targeting priority, trooper shot rules (dodge, cover, alert), troopers tiered by alert on every route, chopper stages, cover rules (wall width, box material, no trooper hidden behind a wall, no forced swipe-and-jump), no overlapping objects, stairs only one level (tunnels - main - rooftops).
- Bot playthroughs: a scripted player runs fourteen routes and must die, extract straight on via BUILDING MAIN FLOOR, take the MAIN FLOOR's stairs down to the TUNNEL and ladder out, find the TUNNEL locked at Alert 2, shoot its alarm box to reopen it, go up to the ROOFTOPS and back down into the main floor, ladder down from the far end of the ROOFTOPS, be captured for missing the ladder, switch back to the middle at the last moment and still go straight on, take a shot in cover without being hurt, camp in cover until the chopper leaves, run into a barrier and still get out (a stumble, not death), trip both main-route wires (Alert 3), and shoot both alarm boxes back to Alert 1. If you edit `route.json` and make it unwinnable, CI fails.
