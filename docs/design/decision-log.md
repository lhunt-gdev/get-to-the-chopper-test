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

### PROPOSED — First combat slice: Rifle Trooper, FIRE, cover, alarm box (prototype plan §15)
- **FIRE (LOCKED Controls v1):** one persistent on-screen FIRE button (bottom right). Hold it to keep shooting. Touches that start on it never count as swipes. Targets come from `Targeting` (auto-priority by default; tapping an enemy overrides it in HYBRID mode).
- **Rifle Trooper (LOCKED roster, behaviour proposed):** stands in a lane ahead. Within `trooper_aim_range` he aims at **your lane**: a red "!" and a red laser dot on the road where you are. After `trooper_aim_time` he fires. Change lane before then and he misses. Cover blocks it too. Higher alert means he aims faster (LOCKED: alert changes enemy pressure), and a trooper can be alert-gated in `route.json` (`min_alert`) so loud routes are busier. He can't shoot behind him. Running into a live one costs a hit and knocks him down.
- **Cover (LOCKED concept):** `"kind": "box"` / `"wall"` obstacles (see "Two kinds of cover" below). Run into one in its lane and you automatically take cover: you stop, crouch, and are safe from troopers ahead. You can keep firing. Swipe left or right to leave and resume the run. Swiping early dodges it and keeps your momentum. No cover button.
- **Alarm box (LOCKED recommendation):** mounted on a wall. It's only shootable in a short window as you pass (`alarm_window_near/far`) and blinks while it is. A hit lowers alert by one level, which can reopen a locked-down route (the door lifts). Miss it and it's gone.
- **Placeholder — damage (Point 4 is OPEN):** 3 hits and you're KILLED IN ACTION, with a short invulnerability after each hit. No recovery yet. HUD shows HP.
- **Placeholder — weapon (Point 5 is OPEN):** one rifle, unlimited ammo, `fire_interval` between shots; troopers take `trooper_health` hits.
- Auto-priority order: an aiming trooper (50) > a live alarm box in its window (20) > the nearest idle trooper (0).
- **First playtest (2026-09-30, user):** the trooper is easy enough to spot, ~1 s (Alert 1) is enough time to dodge, and the FIRE button bottom right is comfortable. Keep these values for now.

### PROPOSED — Chopper countdown (Point 9 / extraction pressure; user direction)
- **Clock (user decision):** an old-style analog timer dial, top centre. The hand sweeps round as the chopper's window runs out, and the last stretch of the dial is red. This replaces the handover's "no big HUD timer" working direction (which was never locked). It stays small.
- **Messages (user decision):** centred just under the clock, short and readable: CHOPPER INBOUND → LANDED → LIFTING OFF. Each shows for a few seconds when its stage starts; LIFTING OFF stays up and blinks.
- **Rules:** the stages run on game time from the start of the run (`chopper_*` in `Tuning`). You can extract any time before the chopper is gone; arriving during LIFTING OFF still counts. When it's gone, the run ends THE CHOPPER LEFT, wherever you are. The helicopter on the helipad starts lifting during LIFTING OFF.
- Numbers are sized to the lengthened test level: lands 15 s, lifts off 48 s, gone 58 s. A clean bot run takes 34–40 s, so a clean run arrives with ~10 s before lift-off. Stopping in cover, taking hits or a long route costs something real.

- **Playtest (2026-09-30, user):** the clock reads well at its size. The user reached the chopper with a little under a third of the time left: slightly generous, but kept as-is for the test level.
- **Direction (user):** the chopper time will vary by level: easier levels get more time, harder levels less. When there's more than one mission, the timeline should live with each mission (e.g. in its `route.json`), with `Tuning` as the default.

### PROPOSED — Longer test level, more troopers (user direction)
- User felt the level was a little short. Every route is roughly doubled, with more obstacles and more cover blocks. Still one test level; the aim is to feel out length.
- **Playtest (2026-09-30, user):** the length feels good now.
- **Troopers are tiered by alert on every route (user decision):** each route has a set for each alert level, with fewer at Alert 1 than at 2 or 3. In the test level each segment has 1 trooper at Alert 1, 2 at Alert 2 and 3 at Alert 3 (`min_alert` in `route.json`). They appear or disappear live as alert goes up or down, so raising or lowering alert changes the pressure on whatever route you're on.
- **Seen troopers stay (user rule):** when alert drops (e.g. you shoot an alarm box), troopers already active and in view don't disappear. A trooper is committed once he's active and within `trooper_commit_distance` (≈ how far you can see through the fog), or has started aiming; after that he stays whatever the alert. Only troopers further ahead, not yet seen, come and go with alert.
- Note: the test level has only one tripwire, so Alert 3 can't be reached yet. The Alert 3 troopers are authored, ready for a second alert trigger.

