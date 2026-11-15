extends RefCounted
# Fabrica de texturas procedurales. Todo se pinta por codigo al arrancar (sin archivos de imagen).
# Casi todas las texturas llevan mapa de normales para que la linterna, las bengalas y las
# farolas les den relieve con las luces 2D.

const SPLAT := 64
const SPLAT_N := 6

var rng := RandomNumberGenerator.new()
var nz := FastNoiseLite.new()

var asphalt: CanvasTexture
var concrete: CanvasTexture
var grass: CanvasTexture
var roof: CanvasTexture
var zombie_sets: Array = []
var kind_sets := {}
var player := {}
var guns := {}
var cars: Array = []
var crate: CanvasTexture
var barrel: CanvasTexture
var barrier: CanvasTexture
var dumpster: CanvasTexture
var tree: CanvasTexture
var fountain: CanvasTexture
var acunit: CanvasTexture
var lamp: CanvasTexture
var machete: CanvasTexture
var stump: CanvasTexture
var items := {}
var splats: Texture2D
var light_round: Texture2D
var light_cone: Texture2D
var vignette: Texture2D


class Pic:
	var w: int
	var h: int
	var c := PackedColorArray()
	var ht := PackedFloat32Array()

	func _init(pw: int, ph: int) -> void:
		w = pw
		h = ph
		c.resize(w * h)
		c.fill(Color(0, 0, 0, 0))
		ht.resize(w * h)
		ht.fill(0.0)

	func put(i: int, col: Color, a: float, hv: float) -> void:
		if a <= 0.0:
			return
		var d: Color = c[i]
		var oa := a + d.a * (1.0 - a)
		var k := a / oa
		c[i] = Color(lerpf(d.r, col.r, k), lerpf(d.g, col.g, k), lerpf(d.b, col.b, k), oa)
		if hv >= 0.0:
			ht[i] = lerpf(ht[i], hv, a)


func build() -> void:
	rng.randomize()
	nz.seed = rng.randi()
	nz.frequency = 1.0
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3

	asphalt = _asphalt()
	concrete = _concrete()
	grass = _grass()
	roof = _roof()
	_lights()
	_splats()

	var skins := [Color(0.45, 0.52, 0.38), Color(0.56, 0.55, 0.47), Color(0.4, 0.44, 0.4), Color(0.6, 0.5, 0.45), Color(0.36, 0.33, 0.3), Color(0.5, 0.56, 0.5)]
	var shirts := [Color(0.35, 0.12, 0.1), Color(0.18, 0.24, 0.38), Color(0.55, 0.52, 0.45), Color(0.2, 0.3, 0.2), Color(0.45, 0.38, 0.2), Color(0.25, 0.25, 0.27), Color(0.5, 0.2, 0.35)]
	var pants := [Color(0.15, 0.18, 0.28), Color(0.28, 0.24, 0.18), Color(0.12, 0.12, 0.13), Color(0.3, 0.3, 0.32)]
	var hairs := [Color(0.1, 0.08, 0.06), Color(0.3, 0.22, 0.12), Color(0.45, 0.42, 0.38), Color(0.05, 0.05, 0.05)]
	for i in 6:
		var sk: Color = skins[i % skins.size()]
		zombie_sets.append(_zombie_set(sk, shirts[rng.randi() % shirts.size()], pants[rng.randi() % pants.size()], hairs[rng.randi() % hairs.size()], "comun"))
	kind_sets["corredor"] = _zombie_set(Color(0.62, 0.6, 0.56), Color(0.7, 0.28, 0.08), Color(0.12, 0.12, 0.14), Color(0.7, 0.28, 0.08), "corredor")
	kind_sets["hinchado"] = _zombie_set(Color(0.55, 0.6, 0.3), Color(0.42, 0.4, 0.3), Color(0.25, 0.22, 0.18), Color(0.2, 0.2, 0.1), "hinchado")
	kind_sets["chillon"] = _zombie_set(Color(0.78, 0.76, 0.72), Color(0.65, 0.64, 0.62), Color(0.4, 0.4, 0.42), Color(0.04, 0.04, 0.05), "chillon")
	kind_sets["bruto"] = _zombie_set(Color(0.4, 0.36, 0.42), Color(0.2, 0.18, 0.2), Color(0.2, 0.2, 0.22), Color(0.1, 0.1, 0.1), "bruto")
	stump = _stump()

	_player()
	_guns()
	for col in [Color(0.55, 0.08, 0.06), Color(0.12, 0.25, 0.45), Color(0.62, 0.62, 0.6), Color(0.15, 0.15, 0.16), Color(0.75, 0.6, 0.15)]:
		cars.append(_car(col))
	crate = _crate()
	barrel = _barrel()
	barrier = _barrier()
	dumpster = _dumpster()
	tree = _tree()
	fountain = _fountain()
	acunit = _acunit()
	lamp = _lamp()
	_items()


# ------------------------------------------------------------------ primitivas de pintura

