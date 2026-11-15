extends CharacterBody2D
# Infectado montado por partes (cabeza, torso, brazos, piernas) para poder desmembrarlo.
# - Sin un brazo pega mas flojo; sin los dos solo muerde.
# - Sin una pierna cojea; sin las dos se arrastra.
# - Sin cabeza muere al instante.
# Oye el ruido de los disparos y le atraen las bengalas y las bombas de tubo.

const L_WALL := 1
const L_PLAYER := 2
const L_ZOMBIE := 4

const KINDS := {
	"comun": {"hp": 100.0, "walk": 36.0, "run": Vector2(86, 108), "scale": 1.0, "dmg": 9.0, "sense": 200.0, "score": 10},
	"corredor": {"hp": 70.0, "walk": 48.0, "run": Vector2(160, 182), "scale": 0.95, "dmg": 7.0, "sense": 230.0, "score": 15},
	"hinchado": {"hp": 130.0, "walk": 28.0, "run": Vector2(58, 66), "scale": 1.2, "dmg": 6.0, "sense": 170.0, "score": 20},
	"chillon": {"hp": 75.0, "walk": 40.0, "run": Vector2(95, 105), "scale": 1.0, "dmg": 5.0, "sense": 320.0, "score": 30},
	"bruto": {"hp": 1000.0, "walk": 38.0, "run": Vector2(74, 80), "scale": 1.7, "dmg": 26.0, "sense": 260.0, "score": 120},
}
const LIMBS := ["head", "arm_l", "arm_r", "leg_l", "leg_r"]

var game
var kind := "comun"
var cfg: Dictionary
var s := 1.0
var radius := 12.5
var hp := 100.0
var limb_hp := {}
var has := {"head": true, "arm_l": true, "arm_r": true, "leg_l": true, "leg_r": true}
var joints := {}
var aggro := false
var dead := false
var body: Node2D
var spr := {}
var walk_ph := 0.0
var run_speed := 100.0
var atk_t := 0.0
var atk_cd := 0.0
var flash := 0.0
var knock := Vector2.ZERO
var move_vel := Vector2.ZERO
var groan_t := 0.0
var think_t := 0.0
var drift := Vector2.ZERO
var lure = null
var was_lured := false
var trail_t := 0.0
var scream_t := 5.0
var scream_hold := 0.0
var charge_cd := 3.0
var charge_wind := 0.0
var charge_t := 0.0
var charge_dir := Vector2.ZERO
var stun_t := 0.0
var shape: CollisionShape2D


func setup(g, k: String, pos: Vector2, start_aggro: bool) -> void:
	game = g
	kind = k
	cfg = KINDS[k]
	position = pos
	aggro = start_aggro
	s = cfg["scale"]
	radius = 12.5 * s
	var wave_mult: float = 1.0 + float(game.wave - 1) * 0.05
	hp = cfg["hp"] * wave_mult
	limb_hp = {"head": hp * 0.42, "arm_l": hp * 0.3, "arm_r": hp * 0.3, "leg_l": hp * 0.38, "leg_r": hp * 0.38}
	if kind == "bruto":
		limb_hp = {"head": 380.0 * wave_mult, "arm_l": 260.0 * wave_mult, "arm_r": 260.0 * wave_mult, "leg_l": 420.0 * wave_mult, "leg_r": 420.0 * wave_mult}
	var run: Vector2 = cfg["run"]
	run_speed = randf_range(run.x, run.y) * (1.0 + minf(game.wave, 12) * 0.012)
	groan_t = randf_range(2.0, 9.0)
	add_to_group("zombies")
	collision_layer = L_ZOMBIE
	collision_mask = L_WALL | L_ZOMBIE | L_PLAYER
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	shape = CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	shape.shape = c
	add_child(shape)
	_build_visual()