### PROPOSED — Two kinds of cover replace the trucks (user decision)
- The tall blocker boxes with the diamond (the placeholder "trucks") are removed and replaced with cover.
- **Wall cover:** a column from floor to ceiling, 1–2 lanes wide. You stand behind it. **Walls are solid (user decision):** no see-through; not knowing what's behind one adds suspense.
- **Fairness rule (user decision):** no trooper may stand in a wall's lanes within 15 m behind it (`RouteGraph.WALL_TROOPER_CLEARANCE`), so running round a wall never drops you onto a hidden trooper. Enforced by route validation, so CI fails if a level breaks it.
- **Box cover:** metal or wood crates, one lane each. You crouch behind them.
- Both follow the LOCKED cover rule: run into it and you take cover; swipe sideways to leave; swipe early to go round it and keep your speed. Running into cover no longer kills you the way a truck did.
- More cover throughout the level. Rooftops and the sewer (service tunnel) get fewer walls and mostly boxes.
- **Playtest (2026-09-30, user):** plays smoothly, as expected.
- **No forced swipe-and-jump (user rule):** when cover fills 3 or more lanes at a spot, the open lanes are the only way through. So no jump or slide obstacle may sit within 4 m of it in those lanes (`RouteGraph.CROSSING_WINDOW`). Otherwise the player would have to swipe and jump at the same moment, which the controls can't do, and the run ends. Tripwires are exempt (running through one only raises alert). Enforced by route validation.

