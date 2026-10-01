class_name Synth
extends RefCounted
## A tiny offline synthesiser for PS1/N64-style sounds: a mono buffer at a low sample rate that
## recipes (SoundBank) draw into with oscillators and filtered noise, then shape with filters,
## echo and bit-crush, and finally turn into an AudioStreamWAV.
##
## Everything is baked into the sound (the web build can't run live audio effects), so echo here
## stands in for the PS1's reverb.

enum Wave { SINE, SQUARE, SAW, TRIANGLE, PULSE }

var s := PackedFloat32Array()
var rate := 22050
var _rng := RandomNumberGenerator.new()


static func create(seconds: float, sample_rate: int = 22050, seed_value: int = 0) -> Synth:
	var syn := Synth.new()
	syn.rate = sample_rate
	syn.s.resize(maxi(1, int(seconds * sample_rate)))
	syn._rng.seed = seed_value
	return syn


func length() -> float:
	return float(s.size()) / rate


## An oscillator from `start` for `dur` seconds, its pitch sliding (exponentially) from f0 to f1.
## The envelope rises over `attack` seconds, then decays: `decay` is how fast (0 = flat, held to
## the end; higher = a sharper pluck).
func tone(start: float, dur: float, f0: float, f1: float, amp: float, wave: Wave = Wave.SINE,
		attack: float = 0.002, decay: float = 4.0) -> void:
	var a := s
	var i0 := int(start * rate)
	var n := int(dur * rate)
	if n <= 0:
		return
	var k0 := maxi(0, -i0)
	var k1 := mini(n, a.size() - i0)
	# Stepped multiplicatively per sample (no pow / exp in the loop: it runs in GDScript).
	var f_step := pow(f1 / f0, 1.0 / n)
	var inc := f0 / rate * pow(f_step, k0)
	var env_step := exp(-decay / n) if decay > 0.0 else 1.0
	var env := amp * pow(env_step, k0)
	var att := maxi(1, int(attack * rate))
	var tail := int(rate * 0.01) if decay <= 0.0 else 0
	var phase := 0.0
	var w := int(wave)
	for k in range(k0, k1):
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		inc *= f_step
		var v: float
		if w == 0:
			v = sin(phase * TAU)
		elif w == 1:
			v = 1.0 if phase < 0.5 else -1.0
		elif w == 2:
			v = phase * 2.0 - 1.0
		elif w == 3:
			v = 1.0 - 4.0 * absf(phase - 0.5)
		else:
			v = 1.0 if phase < 0.25 else -1.0
		var e := env
		if k < att:
			e *= float(k) / att
		if tail > 0 and n - k < tail:
			e *= float(n - k) / tail
		a[i0 + k] += v * e
		env *= env_step
	s = a


## Filtered noise from `start` for `dur` seconds: `lp` / `hp` are one-pole low- and high-pass
## cutoffs in Hz (0 = off). The envelope works like tone().
func noise(start: float, dur: float, amp: float, lp: float = 0.0, hp: float = 0.0,
		attack: float = 0.001, decay: float = 6.0) -> void:
	var a := s
	var i0 := int(start * rate)
	var n := int(dur * rate)
	if n <= 0:
		return
	var k0 := maxi(0, -i0)
	var k1 := mini(n, a.size() - i0)
	var kl := _coef(lp)
	var kh := _coef(hp)
	var use_lp := lp > 0.0
	var use_hp := hp > 0.0
	var low := 0.0
	var high_state := 0.0
	var env_step := exp(-decay / n) if decay > 0.0 else 1.0
	var env := amp * pow(env_step, k0)
	var att := maxi(1, int(attack * rate))
	var tail := int(rate * 0.01) if decay <= 0.0 else 0
	for k in range(k0, k1):
		var v := _rng.randf() * 2.0 - 1.0
		if use_lp:
			low += kl * (v - low)
			v = low * 1.6
		if use_hp:
			high_state += kh * (v - high_state)
			v -= high_state
		var e := env
		if k < att:
			e *= float(k) / att
		if tail > 0 and n - k < tail:
			e *= float(n - k) / tail
		a[i0 + k] += v * e
		env *= env_step
	s = a