func _build_visual() -> void:
	body = Node2D.new()
	body.rotation = randf() * TAU
	add_child(body)
	var set_: Dictionary
	if game.tex.kind_sets.has(kind):
		set_ = game.tex.kind_sets[kind]
	else:
		set_ = game.tex.zombie_sets[randi() % game.tex.zombie_sets.size()]
	var bs := 0.5 * s
	var arm_y := 12.0
	var head_x := 5.0
	var torso_off := Vector2(2, 0)
	match kind:
		"hinchado":
			arm_y = 15.0
			head_x = 9.0
			torso_off = Vector2(4, 0)
		"bruto":
			arm_y = 14.0
			head_x = 6.0
	joints = {
		"leg_l": Vector2(-3, -6) * s, "leg_r": Vector2(-3, 6) * s,
		"arm_l": Vector2(3, -arm_y) * s, "arm_r": Vector2(3, arm_y) * s,
		"head": Vector2(head_x, 0) * s,
	}
	spr["leg_l"] = _part(set_["leg"], joints["leg_l"], Vector2(-5, -11), Vector2(bs, -bs))
	spr["leg_r"] = _part(set_["leg"], joints["leg_r"], Vector2(-5, -11), Vector2(bs, bs))
	var t := Sprite2D.new()
	t.texture = set_["torso"]
	t.offset = torso_off
	t.scale = Vector2(bs, bs)
	body.add_child(t)
	spr["torso"] = t
	spr["arm_l"] = _part(set_["arm"], joints["arm_l"], Vector2(-6, -10), Vector2(bs, -bs))
	spr["arm_r"] = _part(set_["arm"], joints["arm_r"], Vector2(-6, -10), Vector2(bs, bs))
	var h := Sprite2D.new()
	h.texture = set_["head"]
	h.position = joints["head"]
	h.scale = Vector2(bs, bs)
	body.add_child(h)
	spr["head"] = h


func _part(tx: Texture2D, pos: Vector2, off: Vector2, sc: Vector2) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tx
	sp.centered = false
	sp.offset = off
	sp.position = pos
	sp.scale = sc
	body.add_child(sp)
	return sp


func legs_left() -> int:
	return int(has["leg_l"]) + int(has["leg_r"])


func arms_left() -> int:
	return int(has["arm_l"]) + int(has["arm_r"])


func _physics_process(delta: float) -> void:
	if dead or not game.playing:
		return
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	game.prof["ia"] += Time.get_ticks_usec() - t0


func _tick(delta: float) -> void:
	atk_cd -= delta
	flash -= delta
	think_t -= delta
	stun_t -= delta
	var p = game.player
	var ppos: Vector2 = p.global_position
	var dp := ppos - global_position
	var dist := dp.length()

	if not aggro and not p.dead and dist < cfg["sense"] * p.sense_mult():
		become_aggro()

	# Objetivo: senuelo (bengala/bomba), jugador o busqueda lenta
	var new_lure = game.lure_for(global_position)
	if new_lure != null and (dist > 80.0 or new_lure.kind == "bomb"):
		lure = new_lure
		was_lured = true
	else:
		lure = null
		if was_lured:
			was_lured = false
			if dist > 260.0:
				aggro = false
				think_t = 0.0

	var dir := Vector2.ZERO
	var spd := 0.0
	var face_target := false
	if lure != null:
		var lp: Vector2 = lure.global_position
		var dl := global_position.distance_to(lp)
		if dl < 46.0:
			if think_t <= 0.0:
				think_t = randf_range(0.4, 1.0)
				drift = Vector2.from_angle(randf() * TAU)
			dir = drift
			spd = 18.0
		else:
			dir = (lp - global_position).normalized() if dl < 150.0 else game.field_dir(lure.field, global_position)
			spd = run_speed * 0.9
	elif aggro and not p.dead:
		dir = dp / maxf(dist, 0.01) if dist < 150.0 else game.field_dir(game.pfield, global_position)
		spd = run_speed
		face_target = dist < 220.0
	else:
		if think_t <= 0.0:
			think_t = randf_range(1.5, 4.0)
			drift = Vector2.from_angle(randf() * TAU) * randf_range(0.2, 0.7)
		if dist > 380.0:
			dir = (game.field_dir(game.pfield, global_position) + drift).normalized()
		else:
			dir = drift.normalized()
		spd = cfg["walk"]

	if dir == Vector2.ZERO and dist > 1.0:
		dir = dp / dist

	# Efectos de las extremidades perdidas
	var legs := legs_left()
	if legs == 1:
		spd *= 0.55
	elif legs == 0:
		spd = minf(spd, 30.0)

	match kind:
		"chillon":
			if aggro and not p.dead:
				if dist < 230.0 and lure == null:
					dir = -dp / maxf(dist, 0.01)
					spd = run_speed * 0.7
				scream_t -= delta
				if scream_t <= 0.0 and dist < 720.0:
					_scream()
			if scream_hold > 0.0:
				scream_hold -= delta
				spd = 0.0
				face_target = true
		"bruto":
			if _brute(delta, dist, dp):
				return

	# Ataque cuerpo a cuerpo
	if aggro and not p.dead and atk_t <= 0.0 and atk_cd <= 0.0 and dist < radius + 24.0:
		atk_t = 0.32
	if atk_t > 0.0:
		atk_t -= delta
		spd *= 0.3
		face_target = true
		if atk_t <= 0.0:
			atk_cd = 0.9
			if dist < radius + 30.0 and not p.dead:
				p.take_damage(_damage(), global_position)

	if stun_t > 0.0:
		spd = 0.0

	# El empuje se suma aparte para que no se acumule de un fotograma a otro.
	var want := dir * spd
	move_vel = move_vel.lerp(want, 1.0 - exp(-8.0 * delta))
	velocity = move_vel + knock
	knock = knock.move_toward(Vector2.ZERO, 1400.0 * delta)
	move_and_slide()

	var face := velocity.angle() if velocity.length() > 6.0 else body.rotation
	if face_target:
		face = dp.angle()
	body.rotation = lerp_angle(body.rotation, face, 1.0 - exp(-9.0 * delta))
	_animate(delta)

	groan_t -= delta
	if groan_t <= 0.0:
		groan_t = randf_range(4.0, 11.0)
		if dist < 650.0:
			game.sfx.play("growl" if randf() < 0.5 else "growl2", -12.0 if aggro else -18.0, global_position, 1.3 if kind == "corredor" else (0.7 if kind == "bruto" else 1.0))
	if legs == 0:
		trail_t -= delta
		if trail_t <= 0.0:
			trail_t = 0.7
			game.add_decal(global_position, body.rotation, 0.35, game.BLOOD)


