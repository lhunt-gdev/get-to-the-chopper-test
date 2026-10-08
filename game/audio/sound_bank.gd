class_name SoundBank
extends RefCounted
## Every sound in the game, synthesised in code (no audio files), PS1/N64-style: low sample rates,
## a little bit-crush, echo baked in. Inspired by MGS1 (quiet humming ambience, the "!" sting, the
## wall-press thump, alert music) and GoldenEye (punchy, dry gunshots).
##
## Sounds are cached by name. The AudioDirector has them all built in the background, a few
## milliseconds a frame (work): each recipe is a coroutine whose Synth ops stop when the frame's time
## is up and carry on in the next, so no sound, however long, costs a frame more than its share.
## get_stream() builds anything missing at once.

const SFX_RATE := 22050
const AMB_RATE := 11025
const MUSIC_RATE := 16000
## Footstep surfaces, each with a few variations ("step_<surface>_<n>").
const SURFACES := ["office", "tunnel", "gravel", "stairs", "concrete"]
const STEP_VARIANTS := 3
const LOOPS := ["music_menu", "amb_office", "amb_tunnel", "amb_roof", "amb_cctv", "steam", "crackle", "rotor",
		"music_tension", "music_alert", "minigun_fire"]

static var _cache: Dictionary = {}
## The sounds waiting to be built in the background (queue), and the one being built, waiting for
## its next turn ("" when none is).
static var _queue: Array[String] = []
static var _building := ""


static func has(name: String) -> bool:
	return _cache.has(name)


## The sound, built now if it isn't yet (all of it at once: it's wanted now).
static func get_stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		var until := Synth.pace.until_usec
		Synth.pace.until_usec = 0
		if name == _building:
			Synth.pace.go.emit()  # (it's half built in the background: finish that one)
		else:
			_build(name)
		Synth.pace.until_usec = until
	return _cache.get(name)


## Every sound's name, roughly in the order they're first needed. The background builds them in
## this order. First the main menu's: CROSS's gun check (its first sound comes 1.85 s in, before
## the menu music, the longest of all to build, is done) and the buttons' tick, all tiny; then the
## menu music.
static func all_names() -> Array[String]:
	var names: Array[String] = ["slide_back", "slide_home", "mag_out", "mag_slap", "tick", "music_menu", "codec", "codec_open", "codec_static", "codec_close", "amb_office", "door_wood", "gun", "spotted", "hit", "fall",
			"gun_trooper", "cover", "jump", "land", "slide", "stumble", "player_hit", "zap", "beep",
			"alarm_break", "alert_up", "klaxon", "alert_down", "squelch", "door_steel", "door_bars",
			"door_push", "door_shut", "gate_push", "gate_shut",
			"music_tension", "music_alert", "amb_tunnel", "amb_roof", "amb_cctv", "steam", "crackle",
			"rotor", "warn", "jingle", "gameover", "bark", "yelp", "bite", "thunk", "sniper_aim", "sniper_lock", "sniper_shot",
			"minigun_spin", "minigun_fire", "gun_drop", "slowmo"]
	for i in 3:
		names.append("grunt_%d" % i)
	for surface in SURFACES:
		for i in STEP_VARIANTS:
			names.append("step_%s_%d" % [surface, i])
	return names


## Queue a sound to be built in the background (work), if it isn't built or on its way already.
static func queue(name: String) -> void:
	if _cache.has(name) or name == _building or name in _queue:
		return
	_queue.append(name)


## Whether any sound is still waiting to be built in the background.
static func building() -> bool:
	return _building != "" or not _queue.is_empty()


## A turn of building in the background: the sound half built carries on, then the next ones in the
## queue, until `budget_ms` is spent (something always gets done, whatever the budget). The op at
## work when the time runs out finishes its chunk (Synth.CHUNK: a tenth to a quarter of a
## millisecond on a desktop) and waits there for the next turn.
static func work(budget_ms: float) -> void:
	Synth.pace.until_usec = Time.get_ticks_usec() + int(budget_ms * 1000.0)
	if _building != "":
		Synth.pace.go.emit()  # (the one half built carries on)
	else:
		_start_next()
	while _building == "" and not _queue.is_empty() and not Synth.pace.due():
		_start_next()
	Synth.pace.until_usec = 0


## Finishes the sound half built in the background, at once: the level is going (Retry, or the game
## quitting). Left waiting for a next turn that never comes, its coroutines would hold each other
## (and the scripts) for good; letting go of them doesn't free them.
static func finish_half_built() -> void:
	if _building != "":
		get_stream(_building)


## The next sound in the queue that isn't built yet, started: it runs until the turn's time is up,
## then waits for the next turn (or it's done).
static func _start_next() -> void:
	while not _queue.is_empty():
		var name: String = _queue.pop_front()
		if not _cache.has(name):
			_building = name
			_build(name)
			return


## Builds the sound and keeps it. A coroutine: in the background it stops whenever a turn's time is
## up (work); called by get_stream, nothing stops it.
static func _build(name: String) -> void:
	var wav: AudioStreamWAV
	match name:
		"amb_office", "amb_tunnel", "amb_roof", "amb_cctv":
			wav = await _ambience(name)
		"music_tension":
			wav = await _tension()
		"music_alert":
			wav = await _alert_music()
		"music_menu":
			wav = await _menu_music()
		_:
			wav = await _make(name)
	if not _cache.has(name):
		_cache[name] = wav
	if _building == name:
		_building = ""


# --- One-shot sounds ------------------------------------------------------------------

