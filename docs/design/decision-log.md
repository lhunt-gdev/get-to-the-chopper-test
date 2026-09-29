# Decision Log

What's **LOCKED**, **PROPOSED** (under test) and **OPEN**. The handover (`handover.md`) is the baseline; this log wins where they differ. Don't quietly change a LOCKED rule. Log the change here first.

## 2026-09-29

### LOCKED — Enemy roster v1 (Point 2)

| Enemy | Role | Notes |
|---|---|---|
| Rifle Trooper | Baseline mid-range soldier | Core combat grammar |
| Rusher — German Shepherd | Sprints down the route at the player | Dodge or shoot; can't be "covered" from. Replaces the Close-Range Trooper |
| Heavy Trooper | Route/path blocker | Go around or take another route. **Not** a capture trigger (user decision) |
| Sniper | Timed movement threat, laser telegraph | Outside auto-target range, so you dodge him rather than shoot him |
| Security Trooper | Alert specialist | Raises alert if not stopped; letting him is a valid choice |

Behaviour by alert level: see the table in the Point 2 discussion. It's also summarised in each enemy's future scene doc.

### PROPOSED — Tap-to-target (changes LOCKED Controls v1)
- User proposal: tap an enemy to shoot it first.
- Risks: the thumb hides the target on a small screen, taps can be misread as swipes mid-run, and it adds a second thing to look at while dodging.
- **Test, don't decide yet.** `Tuning.targeting_mode` = `AUTO_PRIORITY` / `TAP_TO_TARGET` / `HYBRID` (default: auto-priority, a tap overrides). The logic is in `game/systems/targeting/targeting.gd` and covered by unit tests.
- Auto-priority rule (agreed): the most urgent telegraphed threat first (Security reaching for an alarm, then a close Rusher, then the nearest enemy).

### PROPOSED — 5 lanes
- User wants 5 lanes instead of 3.
- Note: lanes ≠ routes. Route options come from junctions (any number of exits). Lanes only set dodge granularity.
- Risk: on a portrait phone each lane is ~1/5 of the screen, and crossing takes 4 swipes.
- `Tuning.lane_count` (3/5/7). Routes are authored for 5 and remapped when you test 3.

### PROPOSED — Level textures and in-world fork cues (Point 7, route-choice presentation)
- Playtest: "forks are not obvious". The road never visibly split. The only cue was small HUD text for ~1.8 s. Standing in the centre lane silently picked the left route.
- Placeholder PS1 textures, generated in code (`game/rendering/psx_textures.gd`): asphalt with lane lines, compound walls, hazard stripes on jump barriers, rusted pipes to slide under, olive trucks. Each area gets its own wall look (`theme` in `route.json`) so you can tell where you are.
- Fork cue: before each fork, every lane is painted in its route's colour with arrows pointing that way. A sign gantry at the commit point names each route over its lanes. The HUD labels use the same colours.
- Speed, swipe and junction slowdown are unchanged. The user said they feel good.
- Real art replaces these textures later. This is only to make the prototype readable.

### OPEN — Who captures the player?
- Capture is a LOCKED failure state, but no enemy causes it now that Heavies are blockers. Resolve at Point 8 (Failure states).

### Tech
- Godot 4.7.2, GDScript (not C#: mobile C# export is the weaker path), Compatibility renderer.
- Portrait orientation, 270×480 internal resolution stretched up for the PS1 look. **Assumed. Confirm.**
- Test on iPhone via Web export → GitHub Pages → Safari. A native iOS build needs a Mac with Xcode; defer until the loop is fun.
- Routes are data (`route.json`) and every run logs node ids. That's the foundation for the route map and discovery.
