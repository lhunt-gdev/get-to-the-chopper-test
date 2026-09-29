# Get to the Chopper!

PS1-style mobile escape action game (Godot 4.7). This repo is the **proof of concept**: it exists to find out whether the 20–30 seconds between route choices is fun.

- Design baseline: [`docs/design/handover.md`](docs/design/handover.md)
- What's locked, proposed or open: [`docs/design/decision-log.md`](docs/design/decision-log.md)

## Play it on your iPhone

Every push to `main` runs the tests, exports a web build and publishes it to GitHub Pages (`.github/workflows/web-deploy.yml`).

1. Open `https://<your-username>.github.io/<repo-name>/` in **Safari** on the iPhone.
2. For fullscreen: Share → **Add to Home Screen**, then launch it from the icon.
3. After a new push, wait for the Action to go green (~2–3 min), then reload.

Controls: swipe left/right to change lane, up to jump, down to slide. At a fork, be on that side of the road. Tap to start and to retry. On desktop: arrow keys, Enter.

## Run it on your computer

1. Install [Godot 4.7.x](https://godotengine.org/download) (standard build, not .NET).
2. Godot → Import → pick `project.godot` → Run (F5).
3. Tweak feel in `game/config/default_tuning.tres` (Inspector): lane count, speeds, swipe threshold, junction slowdown, targeting mode.

## Current state: walking skeleton

| Works | Not built yet |
|---|---|
| Auto-run, 5 lanes, swipe dodge/jump/slide | Enemies, FIRE, tap-to-target in play |
| Authored branching route from `route.json` | Contextual cover |
| Junction prompt + brief slowdown (never a pause) | Alarm boxes |
| Alert level; tripwire raises it; TUNNEL route sealed above Alert 1 | Chopper countdown / leaving |
| Death, extraction, route summary, discovery saved between sessions | Real route-map screen, art, audio |
| PS1 look: low-res, vertex wobble, affine textures, fog | |

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
- Unit tests: route validity, alert gating, lane→route mapping, swipe direction, targeting priority.
- Bot playthroughs: a scripted player runs four routes and must die, extract via MOTOR POOL, extract via TUNNEL at Alert 1, and be forced via GATE at Alert 2. If you edit `route.json` and make it unwinnable, CI fails.
