**Professional Game Design Handover**

**Purpose:** Give Claude enough context to continue the design process
without reopening decisions that are already locked or mistaking
proposals for approved mechanics.

**Current continuation point:** Point 2 — Enemy Types. Controls v1 and
the alert/route interaction rule are locked. The five-enemy roster
discussed most recently is still only a proposal.

# 1. Executive Summary

**HOT EXFIL** (working title: Get to the Chopper!) is a mobile, third-person, forward-moving action
game presented with a deliberately PS1-era visual language. The player
is trying to reach an extraction helicopter before it departs. The
character generally auto-runs away from the camera, while the player
dodges, jumps, slides, shoots, uses contextual cover, and makes
branching route choices at speed.

**The game is not intended to be an endless runner.** Its identity comes
from authored missions with branching paths, persistent knowledge across
attempts, changing enemy pressure through an alert system, and a
post-run route map inspired by The House of the Dead. The player
improves largely by learning the mission rather than by grinding
numerical stats.

Design north star: *A PS1-style cinematic mobile escape game where every
second matters, route knowledge is progression, and the player
repeatedly learns how to reach extraction more efficiently.*

# 2. Decision Status at Handover

| **Area**                                                 | **Status** | **Handover note**                                                                                                                                         |
|----------------------------------------------------------|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| Core concept and camera                                  | LOCKED     | Third-person camera behind the player; character moves away from the camera toward extraction.                                                            |
| PS1 / Metal Gear Solid-inspired presentation             | LOCKED     | Low-poly, low-resolution, deliberately retro visual language; not a bright modern endless-runner look.                                                    |
| Branching authored routes                                | LOCKED     | Every mission contains meaningful path choices that ultimately aim toward the chopper; some routes can fail or capture the player.                        |
| Post-run route map                                       | LOCKED     | Show the actual route travelled and where the run ended; keep information minimal and let the map grow through discovery.                                 |
| Contextual cover concept                                 | LOCKED     | Running into valid cover automatically puts the player into cover; swiping early avoids it and maintains momentum.                                        |
| Alert / route interaction                                | LOCKED     | Alert changes enemy pressure and can change which routes are open. No alert level is universally optimal.                                                 |
| Controls v1                                              | LOCKED     | Auto-run, swipe movement/jump/slide/route choice, one FIRE control, automatic targeting, timed environmental targets, no analogue stick or manual camera. |
| Enemy roster v1                                          | PROPOSED   | Five archetypes were suggested but the user did not approve them yet. Revisit Point 2 and obtain explicit lock-in.                                        |
| Damage, weapons, scoring, progression, mission structure | OPEN       | Still require design passes and explicit approval.                                                                                                        |

# 3. Core Game Vision

## 3.1 Player fantasy

- You are escaping under pressure and must reach a helicopter extraction
  before the window closes.

- The player should feel that stopping, shooting, choosing cover, and
  selecting a route all have a time cost.

- Repeated attempts should turn panic into mastery: first you react,
  later you deliberately exploit what you have learned.

## 3.2 Intended genre position

- Mobile third-person action runner / branching action escape game.

- Not an endless procedural runner.

- Not a full third-person shooter with analogue movement and manual
  camera.

- Not a conventional stealth game where the optimal strategy is waiting
  for guards to calm down.

# 4. Reference Games and What to Borrow

| **Reference**               | **Borrow**                                                                                                    | **Do not import wholesale**                                                                                |
|-----------------------------|---------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------|
| Subway Surfers / Temple Run | Simple gesture vocabulary, constant forward momentum, readable obstacles, immediate restartability.           | Lane-bound endless-runner structure, procedural repetition, bright arcade tone.                            |
| The House of the Dead       | Branching authored paths, player actions affecting route, replay through route discovery, post-run route map. | Fully on-rails shooting as the entire interaction model.                                                   |
| Metal Gear Solid (PS1)      | PS1 atmosphere, wall/cover language, alerts, enemy awareness, simple/assisted targeting, cinematic tension.   | Full stealth simulation, inventory complexity, waiting for alert countdowns, console-scale control scheme. |

