class_name SoundBank
extends RefCounted
## Every sound in the game, synthesised in code (no audio files), PS1/N64-style: low sample rates,
## a little bit-crush, echo baked in. Inspired by MGS1 (quiet humming ambience, the "!" sting, the
## wall-press thump, alert music) and GoldenEye (punchy, dry gunshots).
##
## Sounds are cached by name. Long ones (ambience loops, music) are built in small steps, so the
## AudioDirector can spread the work over frames; get() builds anything missing at once.

const SFX_RATE := 22050
const AMB_RATE := 11025
const MUSIC_RATE := 16000
## Footstep surfaces, each with a few variations ("step_<surface>_<n>").
const SURFACES := ["office", "tunnel", "gravel", "stairs", "concrete"]
const STEP_VARIANTS := 3
const LOOPS := ["music_menu", "amb_office", "amb_tunnel", "amb_roof", "amb_cctv", "steam", "crackle", "rotor",
		"music_tension", "music_alert"]

static var _cache: Dictionary = {}


static func has(name: String) -> bool:
	return _cache.has(name)


## The sound, built now if it isn't yet.
static func get_stream(name: String) -> AudioStreamWAV:
	if not _cache.has(name):
		for step in steps(name):
			step.call()
	return _cache.get(name)


## Every sound's name, roughly in the order they're first needed.
static func all_names() -> Array[String]:
	var names: Array[String] = ["music_menu", "codec", "tick", "amb_office", "door_wood", "gun", "spotted", "hit", "fall",
			"gun_trooper", "cover", "jump", "land", "slide", "stumble", "player_hit", "zap", "beep",
			"alarm_break", "alert_up", "klaxon", "alert_down", "squelch", "door_steel", "door_bars",
			"music_tension", "music_alert", "amb_tunnel", "amb_roof", "amb_cctv", "steam", "crackle",
			"rotor", "warn", "jingle", "gameover", "bark", "yelp", "bite"]
	for i in 3:
		names.append("grunt_%d" % i)
	for surface in SURFACES:
		for i in STEP_VARIANTS:
			names.append("step_%s_%d" % [surface, i])
	return names


## The work to build a sound, as small steps (each a fraction of a frame's worth, at most).
static func steps(name: String) -> Array[Callable]:
	match name:
		"amb_office", "amb_tunnel", "amb_roof", "amb_cctv":
			return _ambience_steps(name)
		"music_tension":
			return _tension_steps()
		"music_alert":
			return _alert_music_steps()
		"music_menu":
			return _menu_music_steps()
	return [func() -> void: _cache[name] = _make(name)]


# --- One-shot sounds ------------------------------------------------------------------

