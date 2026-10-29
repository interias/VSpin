## Galerie der Ausrüstungssymbole (#83) zur Sichtprüfung und Messung: rendert die Symbole echt (ohne `--headless`, das
## Fenster außerhalb des sichtbaren Bereichs) und schreibt PNGs; misst die Erzeugungszeit je neues Symbol und für ein
## volles Inventar. Spiel, Bus und `user://` bleiben unberührt (nur Beispielteile im Speicher).
##   godot --path games/island-ride --position -32000,-32000 -s res://tools/icon_gallery.gd -- --out=C:/tmp/icons
##         [--compat] [--count=40] [--gear]
## Browser-Profil: `--compat` baut die Symbole wie im Compatibility-Renderer (ohne MSAA); für den echten Renderer dazu
## Godots `--rendering-method gl_compatibility` übergeben (die Ausgabe nennt den laufenden Renderer).
## Bilder in `--out`:
##   sheet_all.png            alle Plätze (Zeilen) × Seltenheit × 3 Varianten, 96 px, beschriftet
##   sheet_<platz>.png        je Platz 4 Seltenheiten × 6 Varianten, 96 px, unter jedem Symbol Muster/Detail (Motiv)
##   single/<platz>_<seltenheit>.png, single/leer_<platz>.png   Einzelbilder, 128 px (mit Rahmen und Schein)
##   silhouettes.png          leere Plätze als graue Silhouette in 96 und 64 px
##   talismans.png            Stein und die drei Sagenmotive, legendäre nach Effekt
##   glow_on.png, glow_off.png   legendäre Teile aller Plätze mit Leuchten an bzw. aus (128 px)
##   inventory_50.png         das Inventar mit 50 Teilen aus der Messung
## `--gear`: nur das Ausrüstungsmenü (scenes/gear_menu.gd) mit einem Beispielstand nur im Speicher (angelegte Teile
##   verschiedener Seltenheit mit einem leeren Platz, rund 20 Teile im Inventar, ein gewähltes Teil mit Vergleich) in den
##   Fenstergrößen 960×1040, 1920×1080 und 1152×648 (je ein SubViewport dieser Größe): `gear_<breite>x<höhe>.png`,
##   dazu `gear_<breite>x<höhe>_legendary.png` mit gewähltem legendärem Teil; keine Messung, keine anderen Bilder.
## Messung (je eine Zeile `MEASURE …`, „offscreen“: das Fenster liegt außerhalb des Bildschirms, VSync aus):
##   baseline     mittlere Bildzeit ohne neue Symbole
##   warmup       die ersten Symbole des Programmlaufs (je Platz eins und eine Silhouette): einmalig Shader/Pipelines
##   new_icon     je neues Symbol (`--count` Stück, einzeln, nach dem Aufwärmen): CPU-Zeit von ItemIcons.texture_for und
##                Zeit bis nach dem Bild, in dem es rendert – Mittel und Maximum, dazu der Aufschlag auf `baseline`
##   inventory_50 50 neue Symbole auf einmal (ItemIconView im Raster): Anlegen der Views, Zahl der Bilder, bis alle
##                gezeigt sind, mittlere und längste Bildzeit dabei (Warteschlange, ItemIcons.PER_FRAME je Bild)
extends SceneTree

const WINDOW := Vector2i(1800, 1060)
const BACKGROUND := Color(0.09, 0.1, 0.12)

