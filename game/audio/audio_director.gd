class_name AudioDirector
extends Node
## Plays the game's sound (all from SoundBank): one-shots, flat or at a point in the world; loops
## stuck to things (wires, steam, the chopper); the area's ambience, crossfading as you move; and
## the music, which follows the alert level (none at 1, tension at 2, alert music at 3).
##
## SoundBank builds sounds in code. Here the building is spread over frames (a few milliseconds
## each: SoundBank.work) from the moment the level loads, under the main menu, so nothing stutters.

## Ambience per area theme.
const AREA_AMBIENCE := {"office": "amb_office", "security": "amb_office", "canteen": "amb_office", "warehouse": "amb_office", "dock": "amb_office", "lobby": "amb_office", "exit": "amb_office", "tunnel": "amb_tunnel", "service": "amb_tunnel", "boiler": "amb_tunnel", "sewer": "amb_tunnel", "pump": "amb_tunnel", "drain": "amb_tunnel", "rooftops": "amb_roof", "towers": "amb_roof", "gantry": "amb_roof", "skylights": "amb_roof", "antennas": "amb_roof", "edge": "amb_roof",
		"helipad": "amb_roof", "compound": "amb_roof", "gate": "amb_roof"}
## Milliseconds of sound-building per frame.
const BUILD_BUDGET_MS := 4.0
## The same under the mission briefing and the opening pan, once the level's textures are made
## there: twice as fast, so less is left for the run, and a desktop still draws the pan at 60 fps.
const HURRY_BUDGET_MS := 8.0
## The same while the main menu itself is up and waits for its music (the first long sound built,
## right after the gun check's and the button's): so it starts within a second on a desktop, its
## frames still well inside 60 fps there. Only on the menu: from START on (the briefing, the opening
## pan) the music still to build goes on at build_ms and starts a little later, as those frames
## make the level's textures too.
const MENU_MUSIC_BUDGET_MS := 10.0

@export var tuning: Tuning

## Milliseconds of sound-building this frame: BUILD_BUDGET_MS, or HURRY_BUDGET_MS (the level sets
## it under the briefing and the pan).
var build_ms := BUILD_BUDGET_MS
var _pool: Array[AudioStreamPlayer] = []
var _amb: Array[AudioStreamPlayer] = []
var _amb_name := ""
var _amb_active := 0
var _cctv: AudioStreamPlayer
var _music := {}
var _music_on := ""
var _world: Node3D
## Loops stuck to things in the world (wires, steam, the chopper), so they can be faded at the end.
var _loops: Array[AudioStreamPlayer3D] = []
var _menu_music: AudioStreamPlayer
var _menu_wanted := false
## Whether the main menu itself is up (from play_menu_music until leave_menu, at START): only then
## is the menu music built at MENU_MUSIC_BUDGET_MS.
var _menu_up := false
## dB the menu music is lowered by (under the mission briefing).
var _menu_duck := 0.0
## dB the area's ambience is lowered by (under the end-of-mission conversation).
var _amb_duck := 0.0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	for i in 2:
		var a := AudioStreamPlayer.new()
		a.volume_db = -80.0
		add_child(a)
		_amb.append(a)
	_cctv = AudioStreamPlayer.new()
	add_child(_cctv)
	for m in ["music_tension", "music_alert"]:
		var mp := AudioStreamPlayer.new()
		mp.volume_db = -80.0
		add_child(mp)
		_music[m] = mp
	_menu_music = AudioStreamPlayer.new()
	_menu_music.volume_db = -80.0
	add_child(_menu_music)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	for name in SoundBank.all_names():
		prewarm(name)


func _exit_tree() -> void:
	SoundBank.finish_half_built()  # (the level's going: the next one carries on with the rest)


## Where world sounds are parented (so they stay put while they play).
func set_world(world: Node3D) -> void:
	_world = world


