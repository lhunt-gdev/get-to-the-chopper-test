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
| Main menu (START MISSION, SETTINGS, CONTROLS) over the swaying camera with an original spy theme; settings saved on the device (sound, volumes, brightness, screen shake, retro filter, aim mode, FIRE side, swipe sensitivity); pause menu; end screens with a debrief and the route taken. Espionage-style UI (MGS codec panels, GoldenEye dossier menus, GTA chunky slanted blocks) in a pixel font made in code: LIFE bar, SNEAKING / CAUTION / ALERT box, codec message box, progress rail with an arrow, pistol-trigger FIRE button that pulls and kicks. Mission intro: start in an office room, GoldenEye-style camera pan round the player, then bash through the door; auto-run, 5 lanes, swipe dodge/jump/slide | Enemies beyond the Rifle Trooper, Rusher and Security Trooper (Heavy, Sniper); the Alert 3 chasing squad and rear-view CCTV |
| Authored branching route from `route.json` | Real damage model and weapons (placeholders: 3 hits, unlimited-ammo rifle) |
| Junction prompt + brief slowdown (never a pause); stairs are narrow one-lane stairwells with a door you burst through at each end, seen through a CCTV security camera; a halfway marker wall across the main floor and the service tunnel with a double door in the middle to burst through (office doors / barred gates; the outer lanes funnel in; 20 m clear after them); the road physically splits (turns, stairs, end-of-level ladders) and straight on stays open until the split; lockdown doors on alert-closed branches; authored bends; routes head back to the centre; sign over the fork (UP / DOWN for stairs) | Recorded or composed audio (the sound is all generated placeholders) |
| Alert level: 2 tripwires on the main route (up to Alert 3), each followed by an alarm box that lowers it; TUNNEL (off BUILDING MAIN FLOOR) sealed above Alert 1. Alert tiers: Alert 1 is sparse (0–2 rifle guards a section, no dogs) plus one alarm runner; Alert 2 has more guards and the guard dogs; Alert 3 no fewer | |
| Stumbles (running into a jump/slide obstacle stuns, slows and costs 1 HP), death at 0 HP, capture (missed the ladder), extraction, route summary, discovery saved between sessions | Real route-map screen, art, audio |
| PS1 look: low-res, vertex wobble, affine textures, fog; MGS-style mood lighting (dark areas lit by the lamps you can see: office ceiling panels, caged tunnel bulbs, rooftop lamp posts and a sweeping searchlight; failing lamps flicker), a cold colour grade with 15-bit dither and vignette, snow on the night rooftops, glowing lasers and beacons, red pulsing lamps and screen edges at ALERT 3 (amber at 2), cinema bars in the opening pan, a typed location caption per area; placeholder textures generated in code (64 px, MGS-style: bevelled panels, grime, rust and water streaks, rivets, worn stencils, a reduced PS1 palette, mipmaps for distance), one look per area (BUILDING MAIN FLOOR is an MGS-style office: panelled walls, tiled floor, ceiling lights, filing cabinets and door-and-chair blockades to jump, sparking live wires to slide under, cabinets and desks for cover); ROOFTOPS are open night sky: stars, city skyline, neighbouring roofs and towers, gravel roofing, vent shafts to jump, double pipes to slide under (running over the edge and down the building), steaming vents and air-con units for cover, no tripwires; tripwires with wall emitters, pipes plumbed into walls or the floor | Distinct obstacle looks for the other areas (proposed in the decision log) |
| FIRE button (hold) with auto-targeting / tap-to-target; Rifle Trooper that aims at your lane (dodge or hide); contextual cover: solid walls (1–2 lanes, stand) and metal/wood boxes (crouch), never a trooper hidden right behind a wall; walls are solid: line of sight is real rays against the walls (corridors, cover walls, huts, stairwells, shut doors), so shots (yours and theirs) go over boxes and round wall edges but never through, the tracer stops at walls, and in cover behind a wall you lean out round its edge to shoot; Rusher (a German Shepherd guard dog): barks with a red "!", then charges down the route locked onto your lane; dodge out of its lane or shoot it (one shot), no jumping it, cover doesn't help; it bites for a hit and a stumble; Security Trooper, the alarm runner (Alert 1, one per run): he spots you from 40 m, then sprints ahead down the route for about two sections to a wall alarm, a little slower than you, with an ALARM bar on the HUD; shoot him (two shots) before he gets there or alert goes up one level; alarm box that lowers alert and can lift a lockdown door; a mist of blood when a trooper is shot and a pool of blood when he goes down | |
| Chopper countdown: analog dial top centre, CHOPPER INBOUND → LANDED → LIFTING OFF under it, THE CHOPPER LEFT if you're too slow; over the last 15 m you're steered into the centre lane, lined up with the chopper | |
| PS1/N64-era sound, all generated in code (no audio files; MGS1 and GoldenEye in mind): ambience per area, footsteps per surface, rifle and trooper shots, the "!" sting, hits, grunts and body falls, door bashes (office, steel, barred), wall-press cover thump, tripwire zap, alarm beeps, live-wire crackle, steam, chopper rotor; music only when the alert rises (tension at 2, alert music at 3); codec, caption ticks, radio squelch, lift-off beeps, extraction jingle and game-over sting | |

## Layout

```
game/
  autoload/     GameState (alert, run lifecycle), RunLog (route travelled, discovery)
  config/       Tuning resource: every number worth playtesting
  input/        SwipeInput: swipes + taps (+ keyboard on desktop)
  player/       Player scene + auto-run movement
  enemies/      one folder per enemy (rifle_trooper/, rusher_dog/, security_trooper/, ...)
  route/        RouteGraph (data) + RouteRunner (walks it, commits choices)
  systems/      alert/, targeting/, extraction/
  ui/           hud/ (in-run HUD), menu/ (main menu, settings, pause, end screens), kit/ (the look and pixel font), route_map/
  audio/        sound synthesis (synth.gd), every sound (sound_bank.gd), playback and music (audio_director.gd)
  rendering/    shared PS1 materials, mood lighting (ambience.gd)
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
- Unit tests: route validity, alert gating, lane→exit rule, route geometry rules, swipe direction, targeting priority, trooper shot rules (dodge, cover, alert), alert tiers (sparse Alert 1, dogs only from Alert 2, one alarm runner), alarm runner rules, chopper stages, cover rules (wall width, box material, no trooper hidden behind a wall, no forced swipe-and-jump), no overlapping objects, stairs only one level (tunnels - main - rooftops).
- Bot playthroughs: a scripted player runs seventeen routes and must die, extract straight on via BUILDING MAIN FLOOR, take the MAIN FLOOR's stairs down to the TUNNEL and ladder out, find the TUNNEL locked at Alert 2, shoot its alarm box to reopen it, go up to the ROOFTOPS and back down into the main floor, ladder down from the far end of the ROOFTOPS, be captured for missing the ladder, switch back to the middle at the last moment and still go straight on, take a shot in cover without being hurt, camp in cover until the chopper leaves, run into a barrier and still get out (a stumble, not death), get bitten by the guard dog and still get out, dodge the dog out of its lane, let the alarm runner reach his alarm (Alert 2), trip both main-route wires (Alert 3), and shoot both alarm boxes back to Alert 1. If you edit `route.json` and make it unwinnable, CI fails.