func blob(p: Pic, cx: float, cy: float, rx: float, ry: float, col: Color, tex_amt := 0.15, freq := 0.3, dome := 0.6, hv := 0.8, rot := 0.0, holes := -2.0, only_on := false) -> void:
	var r := maxf(rx, ry) + 1.5
	var x0 := maxi(0, int(cx - r))
	var x1 := mini(p.w - 1, int(cx + r) + 1)
	var y0 := maxi(0, int(cy - r))
	var y1 := mini(p.h - 1, int(cy + r) + 1)
	var cs := cos(-rot)
	var sn := sin(-rot)
	var aa := minf(rx, ry)
	var ox := rng.randf() * 1000.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - cx
			var dy := y + 0.5 - cy
			var lx := dx * cs - dy * sn
			var ly := dx * sn + dy * cs
			var e := (lx / rx) * (lx / rx) + (ly / ry) * (ly / ry)
			if e > 1.3:
				continue
			var q := sqrt(e)
			var a := clampf((1.0 - q) * aa + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var n := nz.get_noise_2d((x + ox) * freq, y * freq)
			if n < holes:
				continue
			var i := y * p.w + x
			if only_on:
				a *= p.c[i].a
			var dz := sqrt(maxf(0.0, 1.0 - e))
			var sh := lerpf(1.0, 0.45 + 0.55 * dz, dome) * (1.0 + n * tex_amt)
			p.put(i, Color(col.r * sh, col.g * sh, col.b * sh), a * col.a, hv * dz + n * 0.06 if hv >= 0.0 else -1.0)


func capsule(p: Pic, ax: float, ay: float, bx: float, by: float, r: float, col: Color, tex_amt := 0.15, freq := 0.3, dome := 0.6, hv := 0.7, only_on := false) -> void:
	var x0 := maxi(0, int(minf(ax, bx) - r - 1.0))
	var x1 := mini(p.w - 1, int(maxf(ax, bx) + r + 1.0))
	var y0 := maxi(0, int(minf(ay, by) - r - 1.0))
	var y1 := mini(p.h - 1, int(maxf(ay, by) + r + 1.0))
	var abx := bx - ax
	var aby := by - ay
	var l2 := maxf(0.0001, abx * abx + aby * aby)
	var ox := rng.randf() * 1000.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var px := x + 0.5 - ax
			var py := y + 0.5 - ay
			var t := clampf((px * abx + py * aby) / l2, 0.0, 1.0)
			var dx := px - abx * t
			var dy := py - aby * t
			var d := sqrt(dx * dx + dy * dy)
			if d > r + 1.0:
				continue
			var q := d / r
			var a := clampf((1.0 - q) * r + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var i := y * p.w + x
			if only_on:
				a *= p.c[i].a
			var n := nz.get_noise_2d((x + ox) * freq, y * freq)
			var dz := sqrt(maxf(0.0, 1.0 - q * q))
			var sh := lerpf(1.0, 0.45 + 0.55 * dz, dome) * (1.0 + n * tex_amt)
			p.put(i, Color(col.r * sh, col.g * sh, col.b * sh), a * col.a, hv * dz + n * 0.05 if hv >= 0.0 else -1.0)


func rrect(p: Pic, x0: float, y0: float, x1: float, y1: float, rad: float, col: Color, tex_amt := 0.12, freq := 0.2, bevel := 6.0, hv := 0.6, only_on := false, grain := Vector2.ONE, holes := -2.0) -> void:
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var hx := (x1 - x0) * 0.5 - rad
	var hy := (y1 - y0) * 0.5 - rad
	var ox := rng.randf() * 1000.0
	for y in range(maxi(0, int(y0) - 1), mini(p.h - 1, int(y1) + 1) + 1):
		for x in range(maxi(0, int(x0) - 1), mini(p.w - 1, int(x1) + 1) + 1):
			var qx := absf(x + 0.5 - cx) - hx
			var qy := absf(y + 0.5 - cy) - hy
			var outside := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length()
			var dist := outside + minf(maxf(qx, qy), 0.0) - rad
			if dist > 1.0:
				continue
			var a := clampf(0.5 - dist, 0.0, 1.0)
			var i := y * p.w + x
			if only_on:
				a *= p.c[i].a
			var n := nz.get_noise_2d((x + ox) * freq * grain.x, y * freq * grain.y)
			if n < holes:
				continue
			var inner := clampf(-dist / bevel, 0.0, 1.0)
			var sh := (0.6 + 0.4 * inner) * (1.0 + n * tex_amt)
			p.put(i, Color(col.r * sh, col.g * sh, col.b * sh), a * col.a, hv * (0.35 + 0.65 * inner) + n * 0.04 if hv >= 0.0 else -1.0)


func line(p: Pic, ax: float, ay: float, bx: float, by: float, wdt: float, col: Color, hv := -1.0) -> void:
	var x0 := maxi(0, int(minf(ax, bx) - wdt - 1.0))
	var x1 := mini(p.w - 1, int(maxf(ax, bx) + wdt + 1.0))
	var y0 := maxi(0, int(minf(ay, by) - wdt - 1.0))
	var y1 := mini(p.h - 1, int(maxf(ay, by) + wdt + 1.0))
	var abx := bx - ax
	var aby := by - ay
	var l2 := maxf(0.0001, abx * abx + aby * aby)
	var r := wdt * 0.5
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var px := x + 0.5 - ax
			var py := y + 0.5 - ay
			var t := clampf((px * abx + py * aby) / l2, 0.0, 1.0)
			var dx := px - abx * t
			var dy := py - aby * t
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			if a <= 0.0:
				continue
			var i := y * p.w + x
			a *= p.c[i].a
			p.put(i, col, a * col.a, hv)


func to_tex(p: Pic, bump := 3.0, mip := true) -> CanvasTexture:
	var n := p.w * p.h
	var data := PackedByteArray()
	data.resize(n * 4)
	var hd := PackedByteArray()
	hd.resize(n)
	for i in n:
		var col: Color = p.c[i]
		var j := i * 4
		data[j] = clampi(int(col.r * 255.0), 0, 255)
		data[j + 1] = clampi(int(col.g * 255.0), 0, 255)
		data[j + 2] = clampi(int(col.b * 255.0), 0, 255)
		data[j + 3] = clampi(int(col.a * 255.0), 0, 255)
		hd[i] = clampi(int(p.ht[i] * 255.0), 0, 255)
	var img := Image.create_from_data(p.w, p.h, false, Image.FORMAT_RGBA8, data)
	var him := Image.create_from_data(p.w, p.h, false, Image.FORMAT_L8, hd)
	him.bump_map_to_normal_map(bump)
	if mip:
		img.generate_mipmaps()
		him.generate_mipmaps()
	var ct := CanvasTexture.new()
	ct.diffuse_texture = ImageTexture.create_from_image(img)
	ct.normal_texture = ImageTexture.create_from_image(him)
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if mip else CanvasItem.TEXTURE_FILTER_LINEAR
	return ct


# ------------------------------------------------------------------ suelos (texturas repetibles)

func _sn(size: int, freq: float, oct: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = freq
	n.fractal_octaves = oct
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img := n.get_seamless_image(size, size, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


func _tile_tex(s: int, col: PackedFloat32Array, hgt: PackedFloat32Array, bump: float) -> CanvasTexture:
	var n := s * s
	var data := PackedByteArray()
	data.resize(n * 4)
	var hd := PackedByteArray()
	hd.resize(n)
	for i in n:
		var j := i * 4
		data[j] = clampi(int(col[i * 3] * 255.0), 0, 255)
		data[j + 1] = clampi(int(col[i * 3 + 1] * 255.0), 0, 255)
		data[j + 2] = clampi(int(col[i * 3 + 2] * 255.0), 0, 255)
		data[j + 3] = 255
		hd[i] = clampi(int(hgt[i] * 255.0), 0, 255)
	var img := Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, data)
	var him := Image.create_from_data(s, s, false, Image.FORMAT_L8, hd)
	him.bump_map_to_normal_map(bump)
	img.generate_mipmaps()
	him.generate_mipmaps()
	var ct := CanvasTexture.new()
	ct.diffuse_texture = ImageTexture.create_from_image(img)
	ct.normal_texture = ImageTexture.create_from_image(him)
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	ct.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return ct


func _crack(s: int, col: PackedFloat32Array, hgt: PackedFloat32Array, steps: int, dark: float) -> void:
	var x := rng.randf() * s
	var y := rng.randf() * s
	var ang := rng.randf() * TAU
	for k in steps:
		x += cos(ang)
		y += sin(ang)
		ang += rng.randf_range(-0.45, 0.45)
		var ix := posmod(int(x), s)
		var iy := posmod(int(y), s)
		var i := iy * s + ix
		for c in 3:
			col[i * 3 + c] *= dark
		hgt[i] = 0.05
		if k % 3 == 0:
			var j := iy * s + posmod(ix + 1, s)
			for c in 3:
				col[j * 3 + c] *= lerpf(dark, 1.0, 0.5)
			hgt[j] = 0.2
		if rng.randf() < 0.02 and steps > 30:
			_crack_from(s, col, hgt, x, y, ang + rng.randf_range(-1.2, 1.2), steps / 3, dark)


func _crack_from(s: int, col: PackedFloat32Array, hgt: PackedFloat32Array, x: float, y: float, ang: float, steps: int, dark: float) -> void:
	for k in steps:
		x += cos(ang)
		y += sin(ang)
		ang += rng.randf_range(-0.5, 0.5)
		var i := posmod(int(y), s) * s + posmod(int(x), s)
		for c in 3:
			col[i * 3 + c] *= dark
		hgt[i] = 0.1


func _asphalt() -> CanvasTexture:
	var s := 256
	var a := _sn(s, 0.012, 5)
	var b := _sn(s, 0.3, 2)
	var st := _sn(s, 0.008, 3)
	var col := PackedFloat32Array()
	col.resize(s * s * 3)
	var hgt := PackedFloat32Array()
	hgt.resize(s * s)
	for i in s * s:
		var fa := a[i] / 255.0
		var fb := b[i] / 255.0
		var stain := smoothstep(0.62, 0.78, st[i] / 255.0)
		var v := 0.2 + (fa - 0.5) * 0.08 + (fb - 0.5) * 0.1 - stain * 0.06
		var stone := 0.0
		if rng.randf() < 0.04:
			stone = rng.randf_range(0.04, 0.11)
		v += stone
		col[i * 3] = v * 0.97 + stain * 0.01
		col[i * 3 + 1] = v * 0.98
		col[i * 3 + 2] = v * 1.05 - stain * 0.01
		hgt[i] = 0.45 + (fb - 0.5) * 0.5 + stone * 2.5
	for k in 6:
		_crack(s, col, hgt, rng.randi_range(50, 160), 0.45)
	return _tile_tex(s, col, hgt, 2.5)


func _concrete() -> CanvasTexture:
	var s := 128
	var a := _sn(s, 0.03, 4)
	var b := _sn(s, 0.4, 2)
	var col := PackedFloat32Array()
	col.resize(s * s * 3)
	var hgt := PackedFloat32Array()
	hgt.resize(s * s)
	for y in s:
		for x in s:
			var i := y * s + x
			var fa := a[i] / 255.0
			var fb := b[i] / 255.0
			var v := 0.4 + (fa - 0.5) * 0.1 + (fb - 0.5) * 0.07
			var h := 0.6 + (fb - 0.5) * 0.3
			var mx := x % 64
			var my := y % 64
			if mx < 2 or my < 2:
				v *= 0.55
				h = 0.1
			elif mx < 4 or my < 4:
				v *= 1.08
				h = 0.75
			if rng.randf() < 0.01:
				v *= 0.7
			col[i * 3] = v * 1.02
			col[i * 3 + 1] = v * 1.0
			col[i * 3 + 2] = v * 0.95
			hgt[i] = h
	for k in 2:
		_crack(s, col, hgt, rng.randi_range(20, 50), 0.6)
	return _tile_tex(s, col, hgt, 3.0)


func _grass() -> CanvasTexture:
	var s := 128
	var a := _sn(s, 0.04, 3)
	var b := _sn(s, 0.5, 2)
	var col := PackedFloat32Array()
	col.resize(s * s * 3)
	var hgt := PackedFloat32Array()
	hgt.resize(s * s)
	for i in s * s:
		var fa := a[i] / 255.0
		var fb := b[i] / 255.0
		var dirt := smoothstep(0.62, 0.72, fa)
		var g := Color(0.13, 0.24, 0.08) * (0.75 + fb * 0.5)
		var d := Color(0.26, 0.2, 0.13) * (0.8 + fb * 0.3)
		var c := g.lerp(d, dirt)
		col[i * 3] = c.r
		col[i * 3 + 1] = c.g
		col[i * 3 + 2] = c.b
		hgt[i] = 0.4 + fb * 0.4 * (1.0 - dirt)
	for k in 900:
		var x := rng.randi() % s
		var y := rng.randi() % s
		var ang := rng.randf() * TAU
		var l := rng.randi_range(2, 5)
		var br := rng.randf_range(1.1, 1.6)
		for t in l:
			var i := posmod(y + int(sin(ang) * t), s) * s + posmod(x + int(cos(ang) * t), s)
			col[i * 3] *= br
			col[i * 3 + 1] *= br
			col[i * 3 + 2] *= br * 0.9
			hgt[i] = 0.85
	return _tile_tex(s, col, hgt, 3.0)


func _roof() -> CanvasTexture:
	var s := 128
	var a := _sn(s, 0.05, 3)
	var b := _sn(s, 0.7, 1)
	var col := PackedFloat32Array()
	col.resize(s * s * 3)
	var hgt := PackedFloat32Array()
	hgt.resize(s * s)
	for y in s:
		for x in s:
			var i := y * s + x
			var fa := a[i] / 255.0
			var fb := b[i] / 255.0
			var v := 0.25 + (fa - 0.5) * 0.08 + (fb - 0.5) * 0.14
			var h := 0.5 + (fb - 0.5) * 0.6
			if y % 42 < 3:
				v *= 0.6
				h = 0.75
			col[i * 3] = v * 0.95
			col[i * 3 + 1] = v * 0.97
			col[i * 3 + 2] = v * 1.05
			hgt[i] = h
	return _tile_tex(s, col, hgt, 3.5)


# ------------------------------------------------------------------ luces, sangre

func _lights() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	light_round = gt

	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var dx := (x + 0.5 - s * 0.5) / (s * 0.5)
			var dy := (y + 0.5 - s * 0.5) / (s * 0.5)
			var r := sqrt(dx * dx + dy * dy)
			var ang := absf(atan2(dy, dx))
			var cone := (1.0 - smoothstep(0.26, 0.42, ang)) * (1.0 - smoothstep(0.45, 1.0, r)) * smoothstep(0.02, 0.1, r)
			cone *= 0.85 + 0.15 * sin(r * 40.0)
			var glow := (1.0 - smoothstep(0.0, 0.2, r)) * 0.55
			var v := clampf(maxf(cone, glow), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, v))
	light_cone = ImageTexture.create_from_image(img)

	var vg := Gradient.new()
	vg.set_color(0, Color(1, 1, 1, 0))
	vg.set_color(1, Color(1, 1, 1, 1))
	vg.add_point(0.55, Color(1, 1, 1, 0))
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.05, 0.5)
	vt.width = 256
	vt.height = 256
	vignette = vt


func _splats() -> void:
	var p := Pic.new(SPLAT * SPLAT_N, SPLAT)
	for k in SPLAT_N:
		var cx := k * SPLAT + SPLAT * 0.5
		var cy := SPLAT * 0.5
		var base := rng.randf_range(11.0, 17.0)
		var ox := rng.randf() * 100.0
		for y in SPLAT:
			for x in range(k * SPLAT, (k + 1) * SPLAT):
				var dx := x + 0.5 - cx
				var dy := y + 0.5 - cy
				var d := sqrt(dx * dx + dy * dy)
				var ang := atan2(dy, dx)
				var rr := base * (0.75 + 0.45 * nz.get_noise_2d(cos(ang) * 1.6 + ox, sin(ang) * 1.6))
				rr *= 1.0 + 0.35 * maxf(0.0, cos(ang))
				if d < rr + 1.0:
					var a := clampf(rr - d + 0.5, 0.0, 1.0) * (0.8 + 0.2 * nz.get_noise_2d(x * 0.3, y * 0.3))
					var v := 0.75 + 0.25 * (1.0 - d / maxf(rr, 1.0))
					p.put(y * p.w + x, Color(v, v, v), a, 0.5)
		for j in rng.randi_range(8, 16):
			var ang := rng.randf_range(-1.3, 1.3) if rng.randf() < 0.7 else rng.randf() * TAU
			var dist := rng.randf_range(base * 1.0, 29.0)
			var dr := rng.randf_range(1.0, 3.2)
			var px := cx + cos(ang) * dist
			var py := cy + sin(ang) * dist
			if absf(px - cx) < 30.0 and absf(py - cy) < 30.0:
				blob(p, px, py, dr * 1.6, dr, Color(0.9, 0.9, 0.9, 0.9), 0.1, 0.4, 0.2, 0.5, ang)
	var data := PackedByteArray()
	data.resize(p.w * p.h * 4)
	for i in p.w * p.h:
		var col: Color = p.c[i]
		data[i * 4] = clampi(int(col.r * 255.0), 0, 255)
		data[i * 4 + 1] = clampi(int(col.g * 255.0), 0, 255)
		data[i * 4 + 2] = clampi(int(col.b * 255.0), 0, 255)
		data[i * 4 + 3] = clampi(int(col.a * 255.0), 0, 255)
	var img := Image.create_from_data(p.w, p.h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	splats = ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ infectados (por partes, para desmembrar)

func _zombie_set(skin: Color, shirt: Color, pants: Color, hair: Color, kind: String) -> Dictionary:
	return {
		"head": _z_head(skin, hair, kind),
		"torso": _z_torso(skin, shirt, kind),
		"arm": _z_arm(skin, shirt, kind),
		"leg": _z_leg(pants, kind),
	}


func _blood_spots(p: Pic, cx: float, cy: float, rx: float, ry: float, n: int) -> void:
	for k in n:
		blob(p, cx + rng.randf_range(-rx, rx), cy + rng.randf_range(-ry, ry), rng.randf_range(2.5, 7.0), rng.randf_range(2.0, 5.0), Color(0.3, 0.02, 0.02, 0.85), 0.35, 0.4, 0.1, -1.0, rng.randf() * PI, -0.3, true)


func _z_head(skin: Color, hair: Color, kind: String) -> CanvasTexture:
	var p := Pic.new(36, 36)
	if kind == "corredor":
		blob(p, 17, 18, 15, 14, hair, 0.25, 0.25, 0.7, 1.0)
		blob(p, 23, 18, 8.5, 9.0, skin, 0.2, 0.4, 0.7, 0.9)
		blob(p, 27, 18, 3.5, 6.0, Color(0.08, 0.02, 0.02), 0.2, 0.5, 0.3, 0.5)
		return to_tex(p, 3.0)
	blob(p, 17, 5.5, 3.0, 2.4, skin * 0.85, 0.1, 0.4, 0.5, 0.5)
	blob(p, 17, 30.5, 3.0, 2.4, skin * 0.85, 0.1, 0.4, 0.5, 0.5)
	blob(p, 18, 18, 13.5, 12.5, skin, 0.25, 0.3, 0.7, 1.0)
	blob(p, 29.5, 18, 2.6, 2.4, skin * 0.8, 0.1, 0.5, 0.4, 1.0)
	match kind:
		"chillon":
			blob(p, 15, 18, 14.5, 14, hair, 0.35, 0.7, 0.4, 1.0)
			for k in 10:
				var yy := rng.randf_range(6, 30)
				line(p, 22, yy, 3, yy + rng.randf_range(-3, 3), 1.0, Color(0.15, 0.15, 0.17, 0.8))
			blob(p, 30, 18, 3.2, 4.2, Color(0.1, 0.0, 0.0), 0.1, 0.5, 0.2, 0.2)
		"bruto":
			blob(p, 20, 18, 6, 8, skin * 0.8, 0.2, 0.5, 0.3, 1.0)
		_:
			blob(p, 14, 18, 11, 11.5, hair, 0.4, 0.5, 0.5, 1.05, 0.0, 0.0)
	_blood_spots(p, 18, 18, 9, 9, 2)
	return to_tex(p, 3.0)


func _z_torso(skin: Color, shirt: Color, kind: String) -> CanvasTexture:
	var p := Pic.new(64, 72)
	var cx := 30.0
	var cy := 36.0
	match kind:
		"hinchado":
			blob(p, cx - 2, cy, 26, 32, skin, 0.3, 0.15, 0.8, 1.0)
			for k in 26:
				var a := rng.randf() * TAU
				var d := rng.randf_range(0.0, 0.85)
				blob(p, cx - 2 + cos(a) * 24 * d, cy + sin(a) * 30 * d, rng.randf_range(1.5, 3.5), rng.randf_range(1.5, 3.5), Color(0.78, 0.8, 0.4), 0.2, 0.6, 0.9, 1.0, 0.0, -2.0, true)
			for k in 8:
				var a := rng.randf() * TAU
				line(p, cx, cy, cx + cos(a) * 24, cy + sin(a) * 30, 1.0, Color(0.3, 0.12, 0.2, 0.7))
			blob(p, cx - 2, cy, 24, 30, shirt * Color(1, 1, 1, 0.9), 0.3, 0.25, 0.4, -1.0, 0.0, 0.25, true)
		"bruto":
			blob(p, cx, cy, 17, 30, skin, 0.25, 0.25, 0.8, 0.9)
			blob(p, cx + 5, cy - 10, 9, 10, skin * 1.08, 0.2, 0.3, 0.8, 1.0)
			blob(p, cx + 5, cy + 10, 9, 10, skin * 1.08, 0.2, 0.3, 0.8, 1.0)
			blob(p, cx - 2, cy - 22, 9, 8, skin * 1.05, 0.2, 0.3, 0.8, 1.0)
			blob(p, cx - 2, cy + 22, 9, 8, skin * 1.05, 0.2, 0.3, 0.8, 1.0)
			for k in 5:
				var yy := rng.randf_range(cy - 22, cy + 22)
				line(p, cx - 10, yy, cx + 10, yy + rng.randf_range(-8, 8), 1.4, Color(0.55, 0.25, 0.28, 0.8), 0.3)
			blob(p, cx - 6, cy, 8, 22, pants_belt(), 0.2, 0.3, 0.3, 0.6, 0.0, -2.0, true)
		_:
			blob(p, cx, cy, 15, 27, skin, 0.25, 0.3, 0.8, 0.85)
			var holes := -0.45 if kind != "chillon" else -0.7
			blob(p, cx, cy, 16, 28, shirt, 0.3, 0.18, 0.75, 0.9, 0.0, holes)
			for k in 6:
				var yy := rng.randf_range(cy - 22, cy + 22)
				line(p, cx + rng.randf_range(-12, 4), yy, cx + rng.randf_range(4, 12), yy + rng.randf_range(-6, 6), 1.3, Color(shirt.r * 0.5, shirt.g * 0.5, shirt.b * 0.5, 0.6))
			if kind == "corredor":
				blob(p, cx - 9, cy, 6, 11, shirt * 0.8, 0.2, 0.4, 0.5, 0.95)
	blob(p, cx + 10, cy, 6, 7.5, skin * 0.75, 0.2, 0.4, 0.6, 0.7)
	_blood_spots(p, cx, cy, 12, 22, rng.randi_range(2, 5))
	return to_tex(p, 3.0)


func pants_belt() -> Color:
	return Color(0.22, 0.2, 0.18)


func _z_arm(skin: Color, shirt: Color, kind: String) -> CanvasTexture:
	var p := Pic.new(56, 20)
	var r := 6.0
	if kind == "bruto":
		r = 8.0
	elif kind == "hinchado":
		r = 6.5
	capsule(p, 6, 10, 42, 10, r, skin, 0.25, 0.35, 0.7, 0.8)
	if kind != "bruto":
		capsule(p, 6, 10, 21, 10, r + 1.0, shirt, 0.25, 0.3, 0.7, 0.9)
	blob(p, 46, 10, 6.5, 6.0, skin * 0.92, 0.2, 0.4, 0.7, 0.9)
	for k in 4:
		var yy := 6.0 + k * 2.7
		line(p, 48, yy, 54, yy + (yy - 10.0) * 0.3, 1.6, Color(skin.r * 0.55, skin.g * 0.55, skin.b * 0.55, 0.9), 0.6)
	_blood_spots(p, 36, 10, 12, 3, 2)
	return to_tex(p, 3.0)


func _z_leg(pants: Color, kind: String) -> CanvasTexture:
	var p := Pic.new(48, 22)
	var r := 7.5 if kind != "bruto" else 9.0
	capsule(p, 5, 11, 33, 11, r, pants, 0.25, 0.3, 0.7, 0.7)
	blob(p, 37, 11, 8.0, 6.5, Color(0.12, 0.1, 0.09), 0.2, 0.5, 0.6, 0.6)
	_blood_spots(p, 22, 11, 12, 4, 1)
	return to_tex(p, 3.0)


func _stump() -> CanvasTexture:
	var p := Pic.new(24, 24)
	blob(p, 12, 12, 8.5, 8.5, Color(0.45, 0.03, 0.03), 0.4, 0.5, 0.6, 0.8, 0.0, -0.6)
	blob(p, 12, 12, 5.5, 5.5, Color(0.6, 0.06, 0.05), 0.3, 0.6, 0.6, 0.9)
	blob(p, 12, 12, 2.6, 2.6, Color(0.9, 0.86, 0.75), 0.1, 0.5, 0.5, 1.0)
	return to_tex(p, 3.0)


# ------------------------------------------------------------------ superviviente y armas

func _player() -> void:
	var p := Pic.new(72, 64)
	var cx := 30.0
	var cy := 32.0
	var jacket := Color(0.27, 0.32, 0.2)
	var skin := Color(0.85, 0.66, 0.5)
	blob(p, cx - 11, cy, 9, 15, Color(0.32, 0.22, 0.13), 0.25, 0.3, 0.7, 0.8)
	rrect(p, cx - 17, cy - 9, cx - 9, cy + 9, 3, Color(0.25, 0.17, 0.1), 0.2, 0.3, 3.0, 0.85)
	blob(p, cx, cy, 14, 24, jacket, 0.28, 0.25, 0.75, 0.9)
	for k in 4:
		var yy := rng.randf_range(cy - 18, cy + 18)
		line(p, cx - 8, yy, cx + 8, yy + rng.randf_range(-5, 5), 1.2, Color(0.15, 0.18, 0.1, 0.6))
	capsule(p, cx + 2, cy - 19, cx + 25, cy - 5, 5.5, jacket * 0.95, 0.25, 0.3, 0.7, 0.85)
	capsule(p, cx + 2, cy + 19, cx + 25, cy + 5, 5.5, jacket * 0.95, 0.25, 0.3, 0.7, 0.85)
	blob(p, cx + 27, cy - 4, 4.5, 4.0, skin, 0.1, 0.4, 0.6, 0.9)
	blob(p, cx + 27, cy + 4, 4.5, 4.0, skin, 0.1, 0.4, 0.6, 0.9)
	blob(p, cx + 2, cy, 11.5, 11, skin, 0.15, 0.3, 0.7, 1.0)
	blob(p, cx, cy, 11, 10.8, Color(0.2, 0.13, 0.08), 0.35, 0.6, 0.6, 1.05)
	capsule(p, cx - 1, cy - 10, cx - 1, cy + 10, 2.0, Color(0.6, 0.1, 0.08), 0.2, 0.4, 0.5, 1.1)
	player["torso"] = to_tex(p, 3.0)
	var l := Pic.new(48, 22)
	capsule(l, 5, 11, 32, 11, 7.0, Color(0.16, 0.2, 0.32), 0.25, 0.3, 0.7, 0.7)
	rrect(l, 30, 4, 45, 18, 5, Color(0.18, 0.13, 0.09), 0.2, 0.4, 3.0, 0.7)
	player["leg"] = to_tex(l, 3.0)


func _guns() -> void:
	var metal := Color(0.22, 0.23, 0.25)
	var p := Pic.new(32, 12)
	rrect(p, 0, 2, 30, 10, 2, metal, 0.1, 0.5, 2.0, 0.8)
	rrect(p, 2, 3, 26, 7, 1, metal * 1.5, 0.1, 0.5, 1.5, 0.9)
	guns["pistola"] = to_tex(p, 3.0)
	p = Pic.new(50, 18)
	rrect(p, 0, 4, 18, 14, 3, Color(0.42, 0.28, 0.15), 0.3, 0.15, 3.0, 0.7, false, Vector2(0.2, 2.0))
	rrect(p, 14, 6, 34, 12, 2, metal, 0.1, 0.5, 2.0, 0.85)
	rrect(p, 22, 2, 30, 16, 2, Color(0.12, 0.12, 0.13), 0.1, 0.5, 2.0, 0.6)
	rrect(p, 30, 6, 48, 10, 1, metal * 1.4, 0.1, 0.5, 1.0, 0.9)
	line(p, 12, 9, 22, 9, 0.8, Color(0.1, 0.1, 0.1, 0.8))
	guns["ballesta"] = to_tex(p, 3.0)
	p = Pic.new(60, 14)
	rrect(p, 0, 3, 22, 11, 3, Color(0.4, 0.24, 0.12), 0.3, 0.12, 3.0, 0.7, false, Vector2(0.2, 2.0))
	rrect(p, 18, 4, 58, 10, 2, metal, 0.1, 0.5, 2.0, 0.9)
	rrect(p, 30, 3, 44, 11, 2, Color(0.35, 0.22, 0.12), 0.3, 0.2, 2.0, 0.8)
	guns["escopeta"] = to_tex(p, 3.0)
	p = Pic.new(58, 18)
	rrect(p, 0, 4, 16, 14, 2, Color(0.1, 0.1, 0.11), 0.1, 0.5, 2.0, 0.7)
	rrect(p, 14, 5, 44, 13, 2, Color(0.14, 0.15, 0.16), 0.1, 0.5, 2.0, 0.85)
	rrect(p, 26, 12, 33, 18, 1, Color(0.1, 0.1, 0.1), 0.1, 0.5, 1.0, 0.7)
	rrect(p, 40, 7, 56, 11, 1, metal * 1.3, 0.1, 0.5, 1.0, 0.9)
	rrect(p, 20, 6, 32, 9, 1, Color(0.05, 0.05, 0.05), 0.1, 0.5, 1.0, 1.0)
	guns["fusil"] = to_tex(p, 3.0)
	p = Pic.new(44, 10)
	rrect(p, 0, 3, 12, 7, 2, Color(0.08, 0.08, 0.08), 0.2, 0.5, 2.0, 0.7)
	rrect(p, 11, 2, 43, 8, 3, Color(0.7, 0.72, 0.75), 0.15, 0.2, 2.0, 0.9, false, Vector2(0.1, 1.0))
	line(p, 12, 3, 41, 4, 1.0, Color(1, 1, 1, 0.6))
	machete = to_tex(p, 3.0)


# ------------------------------------------------------------------ escenario

func _car(col: Color) -> CanvasTexture:
	var p := Pic.new(184, 88)
	rrect(p, 4, 6, 180, 82, 18, col, 0.12, 0.08, 14.0, 0.6)
	rrect(p, 150, 10, 178, 78, 12, col * 0.92, 0.1, 0.1, 8.0, -1.0, true)
	line(p, 150, 14, 150, 74, 1.2, Color(0, 0, 0, 0.35))
	line(p, 40, 8, 40, 80, 1.0, Color(0, 0, 0, 0.3))
	rrect(p, 112, 14, 136, 74, 8, Color(0.08, 0.11, 0.14), 0.15, 0.3, 4.0, 0.75)
	rrect(p, 116, 18, 124, 70, 3, Color(0.4, 0.5, 0.6, 0.35), 0.1, 0.3, 2.0, -1.0)
	rrect(p, 36, 16, 54, 72, 6, Color(0.08, 0.11, 0.14), 0.15, 0.3, 4.0, 0.75)
	rrect(p, 54, 14, 112, 74, 6, col * 1.08, 0.1, 0.12, 8.0, 1.0)
	for k in 4:
		var y0 := rng.randf_range(20, 68)
		line(p, 120 + rng.randf_range(0, 6), y0, 132, y0 + rng.randf_range(-10, 10), 0.8, Color(0.8, 0.85, 0.9, 0.5))
	rrect(p, 172, 12, 180, 24, 3, Color(1.0, 0.95, 0.75), 0.05, 0.5, 2.0, 0.7)
	rrect(p, 172, 64, 180, 76, 3, Color(1.0, 0.95, 0.75), 0.05, 0.5, 2.0, 0.7)
	rrect(p, 4, 12, 10, 24, 2, Color(0.7, 0.05, 0.05), 0.05, 0.5, 2.0, 0.7)
	rrect(p, 4, 64, 10, 76, 2, Color(0.7, 0.05, 0.05), 0.05, 0.5, 2.0, 0.7)
	blob(p, 132, 3.5, 5, 3, col * 0.8, 0.1, 0.5, 0.6, 0.6)
	blob(p, 132, 84.5, 5, 3, col * 0.8, 0.1, 0.5, 0.6, 0.6)
	for k in rng.randi_range(3, 7):
		var px := rng.randf_range(10, 175)
		var py := rng.randf_range(8, 80)
		blob(p, px, py, rng.randf_range(4, 12), rng.randf_range(3, 8), Color(0.36, 0.2, 0.1, 0.85), 0.5, 0.35, 0.2, 0.4, rng.randf() * PI, 0.0, true)
	for k in 6:
		var y0 := rng.randf_range(8, 80)
		var x0 := rng.randf_range(10, 170)
		line(p, x0, y0, x0 + rng.randf_range(-20, 20), y0 + rng.randf_range(-4, 4), 0.7, Color(0.85, 0.85, 0.85, 0.35))
	return to_tex(p, 4.0)


func _crate() -> CanvasTexture:
	var p := Pic.new(64, 64)
	var wood := Color(0.45, 0.32, 0.18)
	rrect(p, 1, 1, 63, 63, 3, wood, 0.35, 0.15, 4.0, 0.7, false, Vector2(0.15, 1.5))
	for k in 4:
		var x := 2.0 + k * 15.0
		line(p, x, 3, x, 61, 1.5, Color(0.15, 0.09, 0.05, 0.8), 0.3)
	rrect(p, 1, 1, 63, 9, 2, wood * 0.85, 0.3, 0.2, 3.0, 0.9, false, Vector2(1.5, 0.15))
	rrect(p, 1, 55, 63, 63, 2, wood * 0.85, 0.3, 0.2, 3.0, 0.9, false, Vector2(1.5, 0.15))
	line(p, 6, 10, 58, 54, 7.0, Color(0.38, 0.27, 0.15), 0.85)
	for c in [Vector2(5, 5), Vector2(59, 5), Vector2(5, 59), Vector2(59, 59)]:
		blob(p, c.x, c.y, 1.6, 1.6, Color(0.6, 0.6, 0.6), 0.1, 0.5, 0.5, 1.0)
	return to_tex(p, 3.0)


func _barrel() -> CanvasTexture:
	var p := Pic.new(44, 44)
	blob(p, 22, 22, 21, 21, Color(0.62, 0.1, 0.06), 0.2, 0.3, 0.5, 0.8)
	blob(p, 22, 22, 17, 17, Color(0.5, 0.08, 0.05), 0.2, 0.3, 0.3, 0.7)
	blob(p, 22, 22, 14, 14, Color(0.62, 0.1, 0.06), 0.2, 0.3, 0.3, 0.75)
	blob(p, 22, 22, 9.5, 9.5, Color(0.85, 0.7, 0.1), 0.1, 0.4, 0.2, 0.8, 0.0, -0.3)
	blob(p, 22, 22, 7, 7, Color(0.62, 0.1, 0.06), 0.1, 0.4, 0.2, 0.8)
	blob(p, 14, 18, 3, 3, Color(0.3, 0.3, 0.3), 0.1, 0.5, 0.6, 1.0)
	for k in 3:
		blob(p, rng.randf_range(8, 36), rng.randf_range(8, 36), rng.randf_range(3, 6), rng.randf_range(2, 4), Color(0.3, 0.17, 0.08, 0.8), 0.5, 0.4, 0.1, -1.0, rng.randf() * PI, 0.0, true)
	return to_tex(p, 3.0)


func _barrier() -> CanvasTexture:
	var p := Pic.new(96, 28)
	rrect(p, 1, 1, 95, 27, 6, Color(0.55, 0.54, 0.5), 0.2, 0.2, 9.0, 0.8)
	for k in 4:
		var x := 6.0 + k * 6.0
		line(p, x, 2, x + 6, 26, 3.0, Color(0.75, 0.1, 0.08, 0.85))
		line(p, 90 - x, 2, 84 - x, 26, 3.0, Color(0.75, 0.1, 0.08, 0.85))
	return to_tex(p, 3.0)


func _dumpster() -> CanvasTexture:
	var p := Pic.new(112, 64)
	rrect(p, 1, 1, 111, 63, 5, Color(0.14, 0.32, 0.2), 0.2, 0.15, 5.0, 0.8)
	for k in 6:
		var x := 10.0 + k * 18.0
		line(p, x, 4, x, 60, 2.0, Color(0.05, 0.12, 0.07, 0.8), 0.95)
	line(p, 56, 2, 56, 62, 2.5, Color(0.05, 0.08, 0.05, 0.9), 0.4)
	for k in 5:
		blob(p, rng.randf_range(6, 106), rng.randf_range(6, 58), rng.randf_range(4, 10), rng.randf_range(3, 6), Color(0.38, 0.2, 0.08, 0.85), 0.5, 0.3, 0.1, -1.0, rng.randf() * PI, 0.0, true)
	return to_tex(p, 3.0)


func _tree() -> CanvasTexture:
	var p := Pic.new(128, 128)
	for k in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 34.0)
		var r := rng.randf_range(18.0, 30.0)
		var g := Color(0.09, 0.2, 0.08) * rng.randf_range(0.75, 1.35)
		blob(p, 64 + cos(a) * d, 64 + sin(a) * d, r, r * rng.randf_range(0.8, 1.1), g, 0.6, 0.22, 0.8, 1.0, rng.randf() * PI, -0.5)
	for k in 40:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 50.0)
		blob(p, 64 + cos(a) * d, 64 + sin(a) * d, 4, 3, Color(0.18, 0.32, 0.12), 0.4, 0.5, 0.8, 1.0, rng.randf() * PI, -2.0, true)
	return to_tex(p, 5.0)


