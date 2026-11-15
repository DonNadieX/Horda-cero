extends CharacterBody2D
# Superviviente: movimiento, apuntado twin-stick con ayuda al apuntar, armas, machete,
# esquiva, linterna y objetos arrojadizos (bengalas y bombas de tubo).

const ThrowScript = preload("res://scripts/throwable.gd")
const L_WALL := 1
const L_PLAYER := 2
const L_ZOMBIE := 4
const SWING_TIME := 0.2
const RADIUS := 13.0
const SPEED := 205.0

const WEAPONS := [
	{"id": "pistola", "name": "PISTOLA", "dmg": 28.0, "rate": 0.2, "mag_base": 12, "reserve": -1, "reserve_max": -1, "spread": 0.035, "pellets": 1, "noise": 340.0, "alert": 2.5, "speed": 1500.0, "pierce": 0, "reload": 1.0, "snd": "pistol", "limb": 1.0, "bolt": false, "owned": true},
	{"id": "ballesta", "name": "BALLESTA", "dmg": 85.0, "rate": 0.12, "mag_base": 1, "reserve": 20, "reserve_max": 40, "spread": 0.0, "pellets": 1, "noise": 40.0, "alert": 0.0, "speed": 1150.0, "pierce": 3, "reload": 0.75, "snd": "bow", "limb": 1.3, "bolt": true, "owned": true},
	{"id": "escopeta", "name": "ESCOPETA", "dmg": 15.0, "rate": 0.72, "mag_base": 6, "reserve": 30, "reserve_max": 48, "spread": 0.2, "pellets": 8, "noise": 640.0, "alert": 6.0, "speed": 1300.0, "pierce": 0, "reload": 1.9, "snd": "shotgun", "limb": 1.6, "bolt": false, "owned": false},
	{"id": "fusil", "name": "FUSIL", "dmg": 20.0, "rate": 0.09, "mag_base": 30, "reserve": 150, "reserve_max": 240, "spread": 0.06, "pellets": 1, "noise": 500.0, "alert": 1.6, "speed": 1700.0, "pierce": 0, "reload": 1.6, "snd": "rifle", "limb": 1.0, "bolt": false, "owned": false},
]

var game
var body: Node2D
var torso: Sprite2D
var legs: Array = []
var gun: Sprite2D
var blade: Sprite2D
var cone: PointLight2D
var glow: PointLight2D
var muzzle_light: PointLight2D

var hp := 100.0
var max_hp := 100.0
var dead := false
var move := Vector2.ZERO
var aim := Vector2.RIGHT
var aiming := false
var trigger := false
var weapons: Array = []
var cur := 0
var fire_cd := 0.0
var reload_t := 0.0
var reload_total := 1.0
var machete_cd := 0.0
var swing_t := 0.0
var dodge_cd := 0.0
var dodge_t := 0.0
var dodge_dir := Vector2.ZERO
var inv_t := 0.0
var knock := Vector2.ZERO
var move_vel := Vector2.ZERO
var walk_ph := 0.0
var recoil := 0.0
var flares := 2
var bombs := 1
var light_on := true
var laser_len := 0.0
var last_mouse := Vector2.ZERO
var use_mouse := false


func setup(g) -> void:
	game = g
	for w in WEAPONS:
		var d: Dictionary = w.duplicate()
		d["mag_size"] = d["mag_base"]
		d["mag"] = d["mag_base"]
		weapons.append(d)
	collision_layer = L_PLAYER
	collision_mask = L_WALL | L_ZOMBIE
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = RADIUS
	cs.shape = c
	add_child(cs)

	body = Node2D.new()
	add_child(body)
	for side in [-1.0, 1.0]:
		var l := Sprite2D.new()
		l.texture = game.tex.player["leg"]
		l.centered = false
		l.offset = Vector2(-5, -11)
		l.position = Vector2(-3, 6.0 * side)
		l.scale = Vector2(0.5, 0.5 * side)
		body.add_child(l)
		legs.append(l)
	gun = Sprite2D.new()
	gun.centered = false
	gun.position = Vector2(11, 0)
	gun.scale = Vector2(0.5, 0.5)
	body.add_child(gun)
	torso = Sprite2D.new()
	torso.texture = game.tex.player["torso"]
	torso.offset = Vector2(6, 0)
	torso.scale = Vector2(0.5, 0.5)
	body.add_child(torso)
	blade = Sprite2D.new()
	blade.texture = game.tex.machete
	blade.centered = false
	blade.offset = Vector2(0, -5)
	blade.scale = Vector2(0.6, 0.6)
	blade.visible = false
	body.add_child(blade)
	_update_gun()

	cone = PointLight2D.new()
	cone.texture = game.tex.light_cone
	cone.texture_scale = 4.4
	cone.energy = 1.35
	cone.color = Color(1.0, 0.95, 0.82)
	cone.shadow_color = Color(0, 0, 0, 0.85)
	cone.height = 90.0
	cone.add_to_group("luces")
	add_child(cone)
	apply_shadows()
	glow = PointLight2D.new()
	glow.texture = game.tex.light_round
	glow.texture_scale = 1.5
	glow.energy = 0.5
	glow.color = Color(0.85, 0.9, 1.0)
	glow.height = 70.0
	glow.add_to_group("luces")
	add_child(glow)
	muzzle_light = PointLight2D.new()
	muzzle_light.texture = game.tex.light_round
	muzzle_light.texture_scale = 2.4
	muzzle_light.energy = 0.0
	muzzle_light.color = Color(1.0, 0.75, 0.4)
	muzzle_light.height = 60.0
	muzzle_light.add_to_group("luces")
	add_child(muzzle_light)


