extends Node2D
# Objetos arrojadizos:
# - Bengala: luz roja y siseo durante unos segundos. Los infectados cercanos van hacia ella
#   y se olvidan de ti (si no estas pegado a ellos). Perfecta para escapar o reagruparlos.
# - Bomba de tubo: pita cada vez mas rapido atrayendo a TODOS los cercanos y luego explota,
#   arrancando extremidades a lo grande.

var game
var kind := "flare"
var start := Vector2.ZERO
var target := Vector2.ZERO
var t := 0.0
var fly := 0.5
var landed := false
var life := 10.0
var radius := 750.0
var field := PackedInt32Array()
var spr: Sprite2D
var light: PointLight2D
var beep_t := 0.0
var hiss_t := 0.0


func setup(g, k: String, from: Vector2, to: Vector2) -> void:
	game = g
	kind = k
	start = from
	position = from
	target = game.clamp_free(from, to)
	fly = clampf(from.distance_to(target) / 560.0, 0.2, 0.65)
	z_index = 2
	spr = Sprite2D.new()
	if kind != "alarm":
		spr.texture = game.tex.items["flare" if kind == "flare" else "bomb"]
	spr.scale = Vector2(0.55, 0.55)
	add_child(spr)
	light = PointLight2D.new()
	light.texture = game.tex.light_round
	light.shadow_enabled = false
	light.add_to_group("luces")
	light.height = 60.0
	add_child(light)
	if kind == "flare":
		life = 10.0 * (1.0 + 0.5 * game.up("bengalas"))
		radius = 760.0
		light.color = Color(1.0, 0.28, 0.16)
		light.texture_scale = 3.4
		light.energy = 0.7
	elif kind == "alarm":
		life = 9.0
		radius = 1000.0
		light.color = Color(1.0, 0.55, 0.2)
		light.texture_scale = 2.2
		light.energy = 0.0
		fly = 0.0
		landed = true
		field = game.compute_field(from)
		game.lures.append(self)
	else:
		life = 4.0
		radius = 950.0
		light.color = Color(1.0, 0.1, 0.05)
		light.texture_scale = 1.0
		light.energy = 0.0


func _process(delta: float) -> void:
	if not game.playing:
		return
	if not landed:
		t += delta
		var k := minf(t / fly, 1.0)
		position = start.lerp(target, k)
		spr.scale = Vector2.ONE * 0.55 * (1.0 + sin(PI * k) * 0.7)
		spr.rotation += 14.0 * delta
		if k >= 1.0:
			_land()
		return
	life -= delta
	if kind == "flare":
		var fade := clampf(life / 1.5, 0.0, 1.0)
		light.energy = (1.4 + randf() * 0.5) * fade
		light.texture_scale = 3.2 + randf() * 0.35
		var tip := global_position + Vector2.from_angle(spr.rotation) * 7.0
		for i in 2:
			game.fx_top.add(game.fx_top.SPARK, tip, Vector2.from_angle(randf() * TAU) * randf_range(50.0, 190.0), randf_range(0.2, 0.45), 1.6, Color(1.0, 0.55, 0.3), 3.0)
		game.fx_top.add(game.fx_top.FLASH, tip, Vector2.ZERO, 0.08, 9.0 + randf() * 5.0, Color(1.0, 0.4, 0.25, 0.8))
		if randf() < 0.25:
			game.fx_ground.add(game.fx_ground.SMOKE, tip, Vector2(randf_range(-15, 15), randf_range(-30, -10)), 1.6, 12.0, Color(0.6, 0.35, 0.35, 0.35), 0.5)
		hiss_t -= delta
		if hiss_t <= 0.0:
			hiss_t = 1.3
			game.sfx.play("hiss", -12.0, global_position)
		if life <= 0.0:
			_end()
	elif kind == "alarm":
		beep_t -= delta
		if beep_t <= 0.0:
			beep_t = 0.4
			game.sfx.play("alarm", -2.0, global_position, 1.0 if int(life * 2.5) % 2 == 0 else 1.3)
			light.energy = 1.8
			for side in [-1.0, 1.0]:
				game.fx_top.add(game.fx_top.FLASH, global_position + Vector2(side * 22.0, 0).rotated(randf() * 0.2), Vector2.ZERO, 0.3, 14.0, Color(1.0, 0.6, 0.2))
		light.energy = move_toward(light.energy, 0.0, delta * 4.0)
		if life <= 0.0:
			_end()
	else:
		beep_t -= delta
		var interval := clampf(life / 4.0 * 0.6, 0.07, 0.6)
		if beep_t <= 0.0:
			beep_t = interval
			game.sfx.play("beep", -6.0, global_position)
			light.energy = 2.2
			game.fx_top.add(game.fx_top.FLASH, global_position, Vector2.ZERO, 0.12, 8.0, Color(1.0, 0.15, 0.1))
			game.fx_top.add(game.fx_top.RING, global_position, Vector2.ZERO, 0.6, 90.0, Color(1.0, 0.25, 0.2, 0.5))
		light.energy = move_toward(light.energy, 0.0, delta * 9.0)
		if life <= 0.0:
			var lvl: int = game.up("bombas")
			game.explode(global_position, 150.0 + 25.0 * lvl, 260.0 + 50.0 * lvl)
			_end()


func _land() -> void:
	landed = true
	spr.scale = Vector2(0.55, 0.55)
	field = game.compute_field(global_position)
	game.lures.append(self)
	if kind == "flare":
		game.sfx.play("hiss", -6.0, global_position)
		game.fx_top.add(game.fx_top.RING, global_position, Vector2.ZERO, 0.8, 140.0, Color(1.0, 0.4, 0.3, 0.6))
	else:
		game.hud.msg("Bomba de tubo: ¡apártate!", 1.5, Color(1.0, 0.6, 0.3))


func _end() -> void:
	game.lures.erase(self)
	queue_free()