func _animate(delta: float) -> void:
	var v := velocity.length()
	walk_ph += v * delta * 0.085
	var bs := 0.5 * s
	var legs := legs_left()
	var sw := sin(walk_ph)
	if legs > 0:
		var stride := clampf(v / 60.0, 0.15, 1.0)
		spr["leg_l"].scale.x = bs * sw * stride
		spr["leg_r"].scale.x = -bs * sw * stride
	var lunge := 0.0
	if atk_t > 0.0:
		lunge = sin((1.0 - atk_t / 0.32) * PI)
	if legs == 0:
		spr["arm_l"].scale.x = bs * (0.75 + 0.3 * sin(walk_ph * 1.4))
		spr["arm_r"].scale.x = bs * (0.75 + 0.3 * sin(walk_ph * 1.4 + PI))
	else:
		spr["arm_l"].scale.x = bs * (1.0 + 0.35 * lunge)
		spr["arm_r"].scale.x = bs * (1.0 + 0.35 * lunge)
		spr["arm_l"].rotation = -0.08 + sin(walk_ph * 0.5) * 0.12 + lunge * 0.15
		spr["arm_r"].rotation = 0.08 - sin(walk_ph * 0.5 + 1.0) * 0.12 - lunge * 0.15
	if kind == "chillon" and scream_hold > 0.0:
		spr["head"].scale = Vector2(bs, bs) * (1.0 + 0.12 * sin(scream_hold * 40.0))
	if flash > 0.0:
		body.modulate = Color(1.7, 1.5, 1.5)
	elif stun_t > 0.0:
		body.modulate = Color(0.8, 0.8, 1.3)
	else:
		body.modulate = Color(1, 1, 1)


func _damage() -> float:
	var d: float = cfg["dmg"] * (1.0 + float(game.wave - 1) * 0.03)
	match arms_left():
		1:
			d *= 0.6
		0:
			d = maxf(3.0, d * 0.3)
	return d


func become_aggro() -> void:
	if dead or aggro:
		return
	aggro = true
	if randf() < 0.5:
		game.sfx.play("growl", -9.0, global_position, 1.2)


