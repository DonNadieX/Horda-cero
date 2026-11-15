extends Control
# MODO DEPURACION
# - Panel en pantalla: FPS, tiempos por fotograma, llamadas de dibujo, memoria, numero de
#   objetos, tiempo de CPU por sistema (IA, balas, efectos...), estado de luces y pantalla.
# - Registro en archivo (user://depuracion/registro_actual.txt) con eventos, picos de
#   rendimiento (con contexto) y una muestra por segundo.
# - Captura los errores y avisos del propio motor (shaders, OpenGL, scripts) con Logger.
# - Detecta si la sesion anterior se cerro de forma inesperada.
# - Prueba de luces: mide el brillo real de la pantalla con distintas configuraciones para
#   saber si la linterna, las sombras o el relieve fallan en este movil.
# - Informe completo para compartir: se copia al portapapeles y se guarda (con una captura
#   de pantalla) en Descargas/HordaCero o Documentos/HordaCero.

const VERSION := "1.1"
const DIR := "user://depuracion"


class ErrLogger extends Logger:
	var mutex := Mutex.new()
	var pending: Array[String] = []
	var total := 0

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kinds := ["ERROR", "AVISO", "ERROR DE SCRIPT", "ERROR DE SHADER"]
		var txt: String = "%s: %s" % [kinds[clampi(error_type, 0, 3)], rationale if rationale != "" else code]
		if rationale != "" and code != "":
			txt += " [" + code + "]"
		txt += " (%s:%d %s)" % [file, line, function]
		for bt in script_backtraces:
			if bt != null and bt.get_frame_count() > 0:
				txt += "\n" + bt.format(4, 4)
		mutex.lock()
		pending.append(txt)
		total += 1
		if pending.size() > 300:
			pending.pop_front()
		mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		if not error:
			return
		mutex.lock()
		pending.append("STDERR: " + message.strip_edges())
		total += 1
		mutex.unlock()

	func take() -> Array[String]:
		mutex.lock()
		var out: Array[String] = pending.duplicate()
		pending.clear()
		mutex.unlock()
		return out


static var enabled := false
static var inited := false
static var start_ms := 0
static var lines: Array[String] = []
static var errors: Array[String] = []
static var error_total := 0
static var file: FileAccess = null
static var prev_note := ""
static var prev_tail := ""
static var err_logger = null
static var tex_ms := -1
static var light_report := ""
static var frames := 0
static var ft_sum := 0.0
static var ft_hist := PackedFloat32Array()
static var worst: Array = []
static var spikes := 0
static var peaks := {}
static var prof_avg := {}
static var last_shot: Image = null

var game
var font: Font
var last_us := 0
var graph := PackedFloat32Array()
var sec_t := 0.0
var sec_frames := 0
var sec_max := 0.0
var sec_sum := 0.0
var fps_shown := 0.0
var ms_shown := 0.0
var max_shown := 0.0
var spike_cool := 0.0
var lights_on := 0
var testing := false


# ------------------------------------------------------------------ sesion y registro

static func init_session() -> void:
	if inited:
		return
	inited = true
	start_ms = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(DIR)
	var marker := DIR + "/sesion_activa.txt"
	var cur := DIR + "/registro_actual.txt"
	var prev := DIR + "/registro_anterior.txt"
	if FileAccess.file_exists(marker):
		prev_note = "La sesión anterior (%s) no se cerró limpiamente: posible cierre inesperado o Android cerró la app en segundo plano." % FileAccess.get_file_as_string(marker).strip_edges()
		if FileAccess.file_exists(cur):
			prev_tail = _tail(FileAccess.get_file_as_string(cur), 100)
	if FileAccess.file_exists(cur):
		if FileAccess.file_exists(prev):
			DirAccess.remove_absolute(prev)
		DirAccess.rename_absolute(cur, prev)
	file = FileAccess.open(cur, FileAccess.WRITE)
	_mark_active(true)
	if err_logger == null and ClassDB.class_exists("Logger"):
		err_logger = ErrLogger.new()
		OS.add_logger(err_logger)
	note("INFO", "Sesión iniciada %s · Horda Cero %s" % [Time.get_datetime_string_from_system(), VERSION])
	for l in device_info().split("\n"):
		note("INFO", l)
	if prev_note != "":
		note("AVISO", prev_note)


static func _mark_active(active: bool) -> void:
	var marker := DIR + "/sesion_activa.txt"
	if active:
		var m := FileAccess.open(marker, FileAccess.WRITE)
		if m != null:
			m.store_string(Time.get_datetime_string_from_system())
	elif FileAccess.file_exists(marker):
		DirAccess.remove_absolute(marker)


