extends SceneTree
## Procedural sound-effect and music synthesizer for Grim Gauntlet.
## Writes 16-bit mono WAVs into assets/sfx and assets/music.
##
##   godot --headless --path . --script res://tools/gen_sfx.gd
##
## Each sound is built from a few building blocks: oscillators with pitch
## sweeps, filtered noise, and envelopes. Tweak and re-run to taste.

const RATE := 22050
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 666
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/sfx"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/music"))
	gen_sfx()
	gen_music()
	print("Audio generated.")
	quit()


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------

func buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Oscillator with exponential pitch sweep. wave: sine / saw / square / tri
func osc(b: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float, wave := "sine", attack := 0.005, decay_pow := 1.0) -> void:
	var n := int(dur * RATE)
	var s0 := int(start * RATE)
	var ph := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / n
		var f := f0 * pow(f1 / f0, t)
		ph += f / RATE
		var p := fmod(ph, 1.0)
		var v := 0.0
		match wave:
			"sine":
				v = sin(TAU * p)
			"saw":
				v = 2.0 * p - 1.0
			"square":
				v = 1.0 if p < 0.5 else -1.0
			"tri":
				v = 4.0 * absf(p - 0.5) - 1.0
		var env := minf(1.0, float(i) / (attack * RATE + 1.0)) * pow(1.0 - t, decay_pow)
		b[idx] += v * amp * env


## Noise burst through a one-pole low-pass whose cutoff sweeps c0 -> c1 (0..1).
func noise(b: PackedFloat32Array, start: float, dur: float, c0: float, c1: float, amp: float, attack := 0.002, decay_pow := 1.5, highpass := false) -> void:
	var n := int(dur * RATE)
	var s0 := int(start * RATE)
	var lp := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= b.size():
			break
		var t := float(i) / n
		var c := lerpf(c0, c1, t)
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * c
		var v := (w - lp) if highpass else lp
		var env := minf(1.0, float(i) / (attack * RATE + 1.0)) * pow(1.0 - t, decay_pow)
		b[idx] += v * amp * env


## Inharmonic bell / gong partials.
func bell(b: PackedFloat32Array, start: float, dur: float, f: float, amp: float, ratios := [1.0, 2.76, 5.4, 8.93]) -> void:
	var a := amp
	for r in ratios:
		osc(b, start, dur / (1.0 + r * 0.25), f * r, f * r * 0.998, a, "sine", 0.002, 2.0)
		a *= 0.55


func distort(b: PackedFloat32Array, drive: float) -> void:
	for i in b.size():
		b[i] = tanh(b[i] * drive) / tanh(drive)


func normalize(b: PackedFloat32Array, peak := 0.9) -> void:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	for i in b.size():
		b[i] = b[i] / m * peak


func save_wav(b: PackedFloat32Array, path: String, peak := 0.9) -> void:
	normalize(b, peak)
	# short fade-out to avoid clicks
	var fade := mini(200, b.size())
	for i in fade:
		b[b.size() - 1 - i] *= float(i) / fade
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		data.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.save_to_wav(path)


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