static func _make(name: String) -> AudioStreamWAV:
	var seed_value := absi(hash(name))
	if name.begins_with("step_"):
		var parts := name.split("_")
		return _footstep(parts[1], int(parts[2]))
	if name.begins_with("grunt_"):
		return _grunt(int(name.get_slice("_", 1)))
	var syn: Synth
	match name:
		"gun":
			# Your rifle (GoldenEye-style): a hard crack, a chesty thump, a short room echo.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			syn.noise(0.0, 0.2, 0.9, 5200.0, 0.0, 0.0005, 16.0)
			syn.tone(0.0, 0.16, 150.0, 45.0, 0.9, Synth.Wave.SINE, 0.001, 6.0)
			syn.tone(0.0, 0.025, 2200.0, 600.0, 0.35, Synth.Wave.SQUARE, 0.0005, 3.0)
			syn.echo(0.07, 0.25, 0.3)
			syn.crush(8, 2)
			syn.normalize(0.95)
		"gun_trooper":
			# Theirs: duller and further off, with more echo.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			syn.noise(0.0, 0.18, 0.8, 2600.0, 0.0, 0.0005, 14.0)
			syn.tone(0.0, 0.14, 120.0, 40.0, 0.7, Synth.Wave.SINE, 0.001, 6.0)
			syn.echo(0.11, 0.35, 0.4)
			syn.crush(8, 2)
			syn.normalize(0.8)
		"hit":
			# A bullet striking a body: a wet slap and a dull thud.
			syn = Synth.create(0.2, SFX_RATE, seed_value)
			syn.noise(0.0, 0.09, 0.8, 1400.0, 120.0, 0.0005, 9.0)
			syn.tone(0.0, 0.11, 190.0, 60.0, 0.7, Synth.Wave.SINE, 0.001, 7.0)
			syn.crush(9, 1)
			syn.normalize(0.85)
		"fall":
			# A body hitting the floor.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			syn.tone(0.0, 0.28, 95.0, 38.0, 0.9, Synth.Wave.SINE, 0.002, 5.0)
			syn.noise(0.0, 0.3, 0.6, 450.0, 0.0, 0.002, 7.0)
			syn.noise(0.12, 0.15, 0.3, 600.0, 0.0, 0.002, 9.0)  # the rifle clattering
			syn.crush(10, 1)
			syn.normalize(0.8)
		"spotted":
			# MGS's "!": a sharp, dissonant high stab with a metallic shimmer and echo.
			syn = Synth.create(0.9, SFX_RATE, seed_value)
			syn.tone(0.0, 0.5, 1568.0, 1568.0, 0.35, Synth.Wave.SQUARE, 0.0005, 5.0)
			syn.tone(0.0, 0.5, 1661.0, 1661.0, 0.3, Synth.Wave.SQUARE, 0.0005, 5.0)
			syn.tone(0.0, 0.35, 784.0, 784.0, 0.35, Synth.Wave.SAW, 0.0005, 6.0)
			syn.noise(0.0, 0.15, 0.4, 0.0, 3000.0, 0.0005, 10.0)
			syn.lowpass(7000.0)
			syn.echo(0.09, 0.4, 0.45)
			syn.crush(9, 1)
			syn.normalize(0.75)
		"alert_up":
			# Alert raised: a low orchestral hit (a tritone chord and a timpani boom) with a crash.
			syn = Synth.create(1.4, SFX_RATE, seed_value)
			for f in [130.8, 185.0, 261.6, 370.0]:
				syn.tone(0.0, 0.9, f, f * 0.98, 0.22, Synth.Wave.SAW, 0.004, 3.5)
			syn.tone(0.0, 0.6, 70.0, 50.0, 0.8, Synth.Wave.SINE, 0.002, 4.0)
			syn.noise(0.0, 0.7, 0.35, 6000.0, 1500.0, 0.001, 4.0)
			syn.lowpass(3500.0)
			syn.echo(0.13, 0.35, 0.35)
			syn.crush(9, 1)
			syn.normalize(0.85)
		"klaxon":
			# Full alert: a two-tone alarm.
			syn = Synth.create(1.6, SFX_RATE, seed_value)
			for i in 6:
				var f := 660.0 if i % 2 == 0 else 880.0
				syn.tone(i * 0.25, 0.24, f, f, 0.5, Synth.Wave.SQUARE, 0.005, 0.0)
			syn.lowpass(2800.0)
			syn.echo(0.16, 0.3, 0.3)
			syn.crush(8, 2)
			syn.normalize(0.6)
		"alert_down":
			# Alert dropped: a falling codec-style blip.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			for i in 3:
				var f: float = [1320.0, 990.0, 660.0][i]
				syn.tone(i * 0.09, 0.08, f, f, 0.45, Synth.Wave.SQUARE, 0.002, 2.0)
			syn.lowpass(5000.0)
			syn.echo(0.1, 0.2, 0.2)
			syn.normalize(0.55)
		"door_wood":
			# An office door shouldered open: a crash, a thud and a rattle.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			syn.noise(0.0, 0.25, 0.8, 2200.0, 80.0, 0.0005, 8.0)
			syn.tone(0.0, 0.22, 120.0, 50.0, 0.8, Synth.Wave.SINE, 0.001, 5.0)
			for i in 3:
				syn.noise(0.08 + i * 0.06, 0.04, 0.3, 1800.0, 400.0, 0.0005, 8.0)
			syn.echo(0.08, 0.25, 0.3)
			syn.crush(9, 1)
			syn.normalize(0.85)
		"door_steel":
			# A steel door: a hard clang that rings.
			syn = Synth.create(1.0, SFX_RATE, seed_value)
			_clang(syn, 0.0, 1.0)
			syn.tone(0.0, 0.2, 110.0, 45.0, 0.7, Synth.Wave.SINE, 0.001, 5.0)
			syn.echo(0.1, 0.3, 0.3)
			syn.crush(9, 1)
			syn.normalize(0.85)
		"door_bars":
			# Barred gates: clangs and a rattle of bars.
			syn = Synth.create(1.2, SFX_RATE, seed_value)
			_clang(syn, 0.0, 1.0)
			for i in 5:
				_clang(syn, 0.06 + i * 0.07, 0.35 / (i + 1))
			syn.noise(0.0, 0.35, 0.3, 4000.0, 1500.0, 0.001, 6.0)
			syn.echo(0.12, 0.35, 0.35)
			syn.crush(9, 1)
			syn.normalize(0.85)
		"jump":
			# A quick whoosh of clothing and kit.
			syn = Synth.create(0.25, SFX_RATE, seed_value)
			syn.noise(0.0, 0.22, 0.5, 2500.0, 500.0, 0.05, 3.0)
			syn.normalize(0.4)
		"land":
			syn = Synth.create(0.2, SFX_RATE, seed_value)
			syn.noise(0.0, 0.08, 0.6, 900.0, 0.0, 0.0005, 8.0)
			syn.tone(0.0, 0.1, 110.0, 60.0, 0.6, Synth.Wave.SINE, 0.001, 6.0)
			syn.normalize(0.55)
		"slide":
			# Sliding on the floor: a gritty scrape.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			syn.noise(0.0, 0.45, 0.6, 1200.0, 200.0, 0.02, 2.5)
			syn.crush(7, 2)
			syn.normalize(0.45)
		"cover":
			# MGS's wall press: a soft back-to-the-wall thump and a rustle.
			syn = Synth.create(0.3, SFX_RATE, seed_value)
			syn.tone(0.0, 0.12, 85.0, 55.0, 0.9, Synth.Wave.SINE, 0.001, 5.0)
			syn.noise(0.0, 0.1, 0.5, 700.0, 0.0, 0.0005, 7.0)
			syn.noise(0.03, 0.12, 0.25, 5000.0, 1500.0, 0.01, 4.0)
			syn.crush(10, 1)
			syn.normalize(0.7)
		"stumble":
			# Running into something: a crunch and a clatter.
			syn = Synth.create(0.5, SFX_RATE, seed_value)
			syn.noise(0.0, 0.2, 0.8, 1800.0, 60.0, 0.0005, 7.0)
			syn.tone(0.0, 0.18, 100.0, 45.0, 0.8, Synth.Wave.SINE, 0.001, 5.0)
			_clang(syn, 0.05, 0.25)
			syn.crush(9, 1)
			syn.normalize(0.8)
		"player_hit":
			# You're hit: a heavy crunchy thump.
			syn = Synth.create(0.4, SFX_RATE, seed_value)
			syn.tone(0.0, 0.22, 75.0, 40.0, 0.9, Synth.Wave.SINE, 0.001, 4.0)
			syn.noise(0.0, 0.16, 0.7, 1500.0, 0.0, 0.0005, 8.0)
			syn.tone(0.0, 0.12, 220.0, 110.0, 0.35, Synth.Wave.SQUARE, 0.001, 5.0)
			syn.crush(6, 2)
			syn.normalize(0.85)
		"zap":
			# A tripwire or live wire: an electric buzz and crackle.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			syn.tone(0.0, 0.5, 120.0, 100.0, 0.4, Synth.Wave.SAW, 0.002, 3.0)
			for i in 10:
				syn.noise(syn.randf_range(0.0, 0.45), 0.02, 0.6, 0.0, 2000.0, 0.0005, 6.0)
			syn.crush(7, 2)
			syn.normalize(0.7)
		"beep":
			# The alarm box, while you can shoot it.
			syn = Synth.create(0.08, SFX_RATE, seed_value)
			syn.tone(0.0, 0.07, 2093.0, 2093.0, 0.5, Synth.Wave.SQUARE, 0.001, 2.0)
			syn.lowpass(6000.0)
			syn.normalize(0.4)
		"alarm_break":
			# The alarm box destroyed: an electrical crunch dying away.
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			syn.noise(0.0, 0.2, 0.8, 4000.0, 300.0, 0.0005, 7.0)
			syn.tone(0.0, 0.4, 800.0, 80.0, 0.4, Synth.Wave.SQUARE, 0.001, 3.0)
			for i in 6:
				syn.noise(syn.randf_range(0.05, 0.5), 0.015, 0.5, 0.0, 2500.0, 0.0005, 6.0)
			syn.crush(8, 1)
			syn.normalize(0.8)
		"codec":
			# Tap to start: MGS codec's "pi-pi".
			syn = Synth.create(0.4, SFX_RATE, seed_value)
			syn.tone(0.0, 0.07, 1046.0, 1046.0, 0.4, Synth.Wave.SQUARE, 0.001, 1.0)
			syn.tone(0.0, 0.07, 2093.0, 2093.0, 0.15, Synth.Wave.SINE, 0.001, 1.0)
			syn.tone(0.12, 0.07, 1318.0, 1318.0, 0.4, Synth.Wave.SQUARE, 0.001, 1.0)
			syn.tone(0.12, 0.07, 2637.0, 2637.0, 0.15, Synth.Wave.SINE, 0.001, 1.0)
			syn.lowpass(6000.0)
			syn.echo(0.09, 0.2, 0.2)
			syn.normalize(0.5)
		"tick":
			# One letter of a typed caption.
			syn = Synth.create(0.03, SFX_RATE, seed_value)
			syn.tone(0.0, 0.015, 3000.0, 2500.0, 0.4, Synth.Wave.SQUARE, 0.0005, 6.0)
			syn.noise(0.0, 0.01, 0.2, 0.0, 3000.0, 0.0005, 8.0)
			syn.normalize(0.3)
		"squelch":
			# A radio message: a burst of static and a blip.
			syn = Synth.create(0.3, SFX_RATE, seed_value)
			syn.noise(0.0, 0.14, 0.5, 5000.0, 1200.0, 0.002, 4.0)
			syn.tone(0.14, 0.06, 1200.0, 1200.0, 0.35, Synth.Wave.SQUARE, 0.001, 2.0)
			syn.crush(7, 2)
			syn.normalize(0.5)
		"warn":
			# LIFTING OFF: three urgent beeps.
			syn = Synth.create(0.7, SFX_RATE, seed_value)
			for i in 3:
				syn.tone(i * 0.18, 0.12, 880.0, 880.0, 0.5, Synth.Wave.SQUARE, 0.002, 1.0)
			syn.lowpass(4000.0)
			syn.echo(0.09, 0.2, 0.2)
			syn.normalize(0.55)
		"jingle":
			# Extracted: a rising arpeggio and a held chord.
			syn = Synth.create(2.6, SFX_RATE, seed_value)
			var notes := [293.7, 349.2, 440.0, 587.3]
			for i in notes.size():
				syn.tone(i * 0.14, 0.3, notes[i], notes[i], 0.3, Synth.Wave.SQUARE, 0.003, 3.0)
				syn.tone(i * 0.14, 0.3, notes[i] / 2.0, notes[i] / 2.0, 0.2, Synth.Wave.TRIANGLE, 0.003, 3.0)
			for f in [293.7, 370.0, 440.0, 587.3]:
				syn.tone(0.56, 1.8, f, f, 0.16, Synth.Wave.SAW, 0.02, 2.0)
			syn.tone(0.56, 1.8, 73.4, 73.4, 0.4, Synth.Wave.TRIANGLE, 0.01, 2.0)
			syn.lowpass(3500.0)
			syn.echo(0.15, 0.3, 0.3)
			syn.crush(9, 1)
			syn.normalize(0.7)
		"gameover":
			# Game over: a low dissonant swell and a falling tone.
			syn = Synth.create(3.0, SFX_RATE, seed_value)
			for f in [73.4, 103.8, 146.8, 207.7]:
				syn.tone(0.0, 2.8, f, f * 0.97, 0.18, Synth.Wave.SAW, 0.6, 1.5)
			syn.tone(0.0, 1.6, 440.0, 110.0, 0.25, Synth.Wave.SQUARE, 0.01, 2.0)
			syn.noise(0.0, 2.5, 0.2, 800.0, 0.0, 0.8, 1.5)
			syn.lowpass(2200.0)
			syn.echo(0.2, 0.4, 0.35)
			syn.crush(8, 2)
			syn.normalize(0.75)
		"bark":
			# The guard dog: two hard barks (a rough voice through dog-sized formants).
			syn = Synth.create(0.6, SFX_RATE, seed_value)
			for t in [0.0, 0.22]:
				syn.tone(t, 0.13, 520.0, 300.0, 0.7, Synth.Wave.SAW, 0.004, 3.0)
				syn.noise(t, 0.1, 0.5, 4000.0, 600.0, 0.002, 5.0)
			var body := Synth.create(syn.length(), SFX_RATE)
			body.s = syn.s.duplicate()
			syn.resonate(950.0, 4.0)
			body.resonate(1700.0, 5.0)
			syn.mix_in(body, 0.0, 0.6)
			syn.echo(0.09, 0.25, 0.25)
			syn.crush(8, 2)
			syn.normalize(0.85)
		"yelp":
			# Shot: a high, falling yelp.
			syn = Synth.create(0.45, SFX_RATE, seed_value)
			syn.tone(0.0, 0.28, 1100.0, 520.0, 0.7, Synth.Wave.SAW, 0.003, 2.5)
			syn.tone(0.18, 0.2, 800.0, 380.0, 0.4, Synth.Wave.SAW, 0.003, 3.0)
			syn.resonate(1400.0, 4.0)
			syn.crush(8, 2)
			syn.normalize(0.75)
		"bite":
			# Its jaws snapping shut on you, and the weight of it.
			syn = Synth.create(0.35, SFX_RATE, seed_value)
			syn.noise(0.0, 0.05, 0.9, 0.0, 1500.0, 0.0005, 9.0)
			syn.tone(0.0, 0.07, 320.0, 140.0, 0.6, Synth.Wave.SQUARE, 0.001, 6.0)
			syn.tone(0.03, 0.2, 90.0, 45.0, 0.8, Synth.Wave.SINE, 0.002, 5.0)
			syn.noise(0.05, 0.2, 0.4, 900.0, 0.0, 0.002, 6.0)
			syn.crush(8, 2)
			syn.normalize(0.85)
		"steam":
			# A vent hissing (loop).
			syn = Synth.create(2.2, SFX_RATE, seed_value)
			syn.noise(0.0, 2.2, 0.5, 7000.0, 2500.0, 0.0001, 0.0)
			syn.swell(3.0, 0.25)
			syn.loopify(0.2)
			syn.normalize(0.4)
			return syn.to_stream(true)
		"crackle":
			# Live wires (loop): a mains buzz and random crackles.
			syn = Synth.create(2.2, SFX_RATE, seed_value)
			syn.tone(0.0, 2.2, 120.0, 120.0, 0.08, Synth.Wave.SAW, 0.0001, 0.0)
			for i in 16:
				syn.noise(syn.randf_range(0.0, 2.0), syn.randf_range(0.008, 0.03), syn.randf_range(0.4, 1.0), 0.0, 2000.0, 0.0005, 6.0)
			syn.crush(7, 2)
			syn.loopify(0.2)
			syn.normalize(0.5)
			return syn.to_stream(true)
		"rotor":
			# The chopper (loop): the blades' "whup-whup" (a slap of air 5.5 times a second, with a
			# swish between) over a low engine rumble. No tonal whine (playtest: it was a constant
			# buzz), and nothing footstep-like.
			syn = Synth.create(2.0, SFX_RATE, seed_value)
			syn.noise(0.0, 2.0, 0.4, 110.0, 0.0, 0.0001, 0.0)  # engine rumble
			var swish := Synth.create(2.0, SFX_RATE, seed_value + 1)
			swish.noise(0.0, 2.0, 0.3, 900.0, 200.0, 0.0001, 0.0)
			swish.swell(11.0, 0.8)  # rising and falling with each blade
			syn.mix_in(swish, 0.0, 1.0)
			for i in 11:
				var t := i / 5.5
				syn.noise(t, 0.1, 0.8, 380.0, 60.0, 0.004, 6.0)  # the slap
				syn.tone(t, 0.08, 62.0, 44.0, 0.35, Synth.Wave.SINE, 0.004, 5.0)
			syn.loopify(0.05)
			syn.crush(9, 1)
			syn.normalize(0.75)
			return syn.to_stream(true)
		_:
			push_warning("SoundBank: no sound called '%s'" % name)
			syn = Synth.create(0.05, SFX_RATE)
	return syn.to_stream()