var _out := ""
var _count := 40
var _gear := false
var _canvas: Control


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--compat":
			ItemIcons.compatibility = true
		elif arg.begins_with("--count="):
			_count = maxi(int(arg.trim_prefix("--count=")), 1)
		elif arg == "--gear":
			_gear = true
	if _out.is_empty():
		push_error("icon_gallery: --out=<ordner> fehlt")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out.path_join("single"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(WINDOW)
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	_run.call_deferred()


func _run() -> void:
	print("GALLERY renderer=%s compat_profile=%s out=%s" % [RenderingServer.get_current_rendering_method(),
			ItemIcons.compatibility, _out])
	await _frames(5)
	if _gear:
		for size in [Vector2i(960, 1040), Vector2i(1920, 1080), Vector2i(1152, 648)]:
			await _gear_menu(size)
		ItemIcons.clear_cache()
		quit(0)
		return
	await _measure()
	await _sheet_all()
	for slot in Loot.SLOTS:
		await _sheet_slot(slot)
	await _singles()
	await _silhouettes()
	await _talismans()
	await _glow()
	ItemIcons.clear_cache()
	quit(0)


## Beispielteil: Platz und Seltenheit fest, Werte und (bei legendär) Effekt aus `k` – reproduzierbar.
static func sample(slot: String, rarity: String, k: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ItemIcons.fnv1a("%s|%s|%d" % [slot, rarity, k])
	var item := Loot.roll(rng)
	item["slot"] = slot
	item["rarity"] = rarity
	item["stats"][Loot.SLOTS[slot]["stat"]] = rng.randi_range(1, 30)
	item["effect"] = Loot.EFFECTS.keys()[k % Loot.EFFECTS.size()] if rarity == Loot.LEGENDARY else ""
	return item


func _measure() -> void:
	ItemIcons.clear_cache()
	var slots := Loot.SLOTS.keys()
	var rarities := Loot.RARITIES.keys()
	var warm := Time.get_ticks_usec()
	for slot in slots:
		ItemIcons.texture_for(sample(slot, Loot.RARE, 999))
	ItemIcons.silhouette_for("helm")
	await _frames(2)
	print("MEASURE warmup first_7_icons=%.2fms (einmal je Programmlauf: Shader/Pipelines, offscreen)" % [
			(Time.get_ticks_usec() - warm) / 1000.0])
	await _frames(3)
	var base := []
	for i in range(60):
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		base.append((Time.get_ticks_usec() - t0) / 1000.0)
	var baseline := _mean(base)
	print("MEASURE baseline frame_mean=%.2fms frame_max=%.2fms (offscreen)" % [baseline, base.max()])
	var cpu := []
	var frame := []
	for k in range(_count):
		var item := sample(slots[k % slots.size()], rarities[(k / slots.size()) % rarities.size()], 1000 + k)
		var t0 := Time.get_ticks_usec()
		ItemIcons.texture_for(item)
		ItemIcons.flush()
		cpu.append((Time.get_ticks_usec() - t0) / 1000.0)
		await RenderingServer.frame_post_draw
		frame.append((Time.get_ticks_usec() - t0) / 1000.0)
	print(("MEASURE new_icon n=%d cpu_mean=%.2fms cpu_max=%.2fms frame_mean=%.2fms frame_max=%.2fms "
			+ "extra_over_baseline_mean=%.2fms (Erzeugen + Bild, in dem es rendert; offscreen)") % [_count, _mean(cpu),
			cpu.max(), _mean(frame), frame.max(), _mean(frame) - baseline])
	ItemIcons.clear_cache()
	await _frames(3)
	var t0 := Time.get_ticks_usec()
	var grid := _clear_canvas_grid(10)
	for k in range(50):
		grid.add_child(ItemIconView.of_item(sample(slots[k % slots.size()], rarities[k % rarities.size()], 2000 + k)))
	var created := (Time.get_ticks_usec() - t0) / 1000.0
	var frames := []
	while ItemIcons.pending() > 0 and frames.size() < 120:
		var t1 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		frames.append((Time.get_ticks_usec() - t1) / 1000.0)
	var t2 := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	frames.append((Time.get_ticks_usec() - t2) / 1000.0)
	print(("MEASURE inventory_50 create_views=%.2fms frames_until_all_shown=%d frame_mean=%.2fms frame_max=%.2fms "
			+ "total=%.2fms per_icon=%.2fms baseline=%.2fms (offscreen)") % [created, frames.size(), _mean(frames),
			frames.max(), created + frames.reduce(func(a, b): return a + b, 0.0),
			(created + frames.reduce(func(a, b): return a + b, 0.0)) / 50.0, baseline])
	await _settle()
	_save_canvas("inventory_50.png")


func _sheet_all() -> void:
	var box := _clear_canvas_box()
	var header := HBoxContainer.new()
	header.add_child(_label("", 120))
	for rarity in Loot.RARITIES:
		header.add_child(_label(Loot.RARITIES[rarity]["name"], 3 * 104, Loot.color_of(rarity)))
	box.add_child(header)
	for slot in Loot.SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_label(Loot.SLOTS[slot]["name"], 112))
		for rarity in Loot.RARITIES:
			for k in range(3):
				row.add_child(ItemIconView.of_item(sample(slot, rarity, k)))
		box.add_child(row)
	await _settle()
	_save_canvas("sheet_all.png")


func _sheet_slot(slot: String) -> void:
	var box := _clear_canvas_box()
	box.add_child(_label("%s – 4 Seltenheiten × 6 Varianten (96 px)" % Loot.SLOTS[slot]["name"], 0))
	for rarity in Loot.RARITIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_label(Loot.RARITIES[rarity]["name"], 110, Loot.color_of(rarity)))
		for k in range(6):
			var item := sample(slot, rarity, k)
			var variant := ItemIcons.variant_of(item)
			var cell := VBoxContainer.new()
			cell.add_child(ItemIconView.of_item(item))
			var text := "%s · D%d" % [variant["pattern"], variant["detail"]]
			if variant["motif"] != "":
				text = "%s\n%s" % [variant["motif"], text]
			cell.add_child(_label(text, 96, Color(1, 1, 1, 0.75), 12))
			row.add_child(cell)
		box.add_child(row)
	await _settle()
	_save_canvas("sheet_%s.png" % slot)


