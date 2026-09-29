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

### PROPOSED — Blob shadows with dithered edges
- Playtest: "hard to read what to duck under and jump over". Nothing tied obstacles to the ground.
- PS1-style blob shadows, not engine shadow maps (cheaper on iPhone web, truer to the look). The edges fade out with an ordered dither pattern at the game's low resolution, so they look soft but pixel-crisp.
- Each shadow is directly below its object. Under an overhead pipe you see a gap between the pipe and its shadow ("duck"). A barrier's shadow touches it ("jump"). The player's shadow shrinks as they rise, so you can judge jump height.
- Numbers in `Tuning` (Shadows group).

### OPEN — Ambient lighting pass
- User wants a general lighting pass later. Not now.

### PROPOSED — Route splits change the actual geometry (user direction, not built yet)
- The level physically splits at a fork and the player runs down the branch they chose. No more straight road with a label.
- Two kinds of split:
  1. **Corridor:** a branch turns off left or right (~15° to start; the angle goes in `Tuning` to test).
  2. **Stairs:** one branch goes up, another goes down.
- Three height tiers: **roof**, **ground** and **underground** (e.g. sewers). The exit is reached via the roof or ground. From underground the player must get back up, or they hit a dead end or get caught.
- **Lane rule (user decision):** only the outer lanes take a split. Far-left lane takes the left exit and far-right lane takes the right exit, whether that exit is a corridor or stairs. The middle 3 lanes always carry straight on. Doing nothing means straight on.
- **End-of-level ladders (user decision):** the level's dead ends are only at the very end, and each has a ladder to the helicopter: up from the sewer, down from the roof. Ladders are only ever in the outer left or right lanes.
- This covers the LOCKED "dead ends should be rare" rule, since the underground and roof routes aren't traps as long as you're in the right lane at the end. "Get caught" still ties into OPEN "Who captures the player?".
- **Missing the ladder = CAPTURED (user decision):** the player stops and puts their hands up, and 3–4 guards appear from behind. This gives capture its first trigger (see OPEN "Who captures the player?").
- **Geometry (agreed):** a side exit turns off by `Tuning.fork_turn_degrees` (15° to start) toward its side. Stairs are a ramp with steps, and ladders are a short steep climb. Heights: ground 0, roof +`tier_height`, underground −`tier_height`. Both branches are visible before you commit, and the one you don't take disappears after. The run logic stays "distance along the route + lane"; only how it's drawn changes.
- **Prototype layout (agreed):** COMPOUND EXIT: straight → MOTOR POOL → AIRFIELD GATE → HELIPAD; right lane: stairs up → ROOFTOPS. ROOFTOPS: straight → ROOF EDGE; left lane: stairs down → SERVICE TUNNEL (sealed above Alert 1). ROOF EDGE and SERVICE TUNNEL end in outer-lane ladders to HELIPAD.
- **Refinement after first look (user):** 15° looked confusing, because the branch swept across the middle 3 lanes. Now a side branch joins the main road **only at the outer lane**. It starts beside the road, through an opening in the side wall, and the main road keeps its full width going straight on. The outer lane you're in becomes the branch's nearest lane, so you run straight in. Default turn is now 30°.
- **Straight on is always open (user decision):** the player may change lane at the last minute, so the choice is made at the split itself, not 18 m before. Every open branch is fully built ahead of time. The only exception is a dead end ahead (the ladder ends), which has no straight road. Enforced in route validation: a straight exit can't be alert-gated, and any node with a side corridor or stairs must have one.
- **Lockdown doors (user decision):** when alert closes a side route, a lockdown shutter covers that branch's entrance. It slams down if you're watching. The outer lane then carries straight on.
- **Routes come back to the centre (user decision):** a side branch turns out (`fork_turn_degrees`) for `branch_out_length`, then runs parallel to the main road. A segment leading to the end angles back toward the centre line, then straightens, so every route visibly heads back to the helicopter.
- **Bends (user direction):** paths don't need to be straight. A segment can bend left or right at the same angle as a split, with no choice involved. It's authored in `route.json` as `"bends": [{"at": 44, "side": "left"}]`. A bend has the same shape as a side branch: out at `fork_turn_degrees` for `branch_out_length`, then straight again. The route jogs across rather than drifting off at an angle, so "come back to the centre" still holds.
- Lock after the first playtest of the built split.

### OPEN — Who captures the player?
- Capture is a LOCKED failure state, but no enemy causes it now that Heavies are blockers. Resolve at Point 8 (Failure states).

### Tech
- Godot 4.7.2, GDScript (not C#: mobile C# export is the weaker path), Compatibility renderer.
- Portrait orientation, 270×480 internal resolution stretched up for the PS1 look. **Assumed. Confirm.**
- Test on iPhone via Web export → GitHub Pages → Safari. A native iOS build needs a Mac with Xcode; defer until the loop is fun.
- Routes are data (`route.json`) and every run logs node ids. That's the foundation for the route map and discovery.