# Sombras de la linterna: bonitas pero caras, y en algunas GPU moviles dejan la luz a oscuras.
func apply_shadows() -> void:
	var on: bool = game.settings["sombras"]
	cone.shadow_enabled = on
	if OS.has_feature("mobile"):
		cone.shadow_filter = Light2D.SHADOW_FILTER_NONE
	else:
		cone.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		cone.shadow_filter_smooth = 2.0


func weapon() -> Dictionary:
	return weapons[cur]


func _update_gun() -> void:
	var w := weapon()
	var tx: Texture2D = game.tex.guns[w["id"]]
	gun.texture = tx
	gun.offset = Vector2(0, -tx.get_height() * 0.5)


func muzzle_pos() -> Vector2:
	return global_position + aim * 30.0


func machete_range() -> float:
	return 54.0 + 12.0 * game.up("machete")


func sense_mult() -> float:
	var m := 1.0 if light_on else 0.62
	m *= pow(0.82, game.up("sigilo"))
	if dodge_t > 0.0:
		m *= 0.7
	return m


func _unhandled_input(event: InputEvent) -> void:
	if not game.playing or dead:
		return
	if event is InputEventMouseMotion:
		use_mouse = true
	elif event is InputEventMouseButton and event.pressed:
		use_mouse = true
		if event.button_index == MOUSE_BUTTON_RIGHT:
			swing()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				start_reload()
			KEY_Q:
				next_weapon()
			KEY_E:
				swing()
			KEY_SPACE:
				dodge()
			KEY_F:
				throw_item("flare")
			KEY_G:
				throw_item("bomb")
			KEY_L:
				toggle_light()
			KEY_1, KEY_2, KEY_3, KEY_4:
				set_weapon(event.physical_keycode - KEY_1)


func _physics_process(delta: float) -> void:
	if dead or not game.playing:
		velocity = Vector2.ZERO
		return
	var hud = game.hud
	var mv: Vector2 = hud.move_vec
	var kb := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if kb != Vector2.ZERO:
		mv = kb.normalized()
	move = mv

	var av: Vector2 = hud.aim_vec
	if av.length() > 0.18:
		aiming = true
		use_mouse = false
		aim = _assist(av.normalized())
		trigger = av.length() > 0.42
	elif use_mouse and not hud.show_touch:
		var to := get_global_mouse_position() - global_position
		if to.length() > 4.0:
			aim = to.normalized()
		aiming = true
		trigger = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	else:
		aiming = false
		trigger = false
		if move.length() > 0.15:
			aim = aim.slerp(move.normalized(), 1.0 - exp(-8.0 * delta)).normalized()

	inv_t -= delta
	dodge_cd -= delta
	machete_cd -= delta
	fire_cd -= delta
	recoil = move_toward(recoil, 0.0, delta * 8.0)
	muzzle_light.energy = move_toward(muzzle_light.energy, 0.0, delta * 14.0)

	if dodge_t > 0.0:
		dodge_t -= delta
		collision_mask = L_WALL
		velocity = dodge_dir * 640.0
		move_vel = velocity
		game.fx_ground.add(game.fx_ground.SMOKE, global_position, Vector2.ZERO, 0.35, 10.0, Color(0.6, 0.6, 0.65, 0.5))
	else:
		collision_mask = L_WALL | L_ZOMBIE
		var spd: float = SPEED * (1.0 + 0.1 * game.up("botas"))
		if trigger:
			spd *= 0.85
		# El empuje se suma aparte para que no se acumule de un fotograma a otro.
		move_vel = move_vel.lerp(move * spd, 1.0 - exp(-14.0 * delta))
		velocity = move_vel + knock
	knock = knock.move_toward(Vector2.ZERO, 1500.0 * delta)
	move_and_slide()
	position = position.clamp(Vector2(20, 20), Vector2(game.WORLD - 20.0, game.WORLD - 20.0))

	body.rotation = lerp_angle(body.rotation, aim.angle(), 1.0 - exp(-28.0 * delta))
	cone.rotation = body.rotation

	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload()
	elif trigger and fire_cd <= 0.0:
		_shoot()

	if swing_t > 0.0:
		swing_t -= delta
		blade.visible = true
		var k := 1.0 - swing_t / SWING_TIME
		blade.rotation = -1.1 + 2.2 * k
		blade.position = Vector2(4, 0)
		gun.visible = false
	else:
		blade.visible = false
		gun.visible = true

	_update_laser()
	_animate(delta)