**Research basis.** Subway Surfers officially uses swipe left/right,
swipe up to jump and swipe down to roll. Konami’s Metal Gear manuals
document wall pressing/hiding and enemy alert states. The House of the
Dead series uses branching paths whose outcomes can be affected by
player actions, and route maps highlight the path taken after game
over/completion.

# 5. Core Gameplay Loop

1.  Mission starts under extraction pressure

2.  Auto-run through forward route

3.  Dodge / jump / slide / shoot

4.  Reach route junction or conditional branch

5.  Choose or trigger a path

6.  Survive route-specific enemies / hazards / alert consequences

7.  Use or avoid contextual cover

8.  Manage alert opportunities such as alarm boxes

9.  Repeat route decisions

10. Final sprint to visible helicopter

11. Success: extract / Failure: death, capture or chopper leaves

12. Show route map

13. Retry or continue

# 6. LOCKED — Controls v1

**Locked rule:** The player auto-runs. Swipes control lateral dodging,
jumping, sliding and route selection. Cover is contextual. Shooting uses
one FIRE control with generous automatic targeting. Major route choices
briefly slow but never stop the action. There is no analogue stick or
manual camera.

## 6.1 Movement

- Auto-run forward by default.

- Swipe left/right: smooth lateral dodge/change running line; avoid
  rigid three-lane movement where possible.

- Swipe up: jump or vault appropriate geometry.

- Swipe down: slide/crouch under a hazard.

- At an explicit branch, swipe left/right to commit to that route.

## 6.2 Shooting

- One persistent FIRE control.

- Generous automatic target selection in a forward cone; player chooses
  when to engage rather than manually placing a small crosshair.

- Environmental targets such as alarm boxes use short timing windows and
  should be visually readable.

## 6.3 Route-choice presentation

- Major junctions may briefly reduce game speed to aid readability, but
  must not pause the action.

- Use both explicit choices and implicit/conditional branches caused by
  player actions or state.

# 7. LOCKED — Contextual Cover

- Valid cover objects include walls, crates, concrete barriers, vehicles
  and similar readable geometry.

- If the auto-running player collides directly with valid cover, the
  character automatically takes cover.

- Swiping early allows an experienced player to dodge around the cover
  and preserve momentum.

- From cover, swiping away from the obstacle exits cover and resumes the
  run.

- Cover is a time/safety trade-off rather than a separate tactical mode.

- No dedicated cover button.

**Design intent:** Beginners can safely collide with cover and reassess.
Skilled players recognise cover early and choose whether the safety is
worth losing time.

# 8. LOCKED — Branching Route Design

- Every path is authored; procedural route generation is not the current
  direction.

- Most routes eventually reconverge toward extraction, but some can lead
  to capture/death or conditional failure.

- Different routes should change gameplay, not merely scenery:
  combat-heavy, movement-heavy, slower/safer, faster/riskier,
  resource-rich, stealthier, environmental hazard, etc.

- True trap/dead-end routes should be relatively rare so choices do not
  become arbitrary guessing.

- Some apparent dead ends may later be revealed as conditional shortcuts
  if the player has the right state, item, alert level or timing.

- Suggested initial target: roughly 3–5 meaningful route decisions in a
  full mission, subject to prototype testing.

## 8.1 Explicit and implicit branches

- Explicit: visible fork; slight slowdown; player swipes toward chosen
  route.

- Implicit: shoot a switch, destroy a barrier, save someone, fail a
  timed action, enter with a particular alert level, or otherwise cause
  the route to change automatically.

# 9. LOCKED — Alert System and Route Interaction

**Locked rule:** Alert level changes enemy pressure and can alter which
routes exist, but no alert level is universally optimal. Managing — or
even deliberately raising — alert can be strategically useful.

## 9.1 Current working model

- Alert is active as an ongoing pursuit state; the player generally does
  not hide and wait for it to disappear.

- Working three-level structure: Alert 1 / Alert 2 / Alert 3 (names are
  not final).