static func _make(name: String) -> AudioStreamWAV:
	var seed_value := absi(hash(name))
	if name.begins_with("step_"):
		var parts := name.split("_")
		return await _footstep(parts[1], int(parts[2]))
	if name.begins_with("grunt_"):
		return await _grunt(int(name.get_slice("_", 1)))
	var syn: Synth
	match name:
		"gun":
			# Your rifle (GoldenEye-style): a hard crack, a chesty thump, a short room echo.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.2, 0.9, 5200.0, 0.0, 0.0005, 16.0)
			await syn.tone(0.0, 0.16, 150.0, 45.0, 0.9, Synth.Wave.SINE, 0.001, 6.0)
			await syn.tone(0.0, 0.025, 2200.0, 600.0, 0.35, Synth.Wave.SQUARE, 0.0005, 3.0)
			await syn.echo(0.07, 0.25, 0.3)
			await syn.crush(8, 2)
			await syn.normalize(0.95)
		"gun_trooper":
			# Theirs: duller and further off, with more echo.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.18, 0.8, 2600.0, 0.0, 0.0005, 14.0)
			await syn.tone(0.0, 0.14, 120.0, 40.0, 0.7, Synth.Wave.SINE, 0.001, 6.0)
			await syn.echo(0.11, 0.35, 0.4)
			await syn.crush(8, 2)
			await syn.normalize(0.8)
		"hit":
			# A bullet striking a body: a wet slap and a dull thud.
			syn = Synth.create(0.2, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.09, 0.8, 1400.0, 120.0, 0.0005, 9.0)
			await syn.tone(0.0, 0.11, 190.0, 60.0, 0.7, Synth.Wave.SINE, 0.001, 7.0)
			await syn.crush(9, 1)
			await syn.normalize(0.85)
		"gun_drop":
			# The boss's minigun hitting the deck: a heavy thump and a dull clank (on concrete, duller
			# than steel on steel), a bounce, and the clatter of its belt.
			syn = Synth.create(0.9, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.25, 120.0, 45.0, 0.9, Synth.Wave.SINE, 0.001, 5.0)
			await syn.noise(0.0, 0.12, 0.7, 1800.0, 100.0, 0.0005, 9.0)
			await _clang(syn, 0.0, 0.5)
			await syn.tone(0.24, 0.15, 100.0, 50.0, 0.5, Synth.Wave.SINE, 0.001, 7.0)
			await _clang(syn, 0.24, 0.25)
			for i in 6:
				await syn.noise(0.3 + i * 0.05, 0.03, 0.25 * (1.0 - i / 6.0), 3500.0, 600.0, 0.0005, 20.0)
			await syn.lowpass(4000.0)
			await syn.crush(9, 1)
			await syn.normalize(0.85)
		"slowmo":
			# The cut into the boss's KO replay (each shot): a deep whoosh falling away, a low boom under it.
			syn = Synth.create(1.1, SFX_RATE, seed_value)
			await syn.noise(0.0, 1.0, 0.5, 700.0, 60.0, 0.25, 2.5)
			await syn.tone(0.0, 0.9, 140.0, 40.0, 0.7, Synth.Wave.SINE, 0.01, 2.5)
			await syn.echo(0.18, 0.4, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.6)
		"fall":
			# A body hitting the floor.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.28, 95.0, 38.0, 0.9, Synth.Wave.SINE, 0.002, 5.0)
			await syn.noise(0.0, 0.3, 0.6, 450.0, 0.0, 0.002, 7.0)
			await syn.noise(0.12, 0.15, 0.3, 600.0, 0.0, 0.002, 9.0)  # the rifle clattering
			await syn.crush(10, 1)
			await syn.normalize(0.8)
		"spotted":
			# MGS's "!": a sharp, dissonant high stab with a metallic shimmer and echo.
			syn = Synth.create(0.9, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.5, 1568.0, 1568.0, 0.35, Synth.Wave.SQUARE, 0.0005, 5.0)
			await syn.tone(0.0, 0.5, 1661.0, 1661.0, 0.3, Synth.Wave.SQUARE, 0.0005, 5.0)
			await syn.tone(0.0, 0.35, 784.0, 784.0, 0.35, Synth.Wave.SAW, 0.0005, 6.0)
			await syn.noise(0.0, 0.15, 0.4, 0.0, 3000.0, 0.0005, 10.0)
			await syn.lowpass(7000.0)
			await syn.echo(0.09, 0.4, 0.45)
			await syn.crush(9, 1)
			await syn.normalize(0.75)
		"alert_up":
			# Alert raised: a low orchestral hit (a tritone chord and a timpani boom) with a crash.
			syn = Synth.create(1.4, SFX_RATE, seed_value)
			for f in [130.8, 185.0, 261.6, 370.0]:
				await syn.tone(0.0, 0.9, f, f * 0.98, 0.22, Synth.Wave.SAW, 0.004, 3.5)
			await syn.tone(0.0, 0.6, 70.0, 50.0, 0.8, Synth.Wave.SINE, 0.002, 4.0)
			await syn.noise(0.0, 0.7, 0.35, 6000.0, 1500.0, 0.001, 4.0)
			await syn.lowpass(3500.0)
			await syn.echo(0.13, 0.35, 0.35)
			await syn.crush(9, 1)
			await syn.normalize(0.85)
		"klaxon":
			# Full alert: a two-tone alarm.
			syn = Synth.create(1.6, SFX_RATE, seed_value)
			for i in 6:
				var f := 660.0 if i % 2 == 0 else 880.0
				await syn.tone(i * 0.25, 0.24, f, f, 0.5, Synth.Wave.SQUARE, 0.005, 0.0)
			await syn.lowpass(2800.0)
			await syn.echo(0.16, 0.3, 0.3)
			await syn.crush(8, 2)
			await syn.normalize(0.6)
		"alert_down":
			# Alert dropped: a falling codec-style blip.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			for i in 3:
				var f: float = [1320.0, 990.0, 660.0][i]
				await syn.tone(i * 0.09, 0.08, f, f, 0.45, Synth.Wave.SQUARE, 0.002, 2.0)
			await syn.lowpass(5000.0)
			await syn.echo(0.1, 0.2, 0.2)
			await syn.normalize(0.55)
		"door_wood":
			# An office door shouldered open: a crash, a thud and a rattle.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.25, 0.8, 2200.0, 80.0, 0.0005, 8.0)
			await syn.tone(0.0, 0.22, 120.0, 50.0, 0.8, Synth.Wave.SINE, 0.001, 5.0)
			for i in 3:
				await syn.noise(0.08 + i * 0.06, 0.04, 0.3, 1800.0, 400.0, 0.0005, 8.0)
			await syn.echo(0.08, 0.25, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.85)
		"door_steel":
			# A steel door: a hard clang that rings.
			syn = Synth.create(1.0, SFX_RATE, seed_value)
			await _clang(syn, 0.0, 1.0)
			await syn.tone(0.0, 0.2, 110.0, 45.0, 0.7, Synth.Wave.SINE, 0.001, 5.0)
			await syn.echo(0.1, 0.3, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.85)
		"door_bars":
			# Barred gates: clangs and a rattle of bars.
			syn = Synth.create(1.2, SFX_RATE, seed_value)
			await _clang(syn, 0.0, 1.0)
			for i in 5:
				await _clang(syn, 0.06 + i * 0.07, 0.35 / (i + 1))
			await syn.noise(0.0, 0.35, 0.3, 4000.0, 1500.0, 0.001, 6.0)
			await syn.echo(0.12, 0.35, 0.35)
			await syn.crush(9, 1)
			await syn.normalize(0.85)
		"door_push":
			# A zone door shoved open by the alarm runner, up ahead (quieter than your crash): the thump
			# of the push bar, the latch, a short creak of the hinges.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.12, 120.0, 70.0, 0.6, Synth.Wave.SINE, 0.001, 6.0)
			await syn.noise(0.0, 0.03, 0.4, 4000.0, 900.0, 0.0005, 9.0)
			await syn.tone(0.05, 0.3, 380.0, 460.0, 0.16, Synth.Wave.SAW, 0.03, 2.0)
			await syn.tone(0.05, 0.3, 384.0, 452.0, 0.1, Synth.Wave.SQUARE, 0.03, 2.0)
			await syn.lowpass(2500.0)
			await syn.echo(0.08, 0.2, 0.25)
			await syn.crush(9, 1)
			await syn.normalize(0.55)
		"door_shut":
			# It swings shut behind him: a soft thud and the latch clicking home.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.2, 95.0, 50.0, 0.8, Synth.Wave.SINE, 0.002, 5.0)
			await syn.noise(0.0, 0.12, 0.45, 900.0, 0.0, 0.001, 8.0)
			await syn.noise(0.03, 0.02, 0.35, 5000.0, 1500.0, 0.0005, 10.0)
			await syn.echo(0.09, 0.25, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.6)
		"gate_push":
			# A barred gate (or a roller shutter) shoved by him: a rattle of bars, a squeal of hinges.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			for i in 4:
				await _clang(syn, i * 0.05 + syn.randf_range(0.0, 0.02), 0.18 / (i + 1))
			await syn.noise(0.0, 0.3, 0.25, 4000.0, 1200.0, 0.002, 6.0)
			await syn.tone(0.04, 0.3, 820.0, 980.0, 0.1, Synth.Wave.SAW, 0.03, 2.5)
			await syn.lowpass(4500.0)
			await syn.echo(0.1, 0.25, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.5)
		"gate_shut":
			# It clanks shut behind him, and the latch drops.
			syn = Synth.create(0.9, SFX_RATE, seed_value)
			await _clang(syn, 0.0, 0.6)
			await syn.tone(0.0, 0.18, 110.0, 50.0, 0.6, Synth.Wave.SINE, 0.001, 5.0)
			await syn.noise(0.02, 0.03, 0.4, 5000.0, 1500.0, 0.0005, 10.0)
			await syn.echo(0.12, 0.3, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.6)
		"jump":
			# A quick whoosh of clothing and kit.
			syn = Synth.create(0.25, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.22, 0.5, 2500.0, 500.0, 0.05, 3.0)
			await syn.normalize(0.4)
		"land":
			syn = Synth.create(0.2, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.08, 0.6, 900.0, 0.0, 0.0005, 8.0)
			await syn.tone(0.0, 0.1, 110.0, 60.0, 0.6, Synth.Wave.SINE, 0.001, 6.0)
			await syn.normalize(0.55)
		"slide":
			# Sliding on the floor: a gritty scrape.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.45, 0.6, 1200.0, 200.0, 0.02, 2.5)
			await syn.crush(7, 2)
			await syn.normalize(0.45)
		"cover":
			# MGS's wall press: a soft back-to-the-wall thump and a rustle.
			syn = Synth.create(0.3, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.12, 85.0, 55.0, 0.9, Synth.Wave.SINE, 0.001, 5.0)
			await syn.noise(0.0, 0.1, 0.5, 700.0, 0.0, 0.0005, 7.0)
			await syn.noise(0.03, 0.12, 0.25, 5000.0, 1500.0, 0.01, 4.0)
			await syn.crush(10, 1)
			await syn.normalize(0.7)
		"stumble":
			# Running into something: a crunch and a clatter.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.2, 0.8, 1800.0, 60.0, 0.0005, 7.0)
			await syn.tone(0.0, 0.18, 100.0, 45.0, 0.8, Synth.Wave.SINE, 0.001, 5.0)
			await _clang(syn, 0.05, 0.25)
			await syn.crush(9, 1)
			await syn.normalize(0.8)
		"player_hit":
			# You're hit: a heavy crunchy thump.
			syn = Synth.create(0.4, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.22, 75.0, 40.0, 0.9, Synth.Wave.SINE, 0.001, 4.0)
			await syn.noise(0.0, 0.16, 0.7, 1500.0, 0.0, 0.0005, 8.0)
			await syn.tone(0.0, 0.12, 220.0, 110.0, 0.35, Synth.Wave.SQUARE, 0.001, 5.0)
			await syn.crush(6, 2)
			await syn.normalize(0.85)
		"zap":
			# A tripwire or live wire: an electric buzz and crackle.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.5, 120.0, 100.0, 0.4, Synth.Wave.SAW, 0.002, 3.0)
			for i in 10:
				await syn.noise(syn.randf_range(0.0, 0.45), 0.02, 0.6, 0.0, 2000.0, 0.0005, 6.0)
			await syn.crush(7, 2)
			await syn.normalize(0.7)
		"beep":
			# The alarm box, while you can shoot it.
			syn = Synth.create(0.08, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.07, 2093.0, 2093.0, 0.5, Synth.Wave.SQUARE, 0.001, 2.0)
			await syn.lowpass(6000.0)
			await syn.normalize(0.4)
		"alarm_break":
			# The alarm box destroyed: an electrical crunch dying away.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.2, 0.8, 4000.0, 300.0, 0.0005, 7.0)
			await syn.tone(0.0, 0.4, 800.0, 80.0, 0.4, Synth.Wave.SQUARE, 0.001, 3.0)
			for i in 6:
				await syn.noise(syn.randf_range(0.05, 0.5), 0.015, 0.5, 0.0, 2500.0, 0.0005, 6.0)
			await syn.crush(8, 1)
			await syn.normalize(0.8)
		"codec":
			# Tap to start: MGS codec's "pi-pi".
			syn = Synth.create(0.4, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.07, 1046.0, 1046.0, 0.4, Synth.Wave.SQUARE, 0.001, 1.0)
			await syn.tone(0.0, 0.07, 2093.0, 2093.0, 0.15, Synth.Wave.SINE, 0.001, 1.0)
			await syn.tone(0.12, 0.07, 1318.0, 1318.0, 0.4, Synth.Wave.SQUARE, 0.001, 1.0)
			await syn.tone(0.12, 0.07, 2637.0, 2637.0, 0.15, Synth.Wave.SINE, 0.001, 1.0)
			await syn.lowpass(6000.0)
			await syn.echo(0.09, 0.2, 0.2)
			await syn.normalize(0.5)
		"codec_open":
			# The mission briefing's codec screen opening (MGS1-style): a quick chirp rising through a
			# crackle of static, two blips as the faces come on.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.3, 0.3, 6000.0, 900.0, 0.01, 3.0)
			await syn.tone(0.0, 0.16, 500.0, 2600.0, 0.4, Synth.Wave.SQUARE, 0.002, 1.5)
			await syn.tone(0.18, 0.05, 2600.0, 2600.0, 0.3, Synth.Wave.SQUARE, 0.001, 3.0)
			await syn.tone(0.25, 0.05, 3100.0, 3100.0, 0.25, Synth.Wave.SQUARE, 0.001, 3.0)
			await syn.lowpass(7000.0)
			await syn.crush(7, 2)
			await syn.echo(0.07, 0.2, 0.2)
			await syn.normalize(0.5)
		"codec_close":
			# The briefing's codec closing: the chirp falling, the click of it switching off.
			syn = Synth.create(0.35, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.18, 2400.0, 300.0, 0.4, Synth.Wave.SQUARE, 0.001, 2.0)
			await syn.noise(0.0, 0.12, 0.3, 5000.0, 900.0, 0.002, 5.0)
			await syn.tone(0.2, 0.03, 900.0, 900.0, 0.3, Synth.Wave.SQUARE, 0.0005, 6.0)
			await syn.lowpass(6000.0)
			await syn.crush(7, 2)
			await syn.normalize(0.45)
		"codec_static":
			# A new caller on the briefing's codec: a burst of uneven, crackling static (no blip,
			# unlike squelch).
			syn = Synth.create(0.42, SFX_RATE, seed_value)
			for i in 7:
				await syn.noise(i * 0.05 + syn.randf_range(0.0, 0.02), 0.08, syn.randf_range(0.4, 0.8), 7000.0, 600.0, 0.002, 3.0)
			await syn.noise(0.0, 0.4, 0.3, 4000.0, 300.0, 0.02, 2.0)
			await syn.crush(6, 2)
			await syn.normalize(0.5)
		"tick":
			# One letter of a typed caption.
			syn = Synth.create(0.03, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.015, 3000.0, 2500.0, 0.4, Synth.Wave.SQUARE, 0.0005, 6.0)
			await syn.noise(0.0, 0.01, 0.2, 0.0, 3000.0, 0.0005, 8.0)
			await syn.normalize(0.3)
		"sniper_aim":
			# A sniper's laser coming on: a thin rising whine.
			syn = Synth.create(0.35, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.3, 1400.0, 2600.0, 0.25, Synth.Wave.SINE, 0.02, 2.0)
			await syn.tone(0.0, 0.3, 1410.0, 2610.0, 0.12, Synth.Wave.SQUARE, 0.02, 2.0)
			await syn.lowpass(5000.0)
			await syn.normalize(0.35)
		"sniper_lock":
			# Locked on: a fast, high double beep (change lane now).
			syn = Synth.create(0.22, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.05, 3100.0, 3100.0, 0.5, Synth.Wave.SQUARE, 0.001, 1.0)
			await syn.tone(0.09, 0.07, 3100.0, 3100.0, 0.5, Synth.Wave.SQUARE, 0.001, 1.0)
			await syn.lowpass(7000.0)
			await syn.normalize(0.5)
		"sniper_shot":
			# The sniper's rifle, far off: a hard crack, a low thump and a long echo off the city.
			syn = Synth.create(1.6, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.05, 1.0, 9000.0, 1500.0, 0.0005, 30.0)
			await syn.tone(0.0, 0.18, 120.0, 55.0, 0.8, Synth.Wave.TRIANGLE, 0.001, 12.0)
			await syn.noise(0.02, 0.3, 0.35, 2500.0, 200.0, 0.002, 7.0)
			await syn.echo(0.23, 0.45, 0.35)
			await syn.lowpass(7000.0)
			await syn.normalize(0.7)
		"minigun_spin":
			# The boss's minigun spinning up (the telegraph): a motor's whine rising, the barrels'
			# rattle quickening.
			syn = Synth.create(1.0, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.95, 180.0, 900.0, 0.35, Synth.Wave.SQUARE, 0.05, 1.5)
			await syn.tone(0.0, 0.95, 90.0, 450.0, 0.3, Synth.Wave.TRIANGLE, 0.05, 1.5)
			for i in 14:
				var t := 0.9 * (1.0 - pow(1.0 - i / 14.0, 1.6))
				await syn.noise(t, 0.02, 0.25, 4000.0, 900.0, 0.001, 30.0)
			await syn.lowpass(5000.0)
			await syn.crush(8, 1)
			await syn.normalize(0.5)
		"minigun_fire":
			# The minigun firing (loop; on only while the stream is): a buzz-saw roar of shots (50 a
			# second), a low motor under it.
			syn = Synth.create(0.62, SFX_RATE, seed_value)
			for i in 31:
				await syn.noise(i * 0.02, 0.018, 0.9, 7000.0, 600.0, 0.0005, 40.0)
			await syn.tone(0.0, 0.62, 110.0, 110.0, 0.5, Synth.Wave.SQUARE, 0.0, 0.0)
			await syn.tone(0.0, 0.62, 55.0, 55.0, 0.4, Synth.Wave.TRIANGLE, 0.0, 0.0)
			await syn.lowpass(6000.0)
			await syn.crush(7, 1)
			await syn.normalize(0.75)
			await syn.loopify(0.02)
			return await syn.to_stream(true)
		"slide_back":
			# CROSS's press check under the menu: the slide eased back a little (a crisp click and a
			# short metal scrape).
			syn = Synth.create(0.22, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.03, 0.8, 9000.0, 2500.0, 0.0003, 30.0)
			await syn.tone(0.0, 0.08, 3400.0, 3300.0, 0.25, Synth.Wave.SQUARE, 0.0003, 25.0)
			await syn.noise(0.02, 0.12, 0.25, 5000.0, 1500.0, 0.01, 6.0)
			await syn.lowpass(8000.0)
			await syn.crush(9, 1)
			await syn.normalize(0.5)
		"slide_home":
			# ...and let home: a softer, lower click as it seats.
			syn = Synth.create(0.18, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.04, 0.7, 6000.0, 1200.0, 0.0003, 25.0)
			await syn.tone(0.0, 0.06, 2200.0, 2100.0, 0.25, Synth.Wave.SQUARE, 0.0003, 30.0)
			await syn.tone(0.0, 0.05, 300.0, 200.0, 0.3, Synth.Wave.SINE, 0.0005, 30.0)
			await syn.lowpass(7000.0)
			await syn.crush(9, 1)
			await syn.normalize(0.45)
		"mag_out":
			# The magazine released into his palm: the catch's click, then it sliding out.
			syn = Synth.create(0.25, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.02, 0.8, 8000.0, 2500.0, 0.0003, 35.0)
			await syn.tone(0.0, 0.05, 2800.0, 2700.0, 0.2, Synth.Wave.SQUARE, 0.0003, 30.0)
			await syn.noise(0.03, 0.1, 0.3, 4000.0, 800.0, 0.005, 10.0)
			await syn.lowpass(7000.0)
			await syn.crush(9, 1)
			await syn.normalize(0.45)
		"mag_slap":
			# Slapped home: a hard, flat clack with a little body (his palm on the base plate).
			syn = Synth.create(0.25, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.05, 1.0, 5000.0, 600.0, 0.0003, 22.0)
			await syn.tone(0.0, 0.1, 180.0, 90.0, 0.6, Synth.Wave.SINE, 0.0005, 14.0)
			await syn.tone(0.0, 0.05, 2600.0, 2500.0, 0.25, Synth.Wave.SQUARE, 0.0003, 30.0)
			await syn.echo(0.05, 0.15, 0.15)
			await syn.lowpass(6500.0)
			await syn.crush(8, 1)
			await syn.normalize(0.6)
		"thunk":
			# A row of the end screen's tally landing (after Doom's): a short, heavy knock.
			syn = Synth.create(0.18, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.12, 150.0, 70.0, 0.7, Synth.Wave.SQUARE, 0.001, 9.0)
			await syn.noise(0.0, 0.06, 0.45, 1800.0, 300.0, 0.0005, 14.0)
			await syn.lowpass(2400.0)
			await syn.crush(8, 1)
			await syn.normalize(0.55)
		"squelch":
			# A radio message: a burst of static and a blip.
			syn = Synth.create(0.3, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.14, 0.5, 5000.0, 1200.0, 0.002, 4.0)
			await syn.tone(0.14, 0.06, 1200.0, 1200.0, 0.35, Synth.Wave.SQUARE, 0.001, 2.0)
			await syn.crush(7, 2)
			await syn.normalize(0.5)
		"warn":
			# LIFTING OFF: three urgent beeps.
			syn = Synth.create(0.7, SFX_RATE, seed_value)
			for i in 3:
				await syn.tone(i * 0.18, 0.12, 880.0, 880.0, 0.5, Synth.Wave.SQUARE, 0.002, 1.0)
			await syn.lowpass(4000.0)
			await syn.echo(0.09, 0.2, 0.2)
			await syn.normalize(0.55)
		"jingle":
			# Extracted: a rising arpeggio and a held chord.
			syn = Synth.create(2.6, SFX_RATE, seed_value)
			var notes := [293.7, 349.2, 440.0, 587.3]
			for i in notes.size():
				await syn.tone(i * 0.14, 0.3, notes[i], notes[i], 0.3, Synth.Wave.SQUARE, 0.003, 3.0)
				await syn.tone(i * 0.14, 0.3, notes[i] / 2.0, notes[i] / 2.0, 0.2, Synth.Wave.TRIANGLE, 0.003, 3.0)
			for f in [293.7, 370.0, 440.0, 587.3]:
				await syn.tone(0.56, 1.8, f, f, 0.16, Synth.Wave.SAW, 0.02, 2.0)
			await syn.tone(0.56, 1.8, 73.4, 73.4, 0.4, Synth.Wave.TRIANGLE, 0.01, 2.0)
			await syn.lowpass(3500.0)
			await syn.echo(0.15, 0.3, 0.3)
			await syn.crush(9, 1)
			await syn.normalize(0.7)
		"gameover":
			# Game over: a low dissonant swell and a falling tone.
			syn = Synth.create(3.0, SFX_RATE, seed_value)
			for f in [73.4, 103.8, 146.8, 207.7]:
				await syn.tone(0.0, 2.8, f, f * 0.97, 0.18, Synth.Wave.SAW, 0.6, 1.5)
			await syn.tone(0.0, 1.6, 440.0, 110.0, 0.25, Synth.Wave.SQUARE, 0.01, 2.0)
			await syn.noise(0.0, 2.5, 0.2, 800.0, 0.0, 0.8, 1.5)
			await syn.lowpass(2200.0)
			await syn.echo(0.2, 0.4, 0.35)
			await syn.crush(8, 2)
			await syn.normalize(0.75)
		"bark":
			# The guard dog: two hard barks (a rough voice through dog-sized formants).
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			for t in [0.0, 0.22]:
				await syn.tone(t, 0.13, 520.0, 300.0, 0.7, Synth.Wave.SAW, 0.004, 3.0)
				await syn.noise(t, 0.1, 0.5, 4000.0, 600.0, 0.002, 5.0)
			var body := Synth.create(syn.length(), SFX_RATE)
			body.s = syn.s.duplicate()
			await syn.resonate(950.0, 4.0)
			await body.resonate(1700.0, 5.0)
			await syn.mix_in(body, 0.0, 0.6)
			await syn.echo(0.09, 0.25, 0.25)
			await syn.crush(8, 2)
			await syn.normalize(0.85)
		"yelp":
			# Shot: a high, falling yelp.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			await syn.tone(0.0, 0.28, 1100.0, 520.0, 0.7, Synth.Wave.SAW, 0.003, 2.5)
			await syn.tone(0.18, 0.2, 800.0, 380.0, 0.4, Synth.Wave.SAW, 0.003, 3.0)
			await syn.resonate(1400.0, 4.0)
			await syn.crush(8, 2)
			await syn.normalize(0.75)
		"bite":
			# Its jaws snapping shut on you, and the weight of it.
			syn = Synth.create(0.35, SFX_RATE, seed_value)
			await syn.noise(0.0, 0.05, 0.9, 0.0, 1500.0, 0.0005, 9.0)
			await syn.tone(0.0, 0.07, 320.0, 140.0, 0.6, Synth.Wave.SQUARE, 0.001, 6.0)
			await syn.tone(0.03, 0.2, 90.0, 45.0, 0.8, Synth.Wave.SINE, 0.002, 5.0)
			await syn.noise(0.05, 0.2, 0.4, 900.0, 0.0, 0.002, 6.0)
			await syn.crush(8, 2)
			await syn.normalize(0.85)
		"steam":
			# A vent hissing (loop).
			syn = Synth.create(2.2, SFX_RATE, seed_value)
			await syn.noise(0.0, 2.2, 0.5, 7000.0, 2500.0, 0.0001, 0.0)
			await syn.swell(3.0, 0.25)
			await syn.loopify(0.2)
			await syn.normalize(0.4)
			return await syn.to_stream(true)
		"crackle":
			# Live wires (loop): a mains buzz and random crackles.
			syn = Synth.create(2.2, SFX_RATE, seed_value)
			await syn.tone(0.0, 2.2, 120.0, 120.0, 0.08, Synth.Wave.SAW, 0.0001, 0.0)
			for i in 16:
				await syn.noise(syn.randf_range(0.0, 2.0), syn.randf_range(0.008, 0.03), syn.randf_range(0.4, 1.0), 0.0, 2000.0, 0.0005, 6.0)
			await syn.crush(7, 2)
			await syn.loopify(0.2)
			await syn.normalize(0.5)
			return await syn.to_stream(true)
		"rotor":
			# The chopper (loop): the blades' "whup-whup" (a slap of air 5.5 times a second, with a
			# swish between) over a low engine rumble. No tonal whine (playtest: it was a constant
			# buzz), and nothing footstep-like.
			syn = Synth.create(2.0, SFX_RATE, seed_value)
			await syn.noise(0.0, 2.0, 0.4, 110.0, 0.0, 0.0001, 0.0)  # engine rumble
			var swish := Synth.create(2.0, SFX_RATE, seed_value + 1)
			await swish.noise(0.0, 2.0, 0.3, 900.0, 200.0, 0.0001, 0.0)
			await swish.swell(11.0, 0.8)  # rising and falling with each blade
			await syn.mix_in(swish, 0.0, 1.0)
			for i in 11:
				var t := i / 5.5
				await syn.noise(t, 0.1, 0.8, 380.0, 60.0, 0.004, 6.0)  # the slap
				await syn.tone(t, 0.08, 62.0, 44.0, 0.35, Synth.Wave.SINE, 0.004, 5.0)
			await syn.loopify(0.05)
			await syn.crush(9, 1)
			await syn.normalize(0.75)
			return await syn.to_stream(true)
		_:
			push_warning("SoundBank: no sound called '%s'" % name)
			syn = Synth.create(0.05, SFX_RATE)
	return await syn.to_stream()


