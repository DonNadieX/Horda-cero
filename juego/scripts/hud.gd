extends Control
# Interfaz: controles tactiles (dos joysticks flotantes + botones), vida, municion, radar,
# medidor de ruido/alerta, mensajes y pantallas de menu, mejoras, pausa y fin de partida.

const STICK_R := 85.0

var game
var font: Font
var show_touch := false
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var move_id := -1
var aim_id := -1
var move_origin := Vector2.ZERO
var move_pos := Vector2.ZERO
var aim_origin := Vector2.ZERO
var aim_pos := Vector2.ZERO
var btn_ids := {}
var hurt_t := 0.0
var acid := 0.0
var alert_flash := 0.0
var msg_text := ""
var msg_t := 0.0
var msg_color := Color.WHITE
var banner_text := ""
var banner_sub := ""
var banner_t := 0.0
var t := 0.0
var overlay: Control
var overlay_on := false
var _pause_open := false
var settings_back := ""
var screen := ""
var inset := Vector4.ZERO
var inset_t := 0.0
var redraw_i := 0


func setup(g) -> void:
	game = g
	font = ThemeDB.fallback_font
	process_mode = Node.PROCESS_MODE_ALWAYS
	show_touch = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)


# ------------------------------------------------------------------ pantallas

func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(12)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _button(text: String, sz: Vector2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.add_theme_font_size_override("font_size", 32)
	b.add_theme_stylebox_override("normal", _style(Color(0.12, 0.07, 0.06, 0.95), Color(0.75, 0.15, 0.1)))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.09, 0.07, 0.95), Color(1.0, 0.35, 0.2)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.35, 0.1, 0.06, 0.95), Color(1.0, 0.6, 0.3)))
	b.add_theme_stylebox_override("focus", _style(Color(0.12, 0.07, 0.06, 0.0), Color(1.0, 0.5, 0.3)))
	b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.85))
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b


func _label(text: String, sz: int, col: Color, outline := 8) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _open(dim := 0.72) -> VBoxContainer:
	for c in overlay.get_children():
		c.queue_free()
	_release_all()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.01, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	overlay.visible = true
	overlay_on = true
	return vb


func hide_overlay() -> void:
	screen = ""
	overlay.visible = false
	overlay_on = false
	for c in overlay.get_children():
		c.queue_free()


func show_loading() -> void:
	var vb := _open(1.0)
	vb.add_child(_label("HORDA CERO", 84, Color(0.85, 0.12, 0.08), 12))
	vb.add_child(_label("Generando la ciudad...", 28, Color(0.9, 0.85, 0.8)))