func _assist(dir: Vector2) -> Vector2:
	var best = null
	var best_ang := 0.24
	for z in get_tree().get_nodes_in_group("zombies"):
		var to: Vector2 = z.global_position - global_position
		var d := to.length()
		if d > 560.0 or d < 1.0:
			continue
		var ang := absf(dir.angle_to(to))
		if ang < best_ang:
			best_ang = ang
			best = to
	if best != null:
		return dir.slerp((best as Vector2).normalized(), 0.8)
	return dir


func _update_laser() -> void:
	if not aiming:
		laser_len = 0.0
		return
	var a := muzzle_pos()
	var q := PhysicsRayQueryParameters2D.create(a, a + aim * 420.0, L_WALL | L_ZOMBIE)
	var res := get_world_2d().direct_space_state.intersect_ray(q)
	laser_len = 420.0 if res.is_empty() else a.distance_to(res["position"])


func _animate(delta: float) -> void:
	var v := velocity.length()
	walk_ph += v * delta * 0.08
	var stride := clampf(v / 120.0, 0.12, 1.0)
	var sw := sin(walk_ph)
	legs[0].scale.x = 0.5 * sw * stride
	legs[1].scale.x = -0.5 * sw * stride
	gun.position.x = 11.0 - recoil * 5.0
	if inv_t > 0.0 and dodge_t <= 0.0:
		body.modulate = Color(1.6, 0.7, 0.7) if int(inv_t * 30.0) % 2 == 0 else Color(1, 1, 1)
	else:
		body.modulate = Color(1, 1, 1)


func _shoot() -> void:
	var w := weapon()
	if w["mag"] <= 0:
		if w["reserve"] != 0:
			start_reload()
		else:
			game.sfx.play("click", -4.0)
			fire_cd = 0.3
			set_weapon(0)
		return
	w["mag"] -= 1
	fire_cd = w["rate"]
	var mp := muzzle_pos()
	var spread: float = w["spread"] * (1.25 if move.length() > 0.3 else 1.0)
	var dmg_mult: float = 1.0 + 0.2 * game.up("dano")
	var limb_mult: float = w["limb"] * (1.0 + 0.5 * game.up("desmembrar"))
	var pierce: int = w["pierce"] + game.up("perforar")
	for i in w["pellets"]:
		var a := aim.angle() + randfn(0.0, spread)
		game.fire_bullet(mp, Vector2.from_angle(a), w["speed"] * randf_range(0.92, 1.05), w["dmg"] * dmg_mult, pierce, limb_mult, w["bolt"])
	var quiet: bool = game.up("silenciador") > 0 and (w["id"] == "pistola" or w["id"] == "fusil")
	var nmult := 0.4 if quiet else 1.0
	game.make_noise(global_position, w["noise"] * nmult, w["alert"] * nmult)
	var snd: String = w["snd"]
	if quiet and snd == "pistol":
		snd = "pistol_sil"
	game.sfx.play(snd, -6.0 if quiet else -2.0, null, 1.2 if quiet and snd == "rifle" else 1.0)
	if not w["bolt"]:
		game.fx_top.add(game.fx_top.MUZZLE, mp, Vector2.ZERO, 0.06, 18.0 if w["pellets"] == 1 else 26.0, Color(1.0, 0.8, 0.35), 0.0, aim.angle())
		muzzle_light.energy = 1.4 if not quiet else 0.5
		game.fx_ground.add(game.fx_ground.SHELL, global_position + aim.orthogonal() * 6.0, aim.orthogonal().rotated(randf_range(-0.4, 0.4)) * randf_range(90.0, 150.0), 0.5, 1.0, Color(0.85, 0.65, 0.25), 6.0, randf() * TAU)
	recoil = 1.0
	game.shake_cam(2.5 if w["pellets"] == 1 else 6.0)
	if w["mag"] == 0 and w["reserve"] != 0:
		start_reload()