## A metal clang: inharmonic partials ringing down.
static func _clang(syn: Synth, at: float, amp: float) -> void:
	for f in [523.0, 1307.0, 2131.0, 3017.0]:
		await syn.tone(at, 0.8, f, f * 0.995, amp * 0.22, Synth.Wave.SINE, 0.0005, 6.0)
	await syn.noise(at, 0.05, amp * 0.6, 6000.0, 800.0, 0.0005, 8.0)


## Footsteps, a few variations per surface.
static func _footstep(surface: String, variant: int) -> AudioStreamWAV:
	var syn := Synth.create(0.18, SFX_RATE, hash("step_%s_%d" % [surface, variant]))
	var j := 1.0 + 0.06 * (variant - 1)
	match surface:
		"office":  # rubber soles on lino: a soft click
			await syn.noise(0.0, 0.04, 0.6, 5000.0, 1200.0, 0.0005, 9.0)
			await syn.tone(0.0, 0.05, 220.0 * j, 130.0 * j, 0.4, Synth.Wave.SINE, 0.001, 7.0)
		"tunnel":  # wet concrete: a slap with a little splash
			await syn.noise(0.0, 0.06, 0.7, 1600.0, 150.0, 0.0005, 7.0)
			await syn.noise(0.01, 0.07, 0.25, 6000.0, 2500.0, 0.003, 6.0)
			await syn.tone(0.0, 0.06, 140.0 * j, 80.0 * j, 0.4, Synth.Wave.SINE, 0.001, 7.0)
		"gravel":  # a crunch of little stones
			for i in 6:
				await syn.noise(i * 0.012 + syn.randf_range(0.0, 0.006), 0.02, syn.randf_range(0.3, 0.7), 3500.0, 600.0, 0.0005, 8.0)
		"stairs":  # metal-edged steps: a ringing tap
			await syn.noise(0.0, 0.03, 0.5, 4000.0, 800.0, 0.0005, 9.0)
			await syn.tone(0.0, 0.12, 880.0 * j, 870.0 * j, 0.25, Synth.Wave.SINE, 0.0005, 7.0)
			await syn.tone(0.0, 0.1, 1390.0 * j, 1380.0 * j, 0.15, Synth.Wave.SINE, 0.0005, 8.0)
		_:  # concrete
			await syn.noise(0.0, 0.05, 0.6, 2200.0, 200.0, 0.0005, 8.0)
			await syn.tone(0.0, 0.05, 160.0 * j, 90.0 * j, 0.4, Synth.Wave.SINE, 0.001, 7.0)
	await syn.crush(9, 1)
	await syn.normalize(0.5)
	return await syn.to_stream()