## How loud each part of the mix is (dB). Everything plays through the Master bus: buses added
## at runtime scramble the web build's audio routing (sounds reached nothing), so each category's
## volume is applied per sound instead.
func _mix(part: String) -> float:
	match part:
		"Ambience":
			return tuning.ambience_volume_db + Settings.volume_db(Settings.get_value("ambience_volume"))
		"Music":
			return tuning.music_volume_db + Settings.volume_db(Settings.get_value("music_volume"))
		"UI":
			return tuning.ui_volume_db + Settings.volume_db(Settings.get_value("effects_volume"))
	return tuning.sfx_volume_db + Settings.volume_db(Settings.get_value("effects_volume"))


## SOUND on / off and MASTER volume go on the Master bus; the others are applied per sound.
func _apply_settings() -> void:
	AudioServer.set_bus_mute(0, not bool(Settings.get_value("sound_on")))
	AudioServer.set_bus_volume_db(0, Settings.volume_db(Settings.get_value("master_volume")))
	for p in _loops:
		if is_instance_valid(p):
			p.volume_db = p.get_meta("base_db", 0.0) + _mix("Sfx")


## The menu / opening-pan theme: plays (fading in) as soon as it's built. The main menu is up: until
## leave_menu, the music is built faster (MENU_MUSIC_BUDGET_MS).
func play_menu_music() -> void:
	_menu_wanted = true
	_menu_up = true


## START: the main menu has gone (the briefing and the opening pan come next). The menu music plays
## on under them (or starts once it's built), but is built at the normal pace from here.
func leave_menu() -> void:
	_menu_up = false


## The menu music quieter under the mission briefing (Tuning.briefing_music_duck_db), or back up
## (it moves there at the music's usual 20 dB a second).
func duck_menu_music(on: bool) -> void:
	_menu_duck = tuning.briefing_music_duck_db if on else 0.0


## The area's ambience quieter under the end-of-mission conversation (Tuning.end_talk_ambience_duck_db),
## or back up for the debrief (it moves there at the ambience's usual 40 dB a second).
func duck_ambience(on: bool) -> void:
	_amb_duck = tuning.end_talk_ambience_duck_db if on else 0.0


func stop_menu_music(seconds: float = 1.5) -> void:
	_menu_wanted = false
	_menu_up = false
	if _menu_music.playing:
		var t := _menu_music.create_tween()
		t.tween_property(_menu_music, "volume_db", -60.0, seconds)
		t.tween_callback(_menu_music.stop)


## Whether sounds are still being built (spread over frames: see _process).
func building() -> bool:
	return SoundBank.building()


## Queue a sound to be built in the background (if it isn't already).
func prewarm(name: String) -> void:
	SoundBank.queue(name)


## Milliseconds of sound-building this frame: build_ms, or MENU_MUSIC_BUDGET_MS (if more) while the
## main menu itself is up and its music isn't built yet.
func frame_budget_ms() -> float:
	if _menu_up and not SoundBank.has("music_menu"):
		return maxf(build_ms, MENU_MUSIC_BUDGET_MS)
	return build_ms


func _process(delta: float) -> void:
	if SoundBank.building():
		SoundBank.work(frame_budget_ms())
	_fade_music(delta)
	_fade_ambience(delta)
	if _menu_wanted:
		if not _menu_music.playing and SoundBank.has("music_menu"):
			_menu_music.stream = SoundBank.get_stream("music_menu")
			_menu_music.volume_db = -30.0
			_menu_music.play()
		if _menu_music.playing:
			_menu_music.volume_db = move_toward(_menu_music.volume_db, _mix("Music") + _menu_duck, delta * 20.0)


## A one-shot, heard the same wherever you are. pitch_jitter: random +/- pitch, so repeats vary.
## `part`: which part of the mix it belongs to (its volume, see _mix).
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.0, part: String = "Sfx") -> void:
	var p := _free_player()
	if p == null:
		return
	p.stream = SoundBank.get_stream(name)
	p.volume_db = volume_db + _mix(part)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## A one-shot at a point in the world: quieter further away, panned to its side.