func gen_sfx() -> void:
	var d := "res://assets/sfx/"
	var b: PackedFloat32Array

	b = buf(0.12)
	noise(b, 0, 0.05, 0.9, 0.3, 0.7, 0.001, 2.0, true)
	osc(b, 0, 0.1, 900, 260, 0.5, "tri")
	save_wav(b, d + "shoot_bolt.wav", 0.6)

	b = buf(0.25)
	osc(b, 0, 0.22, 260, 620, 0.5, "sine", 0.01)
	osc(b, 0, 0.22, 266, 640, 0.3, "saw", 0.01)
	noise(b, 0, 0.2, 0.2, 0.05, 0.5, 0.02)
	save_wav(b, d + "shoot_magic.wav", 0.55)

	b = buf(0.4)
	noise(b, 0, 0.35, 0.6, 0.05, 1.0, 0.001, 2.0)
	osc(b, 0, 0.3, 140, 40, 0.8, "sine")
	distort(b, 2.0)
	save_wav(b, d + "shoot_cannon.wav", 0.7)

	b = buf(0.18)
	noise(b, 0, 0.16, 0.05, 0.4, 0.8, 0.04, 1.2, true)
	save_wav(b, d + "shoot_axe.wav", 0.5)

	b = buf(0.22)
	osc(b, 0, 0.2, 700, 300, 0.4, "sine", 0.01)
	osc(b, 0, 0.2, 707, 290, 0.4, "sine", 0.01)
	noise(b, 0, 0.18, 0.1, 0.02, 0.3)
	save_wav(b, d + "shoot_wand.wav", 0.5)

	b = buf(0.1)
	osc(b, 0, 0.09, 200, 60, 0.9, "sine")
	noise(b, 0, 0.03, 0.8, 0.3, 0.5)
	save_wav(b, d + "hit.wav", 0.6)

	b = buf(0.08)
	osc(b, 0, 0.05, 1400, 900, 0.3, "square")
	noise(b, 0, 0.06, 0.9, 0.5, 0.6, 0.001, 3.0, true)
	save_wav(b, d + "hit_bone.wav", 0.5)

	b = buf(0.35)
	noise(b, 0, 0.3, 0.5, 0.03, 1.0, 0.001, 1.8)
	osc(b, 0, 0.2, 160, 45, 0.7, "sine")
	for k in 4:
		noise(b, 0.02 + k * 0.04, 0.03, 0.9, 0.6, 0.3, 0.001, 2.0, true)
	save_wav(b, d + "enemy_die.wav", 0.6)

	b = buf(0.3)
	osc(b, 0, 0.25, 220, 110, 0.6, "saw", 0.01)
	osc(b, 0, 0.25, 160, 80, 0.6, "square", 0.01)
	noise(b, 0, 0.12, 0.6, 0.2, 0.4)
	distort(b, 3.0)
	save_wav(b, d + "player_hurt.wav", 0.6)

	b = buf(0.22)
	noise(b, 0, 0.2, 0.03, 0.35, 0.9, 0.05, 1.0)
	save_wav(b, d + "dodge.wav", 0.45)

	b = buf(0.2)
	osc(b, 0, 0.15, 2100, 2100, 0.4, "sine", 0.001, 2.0)
	osc(b, 0.05, 0.15, 2800, 2800, 0.35, "sine", 0.001, 2.0)
	save_wav(b, d + "gold.wav", 0.35)

	b = buf(0.45)
	osc(b, 0, 0.12, 180, 70, 0.9, "sine")
	bell(b, 0.0, 0.4, 420, 0.4)
	noise(b, 0, 0.05, 0.6, 0.2, 0.5)
	save_wav(b, d + "item_drop.wav", 0.6)

	b = buf(1.2)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in notes.size():
		bell(b, k * 0.09, 1.0, notes[k], 0.5, [1.0, 2.0, 3.01])
	osc(b, 0, 1.0, 130, 130, 0.3, "sine", 0.05)
	save_wav(b, d + "item_unique.wav", 0.6)

	b = buf(0.25)
	noise(b, 0, 0.08, 0.3, 0.1, 0.6)
	noise(b, 0.08, 0.08, 0.3, 0.1, 0.5)
	bell(b, 0.12, 0.12, 1500, 0.3)
	save_wav(b, d + "equip.wav", 0.5)

	b = buf(0.8)
	noise(b, 0, 0.6, 0.04, 0.02, 1.0, 0.05, 0.6)
	osc(b, 0, 0.6, 50, 45, 0.6, "saw", 0.05, 0.6)
	osc(b, 0.6, 0.15, 300, 120, 0.5, "square")
	noise(b, 0.6, 0.1, 0.8, 0.3, 0.5)
	save_wav(b, d + "door_open.wav", 0.6)

	b = buf(2.0)
	bell(b, 0, 2.0, 98, 0.8, [1.0, 1.52, 2.33, 3.17, 4.2])
	noise(b, 0, 0.05, 0.4, 0.1, 0.3)
	save_wav(b, d + "room_clear.wav", 0.6)

	b = buf(1.2)
	for k in 3:
		var base := [220.0, 277.18, 329.63][k] as float
		osc(b, k * 0.08, 1.1, base, base * 2.0, 0.3, "saw", 0.2, 1.0)
		osc(b, k * 0.08, 1.1, base * 1.005, base * 2.01, 0.3, "sine", 0.2, 1.0)
	noise(b, 0.0, 1.0, 0.1, 0.4, 0.15, 0.4)
	save_wav(b, d + "level_up.wav", 0.55)

	b = buf(2.0)
	for f in [110.0, 164.81, 220.0, 261.63, 329.63]:
		osc(b, 0, 1.9, f, f, 0.25, "saw", 0.3, 1.2)
		osc(b, 0, 1.9, f * 1.007, f * 1.007, 0.2, "sine", 0.3, 1.2)
	for k in 6:
		bell(b, 0.2 + k * 0.12, 0.8, 1318.5 + k * 120, 0.15, [1.0, 2.0])
	osc(b, 0, 0.6, 80, 30, 0.8, "sine")
	save_wav(b, d + "awaken.wav", 0.65)

	b = buf(0.8)
	noise(b, 0, 0.7, 0.7, 0.02, 1.0, 0.001, 1.6)
	osc(b, 0, 0.5, 90, 28, 1.0, "sine")
	distort(b, 2.5)
	save_wav(b, d + "explosion.wav", 0.7)

	b = buf(1.4)
	for k in 3:
		osc(b, 0, 1.3, 70 + k * 3, 45 + k * 2, 0.5, "saw", 0.1, 0.8)
	noise(b, 0, 1.3, 0.15, 0.05, 0.6, 0.1, 0.8)
	distort(b, 4.0)
	save_wav(b, d + "boss_roar.wav", 0.75)

	b = buf(0.4)
	for k in 4:
		osc(b, k * 0.08, 0.07, 300 + k * 40, 600 + k * 60, 0.5, "sine", 0.005)
	save_wav(b, d + "flask.wav", 0.5)

	b = buf(0.04)
	osc(b, 0, 0.03, 1200, 800, 0.5, "square")
	save_wav(b, d + "ui_click.wav", 0.3)

	b = buf(0.03)
	osc(b, 0, 0.02, 2000, 1800, 0.3, "sine")
	save_wav(b, d + "ui_hover.wav", 0.15)

	b = buf(0.14)
	osc(b, 0, 0.12, 520, 180, 0.5, "square")
	noise(b, 0, 0.08, 0.3, 0.1, 0.4)
	save_wav(b, d + "enemy_shoot.wav", 0.35)

	b = buf(2.4)
	osc(b, 0, 2.0, 220, 40, 0.6, "saw", 0.01, 0.7)
	bell(b, 0.3, 2.0, 73.4, 0.9, [1.0, 1.52, 2.33, 3.17])
	noise(b, 0, 1.0, 0.2, 0.02, 0.5)
	distort(b, 2.0)
	save_wav(b, d + "player_death.wav", 0.7)

	b = buf(0.6)
	osc(b, 0, 0.55, 120, 480, 0.4, "saw", 0.3, 0.5)
	noise(b, 0, 0.55, 0.02, 0.3, 0.4, 0.3, 0.5, true)
	save_wav(b, d + "spawn.wav", 0.4)

	b = buf(0.5)
	noise(b, 0, 0.45, 0.6, 0.05, 1.0, 0.01, 1.2)
	osc(b, 0, 0.4, 300, 80, 0.6, "saw")
	save_wav(b, d + "skill.wav", 0.6)

	b = buf(0.4)
	noise(b, 0, 0.15, 0.7, 0.2, 0.8)
	for k in 3:
		osc(b, 0.12 + k * 0.06, 0.12, 2200 + k * 300, 2200 + k * 300, 0.3, "sine", 0.001, 2.0)
	save_wav(b, d + "salvage.wav", 0.5)

	b = buf(1.5)
	for f in [73.42, 87.31, 103.83]:
		osc(b, 0, 1.4, f, f, 0.4, "saw", 0.4, 1.0)
	noise(b, 0, 1.4, 0.05, 0.05, 0.3, 0.4, 1.0)
	save_wav(b, d + "shrine.wav", 0.55)

	b = buf(0.5)
	noise(b, 0, 0.4, 0.3, 0.05, 0.9, 0.001, 1.5)
	osc(b, 0, 0.3, 110, 50, 0.6, "sine")
	bell(b, 0.05, 0.4, 330, 0.3)
	save_wav(b, d + "chest.wav", 0.6)

	b = buf(0.3)
	osc(b, 0, 0.25, 80, 50, 1.0, "sine")
	noise(b, 0, 0.1, 0.5, 0.1, 0.5)
	save_wav(b, d + "slam.wav", 0.7)