## A guard going down: a short "uh!" (a sawtooth voice through two vowel formants).
static func _grunt(variant: int) -> AudioStreamWAV:
	var syn := Synth.create(0.4, SFX_RATE, 77 + variant)
	var f0: float = [150.0, 132.0, 168.0][variant % 3]
	await syn.tone(0.0, 0.3, f0, f0 * 0.65, 0.6, Synth.Wave.SAW, 0.02, 2.5)
	await syn.noise(0.0, 0.25, 0.08, 3000.0, 500.0, 0.02, 3.0)  # breath
	var dry := Synth.create(syn.length(), SFX_RATE)
	dry.s = syn.s.duplicate()
	await syn.resonate(650.0, 5.0)
	await dry.resonate(1100.0, 6.0)
	await syn.mix_in(dry, 0.0, 0.7)
	await syn.lowpass(3500.0)
	await syn.crush(8, 2)
	await syn.normalize(0.7)
	return await syn.to_stream()


# --- Ambience loops -------------------------------------------------------------------

static func _ambience(name: String) -> AudioStreamWAV:
	var syn: Synth
	match name:
		"amb_office":
			# Air-con roar and the buzz of fluorescent tubes.
			syn = Synth.create(4.0, AMB_RATE, 11)
			await syn.noise(0.0, 4.0, 0.3, 380.0, 0.0, 0.0001, 0.0)
			await syn.tone(0.0, 4.0, 60.0, 60.0, 0.16, Synth.Wave.SINE, 0.0001, 0.0)
			await syn.tone(0.0, 4.0, 120.0, 120.0, 0.07, Synth.Wave.SAW, 0.0001, 0.0)
			await syn.loopify(0.4)
			await syn.normalize(0.35)
		"amb_tunnel":
			# A deep rumble, a low drone, and water dripping with long echoes.
			syn = Synth.create(6.0, AMB_RATE, 12)
			await syn.noise(0.0, 6.0, 0.7, 90.0, 0.0, 0.0001, 0.0)
			await syn.tone(0.0, 6.0, 38.0, 38.0, 0.12, Synth.Wave.SINE, 0.0001, 0.0)
			var drips := Synth.create(6.0, AMB_RATE, 13)
			for i in 5:
				var t := drips.randf_range(0.2, 5.0)
				await drips.tone(t, 0.06, 1700.0, 700.0, 0.3, Synth.Wave.SINE, 0.0005, 9.0)
			await drips.echo(0.23, 0.5, 0.6)
			await syn.mix_in(drips, 0.0, 1.0)
			await syn.loopify(0.5)
			await syn.normalize(0.45)
		"amb_roof":
			# Wind gusting over the roofs, the city rumbling below, a far-off siren.
			syn = Synth.create(6.0, AMB_RATE, 14)
			await syn.noise(0.0, 6.0, 0.45, 520.0, 60.0, 0.0001, 0.0)
			await syn.swell(2.0, 0.5)
			await syn.noise(0.0, 6.0, 0.3, 140.0, 0.0, 0.0001, 0.0)
			for i in 6:
				var f := 650.0 if i % 2 == 0 else 820.0
				await syn.tone(i * 1.0, 1.0, f, f, 0.012, Synth.Wave.SINE, 0.3, 0.0)
			await syn.loopify(0.5)
			await syn.normalize(0.4)
		_:  # amb_cctv
			# A security monitor: mains hum and faint static.
			syn = Synth.create(2.0, AMB_RATE, 15)
			await syn.tone(0.0, 2.0, 60.0, 60.0, 0.12, Synth.Wave.SINE, 0.0001, 0.0)
			await syn.tone(0.0, 2.0, 180.0, 180.0, 0.05, Synth.Wave.SQUARE, 0.0001, 0.0)
			await syn.noise(0.0, 2.0, 0.08, 0.0, 2500.0, 0.0001, 0.0)
			await syn.loopify(0.2)
			await syn.normalize(0.3)
	return await syn.to_stream(true)