## A metal clang: inharmonic partials ringing down.
static func _clang(syn: Synth, at: float, amp: float) -> void:
	for f in [523.0, 1307.0, 2131.0, 3017.0]:
		syn.tone(at, 0.8, f, f * 0.995, amp * 0.22, Synth.Wave.SINE, 0.0005, 6.0)
	syn.noise(at, 0.05, amp * 0.6, 6000.0, 800.0, 0.0005, 8.0)


## Footsteps, a few variations per surface.
static func _footstep(surface: String, variant: int) -> AudioStreamWAV:
	var syn := Synth.create(0.18, SFX_RATE, hash("step_%s_%d" % [surface, variant]))
	var j := 1.0 + 0.06 * (variant - 1)
	match surface:
		"office":  # rubber soles on lino: a soft click
			syn.noise(0.0, 0.04, 0.6, 5000.0, 1200.0, 0.0005, 9.0)
			syn.tone(0.0, 0.05, 220.0 * j, 130.0 * j, 0.4, Synth.Wave.SINE, 0.001, 7.0)
		"tunnel":  # wet concrete: a slap with a little splash
			syn.noise(0.0, 0.06, 0.7, 1600.0, 150.0, 0.0005, 7.0)
			syn.noise(0.01, 0.07, 0.25, 6000.0, 2500.0, 0.003, 6.0)
			syn.tone(0.0, 0.06, 140.0 * j, 80.0 * j, 0.4, Synth.Wave.SINE, 0.001, 7.0)
		"gravel":  # a crunch of little stones
			for i in 6:
				syn.noise(i * 0.012 + syn.randf_range(0.0, 0.006), 0.02, syn.randf_range(0.3, 0.7), 3500.0, 600.0, 0.0005, 8.0)
		"stairs":  # metal-edged steps: a ringing tap
			syn.noise(0.0, 0.03, 0.5, 4000.0, 800.0, 0.0005, 9.0)
			syn.tone(0.0, 0.12, 880.0 * j, 870.0 * j, 0.25, Synth.Wave.SINE, 0.0005, 7.0)
			syn.tone(0.0, 0.1, 1390.0 * j, 1380.0 * j, 0.15, Synth.Wave.SINE, 0.0005, 8.0)
		_:  # concrete
			syn.noise(0.0, 0.05, 0.6, 2200.0, 200.0, 0.0005, 8.0)
			syn.tone(0.0, 0.05, 160.0 * j, 90.0 * j, 0.4, Synth.Wave.SINE, 0.001, 7.0)
	syn.crush(9, 1)
	syn.normalize(0.5)
	return syn.to_stream()