func hear(_pos: Vector2) -> void:
	if not dead:
		become_aggro()


func _scream() -> void:
	scream_t = randf_range(6.5, 8.5)
	scream_hold = 0.9
	game.sfx.play("scream", 2.0, global_position)
	game.fx_top.add(game.fx_top.RING, global_position, Vector2.ZERO, 0.9, 260.0, Color(1.0, 0.3, 0.3, 0.8))
	game.fx_top.add(game.fx_top.RING, global_position, Vector2.ZERO, 1.3, 520.0, Color(1.0, 0.3, 0.3, 0.5))
	game.make_noise(global_position, 760.0, 16.0)
	game.hud.msg("¡Un chillón está llamando a la horda!", 2.0, Color(1.0, 0.5, 0.4))


# Devuelve true si el bruto controla su propio movimiento este fotograma.
func _brute(delta: float, dist: float, dp: Vector2) -> bool:
	charge_cd -= delta
	if charge_wind > 0.0:
		charge_wind -= delta
		velocity = Vector2.ZERO
		body.rotation = lerp_angle(body.rotation, dp.angle(), 1.0 - exp(-12.0 * delta))
		body.position = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		if charge_wind <= 0.0:
			body.position = Vector2.ZERO
			charge_t = 1.0
			charge_dir = dp.normalized()
		_animate(delta)
		return true
	if charge_t > 0.0:
		charge_t -= delta
		velocity = charge_dir * (420.0 if legs_left() == 2 else 220.0)
		move_and_slide()
		body.rotation = charge_dir.angle()
		_animate(delta)
		var p = game.player
		if dist < radius + 22.0 and not p.dead:
			p.take_damage(_damage() * 1.2, global_position)
			p.knock = charge_dir * 380.0
			charge_t = 0.0
			game.shake_cam(10.0)
		elif get_slide_collision_count() > 0:
			var col := get_slide_collision(0)
			var other = col.get_collider()
			if other != null and not other.is_in_group("zombies"):
				charge_t = 0.0
				stun_t = 1.6
				game.shake_cam(8.0)
				game.sfx.play("hit", 4.0, global_position, 0.5)
			elif other != null and other.is_in_group("zombies") and other != self:
				other.knock = charge_dir.orthogonal() * (170.0 if randf() < 0.5 else -170.0)
		return true
	if aggro and charge_cd <= 0.0 and stun_t <= 0.0 and dist > 150.0 and dist < 430.0 and legs_left() > 0:
		charge_cd = randf_range(4.5, 6.5)
		charge_wind = 0.7
		game.sfx.play("roar", 4.0, global_position)
		return true
	return false


# ------------------------------------------------------------------ dano y desmembramiento

func _pick_part(point: Vector2, dir: Vector2) -> String:
	var local := (point - global_position).rotated(-body.rotation)
	var side := "l" if local.y < 0.0 else "r"
	var lat := absf(local.y) / radius
	var from_front := dir.rotated(-body.rotation).x < 0.0
	var roll := randf()
	var part := "torso"
	if from_front:
		if lat > 0.42:
			part = "arm_" + side
		elif roll < 0.33:
			part = "head"
	else:
		if lat > 0.5:
			part = ("leg_" if roll < 0.5 else "arm_") + side
		elif roll < 0.22:
			part = "head"
		elif roll < 0.42:
			part = "leg_" + side
	if part != "torso" and not has[part]:
		part = "torso"
	return part


func hit(dmg: float, point: Vector2, dir: Vector2, limb_mult := 1.0) -> void:
	if dead:
		return
	var part := _pick_part(point, dir)
	knock += dir * (24.0 / s)
	knock = knock.limit_length(160.0)
	become_aggro()
	_apply(part, dmg, dir, limb_mult, point)


func slash(dmg: float, dir: Vector2) -> void:
	if dead:
		return
	var roll := randf()
	var part := "torso"
	if roll < 0.3:
		part = "head"
	elif roll < 0.85:
		part = "arm_l" if randf() < 0.5 else "arm_r"
	if part != "torso" and not has[part]:
		part = "torso"
	knock = (knock + dir * (140.0 / s)).limit_length(200.0)
	stun_t = maxf(stun_t, 0.25 if kind != "bruto" else 0.0)
	atk_t = 0.0
	become_aggro()
	_apply(part, dmg, dir, 1.8, global_position + dir * radius)