static func app_paused(paused: bool) -> void:
	note("INFO", "App en segundo plano" if paused else "App de vuelta en primer plano")
	_mark_active(not paused)


static func end_session() -> void:
	note("INFO", "Sesión cerrada correctamente")
	_mark_active(false)


static func note(cat: String, msg: String) -> void:
	var t := (Time.get_ticks_msec() - start_ms) / 1000.0
	var line := "[%8.2f] %s %s" % [t, cat.rpad(6), msg]
	lines.append(line)
	if lines.size() > 700:
		lines.pop_front()
	if file != null:
		file.store_line(line)
		file.flush()


static func _tail(txt: String, n: int) -> String:
	var ls := txt.split("\n")
	var from := maxi(0, ls.size() - n)
	return "\n".join(ls.slice(from))


static func device_info() -> String:
	var s := PackedStringArray()
	s.append("Sistema: %s %s · Modelo: %s" % [OS.get_name(), OS.get_version(), OS.get_model_name()])
	s.append("CPU: %s · %d núcleos" % [OS.get_processor_name(), OS.get_processor_count()])
	s.append("GPU: %s (%s) · API %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), RenderingServer.get_video_adapter_api_version()])
	s.append("Renderizador: %s / %s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	s.append("Motor: Godot %s" % Engine.get_version_info()["string"])
	var mi := OS.get_memory_info()
	s.append("Memoria del equipo: %d MB en total, %d MB disponibles" % [int(mi.get("physical", -1) / 1048576), int(mi.get("available", -1) / 1048576)])
	s.append("Pantalla: %s · %d ppp · %.0f Hz · Ventana %s (modo %s) · Zona segura %s" % [DisplayServer.screen_get_size(), DisplayServer.screen_get_dpi(), DisplayServer.screen_get_refresh_rate(), DisplayServer.window_get_size(), _mode_name(DisplayServer.window_get_mode()), DisplayServer.get_display_safe_area()])
	return "\n".join(s)


static func _mode_name(m: int) -> String:
	match m:
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return "pantalla completa"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "pantalla completa exclusiva"
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return "maximizada (barras visibles)"
		DisplayServer.WINDOW_MODE_MINIMIZED:
			return "minimizada"
	return "ventana"


static func peak(k: String, v: float) -> void:
	if v > peaks.get(k, -1.0):
		peaks[k] = v


# ------------------------------------------------------------------ nodo: medicion y panel

func setup(g) -> void:
	game = g
	font = ThemeDB.fallback_font
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	last_us = Time.get_ticks_usec()
	graph.resize(150)
	graph.fill(0.0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - last_us) / 1000.0
	last_us = now
	_pull_errors()
	if game == null or game.player == null or testing:
		return
	frames += 1
	ft_sum += ms
	if ft_hist.size() < 40000:
		ft_hist.append(ms)
	graph.remove_at(0)
	graph.append(ms)
	sec_frames += 1
	sec_sum += ms
	sec_max = maxf(sec_max, ms)
	sec_t += ms / 1000.0
	spike_cool -= ms / 1000.0
	for k in game.prof:
		var v: float = game.prof[k] / 1000.0
		prof_avg[k] = lerpf(prof_avg.get(k, v), v, 0.05)
		game.prof[k] = 0
	var paused: bool = get_tree().paused
	if ms > 60.0 and not paused and (Time.get_ticks_msec() - start_ms) > 4000:
		spikes += 1
		var ctx := _context()
		worst.append([ms, (Time.get_ticks_msec() - start_ms) / 1000.0, ctx])
		worst.sort_custom(func(a, b): return a[0] > b[0])
		if worst.size() > 12:
			worst.resize(12)
		if spike_cool <= 0.0:
			spike_cool = 1.0
			note("PICO", "%.0f ms · %s" % [ms, ctx])
	if sec_t >= 1.0:
		fps_shown = sec_frames / sec_t
		ms_shown = sec_sum / maxf(1.0, sec_frames)
		max_shown = sec_max
		lights_on = 0
		for l in get_tree().get_nodes_in_group("luces"):
			if l.enabled and l.is_visible_in_tree():
				lights_on += 1
		var z: int = game.alive_count()
		peak("zombis", z)
		peak("particulas", game.fx_top.ps.size() + game.fx_ground.ps.size())
		peak("balas", game.bullets.size())
		peak("llamadas_dibujo", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		peak("ms_fotograma", max_shown)
		if enabled and game.playing:
			note("MUESTRA", "fps %.0f · %.1f ms (máx %.0f) · %s" % [fps_shown, ms_shown, max_shown, _context()])
		sec_t = 0.0
		sec_frames = 0
		sec_sum = 0.0
		sec_max = 0.0
	if enabled:
		queue_redraw()


func _pull_errors() -> void:
	if err_logger == null:
		return
	for e in err_logger.take():
		error_total += 1
		errors.append(e)
		if errors.size() > 150:
			errors.pop_front()
		note("ERROR", e.replace("\n", " ⏎ "))


func _context() -> String:
	var g = game
	var pr := PackedStringArray()
	for k in prof_avg:
		pr.append("%s %.1f" % [k, prof_avg[k]])
	return "oleada %d · zombis %d · balas %d · partículas %d/%d · sangre %d · restos %d · cadáveres %d · señuelos %d · luces %d · dibujo %d · nodos %d · RAM %.0f MB · VRAM %.0f MB · CPU ms: %s" % [
		g.wave, g.alive_count(), g.bullets.size(), g.fx_top.ps.size(), g.fx_ground.ps.size(), g.decals.size(), g.gibs.size(), g.corpses.size(), g.lures.size(), lights_on,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, ", ".join(pr)]


func _t(pos: Vector2, text: String, col := Color(0.9, 1.0, 0.9), sz := 15) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw() -> void:
	if not enabled or game == null or game.player == null or game.hud.overlay_on:
		return
	var x := size.x * 0.5 - 300.0
	var y := 140.0
	draw_rect(Rect2(x - 8, y - 18, 616, 232), Color(0, 0, 0, 0.55))
	var fcol := Color(0.4, 1.0, 0.4) if fps_shown >= 50.0 else (Color(1.0, 0.85, 0.3) if fps_shown >= 30.0 else Color(1.0, 0.35, 0.3))
	_t(Vector2(x, y), "FPS %.0f · %.1f ms (máx %.0f) · picos >60 ms: %d · v%s" % [fps_shown, ms_shown, max_shown, spikes, VERSION], fcol, 17)
	y += 20
	_t(Vector2(x, y), "Dibujo: %d llamadas · %d objetos · VRAM %.0f MB · RAM %.0f MB · nodos %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	y += 18
	_t(Vector2(x, y), "Zombis %d · balas %d · partículas %d+%d · sangre %d · restos %d · cadáveres %d · señuelos %d" % [game.alive_count(), game.bullets.size(), game.fx_top.ps.size(), game.fx_ground.ps.size(), game.decals.size(), game.gibs.size(), game.corpses.size(), game.lures.size()])
	y += 18
	var p = game.player
	_t(Vector2(x, y), "Luces activas %d · linterna %s · sombras %s · relieve %s" % [lights_on, "SÍ" if p.light_on else "NO", "SÍ" if game.settings["sombras"] else "NO", "SÍ" if game.settings["relieve"] else "NO"])
	y += 18
	var pr := PackedStringArray()
	for k in prof_avg:
		pr.append("%s %.2f" % [k, prof_avg[k]])
	_t(Vector2(x, y), "CPU ms/fotograma: " + " · ".join(pr))
	y += 18
	_t(Vector2(x, y), "Motor: proceso %.1f ms · física %.1f ms · texturas generadas en %d ms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, tex_ms])
	y += 18
	_t(Vector2(x, y), "Ventana %s · %s · zona segura %s" % [DisplayServer.window_get_size(), _mode_name(DisplayServer.window_get_mode()), DisplayServer.get_display_safe_area()])
	y += 18
	_t(Vector2(x, y), "GPU %s · %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	y += 18
	if error_total > 0:
		_t(Vector2(x, y), "Errores del motor: %d · último: %s" % [error_total, errors[-1].left(70) if errors.size() > 0 else ""], Color(1.0, 0.4, 0.35))
	else:
		_t(Vector2(x, y), "Errores del motor: 0", Color(0.6, 0.9, 0.6))
	y += 14
	# Grafica de tiempo por fotograma (linea verde = 16.7 ms, amarilla = 33 ms)
	var gx := x
	var gh := 46.0
	var gy := y + gh
	draw_rect(Rect2(gx, y, 600, gh), Color(0, 0, 0, 0.4))
	var scale_ms := gh / 66.0
	draw_line(Vector2(gx, gy - 16.7 * scale_ms), Vector2(gx + 600, gy - 16.7 * scale_ms), Color(0.3, 1.0, 0.3, 0.5), 1.0)
	draw_line(Vector2(gx, gy - 33.3 * scale_ms), Vector2(gx + 600, gy - 33.3 * scale_ms), Color(1.0, 0.85, 0.3, 0.5), 1.0)
	var bw := 600.0 / graph.size()
	for i in graph.size():
		var v := graph[i]
		var c := Color(0.4, 1.0, 0.4) if v < 20.0 else (Color(1.0, 0.85, 0.3) if v < 40.0 else Color(1.0, 0.3, 0.3))
		draw_rect(Rect2(gx + i * bw, gy - minf(v, 66.0) * scale_ms, maxf(1.0, bw - 0.5), minf(v, 66.0) * scale_ms), c)


# ------------------------------------------------------------------ prueba de luces

func _brightness(img: Image, center: Vector2, half: float) -> float:
	var k := Vector2(img.get_width(), img.get_height()) / get_viewport_rect().size
	var c := center * k
	var hs := half * k.x
	var sum := 0.0
	var n := 0
	var step := maxi(2, int(hs / 12.0))
	for yy in range(int(c.y - hs), int(c.y + hs), step):
		for xx in range(int(c.x - hs), int(c.x + hs), step):
			if xx < 0 or yy < 0 or xx >= img.get_width() or yy >= img.get_height():
				continue
			sum += img.get_pixel(xx, yy).get_luminance()
			n += 1
	return sum / maxf(1.0, n)


func _snap(p) -> Array:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var ps: Vector2 = p.get_global_transform_with_canvas().origin
	var front: Vector2 = ps + p.aim * 150.0
	return [_brightness(img, front, 60.0), _brightness(img, ps, 30.0)]


func run_light_test() -> String:
	if testing or game == null or game.player == null:
		return ""
	testing = true
	var p = game.player
	var hud = game.hud
	var old_light: bool = p.light_on
	var old_sh: bool = game.settings["sombras"]
	var old_rel: bool = game.settings["relieve"]
	var hud_vis: bool = hud.visible
	hud.visible = false
	visible = false
	note("INFO", "Prueba de luces iniciada")
	var res := {}
	p.cone.enabled = false
	p.glow.enabled = false
	res["apagada"] = await _snap(p)
	p.glow.enabled = true
	res["solo_brillo"] = await _snap(p)
	p.cone.enabled = true
	p.cone.shadow_enabled = false
	game.tex.set_relief(true)
	res["linterna"] = await _snap(p)
	p.cone.shadow_enabled = true
	res["linterna_sombras"] = await _snap(p)
	p.cone.shadow_enabled = false
	game.tex.set_relief(false)
	res["linterna_sin_relieve"] = await _snap(p)
	# Restaurar
	p.light_on = old_light
	p.cone.enabled = old_light
	p.glow.enabled = true
	p.cone.shadow_enabled = old_sh
	game.tex.set_relief(old_rel)
	hud.visible = hud_vis
	visible = true
	testing = false

	var base: float = maxf(0.002, res["apagada"][0])
	var r_l: float = res["linterna"][0] / base
	var r_s: float = res["linterna_sombras"][0] / base
	var r_n: float = res["linterna_sin_relieve"][0] / base
	var r_g: float = res["solo_brillo"][1] / maxf(0.002, res["apagada"][1])
	var out := PackedStringArray()
	out.append("Brillo delante del jugador (0-1): apagada %.3f · linterna %.3f · linterna+sombras %.3f · linterna sin relieve %.3f" % [res["apagada"][0], res["linterna"][0], res["linterna_sombras"][0], res["linterna_sin_relieve"][0]])
	out.append("Brillo sobre el jugador: sin luces %.3f · con brillo cercano %.3f" % [res["apagada"][1], res["solo_brillo"][1]])
	out.append("Ganancia: linterna x%.2f · con sombras x%.2f · sin relieve x%.2f · brillo cercano x%.2f" % [r_l, r_s, r_n, r_g])
	var verdict := PackedStringArray()
	if r_l < 1.15 and r_n < 1.15:
		verdict.append("Las luces 2D NO iluminan en este dispositivo (ni con ni sin relieve).")
	elif r_l < 1.15 and r_n >= 1.15:
		verdict.append("El relieve (mapas de normales) apaga la linterna: se desactiva el relieve.")
		game.set_setting("relieve", false)
	else:
		verdict.append("La linterna funciona sin sombras.")
	if r_l >= 1.15 and r_s < (1.0 + (r_l - 1.0) * 0.4):
		verdict.append("Las SOMBRAS dejan la linterna a oscuras en esta GPU: se desactivan.")
		if game.settings["sombras"]:
			game.set_setting("sombras", false)
	elif r_l >= 1.15:
		verdict.append("Las sombras funcionan.")
	out.append("Conclusión: " + " ".join(verdict))
	light_report = "\n".join(out)
	for l in out:
		note("LUCES", l)
	return " ".join(verdict)


# ------------------------------------------------------------------ informe

static func build_report(g) -> String:
	var s := PackedStringArray()
	s.append("===== INFORME DE DEPURACIÓN · HORDA CERO %s =====" % VERSION)
	s.append("Generado: %s · %.0f s de sesión" % [Time.get_datetime_string_from_system(), (Time.get_ticks_msec() - start_ms) / 1000.0])
	s.append("\n== DISPOSITIVO ==")
	s.append(device_info())
	s.append("\n== AJUSTES ==")
	s.append(str(g.settings))
	s.append("\n== RENDIMIENTO ==")
	if frames > 0:
		var sorted := ft_hist.duplicate()
		sorted.sort()
		var p := func(q: float) -> float: return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)]
		s.append("Fotogramas medidos: %d · media %.1f ms (%.0f fps) · mediana %.1f ms · p95 %.1f ms · p99 %.1f ms · peor %.1f ms" % [frames, ft_sum / frames, 1000.0 / (ft_sum / frames), p.call(0.5), p.call(0.95), p.call(0.99), sorted[-1]])
	s.append("Picos de más de 60 ms: %d · texturas generadas en %d ms" % [spikes, tex_ms])
	s.append("Máximos: " + str(peaks))
	var pr := PackedStringArray()
	for k in prof_avg:
		pr.append("%s %.2f" % [k, prof_avg[k]])
	s.append("CPU media por sistema (ms/fotograma): " + ", ".join(pr))
	s.append("Peores fotogramas:")
	for w in worst:
		s.append("  %.0f ms en t=%.1f s · %s" % [w[0], w[1], w[2]])
	s.append("\n== PRUEBA DE LUCES ==")
	s.append(light_report if light_report != "" else "No realizada (Ajustes > Prueba de luces)")
	s.append("\n== ESTADO ACTUAL ==")
	if g.player != null:
		var pl = g.player
		s.append("Jugando: %s · oleada %d · puntos %d · vida %.0f/%.0f · arma %s · linterna %s · posición %s" % [g.playing, g.wave, g.score, pl.hp, pl.max_hp, pl.weapon()["name"], pl.light_on, pl.global_position.round()])
	s.append("\n== ERRORES DEL MOTOR (%d en total) ==" % error_total)
	for e in errors.slice(maxi(0, errors.size() - 60)):
		s.append(e)
	if prev_note != "":
		s.append("\n== SESIÓN ANTERIOR ==")
		s.append(prev_note)
		s.append(prev_tail)
	s.append("\n== REGISTRO (últimas líneas) ==")
	for l in lines.slice(maxi(0, lines.size() - 300)):
		s.append(l)
	var glog := "user://logs/godot.log"
	if FileAccess.file_exists(glog):
		s.append("\n== godot.log (últimas líneas) ==")
		s.append(_tail(FileAccess.get_file_as_string(glog), 150))
	return "\n".join(s)


# Devuelve un texto para mostrar con lo que se pudo hacer.
static func export_report(g, img: Image) -> String:
	var txt := build_report(g)
	var result := PackedStringArray()
	DisplayServer.clipboard_set(txt)
	result.append("Informe copiado al portapapeles")
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dirs: Array = []
	if OS.has_feature("android"):
		dirs = [OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]
	else:
		dirs = [OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]
	dirs.append(ProjectSettings.globalize_path(DIR))
	for d in dirs:
		if d == "":
			continue
		var folder: String = d if d.ends_with("depuracion") else d + "/HordaCero"
		DirAccess.make_dir_recursive_absolute(folder)
		var path := folder + "/informe_%s.txt" % stamp
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			note("AVISO", "No se pudo escribir en %s (%s)" % [folder, error_string(FileAccess.get_open_error())])
			continue
		f.store_string(txt)
		f.close()
		if img != null:
			img.save_png(folder + "/captura_%s.png" % stamp)
		var prevlog := DIR + "/registro_anterior.txt"
		if FileAccess.file_exists(prevlog):
			var pf := FileAccess.open(folder + "/registro_anterior_%s.txt" % stamp, FileAccess.WRITE)
			if pf != null:
				pf.store_string(FileAccess.get_file_as_string(prevlog))
		result.append("Guardado en " + folder)
		note("INFO", "Informe guardado en " + path)
		break
	return "\n".join(result)