- Higher alert means denser/more dangerous enemy deployment and
  potentially environmental lockdown changes.

- Some low-alert routes may remain open only before lockdown.

- Some high-alert routes may open because security shutters,
  reinforcement gates or emergency corridors change state.

## 9.2 Alarm boxes

- Alarm boxes periodically appear as environmental shooting
  opportunities.

- The player must hit the box during a short timing window while moving
  past it.

- Current recommendation: a successful hit reduces alert by one level
  rather than resetting it completely.

- Missing the timing window means the player has already passed the
  opportunity; no backtracking.

# 10. LOCKED — Post-Run Route Map and Discovery

- Shown when the player dies, is captured, misses extraction, or
  completes the mission.

- Highlight the route actually travelled and mark the run endpoint.

- Keep the map deliberately restrained. Do not currently display threat
  ratings, recommended routes, “safe/dangerous” labels or detailed route
  descriptions.

- Unexplored areas should remain unknown; the map should grow through
  play rather than reveal the whole mission tree immediately.

- The player’s knowledge of routes, hazards, shortcuts and failures is
  itself a progression system.

**Core philosophy:** “You do not level up the map. You learn it.”

# 11. LOCKED — Visual / Presentation Direction

- PS1-era low-poly look, with Metal Gear Solid as a key
  mood/presentation reference.

- Low-resolution textures, simple geometry, limited draw distance/fog,
  chunky effects and intentionally retro UI.

- Camera behind and slightly above the player, looking into the route
  ahead.

- Avoid the bright, glossy visual language associated with many modern
  endless runners.

- Cinematic beats should be short and return control immediately; the
  game must maintain urgency.

# 12. Working Direction — Extraction Pressure

**Not yet explicitly locked, but strongly favoured in discussion:** the
helicopter itself should communicate urgency rather than relying solely
on a giant HUD countdown.

- Possible escalation: CHOPPER INBOUND → LANDED → EXTRACTION WINDOW →
  LIFTING OFF → GONE.

- Radio chatter and occasional visual sightings can reinforce urgency.

- Successful final approach should visibly show the helicopter and
  deliver a strong last sprint.

- Suggested successful mission length discussed: approximately 3–5
  minutes; prototype first with a 60–90 second slice.

# 13. PROPOSED — Enemy Roster v1 (Not Yet Approved)

**Important for Claude:** Do not treat this section as locked. It was
the assistant’s recommendation immediately before this handover request.
The user has not approved or rejected it.

| **Proposed enemy**  | **Purpose**                                                                          |
|---------------------|--------------------------------------------------------------------------------------|
| Rifle Trooper       | Baseline medium-range soldier; core combat grammar.                                  |
| Close-Range Trooper | Aggressive short-range pressure unit; prevents cover from becoming universally safe. |
| Heavy Trooper       | High-health route blocker/checkpoint threat; often better avoided than fought.       |
| Sniper              | Timing/movement threat with a readable aim window; suited to rooftops/open routes.   |
| Security Trooper    | Alert specialist who can trigger/raise alarms if not stopped quickly.                |

**Suggested principle:** Get variety primarily from enemy placement,
route context and alert level before expanding the roster.

# 14. Open Design Questions / Remaining Passes

| **Next design pass**                | **Question to resolve**                                                                                                    |
|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| Point 2 — Enemy types               | Revisit the proposed five-archetype roster and obtain explicit approval/changes.                                           |
| Point 3 — Obstacles                 | Define jump, slide, dodge, cover, collapsing, vehicle and hazard categories.                                               |
| Point 4 — Damage model              | Health bar vs hit-based system; recovery rules; failure threshold.                                                         |
| Point 5 — Weapons                   | Starting weapon, ammo, pickups, replacement vs temporary weapons, grenades/specials.                                       |
| Point 6 — Alert details             | Precisely define what raises each alert level, mission starting states, alarm-box strength, and enemy/environment changes. |
| Point 7 — Route-choice presentation | Lock exact slowdown duration/readability language and how environmental cues communicate branches.                         |
| Point 8 — Failure states            | Death, capture, helicopter departure, mission-specific failures; how each appears on route map.                            |
| Point 9 — Extraction sequence       | Define final sprint, helicopter behaviour and success presentation.                                                        |
| Point 10 — Mission structure        | Campaign vs mission select; authored mission count and progression model.                                                  |
| Point 11 — Meta-progression         | Characters, weapons, cosmetics, challenges; avoid stat grind that trivialises route design.                                |
| Point 12 — Scoring                  | Time, damage, accuracy, kills, discovery, secrets; ensure avoidance can score as legitimately as combat.                   |
| Point 13 — Mission themes           | Biomes/environments and what unique mechanic each introduces.                                                              |
| Point 14 — Narrative premise        | Who the player is, who the troopers are, why repeated extraction missions occur, why the chopper will leave.               |

