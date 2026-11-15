extends Node
# Todos los sonidos se sintetizan por codigo: el proyecto no necesita archivos de audio.

const RATE := 22050

var streams := {}
var pool: Array = []
var idx := 0
var listener: Node2D = null
var amb: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 18:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	_gen()
	amb = AudioStreamPlayer.new()
	add_child(amb)
	amb.stream = streams["wind"]
	amb.volume_db = -20.0
	amb.play()


func play(sname: String, vol_db := 0.0, at = null, pitch := 1.0) -> void:
	if not streams.has(sname):
		return
	var v := vol_db
	if at != null and listener != null and is_instance_valid(listener):
		var d: float = listener.global_position.distance_to(at)
		if d > 1500.0:
			return
		v -= d * 0.011
	var p: AudioStreamPlayer = pool[idx]
	idx = (idx + 1) % pool.size()
	p.stream = streams[sname]
	p.volume_db = v
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.play()


func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _burst(dur: float, decay: float, lp: float, thump_hz: float, thump_amt: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += lp * (randf_range(-1.0, 1.0) - y)
		var env := exp(-t * decay)
		s[i] = (y * 1.6 + sin(TAU * thump_hz * t * (1.0 - t * 0.8)) * thump_amt) * env
	return s


func _voice(dur: float, f0: float, f1: float, vib: float, noise: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, k) + vib * sin(TAU * 5.0 * t)
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		y += 0.3 * (randf_range(-1.0, 1.0) - y)
		var trem := 0.65 + 0.35 * sin(TAU * 13.0 * t)
		s[i] = (saw * 0.45 + y * noise) * trem * sin(PI * k)
	return s


func _tone(dur: float, f0: float, f1: float, decay: float, amp := 0.6) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += lerpf(f0, f1, t / dur) / RATE
		s[i] = sin(TAU * ph) * exp(-t * decay) * amp
	return s


func _swish(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var lp := lerpf(f0, f1, k)
		y += lp * (randf_range(-1.0, 1.0) - y)
		s[i] = y * 2.2 * sin(PI * k)
	return s


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gb := 1.0) -> PackedFloat32Array:
	var n := mini(a.size(), b.size())
	for i in n:
		a[i] = (a[i] + b[i] * gb) * 0.7
	return a


func _gen() -> void:
	streams["pistol"] = _wav(_burst(0.22, 24.0, 0.55, 170.0, 0.6))
	streams["pistol_sil"] = _wav(_burst(0.1, 45.0, 0.25, 120.0, 0.25))
	streams["rifle"] = _wav(_burst(0.18, 28.0, 0.7, 120.0, 0.5))
	streams["shotgun"] = _wav(_burst(0.5, 10.0, 0.4, 75.0, 0.85))
	streams["bow"] = _wav(_mix(_tone(0.18, 220.0, 90.0, 20.0, 0.5), _swish(0.18, 0.5, 0.1), 0.6))
	streams["explode"] = _wav(_burst(0.9, 5.0, 0.12, 45.0, 0.95))
	streams["hit"] = _wav(_burst(0.07, 50.0, 0.2, 90.0, 0.3))
	streams["splat"] = _wav(_mix(_burst(0.25, 16.0, 0.08, 60.0, 0.6), _burst(0.12, 30.0, 0.5, 200.0, 0.1), 0.5))
	streams["chop"] = _wav(_mix(_burst(0.16, 25.0, 0.15, 110.0, 0.5), _tone(0.1, 900.0, 600.0, 30.0, 0.2)))
	streams["swish"] = _wav(_swish(0.2, 0.05, 0.6))
	streams["whoosh"] = _wav(_swish(0.3, 0.02, 0.25))
	streams["click"] = _wav(_burst(0.04, 120.0, 0.9, 900.0, 0.2))
	streams["reload"] = _wav(_mix(_burst(0.06, 90.0, 0.9, 700.0, 0.3), _tone(0.12, 400.0, 380.0, 25.0, 0.3)))
	streams["growl"] = _wav(_voice(0.7, 95.0, 70.0, 14.0, 0.7))
	streams["growl2"] = _wav(_voice(0.5, 130.0, 85.0, 20.0, 0.6))
	streams["scream"] = _wav(_voice(1.0, 620.0, 380.0, 50.0, 0.6))
	streams["roar"] = _wav(_voice(1.2, 62.0, 45.0, 6.0, 0.9))
	streams["horde"] = _wav(_mix(_mix(_voice(2.0, 180.0, 240.0, 20.0, 0.6), _voice(2.0, 233.0, 300.0, 26.0, 0.6)), _voice(2.0, 95.0, 120.0, 12.0, 0.8)))
	streams["beep"] = _wav(_tone(0.09, 1400.0, 1400.0, 8.0, 0.4))
	streams["alarm"] = _wav(_mix(_tone(0.35, 880.0, 1100.0, 1.0, 0.35), _tone(0.35, 440.0, 550.0, 1.0, 0.3)))
	streams["hiss"] = _wav(_swish(1.4, 0.6, 0.5))
	streams["throw"] = _wav(_swish(0.25, 0.08, 0.3))
	streams["hurt"] = _wav(_tone(0.18, 260.0, 150.0, 12.0, 0.8))
	streams["pickup"] = _wav(_mix(_tone(0.1, 660.0, 660.0, 4.0, 0.4), _tone(0.22, 990.0, 990.0, 6.0, 0.4)))
	streams["upgrade"] = _wav(_mix(_tone(0.5, 440.0, 880.0, 3.0, 0.4), _tone(0.5, 660.0, 1320.0, 3.0, 0.3)))
	streams["wave"] = _wav(_mix(_tone(1.2, 110.0, 90.0, 2.0, 0.6), _voice(1.2, 150.0, 120.0, 10.0, 0.5)))
	var n := 3 * RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		y += 0.03 * (randf_range(-1.0, 1.0) - y)
		s[i] = y * 4.0 * (0.6 + 0.4 * sin(TAU * t / 3.0))
	streams["wind"] = _wav(s, true)