func show_menu() -> void:
	var vb := _open(0.55)
	screen = "menu"
	vb.add_child(_label("HORDA CERO", 96, Color(0.88, 0.12, 0.08), 14))
	vb.add_child(_label("Sobrevive a la horda en la ciudad muerta", 26, Color(0.95, 0.85, 0.75)))
	if game.best > 0:
		vb.add_child(_label("Récord: %d puntos" % game.best, 24, Color(1.0, 0.8, 0.3)))
	var b := _button("JUGAR", Vector2(340, 96), game.start_game)
	b.add_theme_font_size_override("font_size", 44)
	vb.add_child(b)
	vb.add_child(_button("AJUSTES", Vector2(260, 64), show_settings.bind("menu")))
	var help := "Joystick izquierdo: moverte   ·   Joystick derecho: apuntar y disparar\n" \
		+ "Cada disparo hace RUIDO: si llenas el medidor, llega una horda.\n" \
		+ "La BALLESTA y el MACHETE son silenciosos. Las BENGALAS distraen a los infectados.\n" \
		+ "Apunta a brazos, piernas y cabeza: puedes desmembrarlos.\n" \
		+ "Disparar a un coche con alarma atrae a todos hacia él."
	if not (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		help += "\n\nPC: WASD mover · ratón apuntar/disparar · E machete · Espacio esquivar\nR recargar · Q arma · F bengala · G bomba · L linterna · Esc pausa"
	vb.add_child(_label(help, 20, Color(0.8, 0.8, 0.82), 6))
	b.grab_focus.call_deferred()


func show_upgrades(opts: Array) -> void:
	var vb := _open(0.75)
	vb.add_child(_label("OLEADA %d SUPERADA" % game.wave, 56, Color(0.4, 0.95, 0.45), 10))
	vb.add_child(_label("Elige una mejora", 28, Color(0.95, 0.9, 0.85)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	for id in opts:
		var u: Dictionary = game.UPGRADES[id]
		var card := _button("", Vector2(330, 240), _pick.bind(id))
		var inner := VBoxContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 14)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(inner)
		inner.add_child(_label(u["t"], 30, Color(1.0, 0.75, 0.35), 6))
		inner.add_child(_label(u["d"], 21, Color(0.92, 0.9, 0.88), 4))
		var lvl: int = game.up(id)
		if u["max"] > 1:
			inner.add_child(_label("Nivel %d / %d" % [lvl + 1, u["max"]], 18, Color(0.7, 0.7, 0.7), 4))
		hb.add_child(card)
	if hb.get_child_count() > 0:
		(hb.get_child(0) as Button).grab_focus.call_deferred()
	game.sfx.play("upgrade", -6.0)


func _pick(id: String) -> void:
	game.apply_upgrade(id)


func show_over(wave: int, kills: int, hs: int, limbs: int, score: int, best: int, secs: float) -> void:
	var vb := _open(0.78)
	vb.add_child(_label("HAS CAÍDO", 88, Color(0.88, 0.12, 0.08), 12))
	var txt := "Oleada alcanzada: %d\nInfectados eliminados: %d\nDecapitaciones: %d   ·   Extremidades arrancadas: %d\nTiempo: %d:%02d" % [wave, kills, hs, limbs, int(secs) / 60, int(secs) % 60]
	vb.add_child(_label(txt, 26, Color(0.95, 0.9, 0.85), 6))
	var rec := "¡NUEVO RÉCORD!" if score >= best and score > 0 else "Récord: %d" % best
	vb.add_child(_label("Puntos: %d   ·   %s" % [score, rec], 32, Color(1.0, 0.8, 0.3), 8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var b := _button("JUGAR DE NUEVO", Vector2(360, 90), game.restart)
	hb.add_child(b)
	hb.add_child(_button("MENÚ", Vector2(220, 90), game.to_menu))
	b.grab_focus.call_deferred()


func toggle_pause() -> void:
	if not game.playing or game.over:
		return
	if get_tree().paused:
		if _pause_open:
			_pause_open = false
			hide_overlay()
			get_tree().paused = false
		return
	if game.Dbg.enabled:
		game.Dbg.last_shot = get_viewport().get_texture().get_image()
	get_tree().paused = true
	_pause_open = true
	_show_pause()


func _show_pause() -> void:
	var vb := _open(0.7)
	screen = "pausa"
	vb.add_child(_label("PAUSA", 80, Color(0.95, 0.9, 0.85), 12))
	var b := _button("CONTINUAR", Vector2(340, 80), toggle_pause)
	vb.add_child(b)
	vb.add_child(_button("AJUSTES", Vector2(340, 70), show_settings.bind("pause")))
	vb.add_child(_button("SALIR AL MENÚ", Vector2(340, 70), game.to_menu))
	b.grab_focus.call_deferred()


func show_settings(back: String) -> void:
	settings_back = back
	var st: Dictionary = game.settings
	var vb := _open(0.82)
	screen = "ajustes"
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_label("AJUSTES", 54, Color(0.95, 0.9, 0.85), 10))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	var opts := [
		["sombras", "Sombras de la linterna", "Bonitas pero caras; en algunos móviles apagan la luz"],
		["relieve", "Relieve en texturas", "Mapas de normales: la luz da volumen al suelo y a los personajes"],
		["res_reducida", "Resolución reducida", "Dibuja a 720p y escala: muchos más FPS en móviles"],
		["vibracion", "Vibración", "Al recibir golpes y con explosiones"],
		["depuracion", "Modo depuración", "Panel de rendimiento y registro detallado para informes"],
	]
	for o in opts:
		var on: bool = st[o[0]]
		var b := _button("%s: %s" % [o[1], "SÍ" if on else "NO"], Vector2(470, 62), _toggle_setting.bind(o[0]))
		b.add_theme_font_size_override("font_size", 22)
		b.tooltip_text = o[2]
		grid.add_child(b)
	var tb := _button("Prueba de luces", Vector2(470, 62), _light_test)
	tb.add_theme_font_size_override("font_size", 22)
	grid.add_child(tb)
	var rb := _button("Copiar y guardar informe", Vector2(470, 62), _report)
	rb.add_theme_font_size_override("font_size", 22)
	grid.add_child(rb)
	vb.add_child(_label("El informe incluye datos del móvil, rendimiento, errores y el registro de la partida.\nSe copia al portapapeles y se guarda en Descargas/HordaCero: pégalo o adjúntalo en el chat.", 17, Color(0.75, 0.75, 0.78), 4))
	var back_b := _button("VOLVER", Vector2(260, 66), _settings_back)
	vb.add_child(back_b)
	back_b.grab_focus.call_deferred()


func _toggle_setting(k: String) -> void:
	game.set_setting(k, not game.settings[k])
	show_settings(settings_back)


func _settings_back() -> void:
	if settings_back == "pause":
		_show_pause()
	else:
		show_menu()


func _light_test() -> void:
	var back := settings_back
	hide_overlay()
	var verdict: String = await game.debug.run_light_test()
	show_settings(back)
	_info("Prueba de luces", verdict + "\n\n" + game.Dbg.light_report)


func _report() -> void:
	var r: String = game.debug_report()
	_info("Informe", r + "\n\nEn Android también puedes pegarlo directamente en el chat.")


func _info(title: String, text: String) -> void:
	var back := settings_back
	var vb := _open(0.88)
	screen = "info"
	vb.add_child(_label(title, 44, Color(1.0, 0.8, 0.4), 8))
	var l := _label(text, 18, Color(0.92, 0.92, 0.92), 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(size.x - 80.0, 1100.0), 0)
	vb.add_child(l)
	vb.add_child(_button("VOLVER", Vector2(260, 66), show_settings.bind(back)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		match screen:
			"ajustes", "info":
				_settings_back()
			"pausa":
				toggle_pause()
			"":
				if game.playing:
					toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if game != null and game.playing and not get_tree().paused and not overlay_on:
			toggle_pause()


func msg(text: String, dur := 2.5, color := Color.WHITE) -> void:
	msg_text = text
	msg_t = dur
	msg_color = color


func banner(text: String, sub: String) -> void:
	banner_text = text
	banner_sub = sub
	banner_t = 3.2


func hurt(amount: float) -> void:
	hurt_t = minf(1.0, hurt_t + amount / 22.0)


# ------------------------------------------------------------------ controles tactiles

func _buttons() -> Dictionary:
	# Respeta la zona segura (muesca de la camara, barra de navegacion si aparece).
	var l := inset.x
	var w := size.x - inset.y
	var tp := inset.z
	var h := size.y - inset.w
	return {
		"swing": [Vector2(w - 92.0, h - 320.0), 50.0, "MACHETE", Color(0.75, 0.85, 1.0)],
		"dodge": [Vector2(w - 222.0, h - 378.0), 44.0, "ESQUIVAR", Color(0.5, 1.0, 0.7)],
		"reload": [Vector2(w - 205.0, tp + 150.0), 38.0, "RECARGAR", Color(1.0, 0.9, 0.5)],
		"swap": [Vector2(w - 85.0, tp + 175.0), 42.0, "ARMA", Color(1.0, 0.8, 0.4)],
		"flare": [Vector2(l + 85.0, h - 320.0), 44.0, "BENGALA", Color(1.0, 0.4, 0.3)],
		"bomb": [Vector2(l + 205.0, h - 375.0), 42.0, "BOMBA", Color(1.0, 0.65, 0.25)],
		"light": [Vector2(l + 62.0, tp + 250.0), 32.0, "LUZ", Color(1.0, 1.0, 0.8)],
		"pause": [Vector2(w - 50.0, tp + 50.0), 28.0, "II", Color(0.9, 0.9, 0.9)],
	}


func _update_inset() -> void:
	var ws := DisplayServer.window_get_size()
	if ws.x <= 0 or ws.y <= 0:
		return
	var sa := DisplayServer.get_display_safe_area()
	var k := size.x / float(ws.x)
	inset = Vector4(
		clampf(sa.position.x * k, 0.0, 160.0), clampf((ws.x - sa.end.x) * k, 0.0, 160.0),
		clampf(sa.position.y * k, 0.0, 120.0), clampf((ws.y - sa.end.y) * k, 0.0, 120.0))


func _button_at(p: Vector2) -> String:
	var bs := _buttons()
	for k in bs:
		var b: Array = bs[k]
		var c: Vector2 = b[0]
		if p.distance_to(c) <= float(b[1]) * 1.15:
			return str(k)
	return ""


func _press(b: String) -> void:
	var p = game.player
	match b:
		"swing":
			p.swing()
		"dodge":
			p.dodge()
		"reload":
			p.start_reload()
		"swap":
			p.next_weapon()
		"flare":
			p.throw_item("flare")
		"bomb":
			p.throw_item("bomb")
		"light":
			p.toggle_light()
		"pause":
			toggle_pause()


func _release_all() -> void:
	move_id = -1
	aim_id = -1
	move_vec = Vector2.ZERO
	aim_vec = Vector2.ZERO
	btn_ids.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		show_touch = true
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		toggle_pause()
		return
	if game == null or game.player == null or overlay_on or not game.playing or game.over:
		if move_id != -1 or aim_id != -1:
			_release_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var b := _button_at(event.position)
			if b != "":
				btn_ids[event.index] = b
				_press(b)
				return
			if event.position.x < size.x * 0.45:
				if move_id == -1:
					move_id = event.index
					move_origin = event.position
					move_pos = event.position
			elif aim_id == -1:
				aim_id = event.index
				aim_origin = event.position
				aim_pos = event.position
		else:
			btn_ids.erase(event.index)
			if event.index == move_id:
				move_id = -1
				move_vec = Vector2.ZERO
			if event.index == aim_id:
				aim_id = -1
				aim_vec = Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index == move_id:
			move_pos = event.position
			var v := (move_pos - move_origin) / STICK_R
			if v.length() > 1.0:
				move_origin = move_pos - v.normalized() * STICK_R
				v = v.normalized()
			move_vec = v
		elif event.index == aim_id:
			aim_pos = event.position
			var v := (aim_pos - aim_origin) / STICK_R
			if v.length() > 1.0:
				aim_origin = aim_pos - v.normalized() * STICK_R
				v = v.normalized()
			aim_vec = v


# ------------------------------------------------------------------ dibujo

func _process(delta: float) -> void:
	t += delta
	inset_t -= delta
	if inset_t <= 0.0:
		inset_t = 1.0
		_update_inset()
	hurt_t = maxf(0.0, hurt_t - delta * 1.4)
	acid = maxf(0.0, acid - delta * 0.4)
	alert_flash = maxf(0.0, alert_flash - delta * 0.8)
	msg_t = maxf(0.0, msg_t - delta)
	banner_t = maxf(0.0, banner_t - delta)
	# Redibujar el HUD cuesta CPU: a 30 Hz basta, salvo mientras se mueven los joysticks.
	redraw_i += 1
	if redraw_i % 2 == 0 or move_id != -1 or aim_id != -1 or hurt_t > 0.0:
		queue_redraw()


func _text(pos: Vector2, text: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, pos, text, align, width, sz, 6, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, text, align, width, sz, col)


func _bar(pos: Vector2, sz: Vector2, frac: float, col: Color) -> void:
	draw_rect(Rect2(pos - Vector2(3, 3), sz + Vector2(6, 6)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(pos, Vector2(sz.x * clampf(frac, 0.0, 1.0), sz.y)), col)
	draw_rect(Rect2(pos, Vector2(sz.x * clampf(frac, 0.0, 1.0), sz.y * 0.35)), Color(1, 1, 1, 0.15))


func _draw() -> void:
	if game == null or game.player == null or game.tex == null:
		return
	var t0 := Time.get_ticks_usec()
	_draw_hud()
	game.prof["hud"] += Time.get_ticks_usec() - t0


func _draw_hud() -> void:
	var p = game.player
	var w := size.x
	var h := size.y
	var full := Rect2(0, 0, w, h)
	var vig: Texture2D = game.tex.vignette
	draw_texture_rect(vig, full, false, Color(0, 0, 0, 0.55))
	if hurt_t > 0.0:
		draw_texture_rect(vig, full, false, Color(0.8, 0.0, 0.0, hurt_t * 0.9))
	if game.playing and p.hp < p.max_hp * 0.3 and not p.dead:
		draw_texture_rect(vig, full, false, Color(0.7, 0.0, 0.0, 0.35 + 0.25 * sin(t * 6.0)))
	if acid > 0.0:
		draw_texture_rect(vig, full, false, Color(0.4, 0.8, 0.1, acid * 0.8))
	if alert_flash > 0.0:
		draw_rect(full, Color(0.8, 0.1, 0.05, alert_flash * 0.25))
	if not game.playing and not game.over:
		return

	# Vida
	_text(Vector2(24, 40), "VIDA", 20, Color(0.9, 0.9, 0.9))
	_bar(Vector2(88, 24), Vector2(250, 20), p.hp / p.max_hp, Color(0.85, 0.15, 0.1).lerp(Color(0.3, 0.85, 0.35), p.hp / p.max_hp))
	_text(Vector2(345, 41), "%d" % int(ceil(p.hp)), 20, Color.WHITE)
	# Arma y municion
	var wpn: Dictionary = p.weapon()
	var ammo := "%d / ∞" % wpn["mag"] if wpn["reserve"] < 0 else "%d / %d" % [wpn["mag"], wpn["reserve"]]
	_text(Vector2(24, 82), wpn["name"], 26, Color(1.0, 0.85, 0.5))
	_text(Vector2(200, 82), ammo, 26, Color.WHITE if wpn["mag"] > 0 else Color(1.0, 0.3, 0.2))
	if p.reload_t > 0.0:
		_bar(Vector2(24, 96), Vector2(200, 8), 1.0 - p.reload_t / p.reload_total, Color(1.0, 0.9, 0.5))
		_text(Vector2(232, 106), "RECARGANDO", 16, Color(1.0, 0.9, 0.5))
	elif wpn["id"] == "ballesta" or wpn["id"] == "pistola" and game.up("silenciador") > 0:
		_text(Vector2(24, 112), "silenciosa" if wpn["id"] == "ballesta" else "con silenciador", 16, Color(0.6, 0.9, 1.0))
	_text(Vector2(24, 146), "Bengalas: %d    Bombas: %d" % [p.flares, p.bombs], 20, Color(1.0, 0.65, 0.5))
	if not p.light_on:
		_text(Vector2(24, 176), "Linterna apagada", 18, Color(0.7, 0.8, 1.0))

	# Oleada, puntos y RUIDO
	var cx := w * 0.5
	var left: int = game.alive_count() + game.to_spawn
	_text(Vector2(cx - 300, 40), "OLEADA %d   ·   Quedan %d" % [game.wave, left], 26, Color(0.95, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 600)
	_text(Vector2(cx - 300, 68), "%d puntos" % game.score, 20, Color(1.0, 0.8, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 600)
	var al: float = game.alert / 100.0
	var acol := Color(0.95, 0.8, 0.2).lerp(Color(1.0, 0.15, 0.1), al)
	if al > 0.75:
		acol = acol.lerp(Color.WHITE, 0.3 + 0.3 * sin(t * 14.0))
	_bar(Vector2(cx - 140, 84), Vector2(280, 10), al, acol)
	_text(Vector2(cx - 300, 116), "RUIDO" if al < 0.75 else "¡LA HORDA ESTÁ CERCA!", 16, acol, HORIZONTAL_ALIGNMENT_CENTER, 600)

	# Radar
	_radar(Vector2(cx, h - 74), 60.0)

	# Banner y mensajes
	if overlay_on:
		return
	if banner_t > 0.0:
		var a := clampf(banner_t, 0.0, 1.0)
		_text(Vector2(0, h * 0.3), banner_text, 64, Color(0.95, 0.2, 0.12, a), HORIZONTAL_ALIGNMENT_CENTER, w)
		if banner_sub != "":
			_text(Vector2(0, h * 0.3 + 44), banner_sub, 24, Color(0.95, 0.9, 0.85, a), HORIZONTAL_ALIGNMENT_CENTER, w)
	if msg_t > 0.0:
		var a := clampf(msg_t * 2.0, 0.0, 1.0)
		_text(Vector2(0, h * 0.42), msg_text, 28, Color(msg_color, a), HORIZONTAL_ALIGNMENT_CENTER, w)

	if show_touch and game.playing and not p.dead:
		_draw_touch(p)


func _radar(c: Vector2, r: float) -> void:
	draw_circle(c, r + 3.0, Color(0, 0, 0, 0.55))
	draw_arc(c, r, 0.0, TAU, 40, Color(0.5, 0.9, 0.5, 0.35), 2.0)
	draw_arc(c, r * 0.5, 0.0, TAU, 32, Color(0.5, 0.9, 0.5, 0.15), 1.0)
	var pp: Vector2 = game.player.global_position
	var rng_ := 1100.0
	for l in game.lures:
		if is_instance_valid(l):
			var d: Vector2 = (l.global_position - pp) / rng_ * r
			if d.length() < r:
				draw_circle(c + d, 4.0, Color(1.0, 0.6, 0.2, 0.6 + 0.4 * sin(t * 10.0)))
	for z in get_tree().get_nodes_in_group("zombies"):
		var d: Vector2 = (z.global_position - pp) / rng_ * r
		if d.length() < r:
			var col := Color(1.0, 0.2, 0.15) if z.aggro else Color(0.7, 0.7, 0.7, 0.7)
			draw_circle(c + d, 3.5 if z.kind == "bruto" else 2.2, col)
	var a: float = game.player.aim.angle()
	draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(a) * 7.0, c + Vector2.from_angle(a + 2.4) * 5.0, c + Vector2.from_angle(a - 2.4) * 5.0]), Color.WHITE)


func _draw_touch(p) -> void:
	var w := size.x
	var h := size.y
	# Joysticks
	var mo := move_origin if move_id != -1 else Vector2(inset.x + 170, h - inset.w - 160)
	var mp := move_pos if move_id != -1 else mo
	draw_circle(mo, STICK_R, Color(1, 1, 1, 0.07 if move_id == -1 else 0.12))
	draw_arc(mo, STICK_R, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 2.5)
	draw_circle(mo + (mp - mo).limit_length(STICK_R), 34.0, Color(1, 1, 1, 0.22 if move_id == -1 else 0.4))
	var ao := aim_origin if aim_id != -1 else Vector2(w - inset.y - 290, h - inset.w - 160)
	var ap := aim_pos if aim_id != -1 else ao
	var firing: bool = aim_vec.length() > 0.42
	draw_circle(ao, STICK_R, Color(1, 0.3, 0.2, 0.07 if aim_id == -1 else 0.13))
	draw_arc(ao, STICK_R, 0.0, TAU, 40, Color(1, 0.4, 0.3, 0.3), 2.5)
	draw_arc(ao, STICK_R * 0.42, 0.0, TAU, 32, Color(1, 0.4, 0.3, 0.2), 1.5)
	draw_circle(ao + (ap - ao).limit_length(STICK_R), 34.0, Color(1, 0.35, 0.25, 0.55 if firing else 0.3))
	if aim_id == -1:
		_text(ao + Vector2(-80, 6), "APUNTAR", 16, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 160)
	if move_id == -1:
		_text(mo + Vector2(-80, 6), "MOVER", 16, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 160)
	# Botones
	var bs := _buttons()
	for k in bs:
		var b: Array = bs[k]
		var c: Vector2 = b[0]
		var r: float = b[1]
		var col: Color = b[3]
		var pressed := btn_ids.values().has(k)
		var cd := 0.0
		var label: String = b[2]
		var enabled := true
		match k:
			"swing":
				cd = clampf(p.machete_cd / (0.55 - 0.12 * game.up("machete")), 0.0, 1.0)
			"dodge":
				cd = clampf(p.dodge_cd / (1.5 - 0.25 * game.up("botas")), 0.0, 1.0)
			"flare":
				label = "BENGALA %d" % p.flares
				enabled = p.flares > 0
			"bomb":
				label = "BOMBA %d" % p.bombs
				enabled = p.bombs > 0
			"light":
				enabled = p.light_on
		var alpha := 1.0 if enabled else 0.45
		draw_circle(c, r, Color(0.05, 0.05, 0.06, (0.55 if not pressed else 0.8) * alpha))
		draw_arc(c, r, 0.0, TAU, 40, Color(col, 0.7 * alpha), 3.0)
		if cd > 0.0:
			draw_arc(c, r - 6.0, -PI * 0.5, -PI * 0.5 + TAU * cd, 32, Color(col, 0.5), 6.0)
		var fs := 18
		if label.length() > 7:
			fs = 13
		elif label.length() > 5:
			fs = 15
		_text(c + Vector2(-r, 6), label, fs, Color(col, alpha), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