func blast(dmg: float, dir: Vector2) -> void:
	if dead:
		return
	knock = (knock + dir * (300.0 / s)).limit_length(320.0)
	become_aggro()
	var chance := clampf(dmg / (hp + 60.0), 0.0, 0.85)
	for l in LIMBS:
		if l != "head" and has[l] and randf() < chance:
			limb_hp[l] = 0.0
			_sever(l, (dir + Vector2.from_angle(randf() * TAU) * 0.6).normalized(), 1.6)
	hp -= dmg
	game.blood_hit(global_position, dir, 10)
	flash = 0.08
	if hp <= 0.0:
		if randf() < chance and has["head"]:
			_sever("head", dir, 1.6)
		_die(dir, false)


func _apply(part: String, dmg: float, dir: Vector2, limb_mult: float, point: Vector2) -> void:
	flash = 0.07
	game.blood_hit(point, dir, 5)
	match part:
		"torso":
			hp -= dmg
		"head":
			limb_hp["head"] -= dmg * 2.0
			hp -= dmg * 0.6
			if limb_hp["head"] <= 0.0:
				_sever("head", dir, 1.0)
				_die(dir, true)
				return
		_:
			limb_hp[part] -= dmg * limb_mult
			hp -= dmg * 0.45
			if limb_hp[part] <= 0.0:
				_sever(part, dir, 1.0)
	if hp <= 0.0:
		_die(dir, false)


func _sever(part: String, dir: Vector2, force: float) -> void:
	if not has[part]:
		return
	has[part] = false
	var sp: Sprite2D = spr[part]
	game.spawn_gib(sp, dir, force)
	sp.visible = false
	var st := Sprite2D.new()
	st.texture = game.tex.stump
	st.position = joints[part] + (Vector2(2, 0) * s if part == "head" else Vector2.ZERO)
	st.scale = Vector2(0.42, 0.42) * s
	body.add_child(st)
	if part == "head":
		st.z_index = 1
	var jp: Vector2 = body.to_global(joints[part])
	game.blood_burst(jp, dir, 16)
	game.add_decal(jp + dir * randf_range(8.0, 30.0), dir.angle(), randf_range(0.5, 0.9), game.BLOOD)
	game.sfx.play("splat", -3.0, global_position)
	game.on_dismember(self, part)
	if part.begins_with("leg") and legs_left() == 0:
		var c: CircleShape2D = shape.shape
		c.radius = radius * 0.8
		game.hud.msg("¡Ahora se arrastra!", 1.0, Color(1.0, 0.7, 0.6))


func _die(dir: Vector2, headshot: bool) -> void:
	if dead:
		return
	dead = true
	remove_from_group("zombies")
	shape.set_deferred("disabled", true)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	z_index = -6
	body.modulate = Color(0.72, 0.68, 0.68)
	body.position = Vector2.ZERO
	body.rotation += randf_range(-0.6, 0.6)
	position += dir * 8.0
	var bs := 0.5 * s
	if has["arm_l"]:
		spr["arm_l"].rotation = randf_range(-1.4, -0.2)
		spr["arm_l"].scale.x = bs
	if has["arm_r"]:
		spr["arm_r"].rotation = randf_range(0.2, 1.4)
		spr["arm_r"].scale.x = bs
	if has["leg_l"]:
		spr["leg_l"].scale.x = -bs * randf_range(0.6, 1.0)
	if has["leg_r"]:
		spr["leg_r"].scale.x = -bs * randf_range(0.6, 1.0)
	game.add_decal(global_position, randf() * TAU, randf_range(1.0, 1.5) * s, game.BLOOD)
	game.on_zombie_killed(self, headshot)
	if kind == "hinchado":
		game.bloat_explode(global_position)
		visible = false
		queue_free()
		return
	var tw := create_tween()
	tw.tween_interval(22.0)
	tw.tween_property(self, "modulate:a", 0.0, 3.0)
	tw.tween_callback(queue_free)
	game.add_corpse(self)