# --- Music ----------------------------------------------------------------------------

## A note name ("A4", "G#5", "Bb3") as a frequency.
static func note(n: String) -> float:
	var names := {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
	var semis: int = names[n[0]]
	var i := 1
	if n[i] == "#":
		semis += 1
		i += 1
	elif n[i] == "b":
		semis -= 1
		i += 1
	var octave := int(n.substr(i))
	return 440.0 * pow(2.0, (semis + (octave - 4) * 12) / 12.0)


## The menu and opening-pan theme: an original military-espionage thriller cue (after "too nice"
## and then "too Halloween"): straight time, 120 bpm, 16 bars in E minor that build in four
## stages of 4 bars, then drop back to the ticking to start again:
##  1. a ticking clock (tick-tock eighths) over a soft low-strings pulse and a kick on the one;
##  2. the pulse goes to sixteenths, the kick doubles, a rimshot lands on 4;
##  3. a military snare cadence, the clock ticks in sixteenths, low brass hits each bar;
##  4. everything: the pulse doubled an octave up, syncopated brass power-chord stabs, timpani,
##     and a riser and snare roll over the last bar.
## Roots, a bar each: E E C D, ending E E C B into the loop.
static func _menu_music() -> AudioStreamWAV:
	var beat := 0.5
	var bar := beat * 4.0
	var bars := 16
	var total := bar * bars
	var six := beat / 4.0
	var semi := func(f: float, n: int) -> float: return f * pow(2.0, n / 12.0)
	var roots := ["E2", "E2", "C2", "D2", "E2", "E2", "C2", "D2", "E2", "E2", "C2", "D2", "E2", "E2", "C2", "B1"]
	# Its five parts, each a 32 s buffer made just before it's first drawn into (making one takes a
	# moment: all five at once would be the slowest piece of all the building that can't be split).
	# The clock: tick-tock eighths, sixteenths from stage 3, louder each stage.
	var clock := Synth.create(total, MUSIC_RATE, 82)
	for b in bars:
		var stage := b / 4
		var per := 16 if stage >= 2 else 8
		var amp := 0.1 + 0.035 * stage
		for i in per:
			var t: float = b * bar + i * bar / per
			var tick := i % 2 == 0
			await clock.tone(t, 0.014, 3400.0 if tick else 2500.0, 3000.0 if tick else 2200.0, amp * (1.0 if tick else 0.7), Synth.Wave.SQUARE, 0.0005, 7.0)
			await clock.noise(t, 0.01, amp * 0.5, 0.0, 5000.0, 0.0005, 6.0)
	await clock.lowpass(6000.0)
	# The low-strings pulse: a pedal on the root that kicks up to the octave and leans on the
	# half step and minor third (the spy-thriller ostinato). Eighths, then sixteenths.
	var shape := [0, 0, 12, 0, 1, 0, 12, 0, 0, 0, 12, 0, 3, 0, 2, 0]
	var pulse := Synth.create(total, MUSIC_RATE, 83)
	for b in bars:
		var stage := b / 4
		var root := note(roots[b])
		var amp: float = [0.16, 0.22, 0.26, 0.3][stage]
		for i in 16:
			if stage == 0 and i % 2 == 1:
				continue
			var f: float = semi.call(root, shape[i])
			var t: float = b * bar + i * six
			var accent := 1.3 if i % 4 == 0 else 1.0
			await pulse.tone(t, six * 0.9, f, f, amp * accent, Synth.Wave.SAW, 0.003, 4.0)
			await pulse.tone(t, six * 0.9, f * 1.006, f * 1.006, amp * 0.6 * accent, Synth.Wave.SAW, 0.003, 4.0)
			if stage == 3:  # doubled an octave up
				await pulse.tone(t, six * 0.8, f * 2.0, f * 2.0, amp * 0.45, Synth.Wave.SAW, 0.003, 4.5)
	await pulse.lowpass(1400.0)
	await pulse.drive(1.5)
	# Drums: the kick builds, a rimshot from stage 2, a military snare cadence from stage 3, timpani in stage 4.
	var cadence := [0, 3, 4, 6, 8, 10, 11, 12, 14, 15]
	var drums := Synth.create(total, MUSIC_RATE, 84)
	for b in bars:
		var stage := b / 4
		var t0: float = b * bar
		var kicks: Array = [[0.0], [0.0, 2.0], [0.0, 1.5, 2.0], [0.0, 1.5, 2.0, 3.5]][stage]
		for k in kicks:
			await drums.tone(t0 + k * beat, 0.18, 120.0, 45.0, 0.7, Synth.Wave.SINE, 0.002, 6.0)
		if stage == 1:
			await drums.noise(t0 + 3.0 * beat, 0.05, 0.3, 9000.0, 2500.0, 0.001, 10.0)
			await drums.tone(t0 + 3.0 * beat, 0.03, 900.0, 800.0, 0.15, Synth.Wave.SQUARE, 0.001, 8.0)
		if stage >= 2:
			var roll := b == bars - 1
			for i in 16:
				if roll and i >= 8:
					break
				if not cadence.has(i):
					continue
				var accent := 1.0 if i == 4 or i == 12 else 0.45
				await drums.noise(t0 + i * six, 0.12, 0.34 * accent, 7500.0, 1800.0, 0.001, 8.0)
				await drums.tone(t0 + i * six, 0.06, 220.0, 170.0, 0.18 * accent, Synth.Wave.TRIANGLE, 0.001, 6.0)
			if roll:  # a crescendo roll over the last two beats
				for s in 24:
					await drums.noise(t0 + 2.0 * beat + s * beat / 12.0, 0.05, 0.08 + 0.014 * s, 7500.0, 1800.0, 0.001, 9.0)
		if stage == 3:
			for k in [0.0, 2.5]:
				var f := note(roots[b]) * 2.0
				await drums.tone(t0 + k * beat, 0.6, f * 1.05, f, 0.5, Synth.Wave.SINE, 0.002, 4.0)
				await drums.noise(t0 + k * beat, 0.08, 0.15, 900.0, 0.0, 0.001, 8.0)
	await drums.lowpass(9000.0)
	# Brass: power chords (root, fifth, octave), one low hit a bar in stage 3, syncopated stabs in stage 4.
	var brass := Synth.create(total, MUSIC_RATE, 85)
	for b in range(8, bars):
		var stage := b / 4
		var root := note(roots[b]) * 2.0
		var hits: Array = [[0.0, 1.2]] if stage == 2 else [[0.0, 0.35], [1.5, 0.25], [2.5, 0.35], [3.5, 0.2]]
		if b == bars - 1:
			hits = [[0.0, 0.35], [1.5, 0.25]]
		for h in hits:
			var t: float = b * bar + h[0] * beat
			var d: float = h[1]
			for f in [root, root * 1.4983, root * 2.0]:
				await brass.tone(t, d, f * 0.98, f, 0.2, Synth.Wave.SAW, 0.02, 2.0)
				await brass.tone(t, d, f * 1.005, f * 1.005, 0.14, Synth.Wave.SAW, 0.02, 2.0)
	# The riser over the last bar: a climbing saw and swelling hiss, into the drop.
	var rise := (bars - 1) * bar
	await brass.tone(rise, bar, note("B2"), note("B4"), 0.18, Synth.Wave.SAW, bar * 0.9, 0.0)
	for s in 16:
		await brass.noise(rise + s * six, six, 0.02 + 0.012 * s, 2000.0 + 400.0 * s, 1000.0, 0.002, 0.0)
	await brass.lowpass(1700.0)
	await brass.drive(1.8)
	var mix := Synth.create(total, MUSIC_RATE, 81)
	for part in [clock, pulse, drums, brass]:
		await mix.mix_in(part, 0.0, 1.0)
	# The mixdown: a small hard room, a touch of saturation and PS1 crush.
	await mix.echo(0.09, 0.2, 0.15)
	await mix.normalize(0.9)
	await mix.drive(1.3)
	await mix.crush(10, 1)
	await mix.normalize(0.6)
	return await mix.to_stream(true)


## CAUTION (alert 2): a low pulsing bass, a held dark pad and a ticking clock. 110 bpm, 4 bars.
static func _tension() -> AudioStreamWAV:
	var eighth := 60.0 / 110.0 / 2.0
	var total := eighth * 32.0
	var bass := Synth.create(total, MUSIC_RATE, 21)
	var roots := [73.42, 73.42, 69.30, 65.41]  # D, D, C#, C
	for bar in 4:
		for i in 8:
			var f: float = roots[bar] * (2.0 if i == 7 else 1.0)
			await bass.tone((bar * 8 + i) * eighth, eighth * 0.9, f, f, 0.6 if i % 4 == 0 else 0.4, Synth.Wave.TRIANGLE, 0.003, 3.0)
	var pad := Synth.create(total, MUSIC_RATE, 22)
	for f in [146.8, 146.8 * 1.006, 220.0, 220.0 * 1.006]:  # a detuned pair on each note
		await pad.tone(0.0, total, f, f, 0.11, Synth.Wave.SAW, 1.0, 0.0)
	await pad.lowpass(500.0)
	await pad.swell(2.0, 0.3)
	var tick := Synth.create(total, MUSIC_RATE, 23)
	for i in 16:
		await tick.noise(i * eighth * 2.0, 0.025, 0.25 if i % 4 == 0 else 0.15, 0.0, 5000.0, 0.0005, 8.0)
	await tick.tone(0.0, 0.5, 60.0, 40.0, 0.5, Synth.Wave.SINE, 0.002, 4.0)  # a boom on the downbeat
	await bass.mix_in(pad, 0.0, 1.0)
	await bass.mix_in(tick, 0.0, 1.0)
	await bass.crush(10, 1)
	await bass.normalize(0.55)
	return await bass.to_stream(true)


## ALERT (alert 3): driving MGS-style alert music. 150 bpm, 4 bars: a 16th-note bass ostinato, a
## kick and snare, off-beat brass stabs and a high lead line.
static func _alert_music() -> AudioStreamWAV:
	var six := 60.0 / 150.0 / 4.0
	var total := six * 64.0
	var roots := [73.42, 73.42, 58.27, 65.41]  # D, D, Bb, C
	var pattern := [1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 2, 1, 1.189, 1, 1.335, 1]  # root, octave, minor 3rd, 4th
	var bass := Synth.create(total, MUSIC_RATE, 31)
	for bar in 4:
		for i in 16:
			var f: float = roots[bar] * pattern[i]
			await bass.tone((bar * 16 + i) * six, six * 0.85, f, f, 0.5, Synth.Wave.SAW, 0.002, 3.5)
	await bass.lowpass(900.0)
	var drums := Synth.create(total, MUSIC_RATE, 32)
	for bar in 4:
		var b := bar * 16
		for k in [0, 6, 8, 10]:
			await drums.tone((b + k) * six, 0.14, 150.0, 45.0, 0.8, Synth.Wave.SINE, 0.001, 6.0)
		for k in [4, 12]:
			await drums.noise((b + k) * six, 0.13, 0.55, 6000.0, 1200.0, 0.0005, 7.0)
			await drums.tone((b + k) * six, 0.08, 220.0, 170.0, 0.35, Synth.Wave.TRIANGLE, 0.001, 6.0)
		for k in range(0, 16, 2):
			await drums.noise((b + k) * six, 0.025, 0.18, 0.0, 6000.0, 0.0005, 9.0)
	var stabs := Synth.create(total, MUSIC_RATE, 33)
	for bar in 4:
		for k in [2, 7, 11]:
			for f in [293.7, 349.2, 440.0]:
				var ff: float = f * roots[bar] / 73.42
				await stabs.tone((bar * 16 + k) * six, 0.14, ff, ff, 0.13, Synth.Wave.SQUARE, 0.002, 5.0)
	var lead := Synth.create(total, MUSIC_RATE, 34)
	var line := [880.0, 830.6, 784.0, 698.5, 659.3, 698.5, 784.0, 880.0]
	for i in line.size():
		await lead.tone(32 * six + i * 4 * six, 4 * six * 0.9, line[i], line[i], 0.18, Synth.Wave.PULSE, 0.004, 1.5)
	await lead.lowpass(3500.0)
	await lead.echo(six * 3.0, 0.3, 0.3)
	await bass.mix_in(drums, 0.0, 1.0)
	await bass.mix_in(stabs, 0.0, 1.0)
	await bass.mix_in(lead, 0.0, 1.0)
	await bass.crush(9, 1)
	await bass.normalize(0.6)
	return await bass.to_stream(true)