# ---------------------------------------------------------------------------
# Music loops
# ---------------------------------------------------------------------------

## Slow, dark ambient loop: detuned drones, wind and distant bells.
func gen_music() -> void:
	var dur := 32.0
	var b := buf(dur)
	var n := b.size()
	var drones := [55.0, 82.41, 110.0, 130.81]
	var phases := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var lp := 0.0
	var wind := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in drones.size():
			for det in 2:
				var f: float = drones[k] * (1.0 + (det * 2 - 1) * 0.003)
				var j := k * 2 + det
				phases[j] += f / RATE
				var amp := 0.22 if k < 2 else 0.09 * (0.5 + 0.5 * sin(TAU * t / 16.0 + k))
				s += (2.0 * fmod(phases[j], 1.0) - 1.0) * amp
		var cutoff := 0.03 + 0.02 * sin(TAU * t / dur * 2.0)
		lp += (s - lp) * cutoff
		var w := rng.randf_range(-1, 1)
		wind += (w - wind) * (0.01 + 0.008 * sin(TAU * t / 8.0))
		b[i] = lp * 0.9 + wind * 0.6 * (0.5 + 0.5 * sin(TAU * t / dur * 4.0))
	for k in 4:
		bell(b, 2.0 + k * 8.0, 6.0, [146.83, 138.59, 146.83, 110.0][k], 0.25, [1.0, 2.76, 5.4])
	_loop_crossfade(b, 2.0)
	save_wav(b, "res://assets/music/ambient.wav", 0.55)

	# Boss: pulsing war drums and a dissonant drone.
	dur = 19.2 # 12 bars of 4 beats at 150 bpm... = 48 beats * 0.4s
	b = buf(dur)
	n = b.size()
	phases = [0.0, 0.0, 0.0, 0.0]
	lp = 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		var fr := [41.2, 41.4, 58.27, 61.74]
		for k in 4:
			phases[k] += fr[k] / RATE
			s += (2.0 * fmod(phases[k], 1.0) - 1.0) * (0.3 if k < 2 else 0.12)
		lp += (s - lp) * (0.05 + 0.03 * sin(TAU * t / 4.8))
		b[i] = lp
	var beat := 0.4
	for k in 48:
		var tt := k * beat
		if k % 4 == 0 or k % 4 == 2 or (k % 8 == 7):
			osc(b, tt, 0.35, 110, 38, 1.0, "sine", 0.002, 1.5)
			noise(b, tt, 0.06, 0.5, 0.2, 0.4)
		if k % 4 == 1 or k % 4 == 3:
			noise(b, tt, 0.12, 0.6, 0.3, 0.35, 0.001, 2.5, true)
		if k % 16 == 0:
			for f in [146.83, 207.65]:
				osc(b, tt, 1.4, f, f * 0.99, 0.25, "saw", 0.01, 1.2)
	_loop_crossfade(b, 0.05)
	save_wav(b, "res://assets/music/boss.wav", 0.7)


## Blend the tail into the head so the loop point is seamless.
func _loop_crossfade(b: PackedFloat32Array, seconds: float) -> void:
	var n := int(seconds * RATE)
	var size := b.size()
	for i in n:
		var t := float(i) / n
		b[i] = b[i] * t + b[size - n + i] * (1.0 - t)
	b.resize(size - n)