## A guard going down: a short "uh!" (a sawtooth voice through two vowel formants).
static func _grunt(variant: int) -> AudioStreamWAV:
	var syn := Synth.create(0.4, SFX_RATE, 77 + variant)
	var f0: float = [150.0, 132.0, 168.0][variant % 3]
	syn.tone(0.0, 0.3, f0, f0 * 0.65, 0.6, Synth.Wave.SAW, 0.02, 2.5)
	syn.noise(0.0, 0.25, 0.08, 3000.0, 500.0, 0.02, 3.0)  # breath
	var dry := Synth.create(syn.length(), SFX_RATE)
	dry.s = syn.s.duplicate()
	syn.resonate(650.0, 5.0)
	dry.resonate(1100.0, 6.0)
	syn.mix_in(dry, 0.0, 0.7)
	syn.lowpass(3500.0)
	syn.crush(8, 2)
	syn.normalize(0.7)
	return syn.to_stream()


# --- Ambience loops (built in steps) --------------------------------------------------

static func _ambience_steps(name: String) -> Array[Callable]:
	var box := {}
	var out: Array[Callable] = []
	match name:
		"amb_office":
			# Air-con roar and the buzz of fluorescent tubes.
			out.append(func() -> void:
				box.syn = Synth.create(4.0, AMB_RATE, 11)
				box.syn.noise(0.0, 4.0, 0.3, 380.0, 0.0, 0.0001, 0.0))
			out.append(func() -> void:
				box.syn.tone(0.0, 4.0, 60.0, 60.0, 0.16, Synth.Wave.SINE, 0.0001, 0.0)
				box.syn.tone(0.0, 4.0, 120.0, 120.0, 0.07, Synth.Wave.SAW, 0.0001, 0.0))
			out.append(func() -> void:
				box.syn.loopify(0.4)
				box.syn.normalize(0.35))
		"amb_tunnel":
			# A deep rumble, a low drone, and water dripping with long echoes.
			out.append(func() -> void:
				box.syn = Synth.create(6.0, AMB_RATE, 12)
				box.syn.noise(0.0, 6.0, 0.7, 90.0, 0.0, 0.0001, 0.0))
			out.append(func() -> void:
				box.syn.tone(0.0, 6.0, 38.0, 38.0, 0.12, Synth.Wave.SINE, 0.0001, 0.0)
				var drips := Synth.create(6.0, AMB_RATE, 13)
				for i in 5:
					var t := drips.randf_range(0.2, 5.0)
					drips.tone(t, 0.06, 1700.0, 700.0, 0.3, Synth.Wave.SINE, 0.0005, 9.0)
				box.drips = drips)
			out.append(func() -> void:
				box.drips.echo(0.23, 0.5, 0.6))
			out.append(func() -> void:
				box.syn.mix_in(box.drips, 0.0, 1.0)
				box.syn.loopify(0.5)
				box.syn.normalize(0.45))
		"amb_roof":
			# Wind gusting over the roofs, the city rumbling below, a far-off siren.
			out.append(func() -> void:
				box.syn = Synth.create(6.0, AMB_RATE, 14)
				box.syn.noise(0.0, 6.0, 0.45, 520.0, 60.0, 0.0001, 0.0))
			out.append(func() -> void:
				box.syn.swell(2.0, 0.5)
				box.syn.noise(0.0, 6.0, 0.3, 140.0, 0.0, 0.0001, 0.0))
			out.append(func() -> void:
				for i in 6:
					var f := 650.0 if i % 2 == 0 else 820.0
					box.syn.tone(i * 1.0, 1.0, f, f, 0.012, Synth.Wave.SINE, 0.3, 0.0))
			out.append(func() -> void:
				box.syn.loopify(0.5)
				box.syn.normalize(0.4))
		"amb_cctv":
			# A security monitor: mains hum and faint static.
			out.append(func() -> void:
				box.syn = Synth.create(2.0, AMB_RATE, 15)
				box.syn.tone(0.0, 2.0, 60.0, 60.0, 0.12, Synth.Wave.SINE, 0.0001, 0.0)
				box.syn.tone(0.0, 2.0, 180.0, 180.0, 0.05, Synth.Wave.SQUARE, 0.0001, 0.0)
				box.syn.noise(0.0, 2.0, 0.08, 0.0, 2500.0, 0.0001, 0.0)
				box.syn.loopify(0.2)
				box.syn.normalize(0.3))
	out.append(func() -> void: _cache[name] = box.syn.to_stream(true))
	return out