func _singles() -> void:
	for slot in Loot.SLOTS:
		for rarity in Loot.RARITIES:
			await _single(ItemIconView.of_item(sample(slot, rarity, 0), 128.0), "single/%s_%s.png" % [slot, rarity])
		await _single(ItemIconView.of_slot(slot, 128.0), "single/leer_%s.png" % slot)


func _single(view: ItemIconView, file: String) -> void:
	var box := _clear_canvas_box()
	box.add_child(view)
	await _settle()
	var rect := Rect2i(view.get_global_rect().grow(12.0))
	root.get_texture().get_image().get_region(rect).save_png(_out.path_join(file))


func _silhouettes() -> void:
	var box := _clear_canvas_box()
	box.add_child(_label("Leere Plätze (Silhouette) – 96 px und 64 px", 0))
	for size in [96.0, 64.0]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		for slot in Loot.SLOTS:
			var cell := VBoxContainer.new()
			cell.add_child(ItemIconView.of_slot(slot, size))
			cell.add_child(_label(Loot.SLOTS[slot]["name"], int(size), Color(1, 1, 1, 0.75), 12))
			row.add_child(cell)
		box.add_child(row)
	await _settle()
	_save_canvas("silhouettes.png")


func _talismans() -> void:
	var box := _clear_canvas_box()
	box.add_child(_label("Talismane: Stein (gewöhnlich) und Sagenmotive (magisch/selten aus dem Seed, legendär aus dem Effekt)", 0))
	var rows := {ItemIcons.STONE: [], BossFigure.DRAC: [], BossFigure.TRAMUNTANA: [], BossFigure.DIMONIS: []}
	for k in range(6):
		rows[ItemIcons.STONE].append(sample("talisman", Loot.COMMON, k))
	for k in range(200):
		var rarity: String = [Loot.MAGIC, Loot.RARE][k % 2]
		var item := sample("talisman", rarity, k)
		var motif := ItemIcons.motif_of(item)
		if rows[motif].size() < 4:
			rows[motif].append(item)
	for k in range(Loot.EFFECTS.size()):
		var item := sample("talisman", Loot.LEGENDARY, k)
		rows[ItemIcons.motif_of(item)].append(item)
	for motif in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_label(motif, 110))
		for item in rows[motif]:
			var cell := VBoxContainer.new()
			cell.add_child(ItemIconView.of_item(item))
			var effect := Loot.effect_name(item)
			cell.add_child(_label(effect if effect != "" else Loot.RARITIES[item["rarity"]]["name"], 96,
					Loot.color_of(item["rarity"]), 12))
			row.add_child(cell)
		box.add_child(row)
	await _settle()
	_save_canvas("talismans.png")