func _fountain() -> CanvasTexture:
	var p := Pic.new(160, 160)
	blob(p, 80, 80, 78, 78, Color(0.5, 0.48, 0.44), 0.25, 0.2, 0.3, 0.9)
	blob(p, 80, 80, 66, 66, Color(0.06, 0.12, 0.16), 0.3, 0.12, 0.2, 0.15)
	for k in 5:
		var r := 20.0 + k * 9.0
		for t in 48:
			var a := t * TAU / 48.0
			blob(p, 80 + cos(a) * r, 80 + sin(a) * r, 1.6, 1.0, Color(0.3, 0.4, 0.45, 0.35), 0.1, 0.5, 0.1, -1.0, a + PI * 0.5, -2.0, true)
	blob(p, 80, 80, 16, 16, Color(0.55, 0.52, 0.48), 0.25, 0.3, 0.7, 1.0)
	blob(p, 80, 80, 8, 8, Color(0.62, 0.6, 0.55), 0.2, 0.3, 0.7, 1.0)
	return to_tex(p, 3.0)


func _acunit() -> CanvasTexture:
	var p := Pic.new(48, 48)
	rrect(p, 1, 1, 47, 47, 4, Color(0.55, 0.56, 0.57), 0.15, 0.2, 5.0, 0.9)
	blob(p, 24, 24, 16, 16, Color(0.18, 0.18, 0.19), 0.1, 0.4, 0.2, 0.6)
	for k in 5:
		var a := k * TAU / 5.0
		capsule(p, 24, 24, 24 + cos(a) * 13, 24 + sin(a) * 13, 3.0, Color(0.45, 0.46, 0.48), 0.1, 0.4, 0.4, 0.8)
	blob(p, 24, 24, 4, 4, Color(0.6, 0.6, 0.6), 0.1, 0.5, 0.5, 1.0)
	return to_tex(p, 3.0)


func _lamp() -> CanvasTexture:
	var p := Pic.new(48, 20)
	capsule(p, 4, 10, 36, 10, 3.0, Color(0.2, 0.2, 0.22), 0.1, 0.5, 0.6, 0.8)
	rrect(p, 30, 3, 46, 17, 4, Color(0.35, 0.35, 0.37), 0.1, 0.4, 3.0, 1.0)
	rrect(p, 33, 6, 43, 14, 2, Color(1.0, 0.9, 0.65), 0.05, 0.5, 2.0, 1.0)
	return to_tex(p, 3.0)


func _items() -> void:
	var p := Pic.new(40, 30)
	rrect(p, 1, 1, 39, 29, 3, Color(0.3, 0.33, 0.18), 0.2, 0.3, 4.0, 0.8)
	for k in 5:
		blob(p, 9 + k * 5.5, 15, 2.2, 2.2, Color(0.85, 0.65, 0.2), 0.1, 0.5, 0.6, 1.0)
	items["ammo"] = to_tex(p, 3.0)
	p = Pic.new(34, 34)
	rrect(p, 1, 1, 33, 33, 5, Color(0.9, 0.9, 0.88), 0.1, 0.3, 4.0, 0.8)
	rrect(p, 13, 6, 21, 28, 1, Color(0.8, 0.08, 0.06), 0.05, 0.3, 2.0, 0.95)
	rrect(p, 6, 13, 28, 21, 1, Color(0.8, 0.08, 0.06), 0.05, 0.3, 2.0, 0.95)
	items["med"] = to_tex(p, 3.0)
	p = Pic.new(36, 14)
	capsule(p, 4, 7, 26, 7, 4.5, Color(0.8, 0.1, 0.08), 0.1, 0.4, 0.6, 0.8)
	capsule(p, 26, 7, 32, 7, 3.5, Color(0.9, 0.85, 0.7), 0.1, 0.4, 0.6, 0.9)
	items["flare"] = to_tex(p, 3.0)
	p = Pic.new(36, 18)
	capsule(p, 5, 9, 29, 9, 6.5, Color(0.42, 0.42, 0.4), 0.15, 0.3, 0.7, 0.8)
	rrect(p, 12, 2, 18, 16, 1, Color(0.6, 0.5, 0.15), 0.1, 0.4, 2.0, 0.95)
	blob(p, 31, 9, 3.5, 3.5, Color(0.25, 0.25, 0.25), 0.1, 0.4, 0.5, 0.9)
	line(p, 15, 9, 33, 4, 1.0, Color(0.8, 0.1, 0.1))
	items["bomb"] = to_tex(p, 3.0)