# --- Music (built in steps) -----------------------------------------------------------

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


## The menu and opening-pan theme: an original spy piece in the spirit of GoldenEye N64's menu
## music (not its melody). 100 bpm, 8 bars in A minor: Am, Fmaj7, Dm6, E (two bars each). A plucked
## bass ostinato, brushed drums, a slow string pad, a twangy spy-guitar lead with echo, and brass
## stabs on the turnaround.
static func _menu_music_steps() -> Array[Callable]:
	var box := {}
	var beat := 0.6
	var total := beat * 32.0
	var out: Array[Callable] = []
	var chords := [["A", ["A3", "C4", "E4"]], ["F", ["F3", "A3", "E4"]], ["D", ["D3", "F3", "B3"]], ["E", ["E3", "G#3", "D4"]]]
	var bass_roots := [note("A1"), note("F1"), note("D2"), note("E2")]
	out.append(func() -> void:
		box.bass = Synth.create(total, MUSIC_RATE, 41)
		var minor := [0, -1, 0, 7, 12, -1, 10, 7]
		var major := [0, -1, 0, 7, 12, -1, 4, 7]
		for bar in 8:
			var root: float = bass_roots[bar / 2]
			var pat: Array = major if bar >= 6 else minor
			for e in 8:
				if pat[e] < 0:
					continue
				var f: float = root * pow(2.0, pat[e] / 12.0)
				var t := (bar * 8 + e) * beat / 2.0
				box.bass.tone(t, beat * 0.45, f * 1.01, f, 0.55, Synth.Wave.TRIANGLE, 0.003, 4.0)
				box.bass.tone(t, beat * 0.3, f, f, 0.18, Synth.Wave.SAW, 0.003, 6.0))
	out.append(func() -> void:
		box.bass.lowpass(700.0))
	out.append(func() -> void:
		box.drums = Synth.create(total, MUSIC_RATE, 42)
		for b in 32:
			var t := b * beat
			box.drums.noise(t, 0.05, 0.16, 0.0, 6000.0, 0.002, 6.0)                 # brushed hat
			box.drums.noise(t + beat * 0.62, 0.04, 0.1, 0.0, 6500.0, 0.002, 7.0)    # the swung off-beat
			if b % 4 in [1, 3]:
				box.drums.noise(t, 0.06, 0.3, 4000.0, 1500.0, 0.001, 8.0)           # rim
				box.drums.tone(t, 0.04, 900.0, 700.0, 0.12, Synth.Wave.TRIANGLE, 0.001, 8.0)
			if b % 4 == 0 or b % 8 == 6:
				box.drums.tone(t, 0.16, 110.0, 48.0, 0.5, Synth.Wave.SINE, 0.002, 6.0)  # soft kick
		)
	out.append(func() -> void: box.pad = Synth.create(total, MUSIC_RATE, 43))
	for ci in chords.size():
		for tone_name in chords[ci][1]:
			out.append(func() -> void:
				var f := note(tone_name)
				box.pad.tone(ci * beat * 8.0, beat * 8.0, f, f, 0.07, Synth.Wave.SAW, 0.6, 0.6))
	out.append(func() -> void:
		box.pad.lowpass(1100.0))
	out.append(func() -> void:
		box.lead = Synth.create(total, MUSIC_RATE, 44)
		var line := [
			[1.0, 1.0, "E5"], [2.0, 0.5, "D5"], [2.5, 0.5, "E5"], [3.0, 1.0, "G5"],
			[4.0, 1.5, "F5"], [5.5, 0.5, "E5"], [6.0, 0.5, "D#5"], [6.5, 1.5, "E5"],
			[9.0, 0.5, "C5"], [9.5, 0.5, "A4"], [10.0, 1.0, "C5"], [11.0, 1.0, "E5"],
			[12.0, 1.5, "D5"], [13.5, 0.5, "C5"], [14.0, 2.0, "A4"],
			[17.0, 0.5, "F5"], [17.5, 0.5, "E5"], [18.0, 1.0, "D5"], [19.0, 1.0, "B4"],
			[20.0, 1.5, "D5"], [21.5, 0.5, "F5"], [22.0, 2.0, "A5"],
			[24.0, 1.0, "G#5"], [25.0, 0.5, "F5"], [25.5, 0.5, "E5"], [26.0, 1.0, "D5"], [27.0, 1.0, "B4"],
			[28.0, 2.0, "G#4"], [30.0, 0.5, "B4"], [30.5, 0.5, "D5"], [31.0, 1.0, "E5"],
		]
		for n in line:
			var f := note(n[2])
			var t: float = n[0] * beat
			var d: float = n[1] * beat
			# A twang: it slides up into the note, then rings and fades.
			box.lead.tone(t, 0.035, f * 0.94, f, 0.22, Synth.Wave.PULSE, 0.002, 0.0)
			box.lead.tone(t + 0.035, d * 0.95, f, f * 0.997, 0.22, Synth.Wave.PULSE, 0.003, 2.2)
			box.lead.tone(t, d * 0.9, f * 2.0, f * 2.0, 0.05, Synth.Wave.SINE, 0.003, 3.0)
		box.lead.lowpass(2600.0))
	out.append(func() -> void:
		box.lead.echo(beat * 0.75, 0.38, 0.4))
	out.append(func() -> void:
		box.brass = Synth.create(total, MUSIC_RATE, 45)
		for bar in [6, 7]:
			var t: float = bar * beat * 4.0
			for n in ["E4", "G#4", "B4", "D5"]:
				var f := note(n)
				box.brass.tone(t, 0.32, f * 0.99, f, 0.09, Synth.Wave.SAW, 0.01, 4.0)
				box.brass.tone(t + beat * 2.5, 0.2, f * 0.99, f, 0.07, Synth.Wave.SAW, 0.01, 5.0)
			box.brass.tone(t, 0.5, 70.0, 52.0, 0.5, Synth.Wave.SINE, 0.002, 4.0)  # timpani
		box.brass.lowpass(2400.0))
	out.append(func() -> void:
		box.bass.mix_in(box.drums, 0.0, 1.0))
	out.append(func() -> void:
		box.bass.mix_in(box.pad, 0.0, 1.0))
	out.append(func() -> void:
		box.bass.mix_in(box.lead, 0.0, 1.0)
		box.bass.mix_in(box.brass, 0.0, 1.0))
	out.append(func() -> void:
		box.bass.crush(10, 1)
		box.bass.normalize(0.6)
		_cache["music_menu"] = box.bass.to_stream(true))
	return out