func _glow() -> void:
	for glow in [true, false]:
		ItemIcons.glow_enabled = glow
		var box := _clear_canvas_box()
		box.add_child(_label("Legendär, Leuchten %s (128 px)" % ("an" if glow else "aus"), 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		var first: ItemIconView
		for slot in Loot.SLOTS:
			var view := ItemIconView.of_item(sample(slot, Loot.LEGENDARY, 1), 128.0)
			first = view if first == null else first
			row.add_child(view)
		box.add_child(row)
		await _settle()
		var started := Time.get_ticks_msec()
		while glow and first._time < 0.45 * ItemIconView.GLOW_CYCLE_S * ItemIconView.SHIMMER_SHARE \
				and Time.get_ticks_msec() - started < 3000:
			await RenderingServer.frame_post_draw
		_save_canvas("glow_on.png" if glow else "glow_off.png")
	ItemIcons.glow_enabled = true


## Beispielstand fürs Ausrüstungsmenü, nur im Speicher: angelegt Helm (magisch), Trikot (selten), Rahmen (gewöhnlich) und
## Schuhe (magisch), Laufräder und Talisman leer; im Inventar rund 20 Teile, darunter legendäre.
func _gear_save() -> Dictionary:
	var save := SaveGame.new()
	var data := {"save": save}
	var worn := [["helm", Loot.MAGIC], ["trikot", Loot.RARE], ["rahmen", Loot.COMMON], ["schuhe", Loot.MAGIC]]
	for entry in worn:
		Inventory.equip(save, int(Inventory.add(save, sample(entry[0], entry[1], 1))["id"]))
	var slots := Loot.SLOTS.keys()
	var rarities := Loot.RARITIES.keys()
	for k in range(16):
		Inventory.add(save, sample(slots[k % slots.size()], rarities[(k * 2 + k / 3) % rarities.size()], 10 + k))
	data["legendary_helm"] = Inventory.add(save, sample("helm", Loot.LEGENDARY, 3))
	data["rare_helm"] = Inventory.add(save, sample("helm", Loot.RARE, 7))
	data["legendary_talisman"] = Inventory.add(save, sample("talisman", Loot.LEGENDARY, 4))
	return data


## Ausrüstungsmenü in einem SubViewport der Größe `size`: ein Bild mit gewähltem seltenen Helm (Vergleich mit dem
## magischen angelegten), eins mit gewähltem legendärem Talisman (Platz leer: Silhouette im Vergleich).
func _gear_menu(size: Vector2i) -> void:
	var data := _gear_save()
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var wall := ColorRect.new()  # statt des Startmenüs dahinter
	wall.color = Color(0.16, 0.3, 0.38)
	wall.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(wall)
	var gear: CanvasLayer = load("res://scenes/gear_menu.gd").new()
	viewport.add_child(gear)
	gear.open(data["save"])
	for shot in [["", "rare_helm"], ["_legendary", "legendary_talisman"]]:
		gear.select(int(data[shot[1]]["id"]))
		await _settle()
		await _frames(30)  # RiderPreview und Schimmer
		var file := "gear_%dx%d%s.png" % [size.x, size.y, shot[0]]
		viewport.get_texture().get_image().save_png(_out.path_join(file))
		print("SHOT %s %dx%d" % [_out.path_join(file), size.x, size.y])
	viewport.free()


func _clear_canvas() -> MarginContainer:
	if is_instance_valid(_canvas):
		_canvas.free()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	root.add_child(margin)
	_canvas = margin
	return margin


func _clear_canvas_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_clear_canvas().add_child(box)
	return box


func _clear_canvas_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_clear_canvas().add_child(grid)
	return grid


## Bild des Fensters, beschnitten auf den Inhalt.
func _save_canvas(file: String) -> void:
	var rect := Rect2i(_canvas.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, root.size))
	root.get_texture().get_image().get_region(rect).save_png(_out.path_join(file))
	print("SHOT %s %dx%d" % [_out.path_join(file), rect.size.x, rect.size.y])


static func _label(text: String, width: int, color: Color = Color(1, 1, 1, 0.9), font_size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if width > 0 and font_size <= 12:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


static func _mean(values: Array) -> float:
	return values.reduce(func(a, b): return a + b, 0.0) / maxf(values.size(), 1)


## Wartet, bis alle Symbole gebaut und gerendert sind.
func _settle() -> void:
	while ItemIcons.pending() > 0:
		await RenderingServer.frame_post_draw
	await _frames(3)


func _frames(count: int) -> void:
	for i in range(count):
		await RenderingServer.frame_post_draw
