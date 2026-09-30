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
| Auto-run, 5 lanes, swipe dodge/jump/slide | Enemies beyond the Rifle Trooper (Rusher, Heavy, Sniper, Security) |
| Authored branching route from `route.json` | Real damage model and weapons (placeholders: 3 hits, unlimited-ammo rifle) |
| Junction prompt + brief slowdown (never a pause); the road physically splits (turns, stairs, end-of-level ladders) and straight on stays open until the split; lockdown doors on alert-closed branches; authored bends; routes head back to the centre; lanes painted per exit, sign over the fork | Ambient lighting pass |
| Alert level: 2 tripwires on the main route (up to Alert 3), each followed by an alarm box that lowers it; TUNNEL sealed above Alert 1; troopers tiered by alert on every route | Other alert triggers (e.g. the Security Trooper) |
| Death, capture (missed the ladder), extraction, route summary, discovery saved between sessions | Real route-map screen, art, audio |
| PS1 look: low-res, vertex wobble, affine textures, fog; placeholder textures generated in code, one look per area | |
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
- Unit tests: route validity, alert gating, lane→exit rule, route geometry rules, swipe direction, targeting priority, trooper shot rules (dodge, cover, alert), troopers tiered by alert on every route, chopper stages, cover rules (wall width, box material, no trooper hidden behind a wall).
- Bot playthroughs: a scripted player runs eleven routes and must die, extract straight on via MOTOR POOL, take stairs up then down to the TUNNEL at Alert 1 and ladder out, find the TUNNEL sealed at Alert 2 and ladder down from ROOF EDGE, be captured for missing the ladder, switch back to the middle at the last moment and still go straight on, take a shot in cover without being hurt, shoot the alarm box to reopen the TUNNEL, and camp in cover until the chopper leaves, trip both main-route wires (Alert 3), and shoot both alarm boxes back to Alert 1. If you edit `route.json` and make it unwinnable, CI fails.