func play_at(name: String, pos: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.0, max_distance: float = 45.0) -> void:
	if _world == null:
		play(name, volume_db, pitch_jitter)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = SoundBank.get_stream(name)
	p.volume_db = volume_db + _mix("Sfx")
	p.unit_size = 6.0
	p.max_distance = max_distance
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.top_level = true
	_world.add_child(p)
	p.global_position = pos
	p.play()
	# Freed once it's had time to play out (not on `finished`, which the web's sample playback
	# may not report), so these never pile up.
	get_tree().create_timer(p.stream.get_length() / p.pitch_scale + 0.2).timeout.connect(p.queue_free)


## A loop stuck to `node` (it goes when the node does): live wires, steam, the chopper.
func attach_loop(node: Node3D, name: String, volume_db: float = 0.0, max_distance: float = 15.0, unit_size: float = 3.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = SoundBank.get_stream(name)
	p.set_meta("base_db", volume_db)
	p.volume_db = volume_db + _mix("Sfx")
	p.unit_size = unit_size
	p.max_distance = max_distance
	node.add_child(p)
	# Start somewhere into the loop, so neighbouring loops don't pulse in step.
	p.play(randf() * p.stream.get_length())
	_loops.append(p)
	return p


## The run's over: fade every world loop (the chopper, wires, steam) out over `seconds`, so nothing
## drones on under the end screen.
func fade_loops(seconds: float) -> void:
	for p in _loops:
		if is_instance_valid(p) and p.playing:
			var t := p.create_tween()
			t.tween_property(p, "volume_db", -60.0, seconds)
			t.tween_callback(p.stop)
	_loops.clear()


## The area's ambience (by theme name), crossfading from the last one.
func set_area(theme_name: String) -> void:
	var amb: String = AREA_AMBIENCE.get(theme_name, "amb_roof")
	if amb == _amb_name:
		return
	_amb_name = amb
	_amb_active = 1 - _amb_active
	var p := _amb[_amb_active]
	p.stream = SoundBank.get_stream(amb)
	p.volume_db = -40.0
	p.play()


func _fade_ambience(delta: float) -> void:
	for i in 2:
		var p := _amb[i]
		if not p.playing:
			continue
		var target := _mix("Ambience") + _amb_duck if i == _amb_active else -80.0
		p.volume_db = move_toward(p.volume_db, target, delta * 40.0)
		if p.volume_db <= -79.0 and i != _amb_active:
			p.stop()


## The security-camera hum, while you're in a stairwell.
func set_cctv(on: bool) -> void:
	if on and not _cctv.playing:
		_cctv.stream = SoundBank.get_stream("amb_cctv")
		_cctv.volume_db = -6.0 + _mix("Ambience")
		_cctv.play()
	elif not on and _cctv.playing:
		_cctv.stop()


## Music for this alert level: silence, CAUTION tension or ALERT music.
func set_alert(level: int) -> void:
	var want := ""
	if level == 2:
		want = "music_tension"
	elif level >= 3:
		want = "music_alert"
	if want == _music_on:
		return
	_music_on = want
	if want != "":
		var p: AudioStreamPlayer = _music[want]
		if not p.playing:
			p.stream = SoundBank.get_stream(want)
			p.volume_db = -30.0
			p.play()


func _fade_music(delta: float) -> void:
	for m in _music:
		var p: AudioStreamPlayer = _music[m]
		if not p.playing:
			continue
		var target := _mix("Music") if m == _music_on else -80.0
		p.volume_db = move_toward(p.volume_db, target, delta * (30.0 if m == _music_on else 25.0))
		if p.volume_db <= -79.0 and m != _music_on:
			p.stop()


## Stop the music (the run's over: a jingle or game-over sting plays instead).
func stop_music() -> void:
	_music_on = ""


## Ticks under a caption typing out, one per letter.
func type_ticks(letters: int, per_letter: float) -> void:
	for i in mini(letters, 30):
		get_tree().create_timer(i * per_letter).timeout.connect(func() -> void: play("tick", -8.0, 0.05, "UI"))


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	# All busy: take the one that's been going longest.
	var oldest := _pool[0]
	for p in _pool:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest
