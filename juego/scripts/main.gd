extends Node2D
# HORDA CERO - shooter de supervivencia con vista cenital (twin-stick) para Android.
# Todo (texturas, sonidos y la ciudad) se genera por codigo al arrancar.
#
# Mecanicas principales:
# - Desmembramiento: cada disparo impacta en una parte concreta del infectado.
# - Ruido: cada arma hace ruido; el ruido despierta a los infectados y llena el medidor de
#   ALERTA. Si se llena, llega una horda. La ballesta y el machete son silenciosos.
# - Senuelos: bengalas, bombas de tubo y alarmas de coche atraen a los infectados.

const TexLib = preload("res://scripts/tex.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ZombieScript = preload("res://scripts/zombie.gd")
const ThrowScript = preload("res://scripts/throwable.gd")
const FxScript = preload("res://scripts/fx.gd")
const HudScript = preload("res://scripts/hud.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const Dbg = preload("res://scripts/debug.gd")

const WORLD := 2560.0
const CELL := 32.0
const GW := 80
const STREET := 220.0
const BLOCK := 560.0
const L_WALL := 1
const L_PLAYER := 2
const L_ZOMBIE := 4
const BLOOD := Color(0.5, 0.03, 0.03, 0.92)
const ACID := Color(0.4, 0.6, 0.08, 0.85)
const SCORCH := Color(0.02, 0.02, 0.02, 0.75)
const MAX_DECALS := 280
const MAX_GIBS := 60
const MAX_CORPSES := 40

const UPGRADES := {
	"escopeta": {"t": "Escopeta", "d": "8 perdigones que arrancan\nextremidades. Muy ruidosa.", "max": 1},
	"fusil": {"t": "Fusil automático", "d": "Cadencia altísima y 30 balas\npor cargador.", "max": 1},
	"dano": {"t": "Munición pesada", "d": "+20% de daño con\ntodas las armas.", "max": 3},
	"cargador": {"t": "Cargadores ampliados", "d": "+40% de capacidad\nen cada cargador.", "max": 2},
	"recarga": {"t": "Manos rápidas", "d": "Recargas un 30%\nmás rápido.", "max": 2},
	"silenciador": {"t": "Silenciador", "d": "Pistola y fusil hacen\nun 60% menos de ruido.", "max": 1},
	"desmembrar": {"t": "Carnicero", "d": "+50% de daño\na las extremidades.", "max": 2},
	"perforar": {"t": "Balas perforantes", "d": "Cada bala atraviesa\na un infectado más.", "max": 2},
	"machete": {"t": "Machete afilado", "d": "Golpes más rápidos,\nmás daño y alcance.", "max": 2},
	"bengalas": {"t": "Pirotecnia", "d": "+2 bengalas y duran\nun 50% más.", "max": 3},
	"bombas": {"t": "Bomba casera", "d": "+2 bombas de tubo con\nexplosión más grande.", "max": 3},
	"vida": {"t": "Chaleco", "d": "+25 de vida máxima\ny curación completa.", "max": 3},
	"botas": {"t": "Zapatillas", "d": "+10% de velocidad y\nesquivas más a menudo.", "max": 2},
	"sigilo": {"t": "Pasos sigilosos", "d": "Los infectados tardan\nmás en detectarte.", "max": 2},
	"iman": {"t": "Mochila grande", "d": "Recoges objetos de más lejos\ny los infectados sueltan más.", "max": 1},
}

static var tex_cache = null
static var autostart := false
static var settings := {}

var tex
var sfx
var hud
var player
var world: Node2D
var cam: Camera2D
var fx_layer: CanvasLayer
var fx_top
var fx_ground
var pick_root: Node2D
var ground: Node2D
var ground_cmds: Array = []
var decal_node: Node2D
var decals: Array = []
var gib_node: Node2D
var gibs: Array = []
var corpses: Array = []
var pickups: Array = []
var lures: Array = []
var bullets: Array = []
var barrels: Array = []
var alarm_cars: Array = []
var flicker: Array = []
var blocked := PackedByteArray()
var spawn_cells: Array = []
var free_cells: Array = []
var pfield := PackedInt32Array()
var pfield_t := 0.0
var pcell := Vector2i(-1, -1)
var rng := RandomNumberGenerator.new()
var shake := 0.0
var blink_t := 0.0

var playing := false
var over := false
var wave := 0
var to_spawn := 0
var specials: Array = []
var spawn_t := 0.0
var wave_clear_t := -1.0
var next_wave_t := -1.0
var stall_t := 0.0
var alert := 0.0
var quiet_t := 0.0
var score := 0
var kills := 0
var headshots := 0
var limbs := 0
var time_played := 0.0
var best := 0
var upgrades := {}
var debug
var prof := {"ia": 0, "campo": 0, "balas": 0, "restos": 0, "efectos": 0, "hud": 0}
var fs_t := 0.0
var bfs_q := PackedInt32Array()
# Campo del jugador: se calcula entero (todo el mapa) pero repartido en varios fotogramas.
var pf_build := PackedInt32Array()
var pf_q := PackedInt32Array()
var pf_head := 0
var pf_tail := 0
var pf_active := false
var lamp_lights: Array = []
var cull_t := 0.0


func _ready() -> void:
	rng.randomize()
	_load_settings()
	Dbg.init_session()
	Dbg.enabled = settings["depuracion"]
	ensure_fullscreen()
	apply_resolution()
	sfx = SfxScript.new()
	add_child(sfx)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HudScript.new()
	layer.add_child(hud)
	hud.setup(self)
	debug = Dbg.new()
	layer.add_child(debug)
	debug.setup(self)
	best = _load_best()
	if tex_cache == null:
		hud.show_loading()
		await get_tree().process_frame
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		var t = TexLib.new()
		t.relief = settings["relieve"]
		t.build()
		tex_cache = t
		Dbg.tex_ms = Time.get_ticks_msec() - t0
		Dbg.note("INFO", "Texturas generadas en %d ms" % Dbg.tex_ms)
	tex = tex_cache
	var tb := Time.get_ticks_msec()
	_build_world()
	Dbg.note("INFO", "Ciudad construida en %d ms" % (Time.get_ticks_msec() - tb))
	if autostart:
		autostart = false
		start_game()
	else:
		hud.show_menu()
		for i in 10:
			_spawn_zombie("comun", _random_free(Vector2(WORLD * 0.5, WORLD * 0.5), 300.0), false)


func up(id: String) -> int:
	return upgrades.get(id, 0)


# ------------------------------------------------------------------ ajustes

func _load_settings() -> void:
	if not settings.is_empty():
		return
	var mobile := OS.has_feature("mobile")
	settings = {"sombras": not mobile, "relieve": true, "vibracion": true, "depuracion": false, "res_reducida": mobile}
	var cf := ConfigFile.new()
	if cf.load("user://ajustes.cfg") == OK:
		for k in settings:
			settings[k] = cf.get_value("ajustes", k, settings[k])


func set_setting(k: String, v) -> void:
	settings[k] = v
	var cf := ConfigFile.new()
	for key in settings:
		cf.set_value("ajustes", key, settings[key])
	cf.save("user://ajustes.cfg")
	Dbg.note("AJUSTE", "%s = %s" % [k, v])
	match k:
		"sombras":
			if player != null:
				player.apply_shadows()
		"relieve":
			if tex != null:
				tex.set_relief(v)
		"depuracion":
			Dbg.enabled = v
			debug.queue_redraw()
		"res_reducida":
			apply_resolution()


# Resolucion reducida: el juego se dibuja a 720 p de alto y se escala a la pantalla.
# En un movil de 2400x1080 son ~2,3 veces menos pixeles que calcular.
func apply_resolution() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if settings["res_reducida"] else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


func ensure_fullscreen() -> void:
	if not OS.has_feature("mobile"):
		return
	var m := DisplayServer.window_get_mode()
	if m != DisplayServer.WINDOW_MODE_FULLSCREEN and m != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		Dbg.note("PANTALLA", "Modo inmersivo reactivado (estaba en: %s)" % Dbg._mode_name(m))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			ensure_fullscreen()
			if what == NOTIFICATION_APPLICATION_RESUMED:
				Dbg.app_paused(false)
		NOTIFICATION_APPLICATION_PAUSED:
			Dbg.app_paused(true)
		NOTIFICATION_WM_CLOSE_REQUEST:
			Dbg.end_session()


func debug_report() -> String:
	var img: Image = Dbg.last_shot
	if img == null:
		img = get_viewport().get_texture().get_image()
	return Dbg.export_report(self, img)


# ------------------------------------------------------------------ construccion del mundo

func _build_world() -> void:
	world = Node2D.new()
	add_child(world)
	var cm := CanvasModulate.new()
	cm.color = Color(0.34, 0.36, 0.5)
	world.add_child(cm)

	ground = Node2D.new()
	ground.z_index = -10
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	world.add_child(ground)
	ground.draw.connect(_draw_ground)
	decal_node = Node2D.new()
	decal_node.z_index = -8
	world.add_child(decal_node)
	decal_node.draw.connect(_draw_decals)
	fx_ground = FxScript.new()
	fx_ground.z_index = -7
	fx_ground.game = self
	world.add_child(fx_ground)
	gib_node = Node2D.new()
	gib_node.z_index = -6
	world.add_child(gib_node)

	fx_layer = CanvasLayer.new()
	fx_layer.layer = 1
	fx_layer.follow_viewport_enabled = true
	add_child(fx_layer)
	pick_root = Node2D.new()
	fx_layer.add_child(pick_root)
	fx_top = FxScript.new()
	fx_top.additive = true
	fx_top.draw_bullets = true
	fx_top.game = self
	fx_layer.add_child(fx_top)

	_gen_map()

	player = PlayerScript.new()
	player.setup(self)
	player.position = Vector2(WORLD * 0.5, WORLD * 0.5 + 130.0)
	world.add_child(player)
	sfx.listener = player

	cam = Camera2D.new()
	cam.zoom = Vector2(1.3, 1.3)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(WORLD)
	cam.limit_bottom = int(WORLD)
	cam.position = player.position
	add_child(cam)
	cam.make_current()
	pfield = compute_field(player.position, GW)


func _gen_map() -> void:
	blocked.resize(GW * GW)
	blocked.fill(0)
	for r in [Rect2(-200, -200, WORLD + 400, 200), Rect2(-200, WORLD, WORLD + 400, 200), Rect2(-200, 0, 200, WORLD), Rect2(WORLD, 0, 200, WORLD)]:
		_solid(r, false)
	ground_cmds.append(["tile", tex.asphalt, Rect2(-300, -300, WORLD + 600, WORLD + 600)])
	_street_marks()
	var kinds := ["edificio", "edificio", "edificio", "edificio", "parque", "parque", "parking", "parking"]
	kinds.shuffle()
	var ki := 0
	for by in 3:
		for bx in 3:
			var r := Rect2(STREET + bx * (BLOCK + STREET), STREET + by * (BLOCK + STREET), BLOCK, BLOCK)
			var k := "plaza"
			if not (bx == 1 and by == 1):
				k = kinds[ki]
				ki += 1
			_block(r, k)
	_street_props()
	_lamps()
	ground.queue_redraw()
	for y in GW:
		for x in GW:
			if blocked[y * GW + x] != 0:
				continue
			var c := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
			free_cells.append(c)
			if c.x < 230.0 or c.y < 230.0 or c.x > WORLD - 230.0 or c.y > WORLD - 230.0:
				spawn_cells.append(c)


func _street_marks() -> void:
	var yellow := Color(0.75, 0.62, 0.22, 0.7)
	var white := Color(0.75, 0.75, 0.72, 0.38)
	for i in 4:
		var c := STREET * 0.5 + i * (BLOCK + STREET)
		var x := 0.0
		while x < WORLD:
			var inter := false
			for j in 4:
				var s0 := j * (BLOCK + STREET)
				if x > s0 - 10.0 and x < s0 + STREET + 10.0:
					inter = true
			if not inter and rng.randf() > 0.08:
				ground_cmds.append(["rect", Color(yellow, yellow.a * rng.randf_range(0.5, 1.0)), Rect2(x, c - 3.0, 34.0, 6.0)])
				ground_cmds.append(["rect", Color(yellow, yellow.a * rng.randf_range(0.5, 1.0)), Rect2(c - 3.0, x, 6.0, 34.0)])
			x += 64.0
	for i in 4:
		for j in 4:
			var ox := i * (BLOCK + STREET)
			var oy := j * (BLOCK + STREET)
			for k in 7:
				var o := 22.0 + k * 26.0
				if i < 3:
					ground_cmds.append(["rect", white, Rect2(ox + STREET + 8.0, oy + o, 46.0, 13.0)])
				if j < 3:
					ground_cmds.append(["rect", white, Rect2(ox + o, oy + STREET + 8.0, 13.0, 46.0)])
			ground_cmds.append(["manhole", Color(0.1, 0.1, 0.11), Vector2(ox + STREET * 0.5 + rng.randf_range(-50, 50), oy + STREET * 0.5 + rng.randf_range(-50, 50))])


func _block(r: Rect2, k: String) -> void:
	ground_cmds.append(["tile", tex.concrete, r])
	ground_cmds.append(["outline", Color(0.55, 0.54, 0.5), r])
	var inner := r.grow(-34.0)
	match k:
		"edificio":
			if rng.randf() < 0.5:
				_building(inner)
			else:
				var vertical := rng.randf() < 0.5
				var cut := rng.randf_range(0.4, 0.6)
				var alley := 70.0
				if vertical:
					var w := inner.size.x * cut - alley * 0.5
					_building(Rect2(inner.position, Vector2(w, inner.size.y)))
					_building(Rect2(inner.position + Vector2(w + alley, 0), Vector2(inner.size.x - w - alley, inner.size.y)))
					_prop("dumpster", Vector2(inner.position.x + w + alley * 0.5, inner.position.y + rng.randf_range(120, inner.size.y - 120)), PI * 0.5)
				else:
					var h := inner.size.y * cut - alley * 0.5
					_building(Rect2(inner.position, Vector2(inner.size.x, h)))
					_building(Rect2(inner.position + Vector2(0, h + alley), Vector2(inner.size.x, inner.size.y - h - alley)))
					_prop("dumpster", Vector2(inner.position.x + rng.randf_range(120, inner.size.x - 120), inner.position.y + h + alley * 0.5), 0.0)
		"parque":
			ground_cmds.append(["tile", tex.grass, inner])
			ground_cmds.append(["outline", Color(0.3, 0.27, 0.22), inner])
			var placed: Array = []
			for t in 40:
				if placed.size() >= 8:
					break
				var p := Vector2(rng.randf_range(inner.position.x + 60, inner.end.x - 60), rng.randf_range(inner.position.y + 60, inner.end.y - 60))
				var ok := true
				for q in placed:
					if p.distance_to(q) < 130.0:
						ok = false
				if ok:
					placed.append(p)
					_tree(p)
			for i in 2:
				_prop("crate", Vector2(rng.randf_range(inner.position.x + 40, inner.end.x - 40), rng.randf_range(inner.position.y + 40, inner.end.y - 40)), rng.randf() * PI)
		"parking":
			ground_cmds.append(["tile", tex.asphalt, inner])
			for row in 2:
				var y := inner.position.y + 70.0 if row == 0 else inner.end.y - 70.0
				var x := inner.position.x + 40.0
				while x < inner.end.x - 30.0:
					ground_cmds.append(["rect", Color(0.8, 0.8, 0.78, 0.5), Rect2(x - 2.0, y - 60.0, 4.0, 120.0)])
					if rng.randf() < 0.6 and x + 70.0 < inner.end.x:
						_car(Vector2(x + 35.0, y + rng.randf_range(-6, 6)), PI * 0.5 + rng.randf_range(-0.08, 0.08) + (PI if rng.randf() < 0.5 else 0.0))
					x += 70.0
			_prop("dumpster", Vector2(inner.get_center().x + rng.randf_range(-100, 100), inner.get_center().y), 0.0)
			_barrel(inner.get_center() + Vector2(rng.randf_range(-150, 150), rng.randf_range(-40, 40)))
		"plaza":
			var c := r.get_center()
			_solid_circle(c, 74.0)
			var f := Sprite2D.new()
			f.texture = tex.fountain
			f.position = c
			world.add_child(f)
			for a in 4:
				var p := c + Vector2.from_angle(a * PI * 0.5 + PI * 0.25) * 190.0
				_prop("crate", p, rng.randf() * PI)
			_barrel(c + Vector2(-210, -40))
			_barrel(c + Vector2(215, 60))


func _building(r: Rect2) -> void:
	_solid(r, true)
	var details: Array = []
	for i in rng.randi_range(1, 4):
		var p := Vector2(rng.randf_range(r.position.x + 24, r.end.x - 54), rng.randf_range(r.position.y + 24, r.end.y - 54))
		details.append(["ac", p])
	for i in rng.randi_range(1, 3):
		details.append(["vent", Vector2(rng.randf_range(r.position.x + 30, r.end.x - 30), rng.randf_range(r.position.y + 30, r.end.y - 30))])
	if r.size.x > 160.0 and r.size.y > 160.0:
		details.append(["stair", Vector2(rng.randf_range(r.position.x + 40, r.end.x - 110), rng.randf_range(r.position.y + 40, r.end.y - 90))])
	var tint := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.05), rng.randf_range(0.85, 1.1))
	var sh := Node2D.new()
	sh.z_index = -4
	world.add_child(sh)
	sh.draw.connect(_draw_shadow.bind(sh, r, Vector2(18, 24)))
	var vis := Node2D.new()
	vis.z_index = 5
	vis.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	world.add_child(vis)
	vis.draw.connect(_draw_building.bind(vis, r, details, tint))


func _draw_shadow(n: Node2D, r: Rect2, o: Vector2) -> void:
	var a := r.position
	var b := r.end
	n.draw_colored_polygon(PackedVector2Array([a, Vector2(b.x, a.y), Vector2(b.x + o.x, a.y + o.y), b + o, Vector2(a.x + o.x, b.y + o.y), Vector2(a.x, b.y)]), Color(0, 0, 0, 0.5))


func _draw_building(n: Node2D, r: Rect2, details: Array, tint: Color) -> void:
	n.draw_texture_rect(tex.roof, r, true, tint)
	var edge := Color(0.42, 0.41, 0.4) * tint
	var w := 10.0
	n.draw_rect(Rect2(r.position, Vector2(r.size.x, w)), edge * 1.15)
	n.draw_rect(Rect2(r.position + Vector2(0, r.size.y - w), Vector2(r.size.x, w)), edge * 0.8)
	n.draw_rect(Rect2(r.position, Vector2(w, r.size.y)), edge * 1.05)
	n.draw_rect(Rect2(r.position + Vector2(r.size.x - w, 0), Vector2(w, r.size.y)), edge * 0.85)
	n.draw_rect(r.grow(-w), Color(0, 0, 0, 0.35), false, 3.0)
	n.draw_rect(r, Color(0, 0, 0, 0.6), false, 2.0)
	for d in details:
		var p: Vector2 = d[1]
		match d[0]:
			"ac":
				n.draw_rect(Rect2(p + Vector2(5, 6), Vector2(30, 30)), Color(0, 0, 0, 0.4))
				n.draw_texture_rect(tex.acunit, Rect2(p, Vector2(30, 30)), false)
			"vent":
				n.draw_circle(p + Vector2(3, 4), 9.0, Color(0, 0, 0, 0.35))
				n.draw_circle(p, 9.0, Color(0.45, 0.45, 0.47))
				n.draw_circle(p, 5.0, Color(0.12, 0.12, 0.13))
			"stair":
				n.draw_rect(Rect2(p + Vector2(8, 10), Vector2(70, 50)), Color(0, 0, 0, 0.4))
				n.draw_rect(Rect2(p, Vector2(70, 50)), Color(0.5, 0.48, 0.45) * tint)
				n.draw_rect(Rect2(p, Vector2(70, 50)), Color(0, 0, 0, 0.5), false, 2.0)
				n.draw_rect(Rect2(p + Vector2(48, 14), Vector2(14, 22)), Color(0.25, 0.18, 0.12))


func _tree(p: Vector2) -> void:
	_solid_circle(p, 12.0, true)
	var s := rng.randf_range(0.85, 1.15)
	var shadow := Sprite2D.new()
	shadow.texture = tex.tree
	shadow.position = p + Vector2(14, 18)
	shadow.scale = Vector2(s, s)
	shadow.modulate = Color(0, 0, 0, 0.45)
	shadow.z_index = -4
	world.add_child(shadow)
	var c := Sprite2D.new()
	c.texture = tex.tree
	c.position = p
	c.scale = Vector2(s, s)
	c.rotation = rng.randf() * TAU
	c.z_index = 6
	c.modulate = Color(1, 1, 1, 0.93)
	world.add_child(c)


func _car(p: Vector2, rot: float) -> void:
	var sb := _body_at(p, rot)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = Vector2(90, 42)
	cs.shape = sh
	sb.add_child(cs)
	_occluder(sb, Vector2(44, 20))
	var txi: CanvasTexture = tex.cars[rng.randi() % tex.cars.size()]
	var shadow := Sprite2D.new()
	shadow.texture = txi
	shadow.position = p + Vector2(6, 8)
	shadow.rotation = rot
	shadow.scale = Vector2(0.5, 0.5)
	shadow.modulate = Color(0, 0, 0, 0.5)
	shadow.z_index = -4
	world.add_child(shadow)
	var sp := Sprite2D.new()
	sp.texture = txi
	sp.scale = Vector2(0.5, 0.5)
	sb.add_child(sp)
	sb.add_to_group("cars")
	var alarm := rng.randf() < 0.35
	sb.set_meta("alarm", alarm)
	if alarm:
		alarm_cars.append(sb)
	_block_rot(p, Vector2(92, 44), rot)


func _prop(kind: String, p: Vector2, rot: float) -> void:
	var size := Vector2(32, 32)
	var txi: CanvasTexture = tex.crate
	match kind:
		"dumpster":
			size = Vector2(56, 32)
			txi = tex.dumpster
		"barrier":
			size = Vector2(48, 14)
			txi = tex.barrier
	var sb := _body_at(p, rot)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = size
	cs.shape = sh
	sb.add_child(cs)
	_occluder(sb, size * 0.5)
	var shadow := Sprite2D.new()
	shadow.texture = txi
	shadow.position = p + Vector2(4, 6)
	shadow.rotation = rot
	shadow.scale = Vector2(0.5, 0.5)
	shadow.modulate = Color(0, 0, 0, 0.45)
	shadow.z_index = -4
	world.add_child(shadow)
	var sp := Sprite2D.new()
	sp.texture = txi
	sp.scale = Vector2(0.5, 0.5)
	sb.add_child(sp)
	_block_rot(p, size, rot)


func _barrel(p: Vector2) -> void:
	var sb := _body_at(p, rng.randf() * TAU)
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 11.0
	cs.shape = c
	sb.add_child(cs)
	var sp := Sprite2D.new()
	sp.texture = tex.barrel
	sp.scale = Vector2(0.5, 0.5)
	sb.add_child(sp)
	sb.add_to_group("barrels")
	sb.set_meta("hp", 30.0)
	barrels.append(sb)
	_block_rect(Rect2(p - Vector2(16, 16), Vector2(32, 32)))


func _street_props() -> void:
	var center := Vector2(WORLD, WORLD) * 0.5
	var n_cars := 0
	var tries := 0
	while n_cars < 14 and tries < 200:
		tries += 1
		var i := rng.randi() % 4
		var c := STREET * 0.5 + i * (BLOCK + STREET)
		var along := rng.randf_range(80.0, WORLD - 80.0)
		var horiz := rng.randf() < 0.5
		var p := Vector2(along, c + rng.randf_range(-55, 55)) if horiz else Vector2(c + rng.randf_range(-55, 55), along)
		if p.distance_to(center) < 300.0 or not _area_free(p, 70.0):
			continue
		var rot := (0.0 if horiz else PI * 0.5) + rng.randf_range(-0.4, 0.4) + (PI if rng.randf() < 0.5 else 0.0)
		_car(p, rot)
		n_cars += 1
	for k in 16:
		var i := rng.randi() % 4
		var c := STREET * 0.5 + i * (BLOCK + STREET)
		var along := rng.randf_range(80.0, WORLD - 80.0)
		var horiz := rng.randf() < 0.5
		var p := Vector2(along, c + rng.randf_range(-80, 80)) if horiz else Vector2(c + rng.randf_range(-80, 80), along)
		if p.distance_to(center) < 280.0 or not _area_free(p, 40.0):
			continue
		var r := rng.randf()
		if r < 0.4:
			_barrel(p)
		elif r < 0.75:
			_prop("barrier", p, (0.0 if horiz else PI * 0.5) + rng.randf_range(-0.6, 0.6))
		else:
			_prop("crate", p, rng.randf() * PI)


func _lamps() -> void:
	var spots: Array = []
	for bx in 3:
		for by in 3:
			var r := Rect2(STREET + bx * (BLOCK + STREET), STREET + by * (BLOCK + STREET), BLOCK, BLOCK)
			spots.append([r.position + Vector2(16, 16), Vector2(-1, -1)])
			spots.append([Vector2(r.end.x - 16, r.position.y + 16), Vector2(1, -1)])
			spots.append([Vector2(r.position.x + 16, r.end.y - 16), Vector2(-1, 1)])
			spots.append([r.end - Vector2(16, 16), Vector2(1, 1)])
	spots.shuffle()
	for i in 11:
		var p: Vector2 = spots[i][0]
		var d: Vector2 = spots[i][1]
		var ang := d.angle()
		var sp := Sprite2D.new()
		sp.texture = tex.lamp
		sp.centered = false
		sp.offset = Vector2(-4, -10)
		sp.position = p
		sp.rotation = ang
		sp.scale = Vector2(0.9, 0.9)
		sp.z_index = 6
		world.add_child(sp)
		var l := PointLight2D.new()
		l.add_to_group("luces")
		l.texture = tex.light_round
		l.texture_scale = 2.3
		l.energy = 1.25
		l.color = Color(1.0, 0.72, 0.42)
		l.height = 120.0
		l.position = p + Vector2.from_angle(ang) * 34.0
		world.add_child(l)
		lamp_lights.append(l)
		if rng.randf() < 0.3:
			flicker.append(l)
		_solid_circle(p, 5.0, false)


func _body_at(p: Vector2, rot: float) -> StaticBody2D:
	var sb := StaticBody2D.new()
	sb.collision_layer = L_WALL
	sb.collision_mask = 0
	sb.position = p
	sb.rotation = rot
	world.add_child(sb)
	return sb


func _occluder(n: Node2D, hs: Vector2) -> void:
	var oc := LightOccluder2D.new()
	var op := OccluderPolygon2D.new()
	op.polygon = PackedVector2Array([-hs, Vector2(hs.x, -hs.y), hs, Vector2(-hs.x, hs.y)])
	oc.occluder = op
	n.add_child(oc)


func _solid(r: Rect2, occlude: bool) -> StaticBody2D:
	var sb := _body_at(r.get_center(), 0.0)
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	sb.add_child(cs)
	if occlude:
		_occluder(sb, r.size * 0.5)
	_block_rect(r.grow(8.0))
	return sb


func _solid_circle(p: Vector2, radius: float, occlude := false) -> void:
	var sb := _body_at(p, 0.0)
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	cs.shape = c
	sb.add_child(cs)
	if occlude:
		var pts := PackedVector2Array()
		for i in 8:
			pts.append(Vector2.from_angle(i * TAU / 8.0) * radius)
		var oc := LightOccluder2D.new()
		var op := OccluderPolygon2D.new()
		op.polygon = pts
		oc.occluder = op
		sb.add_child(oc)
	_block_rect(Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0).grow(8.0))


func _block_rot(p: Vector2, size: Vector2, rot: float) -> void:
	var hs := size * 0.5
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for c in [Vector2(-hs.x, -hs.y), Vector2(hs.x, -hs.y), Vector2(hs.x, hs.y), Vector2(-hs.x, hs.y)]:
		var q: Vector2 = p + (c as Vector2).rotated(rot)
		mn = mn.min(q)
		mx = mx.max(q)
	_block_rect(Rect2(mn, mx - mn).grow(4.0))


func _block_rect(r: Rect2) -> void:
	var x0 := clampi(int(r.position.x / CELL), 0, GW - 1)
	var y0 := clampi(int(r.position.y / CELL), 0, GW - 1)
	var x1 := clampi(int(r.end.x / CELL), 0, GW - 1)
	var y1 := clampi(int(r.end.y / CELL), 0, GW - 1)
	if r.end.x < 0.0 or r.end.y < 0.0 or r.position.x > WORLD or r.position.y > WORLD:
		return
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			blocked[y * GW + x] = 1


func _area_free(p: Vector2, radius: float) -> bool:
	for o in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
		if is_blocked(p + o):
			return false
	return true


func is_blocked(p: Vector2) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= WORLD or p.y >= WORLD:
		return true
	return blocked[int(p.y / CELL) * GW + int(p.x / CELL)] != 0


func _draw_ground() -> void:
	for c in ground_cmds:
		match c[0]:
			"tile":
				ground.draw_texture_rect(c[1], c[2], true)
			"rect":
				ground.draw_rect(c[2], c[1])
			"outline":
				ground.draw_rect(c[2], c[1], false, 4.0)
				ground.draw_rect((c[2] as Rect2).grow(3.0), Color(0, 0, 0, 0.35), false, 2.0)
			"manhole":
				var p: Vector2 = c[2]
				ground.draw_circle(p, 17.0, Color(0.06, 0.06, 0.07))
				ground.draw_circle(p, 14.0, c[1])
				for k in 4:
					ground.draw_line(p + Vector2(-11, -6 + k * 4), p + Vector2(11, -6 + k * 4), Color(0.2, 0.2, 0.21), 1.5)
	ground.draw_rect(Rect2(0, 0, WORLD, WORLD), Color(0.7, 0.55, 0.1, 0.8), false, 8.0)


# ------------------------------------------------------------------ campos de flujo (persecucion)

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, GW - 1), clampi(int(p.y / CELL), 0, GW - 1))


# Campo de flujo (BFS) limitado a un radio de celdas alrededor del objetivo: fuera de el,
# los infectados caminan en linea recta hasta entrar en la zona.
func compute_field(target: Vector2, radius := 26) -> PackedInt32Array:
	var f := PackedInt32Array()
	f.resize(GW * GW)
	f.fill(-1)
	if bfs_q.size() != GW * GW:
		bfs_q.resize(GW * GW)
	var q := bfs_q
	var tc := _cell(target)
	var x0 := maxi(0, tc.x - radius)
	var x1 := mini(GW - 1, tc.x + radius)
	var y0 := maxi(0, tc.y - radius)
	var y1 := mini(GW - 1, tc.y + radius)
	var head := 0
	var tail := 0
	var ti := tc.y * GW + tc.x
	f[ti] = 0
	q[tail] = ti
	tail += 1
	while head < tail:
		var i := q[head]
		head += 1
		var x := i % GW
		var y := i / GW
		var d := f[i] + 1
		if x > x0 and f[i - 1] < 0 and blocked[i - 1] == 0:
			f[i - 1] = d
			q[tail] = i - 1
			tail += 1
		if x < x1 and f[i + 1] < 0 and blocked[i + 1] == 0:
			f[i + 1] = d
			q[tail] = i + 1
			tail += 1
		if y > y0 and f[i - GW] < 0 and blocked[i - GW] == 0:
			f[i - GW] = d
			q[tail] = i - GW
			tail += 1
		if y < y1 and f[i + GW] < 0 and blocked[i + GW] == 0:
			f[i + GW] = d
			q[tail] = i + GW
			tail += 1
	return f


func _pf_start(tc: Vector2i) -> void:
	pf_build = PackedInt32Array()
	pf_build.resize(GW * GW)
	pf_build.fill(-1)
	if pf_q.size() != GW * GW:
		pf_q.resize(GW * GW)
	var ti := tc.y * GW + tc.x
	pf_build[ti] = 0
	pf_q[0] = ti
	pf_head = 0
	pf_tail = 1
	pf_active = true


func _pf_step(budget: int) -> void:
	var f := pf_build
	var q := pf_q
	var n := 0
	while pf_head < pf_tail and n < budget:
		n += 1
		var i := q[pf_head]
		pf_head += 1
		var x := i % GW
		var y := i / GW
		var d := f[i] + 1
		if x > 0 and f[i - 1] < 0 and blocked[i - 1] == 0:
			f[i - 1] = d
			q[pf_tail] = i - 1
			pf_tail += 1
		if x < GW - 1 and f[i + 1] < 0 and blocked[i + 1] == 0:
			f[i + 1] = d
			q[pf_tail] = i + 1
			pf_tail += 1
		if y > 0 and f[i - GW] < 0 and blocked[i - GW] == 0:
			f[i - GW] = d
			q[pf_tail] = i - GW
			pf_tail += 1
		if y < GW - 1 and f[i + GW] < 0 and blocked[i + GW] == 0:
			f[i + GW] = d
			q[pf_tail] = i + GW
			pf_tail += 1
	pf_build = f
	pf_q = q
	if pf_head >= pf_tail:
		pf_active = false
		pfield = pf_build


const NB_X := [-1, 0, 1, -1, 1, -1, 0, 1]
const NB_Y := [-1, -1, -1, 0, 0, 1, 1, 1]


func field_dir(f: PackedInt32Array, pos: Vector2) -> Vector2:
	if f.size() != GW * GW:
		return Vector2.ZERO
	var cx := clampi(int(pos.x / CELL), 0, GW - 1)
	var cy := clampi(int(pos.y / CELL), 0, GW - 1)
	var best := f[cy * GW + cx]
	if best < 0:
		best = 1 << 30
	var bx := -1
	var by := -1
	for k in 8:
		var nx: int = cx + NB_X[k]
		var ny: int = cy + NB_Y[k]
		if nx < 0 or ny < 0 or nx >= GW or ny >= GW:
			continue
		var v := f[ny * GW + nx]
		if v < 0 or v >= best:
			continue
		if nx != cx and ny != cy and (blocked[cy * GW + nx] != 0 or blocked[ny * GW + cx] != 0):
			continue
		best = v
		bx = nx
		by = ny
	if bx < 0:
		return Vector2.ZERO
	return (Vector2((bx + 0.5) * CELL, (by + 0.5) * CELL) - pos).normalized()


func lure_for(pos: Vector2):
	var best = null
	var bd := 1e12
	for l in lures:
		if not is_instance_valid(l) or not l.landed:
			continue
		var d: float = pos.distance_squared_to(l.global_position)
		if d < l.radius * l.radius and d < bd:
			bd = d
			best = l
	return best


func clamp_free(from: Vector2, to: Vector2) -> Vector2:
	var p := to
	var step := (from - to).normalized() * 12.0
	for i in 40:
		if not is_blocked(p):
			return p
		p += step
	return from


# ------------------------------------------------------------------ partida

func start_game() -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		z.queue_free()
	hud.hide_overlay()
	playing = true
	next_wave_t = 1.2
	hud.msg("Sobrevive. El ruido atrae a la horda.", 3.5, Color(1.0, 0.85, 0.6))


func restart() -> void:
	autostart = true
	get_tree().paused = false
	get_tree().reload_current_scene()


func to_menu() -> void:
	autostart = false
	get_tree().paused = false
	get_tree().reload_current_scene()


func _start_wave() -> void:
	wave += 1
	to_spawn = 10 + wave * 6
	specials.clear()
	if wave >= 3:
		for i in 1 + wave / 4:
			specials.append("chillon")
	if wave % 4 == 0:
		for i in wave / 4:
			specials.append("bruto")
	spawn_t = 1.0
	stall_t = 0.0
	var idle := int(to_spawn * 0.35)
	for i in idle:
		_spawn_zombie(_roll_kind(), _random_free(player.global_position, 600.0), false)
	to_spawn -= idle
	Dbg.note("JUEGO", "Empieza la oleada %d (%d por aparecer)" % [wave, to_spawn + idle])
	hud.banner("OLEADA %d" % wave, "Hay ruido en la ciudad..." if wave > 1 else "Usa la ballesta y el machete para no hacer ruido")
	sfx.play("wave", -2.0)


func _roll_kind() -> String:
	var r := rng.randf()
	if wave >= 2 and r < minf(0.05 + wave * 0.012, 0.16):
		return "hinchado"
	if wave >= 2 and r < 0.17 + minf(wave * 0.035, 0.32):
		return "corredor"
	return "comun"


func alive_count() -> int:
	return get_tree().get_nodes_in_group("zombies").size()


func _random_free(avoid: Vector2, min_d: float) -> Vector2:
	for i in 30:
		var c: Vector2 = free_cells[rng.randi() % free_cells.size()]
		if c.distance_to(avoid) > min_d:
			return c + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
	return free_cells[rng.randi() % free_cells.size()]


func _edge_spawn() -> Vector2:
	var pp: Vector2 = player.global_position
	for i in 20:
		var c: Vector2 = spawn_cells[rng.randi() % spawn_cells.size()]
		if c.distance_to(pp) > 760.0:
			return c
	return _random_free(pp, 760.0)


func _spawn_zombie(kind: String, pos: Vector2, aggro: bool):
	var z = ZombieScript.new()
	z.setup(self, kind, pos, aggro)
	world.add_child(z)
	return z


func _director(delta: float) -> void:
	if next_wave_t > 0.0:
		next_wave_t -= delta
		if next_wave_t <= 0.0:
			_start_wave()
		return
	if wave_clear_t > 0.0:
		wave_clear_t -= delta
		if wave_clear_t <= 0.0:
			_offer_upgrades()
		return
	var alive := alive_count()
	var cap := mini(26 + wave * 4, 70)
	if to_spawn > 0:
		spawn_t -= delta
		if spawn_t <= 0.0 and alive < cap:
			spawn_t = maxf(0.35, 1.5 - wave * 0.09)
			var kind := _roll_kind()
			if specials.size() > 0 and rng.randf() < float(specials.size()) / float(to_spawn):
				kind = specials.pop_back()
				if kind == "bruto":
					hud.msg("¡UN BRUTO! Apunta a las piernas o esquívalo", 3.0, Color(1.0, 0.35, 0.25))
					sfx.play("roar", 2.0)
			_spawn_zombie(kind, _edge_spawn(), false)
			to_spawn -= 1
	elif alive == 0:
		wave_clear_t = 2.2
		hud.banner("OLEADA %d SUPERADA" % wave, "")
		sfx.play("upgrade", -4.0)
	elif alive <= 4:
		stall_t += delta
		if stall_t > 15.0:
			stall_t = -1000.0
			for z in get_tree().get_nodes_in_group("zombies"):
				z.become_aggro()
			hud.msg("Los últimos infectados te han olido", 2.0)


func _offer_upgrades() -> void:
	var avail: Array = []
	for id in UPGRADES:
		if up(id) < UPGRADES[id]["max"]:
			avail.append(id)
	avail.shuffle()
	var opts: Array = []
	if wave == 1:
		for id in ["escopeta", "fusil"]:
			if avail.has(id):
				opts.append(id)
				avail.erase(id)
				break
	for id in avail:
		if opts.size() >= 3:
			break
		opts.append(id)
	get_tree().paused = true
	hud.show_upgrades(opts)


func apply_upgrade(id: String) -> void:
	upgrades[id] = up(id) + 1
	Dbg.note("JUEGO", "Mejora elegida: " + id)
	var lvl := up(id)
	match id:
		"escopeta":
			player.weapons[2]["owned"] = true
			player.set_weapon(2)
		"fusil":
			player.weapons[3]["owned"] = true
			player.set_weapon(3)
		"cargador":
			for w in player.weapons:
				if w["mag_base"] == 1:
					w["mag_size"] = 1 + lvl
				else:
					w["mag_size"] = int(round(w["mag_base"] * (1.0 + 0.4 * lvl)))
		"bengalas":
			player.flares += 2
		"bombas":
			player.bombs += 2
		"vida":
			player.max_hp += 25.0
			player.hp = player.max_hp
	player.refill(0.4)
	player.heal(25.0)
	player.flares = mini(player.flares + 1, 8)
	get_tree().paused = false
	hud.hide_overlay()
	sfx.play("upgrade", -2.0)
	next_wave_t = 2.5


func game_over() -> void:
	if over:
		return
	over = true
	vibrate(300)
	Dbg.note("JUEGO", "Partida terminada: oleada %d, %d puntos, %d s" % [wave, score, int(time_played)])
	if score > best:
		best = score
		_save_best(best)
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		playing = false
		hud.show_over(wave, kills, headshots, limbs, score, best, time_played))


func _load_best() -> int:
	if not FileAccess.file_exists("user://record.txt"):
		return 0
	var f := FileAccess.open("user://record.txt", FileAccess.READ)
	if f == null:
		return 0
	return int(f.get_as_text())


func _save_best(v: int) -> void:
	var f := FileAccess.open("user://record.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(str(v))


# ------------------------------------------------------------------ bucle principal

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var t0 := Time.get_ticks_usec()
	_update_bullets(delta)
	var t1 := Time.get_ticks_usec()
	_update_gibs(delta)
	var t2 := Time.get_ticks_usec()
	prof["balas"] += t1 - t0
	prof["restos"] += t2 - t1
	if not playing:
		return
	if pf_active:
		_pf_step(1700)
		prof["campo"] += Time.get_ticks_usec() - t2
	else:
		pfield_t -= delta
		if pfield_t <= 0.0:
			pfield_t = 0.25
			var c := _cell(player.global_position)
			if c != pcell:
				pcell = c
				_pf_start(c)


func _process(delta: float) -> void:
	if player == null:
		return
	for l in flicker:
		l.energy = 1.25 if randf() > 0.06 else 0.15
	fs_t -= delta
	if fs_t <= 0.0:
		fs_t = 3.0
		ensure_fullscreen()
	# Apaga las farolas que no se ven: cada luz encendida obliga a la GPU a recalcular
	# todos los pixeles que toca (y el suelo ocupa toda la ciudad).
	cull_t -= delta
	if cull_t <= 0.0:
		cull_t = 0.2
		var view := get_viewport_rect().size / cam.zoom
		var reach := view.length() * 0.5 + 300.0
		for l in lamp_lights:
			l.enabled = l.position.distance_to(cam.position) < reach
	_update_camera(delta)
	_update_pickups(delta)
	blink_t -= delta
	if blink_t <= 0.0:
		blink_t = 1.4
		for c in alarm_cars:
			if is_instance_valid(c) and c.global_position.distance_to(player.global_position) < 900.0:
				for side in [-1.0, 1.0]:
					fx_top.add(fx_top.FLASH, c.to_global(Vector2(40, 15 * side)), Vector2.ZERO, 0.25, 4.0, Color(1.0, 0.15, 0.1, 0.9))
	if not playing:
		return
	time_played += delta
	quiet_t -= delta
	if quiet_t <= 0.0:
		alert = maxf(0.0, alert - delta * 6.0)
	_director(delta)


func _update_camera(delta: float) -> void:
	var target: Vector2 = player.global_position
	if player.aiming:
		target += player.aim * 80.0
	cam.position = cam.position.lerp(target, 1.0 - exp(-6.0 * delta))
	shake = move_toward(shake, 0.0, delta * 30.0)
	cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))


func shake_cam(v: float) -> void:
	shake = maxf(shake, v)


func vibrate(ms: int) -> void:
	if OS.has_feature("mobile") and settings["vibracion"]:
		Input.vibrate_handheld(ms)


# ------------------------------------------------------------------ ruido y alerta

func make_noise(pos: Vector2, radius: float, alert_add: float) -> void:
	if radius > 0.0:
		var r2 := radius * radius
		for z in get_tree().get_nodes_in_group("zombies"):
			if pos.distance_squared_to(z.global_position) < r2:
				z.hear(pos)
		if radius > 150.0:
			fx_top.add(fx_top.RING, pos, Vector2.ZERO, 0.5, radius, Color(0.9, 0.9, 1.0, 0.12))
	if alert_add > 0.0 and playing and not over:
		alert = minf(100.0, alert + alert_add)
		quiet_t = 2.5
		if alert >= 100.0:
			_horde()


func _horde() -> void:
	alert = 30.0
	Dbg.note("JUEGO", "Horda por ruido (oleada %d, %d zombis vivos)" % [wave, alive_count()])
	hud.msg("¡LA HORDA TE HA OÍDO!", 3.0, Color(1.0, 0.25, 0.2))
	hud.alert_flash = 1.0
	sfx.play("horde", 2.0)
	vibrate(200)
	var n := 6 + wave * 2
	for i in n:
		var z = _spawn_zombie("corredor" if rng.randf() < 0.35 else "comun", _edge_spawn(), true)
		z.become_aggro()
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.distance_to(player.global_position) < 1300.0:
			z.become_aggro()


func trigger_alarm(car: Node2D) -> void:
	if not car.get_meta("alarm", false):
		return
	car.set_meta("alarm", false)
	alarm_cars.erase(car)
	var a = ThrowScript.new()
	a.setup(self, "alarm", car.global_position, car.global_position)
	world.add_child(a)
	hud.msg("¡Alarma de coche! Atrae a todos los infectados", 2.5, Color(1.0, 0.5, 0.3))
	make_noise(car.global_position, 300.0, 35.0)


# ------------------------------------------------------------------ balas

func fire_bullet(p: Vector2, dir: Vector2, speed: float, dmg: float, pierce: int, limb_mult: float, bolt: bool) -> void:
	var ex: Array[RID] = [player.get_rid()]
	bullets.append({"p": p, "tail": p, "v": dir * speed, "dmg": dmg, "pierce": pierce, "limb": limb_mult, "bolt": bolt, "life": 0.75, "ex": ex})


func _update_bullets(delta: float) -> void:
	if bullets.is_empty():
		return
	var space := get_world_2d().direct_space_state
	var keep: Array = []
	for b in bullets:
		b["life"] -= delta
		if b["life"] <= 0.0:
			continue
		var from: Vector2 = b["p"]
		var v: Vector2 = b["v"]
		var to := from + v * delta
		var alive := true
		var steps := 0
		while steps < 4:
			steps += 1
			var q := PhysicsRayQueryParameters2D.create(from, to, L_WALL | L_ZOMBIE)
			q.exclude = b["ex"]
			var res := space.intersect_ray(q)
			if res.is_empty():
				break
			var col = res["collider"]
			var hp_: Vector2 = res["position"]
			if col != null and col.is_in_group("zombies"):
				col.hit(b["dmg"], hp_, v.normalized(), b["limb"])
				b["ex"].append(res["rid"])
				b["pierce"] -= 1
				b["dmg"] *= 0.8
				if b["pierce"] < 0:
					alive = false
					break
				from = hp_
				continue
			_bullet_wall(col, hp_, v.normalized(), b["bolt"])
			alive = false
			break
		if alive:
			b["p"] = to
			keep.append(b)
	bullets = keep


func _bullet_wall(col, p: Vector2, dir: Vector2, bolt: bool) -> void:
	for i in 5:
		fx_top.add(fx_top.SPARK, p, (-dir).rotated(randf_range(-1.0, 1.0)) * randf_range(80, 260), 0.2, 1.4, Color(1.0, 0.8, 0.45), 4.0)
	fx_ground.add(fx_ground.SMOKE, p, -dir * 20.0, 0.5, 5.0, Color(0.6, 0.6, 0.6, 0.6))
	if col == null:
		return
	if col.is_in_group("barrels"):
		var hpv: float = col.get_meta("hp") - (60.0 if bolt else 12.0)
		col.set_meta("hp", hpv)
		if hpv <= 0.0:
			_barrel_explode(col)
	elif col.is_in_group("cars"):
		sfx.play("hit", -10.0, p, 1.6)
		trigger_alarm(col)


func _barrel_explode(b: Node2D) -> void:
	if not is_instance_valid(b) or b.get_meta("hp", 1.0) < -1000.0:
		return
	b.set_meta("hp", -9999.0)
	var p := b.global_position
	barrels.erase(b)
	b.queue_free()
	explode(p, 140.0, 230.0)


func explode(pos: Vector2, radius: float, dmg: float) -> void:
	sfx.play("explode", 4.0, pos)
	shake_cam(16.0)
	vibrate(120)
	fx_top.add(fx_top.FLASH, pos, Vector2.ZERO, 0.35, radius * 0.9, Color(1.0, 0.6, 0.25, 0.9))
	fx_top.add(fx_top.FLASH, pos, Vector2.ZERO, 0.18, radius * 0.45, Color(1.0, 0.95, 0.7, 1.0))
	fx_top.add(fx_top.RING, pos, Vector2.ZERO, 0.45, radius * 1.3, Color(1.0, 0.7, 0.4, 0.7))
	for i in 40:
		fx_top.add(fx_top.SPARK, pos, Vector2.from_angle(randf() * TAU) * randf_range(150, 600), randf_range(0.25, 0.6), 2.0, Color(1.0, randf_range(0.4, 0.8), 0.2), 3.0)
	for i in 14:
		fx_ground.add(fx_ground.SMOKE, pos + Vector2.from_angle(randf() * TAU) * randf_range(0, radius * 0.5), Vector2.from_angle(randf() * TAU) * randf_range(20, 70), randf_range(1.2, 2.4), randf_range(18, 34), Color(0.25, 0.24, 0.24, 0.7), 1.0)
	add_decal(pos, randf() * TAU, radius / 40.0, SCORCH)
	var l := PointLight2D.new()
	l.add_to_group("luces")
	l.texture = tex.light_round
	l.texture_scale = radius / 50.0
	l.energy = 2.6
	l.color = Color(1.0, 0.6, 0.3)
	l.height = 80.0
	l.position = pos
	world.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	for z in get_tree().get_nodes_in_group("zombies"):
		var d: float = z.global_position.distance_to(pos)
		if d < radius + z.radius:
			var f := 1.0 - clampf(d / radius, 0.0, 1.0)
			z.blast(dmg * (0.35 + 0.65 * f), (z.global_position - pos).normalized())
	var pd: float = player.global_position.distance_to(pos)
	if pd < radius * 0.85:
		player.take_damage(5.0 + dmg * 0.15 * (1.0 - pd / radius), pos)
		player.knock = (player.global_position - pos).normalized() * 260.0
	for b in barrels.duplicate():
		if is_instance_valid(b) and b.global_position.distance_to(pos) < radius * 0.9:
			get_tree().create_timer(0.15).timeout.connect(_barrel_explode.bind(b))
	make_noise(pos, 1000.0, 22.0)


func bloat_explode(pos: Vector2) -> void:
	sfx.play("splat", 6.0, pos, 0.6)
	sfx.play("explode", -4.0, pos, 1.6)
	shake_cam(8.0)
	for i in 34:
		fx_ground.add(fx_ground.DOT, pos, Vector2.from_angle(randf() * TAU) * randf_range(80, 340), randf_range(0.3, 0.6), randf_range(2.0, 4.5), Color(0.5, 0.7, 0.12, 0.95), 5.0)
	fx_top.add(fx_top.FLASH, pos, Vector2.ZERO, 0.3, 90.0, Color(0.5, 0.8, 0.15, 0.6))
	for i in 3:
		add_decal(pos + Vector2.from_angle(randf() * TAU) * randf_range(0, 40), randf() * TAU, randf_range(1.2, 2.0), ACID)
	for z in get_tree().get_nodes_in_group("zombies"):
		var d: float = z.global_position.distance_to(pos)
		if d < 105.0:
			z.blast(70.0, (z.global_position - pos).normalized())
	if player.global_position.distance_to(pos) < 100.0:
		player.take_damage(16.0, pos)
		hud.acid = 1.0
	make_noise(pos, 520.0, 8.0)


# ------------------------------------------------------------------ sangre, restos y cadaveres

func add_decal(pos: Vector2, rot: float, sc: float, col: Color) -> void:
	decals.append([pos, rot, sc, rng.randi() % tex.SPLAT_N, col])
	if decals.size() > MAX_DECALS:
		decals.pop_front()
	decal_node.queue_redraw()


func _draw_decals() -> void:
	var s: float = tex.SPLAT
	for d in decals:
		decal_node.draw_set_transform(d[0], d[1], Vector2(d[2], d[2]))
		decal_node.draw_texture_rect_region(tex.splats, Rect2(-s * 0.5, -s * 0.5, s, s), Rect2(d[3] * s, 0, s, s), d[4])
	decal_node.draw_set_transform_matrix(Transform2D.IDENTITY)


func blood_hit(pos: Vector2, dir: Vector2, n: int) -> void:
	for i in n:
		fx_ground.add(fx_ground.DOT, pos, dir.rotated(randfn(0.0, 0.5)) * randf_range(60, 260), randf_range(0.2, 0.45), randf_range(1.4, 3.0), Color(0.55, 0.03, 0.03, 0.95), 6.0)
	if randf() < 0.35:
		add_decal(pos + dir * randf_range(8, 34), dir.angle(), randf_range(0.22, 0.45), BLOOD)


func blood_burst(pos: Vector2, dir: Vector2, n: int) -> void:
	for i in n:
		fx_ground.add(fx_ground.DOT, pos, dir.rotated(randfn(0.0, 0.8)) * randf_range(60, 360), randf_range(0.3, 0.6), randf_range(1.8, 4.0), Color(0.6, 0.03, 0.03, 0.95), 5.0)


func spawn_gib(sp: Sprite2D, dir: Vector2, force: float) -> void:
	var g := Sprite2D.new()
	g.texture = sp.texture
	g.centered = sp.centered
	g.offset = sp.offset
	g.transform = sp.global_transform
	g.modulate = Color(0.9, 0.85, 0.85)
	gib_node.add_child(g)
	var v := dir * randf_range(200.0, 360.0) * force + Vector2.from_angle(randf() * TAU) * randf_range(20.0, 90.0)
	gibs.append({"n": g, "v": v, "s": randf_range(-14.0, 14.0), "t": 0.0, "drip": 0.0})
	if gibs.size() > MAX_GIBS:
		var old: Dictionary = gibs.pop_front()
		if is_instance_valid(old["n"]):
			old["n"].queue_free()


func _update_gibs(delta: float) -> void:
	for g in gibs:
		var n: Sprite2D = g["n"]
		g["t"] += delta
		var v: Vector2 = g["v"]
		if v.length() > 6.0:
			var np := n.position + v * delta
			if is_blocked(np):
				v = -v * 0.3
			else:
				n.position = np
			v *= exp(-4.5 * delta)
			g["v"] = v
			n.rotation += g["s"] * delta
			g["s"] *= exp(-3.5 * delta)
			g["drip"] -= delta
			if g["drip"] <= 0.0:
				g["drip"] = 0.05
				add_decal(n.position, randf() * TAU, randf_range(0.12, 0.22), BLOOD)
		if g["t"] > 30.0:
			n.modulate.a = maxf(0.0, 1.0 - (g["t"] - 30.0) / 3.0)


func add_corpse(z: Node2D) -> void:
	corpses.append(z)
	if corpses.size() > MAX_CORPSES:
		var old = corpses.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# ------------------------------------------------------------------ puntuacion y objetos

func on_dismember(_z, _part: String) -> void:
	limbs += 1
	score += 2


func on_zombie_killed(z, headshot: bool) -> void:
	kills += 1
	score += int(z.cfg["score"])
	if headshot:
		headshots += 1
		score += 5
	var pos: Vector2 = z.global_position
	if z.kind == "bruto":
		spawn_pickup("med", pos + Vector2(-16, 0))
		spawn_pickup("ammo", pos + Vector2(16, 0))
		spawn_pickup("bomb", pos + Vector2(0, 16))
		return
	var m := 1.0 + 0.5 * up("iman")
	var r := rng.randf()
	if r < 0.08 * m:
		spawn_pickup("ammo", pos)
	elif r < 0.115 * m:
		spawn_pickup("med", pos)
	elif r < 0.14 * m:
		spawn_pickup("flare", pos)
	elif r < 0.15 * m:
		spawn_pickup("bomb", pos)


func spawn_pickup(kind: String, pos: Vector2) -> void:
	var sp := Sprite2D.new()
	sp.texture = tex.items[kind]
	sp.position = pos
	sp.scale = Vector2(0.6, 0.6)
	pick_root.add_child(sp)
	pickups.append({"kind": kind, "n": sp, "t": 0.0})


func _update_pickups(delta: float) -> void:
	if pickups.is_empty():
		return
	var keep: Array = []
	var pp: Vector2 = player.global_position
	var reach := 34.0 + 70.0 * up("iman")
	for p in pickups:
		var n: Sprite2D = p["n"]
		p["t"] += delta
		var t: float = p["t"]
		n.scale = Vector2.ONE * (0.6 + 0.06 * sin(t * 6.0))
		n.rotation = sin(t * 2.0) * 0.2
		n.visible = t < 20.0 or int(t * 8.0) % 2 == 0
		if playing and not player.dead and n.position.distance_to(pp) < reach:
			_collect(p["kind"])
			n.queue_free()
			continue
		if t > 25.0:
			n.queue_free()
			continue
		keep.append(p)
	pickups = keep


func _collect(kind: String) -> void:
	sfx.play("pickup", -4.0)
	match kind:
		"ammo":
			player.refill(0.3)
			var w: Dictionary = player.weapon()
			if w["reserve"] < 0:
				w["mag"] = w["mag_size"]
			hud.msg("+ Munición", 1.0, Color(1.0, 0.9, 0.4))
		"med":
			player.heal(30.0)
			hud.msg("+ Botiquín", 1.0, Color(0.5, 1.0, 0.5))
		"flare":
			player.flares = mini(player.flares + 1, 8)
			hud.msg("+ Bengala", 1.0, Color(1.0, 0.5, 0.4))
		"bomb":
			player.bombs = mini(player.bombs + 1, 5)
			hud.msg("+ Bomba de tubo", 1.0, Color(1.0, 0.7, 0.3))