# 15. Recommended First Playable Prototype

**Goal:** Prove the 20–30 seconds between route decisions before
expanding content.

- 60–90 second authored mission slice.

- Auto-run and swipe dodge/jump/slide.

- One simple shooting encounter using FIRE + auto-targeting.

- One valid cover object that can be hit or dodged early.

- One alarm box timing opportunity.

- At least one visible alert-state change.

- Two route choices.

- One route whose availability changes with alert level.

- One capture/death possibility.

- Visible helicopter extraction at the end.

- Post-run route map showing the chosen path and endpoint.

# 16. Design Principles to Preserve

- Momentum over simulation. Every feature should respect the
  forward-running escape fantasy.

- Few controls, many consequences. Complexity should come from level
  design and timing, not button count.

- Route choices must alter gameplay, not just scenery.

- Knowledge is progression. Replay should make the player smarter, not
  merely numerically stronger.

- No universal optimal alert state. Alert is a strategic map modifier as
  well as a difficulty pressure system.

- Failure should teach. Capture/death paths should make sense in
  hindsight and feed the route-discovery loop.

- Start restrained. Add route metadata, enemy types, progression and
  information only when testing shows a need.

# 17. Exact Continuation Instruction for Claude

Continue at Point 2 — Enemy Types. Present the proposed five-archetype
roster as a recommendation, not a decision. Critically assess whether
each archetype earns its place in a fast, auto-running mobile game with
PS1/MGS presentation, branching House-of-the-Dead-style routes,
contextual cover and a persistent alert system. Keep the roster minimal,
explain how each enemy behaves at different alert levels and on
different routes, then ask for/obtain explicit lock-in before moving to
Point 3 — Obstacles.

# 18. Reference Sources

- [<u>Subway Surfers Help Center —
  Basics</u>](https://sybo.helpshift.com/hc/en/5-subway-surfers/faq/205-basics/)
  — Official control reference: swipe left/right, swipe up to jump,
  swipe down to roll.

- [<u>Konami — Metal Gear Solid Master Collection
  manual</u>](https://metalgear.konami.net/manual/mc1/mgs1/ps5/en/index.html)
  — Official reference for MGS controls, stealth techniques, camera and
  enemy alert levels.

- [<u>Konami — Metal Gear Solid: Peace Walker manual, Special
  Controls</u>](https://metalgear.konami.net/manual/mc2/mgspw/ps5/en/page08.html)
  — Official example of wall press/hiding behaviour.

- [<u>The House of the Dead III Xbox
  manual</u>](https://www.gamesdatabase.org/Media/SYSTEM/Microsoft_Xbox/Manual/formated/House_of_the_Dead_3_-_Sega.pdf)
  — Manual explicitly describes the branching story system and outcomes
  affected by player actions.

- [<u>The Wiki of the Dead — Branching
  paths</u>](https://thehouseofthedead.fandom.com/wiki/Branching_paths)
  — Secondary reference summarising path variations and post-run route
  maps across the series.

# 19. Handover Caution

**Do not silently “improve” locked mechanics.** If a later system
genuinely conflicts with a locked rule, call out the conflict and
propose an alternative, but preserve the existing decision until the
user explicitly changes it. The project is currently in
design-definition mode, not implementation mode.