## One-pole low-pass over the whole buffer.
func lowpass(hz: float) -> void:
	var a := s
	var k := _coef(hz)
	var y := 0.0
	for i in a.size():
		y += k * (a[i] - y)
		a[i] = y
	s = a


func highpass(hz: float) -> void:
	var a := s
	var k := _coef(hz)
	var y := 0.0
	for i in a.size():
		y += k * (a[i] - y)
		a[i] -= y
	s = a


## A resonant band-pass (a formant, for voices and ringing metal), mixed back over the dry
## sound by `mix` (1 = only the band).
func resonate(hz: float, q: float, mix: float = 1.0) -> void:
	var a := s
	var w := TAU * hz / rate
	var alpha := sin(w) / (2.0 * q)
	var b0 := alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in a.size():
		var x := a[i]
		var y := (b0 * x - b0 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		a[i] = lerpf(x, y * 4.0, mix)
	s = a


## Feedback echo: repeats every `delay` seconds, each `feedback` as loud, mixed in at `mix`.
func echo(delay: float, feedback: float, mix: float) -> void:
	var a := s
	var d := int(delay * rate)
	if d <= 0:
		return
	var wet := PackedFloat32Array()
	wet.resize(a.size())
	for i in a.size():
		var back := wet[i - d] if i >= d else 0.0
		wet[i] = a[i] + back * feedback
	for i in a.size():
		a[i] += (wet[i] - a[i]) * mix
	s = a


## PS1/N64 grit: quantise to `bits` and hold each sample for `hold` samples (a lower rate).
func crush(bits: int, hold: int = 1) -> void:
	var a := s
	var steps := pow(2.0, bits - 1)
	var held := 0.0
	for i in a.size():
		if i % maxi(1, hold) == 0:
			held = roundf(clampf(a[i], -1.0, 1.0) * steps) / steps
		a[i] = held
	s = a


## Overdrive: soft-clips the sound (tanh), so it growls and the peaks flatten. 1 is gentle.
func drive(amount: float) -> void:
	var a := s
	var norm := tanh(amount)
	for i in a.size():
		a[i] = tanh(a[i] * amount) / norm
	s = a


func gain(g: float) -> void:
	var a := s
	for i in a.size():
		a[i] *= g
	s = a


## Scale so the loudest sample is `peak`.
func normalize(peak: float = 0.9) -> void:
	var a := s
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	var g := peak / m
	for i in a.size():
		a[i] *= g
	s = a


## For a loop: fade the last `seconds` into the start so it repeats without a click.
func loopify(seconds: float) -> void:
	var a := s
	var n := mini(int(seconds * rate), a.size() / 2)
	var total := a.size() - n
	var out := PackedFloat32Array()
	out.resize(total)
	for i in total:
		out[i] = a[i]
	for k in n:
		var t := float(k) / n
		out[k] = a[k] * t + a[total + k] * (1.0 - t)
	s = out


## Slow swell for a loop (wind gusts): multiply by 1 + depth * sin(cycles round the loop).
func swell(cycles: float, depth: float) -> void:
	var a := s
	for i in a.size():
		a[i] *= 1.0 + depth * sin(TAU * cycles * float(i) / a.size())
	s = a


## Mix another buffer in from `start` seconds (same rate).
func mix_in(other: Synth, start: float, amp: float = 1.0) -> void:
	var a := s
	var i0 := int(start * rate)
	var b := other.s
	for k in b.size():
		var i := i0 + k
		if i >= 0 and i < a.size():
			a[i] += b[k] * amp
	s = a


func to_stream(loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = s.size()
	return wav


func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func _coef(hz: float) -> float:
	if hz <= 0.0:
		return 1.0
	return clampf(1.0 - exp(-TAU * hz / rate), 0.0001, 1.0)