## CAUTION (alert 2): a low pulsing bass, a held dark pad and a ticking clock. 110 bpm, 4 bars.
static func _tension_steps() -> Array[Callable]:
	var box := {}
	var eighth := 60.0 / 110.0 / 2.0
	var total := eighth * 32.0
	var out: Array[Callable] = []
	out.append(func() -> void:
		box.bass = Synth.create(total, MUSIC_RATE, 21)
		var roots := [73.42, 73.42, 69.30, 65.41]  # D, D, C#, C
		for bar in 4:
			for i in 8:
				var f: float = roots[bar] * (2.0 if i == 7 else 1.0)
				box.bass.tone((bar * 8 + i) * eighth, eighth * 0.9, f, f, 0.6 if i % 4 == 0 else 0.4, Synth.Wave.TRIANGLE, 0.003, 3.0))
	out.append(func() -> void: box.pad = Synth.create(total, MUSIC_RATE, 22))
	for f in [146.8, 146.8 * 1.006, 220.0, 220.0 * 1.006]:  # a detuned pair on each note
		out.append(func() -> void: box.pad.tone(0.0, total, f, f, 0.11, Synth.Wave.SAW, 1.0, 0.0))
	out.append(func() -> void:
		box.pad.lowpass(500.0)
		box.pad.swell(2.0, 0.3))
	out.append(func() -> void:
		box.tick = Synth.create(total, MUSIC_RATE, 23)
		for i in 16:
			box.tick.noise(i * eighth * 2.0, 0.025, 0.25 if i % 4 == 0 else 0.15, 0.0, 5000.0, 0.0005, 8.0)
		box.tick.tone(0.0, 0.5, 60.0, 40.0, 0.5, Synth.Wave.SINE, 0.002, 4.0))  # a boom on the downbeat
	out.append(func() -> void:
		box.bass.mix_in(box.pad, 0.0, 1.0)
		box.bass.mix_in(box.tick, 0.0, 1.0)
		box.bass.crush(10, 1)
		box.bass.normalize(0.55)
		_cache["music_tension"] = box.bass.to_stream(true))
	return out


## ALERT (alert 3): driving MGS-style alert music. 150 bpm, 4 bars: a 16th-note bass ostinato, a
## kick and snare, off-beat brass stabs and a high lead line.
static func _alert_music_steps() -> Array[Callable]:
	var box := {}
	var six := 60.0 / 150.0 / 4.0
	var total := six * 64.0
	var out: Array[Callable] = []
	var roots := [73.42, 73.42, 58.27, 65.41]  # D, D, Bb, C
	var pattern := [1, 1, 2, 1, 1, 1, 2, 1, 1, 1, 2, 1, 1.189, 1, 1.335, 1]  # root, octave, minor 3rd, 4th
	for bar in 4:
		out.append(func() -> void:
			if bar == 0:
				box.bass = Synth.create(total, MUSIC_RATE, 31)
			for i in 16:
				var f: float = roots[bar] * pattern[i]
				box.bass.tone((bar * 16 + i) * six, six * 0.85, f, f, 0.5, Synth.Wave.SAW, 0.002, 3.5))
	out.append(func() -> void:
		box.bass.lowpass(900.0))
	out.append(func() -> void:
		box.drums = Synth.create(total, MUSIC_RATE, 32)
		for bar in 4:
			var b := bar * 16
			for k in [0, 6, 8, 10]:
				box.drums.tone((b + k) * six, 0.14, 150.0, 45.0, 0.8, Synth.Wave.SINE, 0.001, 6.0)
			for k in [4, 12]:
				box.drums.noise((b + k) * six, 0.13, 0.55, 6000.0, 1200.0, 0.0005, 7.0)
				box.drums.tone((b + k) * six, 0.08, 220.0, 170.0, 0.35, Synth.Wave.TRIANGLE, 0.001, 6.0)
			for k in range(0, 16, 2):
				box.drums.noise((b + k) * six, 0.025, 0.18, 0.0, 6000.0, 0.0005, 9.0))
	out.append(func() -> void:
		box.stabs = Synth.create(total, MUSIC_RATE, 33)
		for bar in 4:
			for k in [2, 7, 11]:
				for f in [293.7, 349.2, 440.0]:
					var ff: float = f * roots[bar] / 73.42
					box.stabs.tone((bar * 16 + k) * six, 0.14, ff, ff, 0.13, Synth.Wave.SQUARE, 0.002, 5.0))
	out.append(func() -> void:
		box.lead = Synth.create(total, MUSIC_RATE, 34)
		var line := [880.0, 830.6, 784.0, 698.5, 659.3, 698.5, 784.0, 880.0]
		for i in line.size():
			box.lead.tone(32 * six + i * 4 * six, 4 * six * 0.9, line[i], line[i], 0.18, Synth.Wave.PULSE, 0.004, 1.5)
		box.lead.lowpass(3500.0)
		box.lead.echo(six * 3.0, 0.3, 0.3))
	out.append(func() -> void:
		box.bass.mix_in(box.drums, 0.0, 1.0)
		box.bass.mix_in(box.stabs, 0.0, 1.0)
		box.bass.mix_in(box.lead, 0.0, 1.0))
	out.append(func() -> void:
		box.bass.crush(9, 1)
		box.bass.normalize(0.6)
		_cache["music_alert"] = box.bass.to_stream(true))
	return out