func start_reload() -> void:
	var w := weapon()
	if reload_t > 0.0 or w["mag"] >= w["mag_size"] or w["reserve"] == 0:
		return
	reload_total = w["reload"] * pow(0.7, game.up("recarga"))
	reload_t = reload_total
	game.sfx.play("reload", -4.0)


func _finish_reload() -> void:
	var w := weapon()
	var need: int = w["mag_size"] - w["mag"]
	if w["reserve"] < 0:
		w["mag"] = w["mag_size"]
	else:
		var take: int = mini(need, w["reserve"])
		w["mag"] += take
		w["reserve"] -= take
	game.sfx.play("click", -6.0)


func set_weapon(i: int) -> void:
	if i < 0 or i >= weapons.size() or i == cur:
		return
	if not weapons[i]["owned"]:
		return
	cur = i
	reload_t = 0.0
	fire_cd = 0.25
	_update_gun()
	game.sfx.play("reload", -8.0, null, 1.4)


func next_weapon() -> void:
	for k in range(1, weapons.size() + 1):
		var i := (cur + k) % weapons.size()
		var w: Dictionary = weapons[i]
		if w["owned"] and (w["mag"] > 0 or w["reserve"] != 0):
			set_weapon(i)
			game.hud.msg(w["name"], 0.8)
			return


func refill(frac: float) -> void:
	for w in weapons:
		if w["owned"] and w["reserve_max"] > 0:
			w["reserve"] = mini(w["reserve_max"], w["reserve"] + int(ceil(w["reserve_max"] * frac)))


func swing() -> void:
	if machete_cd > 0.0 or dead or not game.playing:
		return
	var lvl: int = game.up("machete")
	machete_cd = 0.55 - 0.12 * lvl
	swing_t = SWING_TIME
	game.sfx.play("swish", -4.0)
	var r := machete_range()
	var hit_any := false
	for z in get_tree().get_nodes_in_group("zombies"):
		var to: Vector2 = z.global_position - global_position
		if to.length() < r + z.radius and absf(aim.angle_to(to)) < 1.2:
			z.slash(60.0 + 25.0 * lvl, to.normalized())
			hit_any = true
	if hit_any:
		game.sfx.play("chop", -2.0)
		game.shake_cam(4.0)


func dodge() -> void:
	if dodge_cd > 0.0 or dead or not game.playing:
		return
	dodge_cd = 1.5 - 0.25 * game.up("botas")
	dodge_t = 0.2
	inv_t = maxf(inv_t, 0.3)
	dodge_dir = move.normalized() if move.length() > 0.1 else aim
	game.sfx.play("whoosh", -4.0)


func toggle_light() -> void:
	light_on = not light_on
	cone.enabled = light_on
	game.sfx.play("click", -4.0)
	game.hud.msg("Linterna encendida" if light_on else "Linterna apagada: te detectan más tarde", 1.6)


func throw_item(kind: String) -> void:
	if dead or not game.playing:
		return
	if kind == "flare":
		if flares <= 0:
			game.hud.msg("No te quedan bengalas", 1.2)
			return
		flares -= 1
	else:
		if bombs <= 0:
			game.hud.msg("No te quedan bombas", 1.2)
			return
		bombs -= 1
	var t = ThrowScript.new()
	t.setup(game, kind, global_position + aim * 16.0, global_position + aim * 320.0)
	game.world.add_child(t)
	game.sfx.play("throw", -2.0)


func heal(v: float) -> void:
	hp = minf(max_hp, hp + v)


func take_damage(amount: float, from_pos: Vector2) -> void:
	if dead or inv_t > 0.0:
		return
	hp -= amount
	inv_t = 0.3
	var dir := (global_position - from_pos).normalized()
	knock = dir * 120.0
	game.hud.hurt(amount)
	game.sfx.play("hurt", -2.0)
	game.shake_cam(7.0)
	game.vibrate(50)
	game.blood_hit(global_position, dir, 6)
	if hp <= 0.0:
		hp = 0.0
		_die()


func _die() -> void:
	dead = true
	body.modulate = Color(0.6, 0.4, 0.4)
	body.rotation += 0.6
	cone.enabled = false
	game.add_decal(global_position, randf() * TAU, 1.4, game.BLOOD)
	game.game_over()
