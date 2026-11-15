extends Node2D
# Particulas ligeras dibujadas a mano (mucho mas baratas que crear un nodo por chispa).
# Una instancia vive por encima de la oscuridad (chispas, fogonazos, balas, ondas de ruido)
# y otra en el suelo del mundo (sangre, humo, casquillos).

enum { DOT, SPARK, SMOKE, FLASH, RING, SHELL, MUZZLE }

const MAX := 700

var game
var additive := false
var draw_bullets := false
var ps: Array = []


func _ready() -> void:
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m


func add(kind: int, pos: Vector2, vel: Vector2, life: float, size: float, col: Color, drag := 3.0, extra := 0.0) -> void:
	if ps.size() >= MAX:
		ps.pop_front()
	ps.append([kind, pos, vel, life, life, size, col, drag, extra])


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var alive: Array = []
	for p in ps:
		p[3] -= delta
		if p[3] > 0.0:
			p[1] += p[2] * delta
			p[2] *= exp(-p[7] * delta)
			alive.append(p)
	ps = alive
	queue_redraw()
	if game != null:
		game.prof["efectos"] += Time.get_ticks_usec() - t0


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	for p in ps:
		var k: int = p[0]
		var pos: Vector2 = p[1]
		var t: float = p[3] / p[4]
		var sz: float = p[5]
		var col: Color = p[6]
		match k:
			DOT:
				draw_circle(pos, sz * (0.5 + 0.5 * t), Color(col, col.a * minf(1.0, t * 2.0)))
			SPARK:
				var v: Vector2 = p[2]
				draw_line(pos, pos - v * 0.035, Color(col, col.a * t), sz)
			SMOKE:
				draw_circle(pos, sz * (1.7 - t * 0.7), Color(col, col.a * t * 0.5))
			FLASH:
				draw_circle(pos, sz * (0.6 + 0.4 * t), Color(col, col.a * t))
			RING:
				var r := lerpf(sz * 0.15, sz, 1.0 - t)
				draw_arc(pos, r, 0.0, TAU, 48, Color(col, col.a * t), 1.5 + 3.0 * t)
			SHELL:
				var a: float = p[8] + (1.0 - t) * 20.0
				var d := Vector2.from_angle(a) * 2.5
				draw_line(pos - d, pos + d, col, 2.0)
			MUZZLE:
				var dir := Vector2.from_angle(p[8])
				var side := dir.orthogonal() * sz * 0.35
				var tip := pos + dir * sz * (0.7 + 0.6 * t)
				draw_colored_polygon(PackedVector2Array([pos + side, tip, pos - side]), Color(col, col.a * t))
				draw_circle(pos, sz * 0.4 * t + 2.0, Color(1, 1, 0.85, t))
	if draw_bullets and game != null:
		_draw_combat()
	if game != null:
		game.prof["efectos"] += Time.get_ticks_usec() - t0


func _draw_combat() -> void:
	for b in game.bullets:
		var p: Vector2 = b["p"]
		var v: Vector2 = b["v"]
		var d := v.normalized()
		var tail: Vector2 = b["tail"]
		if b["bolt"]:
			draw_line(p - d * 22.0, p, Color(0.75, 0.6, 0.4, 0.95), 2.5)
			draw_line(p - d * 4.0, p, Color(0.9, 0.9, 1.0), 3.0)
		else:
			var from := p - d * minf(30.0, p.distance_to(tail))
			draw_line(from, p, Color(1.0, 0.75, 0.35, 0.55), 3.0)
			draw_line(p - d * 10.0, p, Color(1.0, 0.95, 0.8, 0.95), 1.6)
	var pl = game.player
	if pl != null and not pl.dead and game.playing:
		if pl.laser_len > 0.0:
			var a: Vector2 = pl.muzzle_pos()
			var e: Vector2 = a + pl.aim * pl.laser_len
			draw_line(a, e, Color(1.0, 0.1, 0.05, 0.18), 1.5)
			draw_circle(e, 2.5, Color(1.0, 0.2, 0.1, 0.6))
		if pl.swing_t > 0.0:
			var k: float = 1.0 - pl.swing_t / pl.SWING_TIME
			var base: float = pl.aim.angle()
			var r: float = pl.machete_range()
			draw_arc(pl.global_position, r * 0.85, base - 1.1, base - 1.1 + 2.2 * k, 20, Color(0.9, 0.95, 1.0, 0.35 * (1.0 - k)), 7.0)