### PROPOSED — Two tripwires and two alarm boxes on the main route (user decision)
- The main (ground) route has 2 tripwires: COMPOUND EXIT and MOTOR POOL. Each is followed a little later by an alarm box on a side wall, so a player who trips a wire gets a chance to shoot the alert back down. The ROOFTOPS alarm box (which can lift the TUNNEL's lockdown door) stays.
- Alarm boxes get a small light on top that blinks the whole time the box is live, so they're seen instantly. The face light still shows the shootable window.
- Tripping both wires reaches Alert 3, so the Alert 3 trooper tier is now testable.

### PROPOSED — Levels stack realistically: tunnels, main level, rooftops (user decision)
- The tiers are physically stacked: underground (tunnels, sewer) under the main (ground) level, under the rooftops. **Stairs only move one tier** (no stairs from a roof straight into a tunnel). Ladders still only lead to the end of the level. Enforced by route validation.
- **The tunnel is reached only from the main route.** In the test level, MOTOR POOL's left lane takes stairs down to SERVICE TUNNEL (sealed above Alert 1, with a lockdown door). MOTOR POOL's own tripwire and alarm box now drive that door: trip the wire and the tunnel locks, shoot the box and it reopens.
- ROOFTOPS gets a left-lane staircase back down to AIRFIELD GATE (main level) and still carries straight on to ROOF EDGE and its ladders.
- This replaces the earlier layout (ROOFTOPS → stairs down → TUNNEL).

### PROPOSED — Mission layout: main, up and down (user direction, 2026-09-30)
- A mission has three tiers: the main level (the building), up (ROOFTOPS) and down (SERVICE TUNNEL). ROOF EDGE is removed as a separate area. It's just the far stretch of the ROOFTOPS and shows as ROOFTOPS on screen, because a stretch that ends in ladders can't also have a staircase in its outer lanes.
- **No fixed lane rule (user decision):** up and down are not always the same lane, and they don't branch off in the same places. Levels should feel intended, not formulaic.
- **Late branches needn't come back (user decision):** an up or down route that branches off early rejoins the main level. One that branches off near the end can run to its own ladders instead. Test level: the ROOFTOPS (early) come back down into BUILDING MAIN FLOOR; the SERVICE TUNNEL (late) runs to its ladders.
- Every route must still reach the end of the mission (route validation).
- **The roof detour is the slow route (user decision):** coming back down into BUILDING MAIN FLOOR adds ~190 m (a clean run takes ~48 s, not ~38 s). Rather than shorten it, the mission gets more chopper time. Each mission now carries its own timeline (`"chopper"` in `route.json`: lands 15 s, lifts off 58 s, gone 68 s here), with `Tuning` as the default.

### OPEN — Missions / story stages (Point 10)
- The full game has story stages that act as missions. Each reuses the main / up / down structure with its own layout, obstacle looks, trooper sets and chopper time. The test level is one mission.

### PROPOSED — Readable, grounded obstacles (user direction)
- **Tripwire emitters:** each laser comes out of an emitter box at each end, set in the side wall. If a wire stops mid-road, the emitter sits on a floor post. That makes the beam easier to spot.
- **Pipes are plumbed in:** nuts where pipe pieces join. A pipe end next to a wall runs into the wall with a mounting plate; an end in the open bends down into the floor with a foot. No pipe is left floating.
- **No overlapping objects (user rule):** obstacles and troopers sharing a lane need a clear gap between them (`RouteGraph.MIN_GAP`, allowing for each object's depth). Enforced by route validation.

### PROPOSED — BUILDING MAIN FLOOR replaces MOTOR POOL (user decision)
- The main route's second segment is now inside a building: an MGS PS1-style complex/office. Blue-grey panelled walls with a dado stripe, a grey tiled floor, and a ceiling with fluorescent light panels. The fork sign reads MAIN FLOOR.
- **Pipes belong underground (user decision):** pipes are mostly in the tunnels. The main floor gets only the odd small pipe.

### PROPOSED — Each level has its own obstacle set (user direction; main floor built, the rest proposed)
- Gameplay kinds don't change (jump, slide, cover, tripwire); each level changes how they look, so levels are distinct and still read the same way.
- **Main floor (user spec, 2026-09-30):**
  - Interior: blue-grey panelled walls with a dado stripe, a grey tiled floor, and a ceiling with fluorescent light panels.
  - Jump: low filing cabinets, and makeshift blockades of doors and chairs thrown on their sides.
  - Slide: **live electrical wires hanging low, with sparks.** Some are cut, with sparks at the end. This replaces the air-con ducts, which didn't fit visually.
  - Cover: tall metal cabinets and desks, only a few wooden crates. Walls are office partitions.
  - Pipes: only the odd small pipe (`"look": "pipe"`).
  - **Wire span rule (user rule):** low-hanging live wires only ever span 3 or 4 neighbouring lanes, never all 5. Enforced by route validation.
- **Details (user, 2026-09-30):** now and then an office door, a window or a notice board on the side walls. Loose paper scattered on the floor around the low filing cabinets, as if they were tipped over or shoved aside in a hurry.
- **The main route is all office for now (user decision):** the player starts inside the building. COMPOUND EXIT becomes MAIN FLOOR LOBBY and AIRFIELD GATE becomes MAIN FLOOR EXIT, both office-themed; no road sections on the main route. The helipad stays outside. Stairs up to the ROOFTOPS and down to the TUNNEL now start inside the building (consistent with the stacked tiers). The compound and gate themes are kept for later levels.
- **Walls at the edge join the outer wall (user rule, every level):** a wall cover in an edge lane runs right into the side wall, with no gap.
- **Proposed for the rest, needs the user's pick:** COMPOUND: concrete road barriers, boom-gate arms, sandbags / crates / concrete walls. SERVICE TUNNEL: valve housings, pipes, concrete pillars / metal crates. ROOFTOPS: low parapets or skylight frames, antenna cables / water pipes, air-con units / water tanks. AIRFIELD GATE: barriers, boom-gate arms, sandbags / containers.

### OPEN — FIRE button position setting (later)
- User wants a player setting to put FIRE on the left, the right or in the middle. Build it when there's a settings screen. The button's position is already one function (`SwipeInput.fire_button`), so it's a small change.

### PROPOSED — Obstacles stun instead of kill (user decision; part of the OPEN damage model, Point 4)
- Running into a jump or slide obstacle no longer ends the run. You **stumble**: a short stun (`obstacle_stun_time`, no swipes), your speed drops (`obstacle_slow_factor`) and recovers over `obstacle_slow_recover`, and you lose `obstacle_damage` HP (default 1, from the same pool as trooper hits; set 0 to try "time cost only").
- Why HP as well: without it, a player could shrug off obstacles and just take the time hit, and jumping and sliding would stop mattering. Obstacles and troopers share one health pool, so a messy run is what fails.
- A short grace after a stumble (`obstacle_grace`) so one fumble can't chain straight into another.
- The chopper clock turns each stumble into a real cost (about a second).
- Tripwires unchanged: running through one only raises alert. Placeholder 3 HP stays.
- **Playtest (2026-09-30, user):** feels good; keep the current values.

### OPEN — Who captures the player?
- Capture is a LOCKED failure state, but no enemy causes it now that Heavies are blockers. Resolve at Point 8 (Failure states).

### Tech
- Godot 4.7.2, GDScript (not C#: mobile C# export is the weaker path), Compatibility renderer.
- Portrait orientation, 270×480 internal resolution stretched up for the PS1 look. **Assumed. Confirm.**
- Test on iPhone via Web export → GitHub Pages → Safari. A native iOS build needs a Mac with Xcode; defer until the loop is fun.
- Routes are data (`route.json`) and every run logs node ids. That's the foundation for the route map and discovery.
