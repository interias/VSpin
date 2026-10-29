## Ausrüstungssymbole (#83, CONTEXT.md „Ausrüstungssymbol“): je Teil der Arcade-Beute (Loot) ein kleines Bild, das
## zeigt, **was** es ist (Silhouette des Platzes) und **wie gut** (Rahmen, Hintergrund und Leuchten in der Farbe der
## Seltenheit, gezeichnet von ItemIconView). Reine Anzeige (ADR-0010): nichts hier wirkt auf Werte oder Beute.
##
## Erzeugung: je Platz ein Low-Poly-Modell aus Grundkörpern (wie die Tiere #40 und Sagengestalten #51, eigene Formen,
## keine Dateien), gerendert in einem eigenen `SubViewport` (SIZE × SIZE, transparenter Hintergrund, feste
## orthografische Kamera, festes Licht) **einmal** (`UPDATE_ONCE`); die `ViewportTexture` bleibt danach stehen. Kein
## Zurücklesen von der GPU (`get_image()` bremst die Pipeline), nichts ins Repo, kein `user://`-Cache. Die Viewports
## hängen unter einem eigenen Knoten `ItemIconStudio` an der Wurzel des Baums (beim ersten Symbol angelegt) und werden je
## Inhalt im Speicher gehalten (`texture_for` zweimal = ein Bild). Lazy: erst beim ersten Anzeigen; `texture_for` gibt die
## Textur sofort zurück, Modell und Bild entstehen in einer Warteschlange – wenige je Bild (PER_FRAME), damit ein
## Inventar mit 50 neuen Teilen das Menü nicht ruckeln lässt (die Symbole erscheinen dann über wenige Bilder verteilt).
##
##   Rahmen      Diamantrahmen mit Sattel, Rennlenker und Kettenblatt, schräg von vorn; Muster auf Ober- und Unterrohr,
##               Detail: keine, eine oder zwei Trinkflaschen.
##   Laufräder   Speichenrad mit Reifen, hoher Felgenflanke (Muster als Dekor), Nabe und Kassette, leicht gekippt;
##               Detail: 16 oder 24 Speichen oder ein Dreispeichenrad.
##   Trikot      Trikot von vorn mit Ärmeln, Kragen, Reißverschluss und Brustband; Muster auf dem Rumpf (Streifen quer,
##               Karo, Verlauf von oben nach unten); Detail: Seitenteile oder Schulterpasse.
##   Helm        schlanker Aerohelm im Profil (lang gestreckte Tropfenform mit langer Heckspitze), Lüftungsschlitze in
##               Längsrichtung auf drei Bahnen, Visierkante und Visier vorn; Muster: Mittelstreifen, Karo-Flecken oder
##               zweistufiger Verlauf; Detail: 2–4 Schlitze je Bahn, Spiegelvisier.
##   Schuhe      Radschuh im Profil: dunkle Sohle mit heller Zwischensohle, hohe Ferse, abfallender Spann, flache Spitze,
##               Fersenkappe, Drehverschluss seitlich und Pedalplatte mit rotem Cleat unter dem Ballen (starke Hell-Dunkel-
##               Kontraste, damit er bei 64 px lesbar bleibt); Detail: Klettriemen oder zweiter Drehverschluss.
##   Talisman    Sagen-Amulett: Anhänger mit Öse und Band, darauf das Motiv – Drac (Drachenkopf), Tramuntana
##               (Windspirale) oder Dimonis (Hörnermaske); gewöhnliche Talismane sind ein schlichter Stein am Band.
##
## **Variante** (`variant_of`) deterministisch aus dem **Inhalt** des Teils, nie aus der `id` (ein Fund hat beim
## Einblenden noch keine, ArcadeStage.loot_found): Schlüssel `key_of` = Platz, Seltenheit, ganzzahlige Werte in
## Reihenfolge von Loot.STATS und Effekt, gehasht mit FNV-1a (32 Bit) über die UTF-8-Bytes – über Programmstarts stabil,
## unabhängig von der Reihenfolge im Dictionary und von 3 gegen 3.0 (JSON). Daraus: drei verschiedene Farben aus PALETTE
## (mediterran: Terrakotta, Ocker, Oliv, Meerblau, Türkis, Kalkweiß, Nachtblau, Bougainvillea, Lavendel, Koralle),
## Muster (PATTERNS: Streifen, Karo, Verlauf) und Detailteil (0..DETAILS−1). Die Seltenheit setzt die Zierfarbe
## (TRIMS: dunkel, Silber, **blasses Silbergold** bei selten, **sattes Gold** bei legendär) an Steuerrohr, Naben, Kragen,
## Helmrand, Fersenlasche und Anhängerrand.
##
## **Selten und legendär** liegen als Rahmenfarbe (Loot: Gelb, Orange) nah beieinander und bleiben so (sie färben auch
## Lichtsäule, Schrift und Fahrer). Im Symbol trennen sie Hintergrund (`backdrop_for`) und Zier: selten goldgelb und hell mit
## silbergoldener Zier, legendär tief Glutorange bis Blutrot mit Strahlenkranz und goldener Zier – auch bei 56 px und ohne
## Leuchten. Die Varianten (`variant_of`: Palette, Muster, Detail, Motiv) sind unverändert; nur Modelle, Hintergründe und Zierfarbe (`trim`) sind neu.
##
## **Talisman-Motiv** (`motif_of`): gewöhnlich → Stein. Legendär mit Effekt → aus dem Effekt (EFFECT_MOTIFS): die
## Windböe-Effekte `rueckstoss` und `auf_dem_sprung` → Tramuntana; `tiefer_atem` (der Feueratem) und `im_fluss` (der Drac
## kam aus dem Wasser) → Drac; `kombo_ernte` (Fest im Takt der Dorffeste) → Dimonis. Magisch, selten und legendär ohne
## (bekannten) Effekt → aus dem Seed.
##
## **Leerer Platz** (`silhouette_for`): die Grundform des Platzes als graue, unbeleuchtete Silhouette.
## **Leuchten** legendärer Teile ist ein Effekt des Rahmens (ItemIconView), kein Leuchten in der 3D-Welt; an/aus über
## `glow_enabled`, das GraphicsSettings.apply_engine aus `settings.cfg [graphics] item_glow` setzt (Menü „Leuchten
## (Ausrüstung)“). **Browser** (Compatibility-Renderer, `compatibility`): dieselben Modelle ohne MSAA.
class_name ItemIcons
extends RefCounted

## Kantenlänge des gerenderten Bildes (px); angezeigt wird es in jeder Größe (ItemIconView, z. B. 96 im Halbbild).
const SIZE := 128
## Höchstens so viele neue Symbole baut und rendert das Studio je Bild (je ~0,5 ms CPU plus ~1 ms Rendern); im
## Compatibility-Renderer weniger (dort kostet das Anlegen des Render-Puffers mehr).
const PER_FRAME := 6
const PER_FRAME_COMPATIBILITY := 4
## Blickrichtung der Kamera (von vorn, leicht von oben) und Rand um das Modell (Faktor auf seine Ausdehnung).
const VIEW_DIR := Vector3(0.0, 0.42, 1.0)
const MARGIN := 1.12
## Drehung je Platz (Bogenmaß), damit jede Form ihre kennzeichnende Seite zeigt.
const TURN := {
	"rahmen": Vector3(0.0, -0.62, 0.0),
	"laufraeder": Vector3(0.14, -0.55, 0.0),
	"trikot": Vector3(0.0, 0.3, 0.0),
	"helm": Vector3(0.0, -0.32, 0.04),
	"schuhe": Vector3(0.0, -0.3, 0.0),
	"talisman": Vector3(0.0, 0.25, -0.1),
}
## Farbpalette der Insel (Varianten wählen drei verschiedene).
const PALETTE := [
	Color(0.78, 0.38, 0.24),  # Terrakotta
	Color(0.86, 0.66, 0.26),  # Ocker
	Color(0.45, 0.53, 0.25),  # Oliv
	Color(0.16, 0.4, 0.68),  # Meerblau
	Color(0.18, 0.66, 0.66),  # Türkis
	Color(0.93, 0.91, 0.85),  # Kalkweiß
	Color(0.15, 0.19, 0.34),  # Nachtblau
	Color(0.8, 0.2, 0.5),  # Bougainvillea
	Color(0.57, 0.5, 0.78),  # Lavendel
	Color(0.88, 0.32, 0.28),  # Koralle
]
const STRIPES := "streifen"
const CHECK := "karo"
const FADE := "verlauf"
const PATTERNS := [STRIPES, CHECK, FADE]
## Zahl der Detailvarianten je Platz.
const DETAILS := 3
## Zierfarbe je Rang der Seltenheit (gewöhnlich, magisch, selten, legendär).
## Selten: helles Silbergold (blass, kühl), legendär: sattes Gold – auch ohne Leuchten und neben den Rahmenfarben unterscheidbar.
const TRIMS := [Color(0.22, 0.22, 0.24), Color(0.78, 0.8, 0.84), Color(0.94, 0.9, 0.72), Color(1.0, 0.7, 0.08)]
## Hintergrund (Mitte, Rand) je Seltenheit mit eigener Farbe: gewöhnlich und magisch dunkel in der Rahmenfarbe; **selten**
## goldgelb und hell (die Rahmenfarbe bleibt Gelb aus Loot), **legendär** tiefes Glutorange bis Blutrot mit Strahlenkranz
## (`backdrop_for`). Der Farbton liegt rund 0,07 auseinander, die Helligkeit des Randes deutlich (Test).
const BACKDROPS := {
	Loot.RARE: [Color(0.82, 0.68, 0.2), Color(0.46, 0.34, 0.06)],
	Loot.LEGENDARY: [Color(0.9, 0.3, 0.04), Color(0.24, 0.02, 0.04)],
}
## Strahlen des legendären Hintergrunds: Zahl, Farbe, Stärke.
const RAYS := 12
const RAY_COLOR := Color(1.0, 0.6, 0.12)
const RAY_STRENGTH := 0.5
## Kantenlänge des legendären Hintergrundbildes (px, wird skaliert).
const RAY_SIZE := 80
const DARK := Color(0.12, 0.12, 0.14)
## Zwischensohle des Radschuhs (hell, setzt die dunkle Sohle vom Obermaterial ab).
const MIDSOLE := Color(0.93, 0.91, 0.85)
const METAL := Color(0.66, 0.68, 0.72)
## Farbe der Silhouette leerer Plätze.
const SILHOUETTE := Color(0.44, 0.46, 0.5)
## Talisman-Motive: der Stein (gewöhnlich) und die Sagengestalten der Bosse (BossFigure.KINDS).
const STONE := "stein"
const MOTIFS := [BossFigure.DRAC, BossFigure.TRAMUNTANA, BossFigure.DIMONIS]
const EFFECT_MOTIFS := {
	"rueckstoss": BossFigure.TRAMUNTANA,
	"auf_dem_sprung": BossFigure.TRAMUNTANA,
	"tiefer_atem": BossFigure.DRAC,
	"im_fluss": BossFigure.DRAC,
	"kombo_ernte": BossFigure.DIMONIS,
}

## Leuchten legendärer Teile an/aus (Menü „Leuchten (Ausrüstung)“; setzt GraphicsSettings.apply_engine).
static var glow_enabled := true
## Compatibility-Renderer (Web)? Neue Symbole ohne MSAA. Für Tests und Galerie überschreibbar.
static var compatibility := RenderingServer.get_current_rendering_method() == "gl_compatibility"
## Zahl der bisher erzeugten Bilder (für Tests und Messung: ein Treffer im Cache erzeugt nichts).
static var built := 0
## Schlüssel → {viewport, texture, variant}.
static var _cache := {}
## Wartende Einträge (Viewport noch ohne Modell), älteste zuerst.
static var _queue: Array[Dictionary] = []
static var _studio: Node
static var _material: StandardMaterial3D
static var _silhouette_material: StandardMaterial3D
static var _environment: Environment
static var _backdrops := {}
static var _shimmer: GradientTexture2D


## Bild des Teils `item` (Loot-Teil, mit oder ohne `id`): beim ersten Aufruf erzeugt, danach aus dem Cache.
static func texture_for(item: Dictionary) -> Texture2D:
	return _entry(key_of(item), func(): return variant_of(item))["texture"]


## Graue Silhouette des leeren Platzes `slot` (Loot.SLOTS).
static func silhouette_for(slot: String) -> Texture2D:
	return _entry("silhouette:" + slot, func(): return silhouette_variant(slot))["texture"]


## Viewport hinter dem Bild von `item` (für Messung und Tests; erzeugt es wie `texture_for`).
static func viewport_for(item: Dictionary) -> SubViewport:
	return _entry(key_of(item), func(): return variant_of(item))["viewport"]


## Zahl der Bilder im Cache.
static func cache_size() -> int:
	return _cache.size()


## Zahl der Symbole, deren Modell noch in der Warteschlange wartet.
static func pending() -> int:
	return _queue.size()


## Baut alle wartenden Symbole sofort (Tests, Galerie); gerendert werden sie im nächsten Bild.
static func flush() -> void:
	while not _queue.is_empty():
		_build(_queue.pop_front())


## Gibt alle Bilder frei (Tests, Galerie). Angezeigte Symbole werden danach leer, bis sie neu gesetzt werden.
static func clear_cache() -> void:
	_cache.clear()
	_queue.clear()
	if is_instance_valid(_studio):
		_studio.free()
	_studio = null


## Kanonischer Inhalt eines Teils: Platz, Seltenheit, Werte (ganzzahlig, Reihenfolge Loot.STATS) und Effekt – ohne `id`.
static func key_of(item: Dictionary) -> String:
	var parts := [str(item.get("slot", "")), str(item.get("rarity", ""))]
	var stats = item.get("stats", {})
	for stat in Loot.STATS:
		if stats is Dictionary and stats.has(stat):
			var value = stats[stat]
			parts.append("%s=%d" % [stat, roundi(value) if value is float or value is int else 0])
	parts.append(Loot.effect_of(item))
	return "|".join(parts)


## Seed der Variante: FNV-1a (32 Bit) über `key_of` – stabil über Programmstarts.
static func seed_of(item: Dictionary) -> int:
	return fnv1a(key_of(item))


## FNV-1a, 32 Bit, über die UTF-8-Bytes von `text`.
static func fnv1a(text: String) -> int:
	var hash_value := 2166136261
	for byte in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * 16777619) & 0xFFFFFFFF
	return hash_value


## Aussehen von `item`: {slot, rarity, rank, seed, silhouette, palette [3 Indizes], primary, secondary, accent, pattern,
## detail, trim, motif}.
static func variant_of(item: Dictionary) -> Dictionary:
	var seed_value := seed_of(item)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var first := rng.randi_range(0, PALETTE.size() - 1)
	var second := (first + rng.randi_range(1, PALETTE.size() - 1)) % PALETTE.size()
	var third := rng.randi_range(0, PALETTE.size() - 3)
	while third == first or third == second:
		third += 1
	var rarity: String = item.get("rarity") if Loot.RARITIES.has(item.get("rarity")) else Loot.COMMON
	var rank := Loot.RARITIES.keys().find(rarity)
	return {"slot": str(item.get("slot", "")), "rarity": rarity, "rank": rank, "seed": seed_value, "silhouette": false,
		"palette": [first, second, third], "primary": PALETTE[first], "secondary": PALETTE[second],
		"accent": PALETTE[third], "pattern": PATTERNS[rng.randi_range(0, PATTERNS.size() - 1)],
		"detail": rng.randi_range(0, DETAILS - 1), "trim": TRIMS[rank], "motif": motif_of(item)}


## Grundform des leeren Platzes `slot`: ohne Muster und Details, Talisman als schlichter Anhänger.
static func silhouette_variant(slot: String) -> Dictionary:
	return {"slot": slot, "rarity": "", "rank": 0, "seed": 0, "silhouette": true, "palette": [],
		"primary": SILHOUETTE, "secondary": SILHOUETTE, "accent": SILHOUETTE, "pattern": "", "detail": 0,
		"trim": SILHOUETTE, "motif": ""}


## Motiv eines Talismans (STONE oder MOTIFS, Regeln oben); "" für andere Plätze.
static func motif_of(item: Dictionary) -> String:
	if item.get("slot") != "talisman":
		return ""
	if item.get("rarity") == Loot.COMMON or not Loot.RARITIES.has(item.get("rarity")):
		return STONE
	var effect := Loot.effect_of(item)
	if EFFECT_MOTIFS.has(effect):
		return EFFECT_MOTIFS[effect]
	return MOTIFS[(seed_of(item) >> 8) % MOTIFS.size()]


## Modell zu `variant` (ohne Kamera und Licht): Node3D „Model“ mit einem MeshInstance3D „Mesh“, gedreht nach TURN; Meta
## `parts` nennt die Bauteile, Meta `metrics` Maße (Talisman mit Motiv: `pendant_width`, `motif_width`; für Tests).
static func build_model(variant: Dictionary) -> Node3D:
	var parts := Parts.new()
	var names: Array[String] = []
	var metrics := {}
	match variant["slot"]:
		"rahmen":
			_build_frame(parts, names, variant)
		"laufraeder":
			_build_wheel(parts, names, variant)
		"trikot":
			_build_jersey(parts, names, variant)
		"helm":
			_build_helmet(parts, names, variant)
		"schuhe":
			_build_shoe(parts, names, variant)
		"talisman":
			metrics = _build_talisman(parts, names, variant)
		_:
			parts.box(Vector3(0.5, 0.5, 0.5), Transform3D(), variant["primary"])
			names.append("Kiste")
	var model := Node3D.new()
	model.name = "Model"
	model.rotation = TURN.get(variant["slot"], Vector3.ZERO)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = parts.commit()
	mesh.material_override = _silhouette_shader() if variant["silhouette"] else _shaded()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(mesh)
	model.set_meta("parts", names)
	model.set_meta("metrics", metrics)
	return model


## Farben des Hintergrunds [Mitte, Rand] zur Seltenheit `rarity` (BACKDROPS, sonst die Rahmenfarbe abgedunkelt).
static func backdrop_colors(rarity: String) -> Array:
	if BACKDROPS.has(rarity):
		return BACKDROPS[rarity]
	var color := Loot.color_of(rarity)
	return [color.darkened(0.42), color.darkened(0.84)]


## Hintergrund des Symbols zur Seltenheit `rarity` (radialer Verlauf, hell in der Mitte; legendär mit Strahlenkranz); geteilt.
static func backdrop_for(rarity: String) -> Texture2D:
	if not _backdrops.has(rarity):
		if rarity == Loot.LEGENDARY:
			_backdrops[rarity] = _sunburst()
			return _backdrops[rarity]
		var colors := backdrop_colors(rarity)
		var gradient := Gradient.new()
		gradient.set_color(0, colors[0])
		gradient.set_color(1, colors[1])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.42)
		texture.fill_to = Vector2(1.05, 1.05)
		texture.width = 64
		texture.height = 64
		_backdrops[rarity] = texture
	return _backdrops[rarity]


## Legendärer Hintergrund: derselbe radiale Verlauf wie die anderen (Mitte hoch bei 0,42), dazu RAYS weiche Strahlen von der
## Mitte, nach außen schwächer. Einmal gezeichnet (RAY_SIZE², wenige ms) und geteilt.
static func _sunburst() -> ImageTexture:
	var colors := backdrop_colors(Loot.LEGENDARY)
	var image := Image.create(RAY_SIZE, RAY_SIZE, false, Image.FORMAT_RGB8)
	var middle := Vector2(0.5, 0.42) * RAY_SIZE
	for y: int in range(RAY_SIZE):
		for x: int in range(RAY_SIZE):
			var offset := Vector2(x + 0.5, y + 0.5) - middle
			var t := clampf(offset.length() / (RAY_SIZE * 0.62), 0.0, 1.0)
			var ray := pow(0.5 + 0.5 * cos(offset.angle() * RAYS), 2.0)
			var color: Color = (colors[0] as Color).lerp(colors[1], t)
			image.set_pixel(x, y, color.lerp(RAY_COLOR, ray * RAY_STRENGTH * (1.0 - t * 0.55) * minf(t * 4.0, 1.0)))
	return ImageTexture.create_from_image(image)


## Schimmer-Streifen des Leuchtens (durchsichtig – hell – durchsichtig); geteilt.
static func shimmer_texture() -> Texture2D:
	if _shimmer == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 0.95, 0.8, 0.38), Color(1, 1, 1, 0)])
		_shimmer = GradientTexture2D.new()
		_shimmer.gradient = gradient
		_shimmer.width = 32
		_shimmer.height = 4
	return _shimmer


static func _entry(key: String, make_variant: Callable) -> Dictionary:
	if not _cache.has(key):
		_cache[key] = _render(make_variant.call())
	return _cache[key]


## Eigener Viewport (noch leer, wartet in der Warteschlange auf Modell, Kamera und Licht). Außer im Compatibility-Renderer
## schon hier transparent: sonst zeigt ein wartendes Symbol in Forward+ ein schwarzes Quadrat statt des Hintergrunds (im
## Compatibility-Renderer ist es ohnehin durchsichtig, dort kostet das frühe Umschalten ~0,6 ms je Symbol).
static func _render(variant: Dictionary) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "Icon%d" % built
	viewport.world_3d = World3D.new()
	viewport.world_3d.environment = _shared_environment()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if compatibility else Viewport.MSAA_4X
	viewport.transparent_bg = not compatibility
	viewport.positional_shadow_atlas_size = 0
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_studio_node().add_child(viewport)
	built += 1
	var entry := {"viewport": viewport, "texture": viewport.get_texture(), "variant": variant}
	_queue.append(entry)
	return entry


## Modell, Kamera und Licht in den Viewport von `entry`; er rendert einmal im nächsten Bild.
static func _build(entry: Dictionary) -> void:
	var viewport: SubViewport = entry["viewport"]
	if not is_instance_valid(viewport):
		return
	# Größe (und im Compatibility-Renderer die Transparenz) erst hier: jede Änderung legt den Render-Puffer neu an (dort
	# ~0,6 ms), so verteilt sie die Warteschlange über die Bilder.
	viewport.transparent_bg = true
	viewport.size = Vector2i(SIZE, SIZE)
	var light := DirectionalLight3D.new()
	light.transform = Transform3D(Basis.looking_at(Vector3(0.5, -0.8, -0.55)), Vector3.ZERO)
	light.light_energy = 1.2
	viewport.add_child(light)
	var model := build_model(entry["variant"])
	viewport.add_child(model)
	viewport.add_child(_camera_for(model))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Je Bild höchstens PER_FRAME (Compatibility: PER_FRAME_COMPATIBILITY) wartende Symbole bauen (ruft das Studio).
static func _drain() -> void:
	for i in range(mini(PER_FRAME_COMPATIBILITY if compatibility else PER_FRAME, _queue.size())):
		_build(_queue.pop_front())


## Orthografische Kamera aus VIEW_DIR, die das gedrehte Modell mit Rand MARGIN füllt.
static func _camera_for(model: Node3D) -> Camera3D:
	var basis := Basis.looking_at(-VIEW_DIR.normalized())
	var box: AABB = (model.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i: int in range(8):
		var corner := basis.inverse() * (model.transform * box.get_endpoint(i))
		low = Vector2(minf(low.x, corner.x), minf(low.y, corner.y))
		high = Vector2(maxf(high.x, corner.x), maxf(high.y, corner.y))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(high.x - low.x, high.y - low.y) * MARGIN
	camera.near = 0.05
	camera.far = 40.0
	var middle := (low + high) / 2.0
	camera.transform = Transform3D(basis, basis * Vector3(middle.x, middle.y, 12.0))
	return camera


static func _studio_node() -> Node:
	if not is_instance_valid(_studio):
		_studio = Studio.new()
		_studio.name = "ItemIconStudio"
		_attach.call_deferred()
	return _studio


## Hängt das Studio an die Wurzel (verzögert: die Wurzel kann gerade Kinder aufbauen); beim Verlassen des Baums (Ende
## des Spiels) leert sich der Cache.
static func _attach() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or not is_instance_valid(_studio) or _studio.is_inside_tree():
		return
	_studio.tree_exiting.connect(func(): _cache.clear())
	tree.root.add_child(_studio)


static func _shared_environment() -> Environment:
	if _environment == null:
		_environment = Environment.new()
		_environment.background_mode = Environment.BG_CLEAR_COLOR
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = Color(0.92, 0.9, 0.86)
		_environment.ambient_light_energy = 0.62
		_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return _environment


static func _shaded() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.8
	return _material


static func _silhouette_shader() -> StandardMaterial3D:
	if _silhouette_material == null:
		_silhouette_material = StandardMaterial3D.new()
		_silhouette_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_silhouette_material.albedo_color = SILHOUETTE
	return _silhouette_material


# --- Bausteine ---------------------------------------------------------------------------------------------------------

## Farbe des Abschnitts `i` von `count` eines Rohrs/Bandes nach dem Muster der Variante.
static func _band(v: Dictionary, i: int, count: int) -> Color:
	match v["pattern"]:
		STRIPES:
			return v["secondary"] if i % 2 == 1 else v["primary"]
		CHECK:
			return [v["primary"], v["secondary"], v["accent"]][i % 3]
		FADE:
			return (v["primary"] as Color).lerp(v["secondary"], float(i) / maxf(count - 1, 1))
	return v["primary"]


## Farbe der Zelle (Zeile `row` von `rows`, Spalte `col`) einer Fläche nach dem Muster der Variante.
static func _cell(v: Dictionary, row: int, rows: int, col: int) -> Color:
	match v["pattern"]:
		STRIPES:
			return v["secondary"] if row % 2 == 1 else v["primary"]
		CHECK:
			return v["secondary"] if (row + col) % 2 == 1 else v["primary"]
		FADE:
			return (v["primary"] as Color).lerp(v["secondary"], float(row) / maxf(rows - 1, 1))
	return v["primary"]


## Basis, die die y-Achse auf `direction` dreht.
static func _along(direction: Vector3) -> Basis:
	var dir := direction.normalized()
	if absf(dir.dot(Vector3.UP)) > 0.999:
		return Basis() if dir.y > 0.0 else Basis(Vector3.RIGHT, PI)
	return Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir))


static func _tube(p: Parts, a: Vector3, b: Vector3, radius: float, color: Color,
		segments: int = 6) -> void:
	p.cylinder(radius, radius, a.distance_to(b), (a + b) / 2.0, color, segments, _along(b - a))


## Rohr in `count` Abschnitten in den Farben des Musters.
static func _painted_tube(p: Parts, v: Dictionary, a: Vector3, b: Vector3, radius: float,
		count: int) -> void:
	for i: int in range(count):
		_tube(p, a.lerp(b, float(i) / count), a.lerp(b, float(i + 1) / count), radius, _band(v, i, count))


## Kegel von `base` (Radius `radius`) zur Spitze `tip`.
static func _cone(p: Parts, base: Vector3, tip: Vector3, radius: float, color: Color,
		segments: int = 5) -> void:
	p.cylinder(0.0, radius, base.distance_to(tip), (base + tip) / 2.0, color, segments, _along(tip - base))


static func _torus(p: Parts, inner: float, outer: float, at: Vector3, color: Color, basis: Basis,
		rings: int = 20, segments: int = 6) -> void:
	var ratio := inner / outer
	p.add("torus|%.3f|%d|%d" % [ratio, rings, segments], func():
		var mesh := TorusMesh.new()
		mesh.inner_radius = ratio
		mesh.outer_radius = 1.0
		mesh.rings = rings
		mesh.ring_segments = segments
		return mesh, Transform3D(basis * Basis.from_scale(Vector3.ONE * outer), at), color)


## Kugel mit wenigen Flächen (Low-Poly), skaliert (`scale` = Durchmesser je Achse).
static func _blob(p: Parts, at: Vector3, scale: Vector3, color: Color, segments: int = 7,
		rings: int = 4, hemisphere: bool = false, basis: Basis = Basis()) -> void:
	p.add("blob|%d|%d|%s" % [segments, rings, hemisphere], func():
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 0.5 if hemisphere else 1.0
		mesh.is_hemisphere = hemisphere
		mesh.radial_segments = segments
		mesh.rings = rings
		return mesh, Transform3D(basis * Basis.from_scale(scale), at), color)


# --- Modelle je Platz (x vorn, y oben, z seitlich; Größe ~1) -----------------------------------------------------------

static func _build_frame(p: Parts, names: Array[String], v: Dictionary) -> void:
	var bb := Vector3.ZERO
	var seat := Vector3(-0.2, 0.6, 0.0)
	var head_top := Vector3(0.52, 0.58, 0.0)
	var head_low := Vector3(0.58, 0.36, 0.0)
	var rear := Vector3(-0.64, 0.02, 0.0)
	var fork := Vector3(0.76, 0.02, 0.0)
	_painted_tube(p, v, seat, head_top, 0.045, 6)
	_painted_tube(p, v, bb, head_low, 0.056, 7)
	_tube(p, bb, seat + Vector3(0.0, 0.02, 0.0), 0.045, v["primary"])
	_tube(p, head_low + Vector3(0.015, -0.05, 0.0), head_top + Vector3(-0.01, 0.04, 0.0), 0.058,
			v["trim"] if v["rank"] >= 1 else v["secondary"])
	var stays: Color = (v["primary"] as Color).darkened(0.25)
	for z in [-0.06, 0.06]:
		_tube(p, bb + Vector3(0.0, 0.0, z), rear + Vector3(0.0, 0.0, z), 0.026, stays)
		_tube(p, seat + Vector3(0.0, -0.04, z * 0.6), rear + Vector3(0.0, 0.0, z), 0.024, stays)
		_tube(p, head_low + Vector3(0.0, 0.0, z * 0.6), fork + Vector3(0.0, 0.0, z), 0.03, v["secondary"])
	names.append_array(["Oberrohr", "Unterrohr", "Sitzrohr", "Steuerrohr", "Streben", "Gabel"])
	var post := seat + Vector3(-0.04, 0.16, 0.0)
	_tube(p, seat, post, 0.026, METAL)
	p.box(Vector3(0.3, 0.055, 0.14), Transform3D(Basis(), post + Vector3(-0.04, 0.03, 0.0)), DARK)
	p.box(Vector3(0.17, 0.045, 0.07), Transform3D(Basis(), post + Vector3(0.16, 0.025, 0.0)), DARK)
	names.append("Sattel")
	var stem := head_top + Vector3(0.14, 0.06, 0.0)
	_tube(p, head_top + Vector3(0.0, 0.03, 0.0), stem, 0.028, DARK)
	var tape: Color = v["accent"]
	_tube(p, stem + Vector3(0.0, 0.0, -0.22), stem + Vector3(0.0, 0.0, 0.22), 0.026, tape)
	for z in [-0.22, 0.22]:
		var a := stem + Vector3(0.0, 0.0, z)
		var b := a + Vector3(0.1, -0.05, 0.0)
		var c := b + Vector3(0.0, -0.13, 0.0)
		var d := c + Vector3(-0.1, -0.02, 0.0)
		_tube(p, a, b, 0.026, tape)
		_tube(p, b, c, 0.026, tape)
		_tube(p, c, d, 0.026, tape)
	names.append("Lenker")
	p.cylinder(0.14, 0.14, 0.03, bb + Vector3(0.0, 0.0, 0.08), METAL.darkened(0.25), 12, Basis(Vector3.RIGHT, PI / 2.0))
	p.box(Vector3(0.045, 0.22, 0.035), Transform3D(Basis(Vector3.BACK, 0.5), bb + Vector3(0.05, -0.09, 0.11)), DARK)
	names.append("Kettenblatt")
	if v["detail"] >= 1:
		_bottle(p, bb, head_low, 0.35, v["accent"] if v["detail"] == 1 else v["secondary"])
		names.append("Trinkflasche")
	if v["detail"] == 2:
		_bottle(p, bb, seat, 0.38, v["accent"])


## Trinkflasche am Rohr `a` → `b` ab Anteil `from`, auf der Oberseite.
static func _bottle(p: Parts, a: Vector3, b: Vector3, from: float, color: Color) -> void:
	var dir := (b - a).normalized()
	var side := Vector3(-dir.y, dir.x, 0.0) * 0.085
	var start := a.lerp(b, from) + side
	var end := start + dir * 0.24
	_tube(p, start, end, 0.05, color, 8)
	_tube(p, end, end + dir * 0.04, 0.026, DARK)


static func _build_wheel(p: Parts, names: Array[String], v: Dictionary) -> void:
	var axis := Basis(Vector3.RIGHT, PI / 2.0)
	_torus(p, 0.43, 0.5, Vector3.ZERO, DARK, axis, 26, 6)
	names.append("Reifen")
	_torus(p, 0.31, 0.44, Vector3.ZERO, v["primary"], Basis.from_scale(Vector3(1.0, 1.0, 0.55)) * axis, 26, 4)
	names.append("Felgenflanke")
	var decals: int = {STRIPES: 6, CHECK: 12, FADE: 0}.get(v["pattern"], 0)
	for i: int in range(decals):
		var angle := TAU * i / decals
		var color: Color = v["secondary"] if v["pattern"] == STRIPES or i % 2 == 0 else v["accent"]
		if v["rank"] >= 3:
			color = v["trim"] if i % 2 == 0 else color
		for z in [-0.04, 0.04]:
			p.box(Vector3(0.12 if decals == 6 else 0.07, 0.05, 0.012),
					Transform3D(Basis(Vector3.BACK, angle + PI / 2.0), Vector3(cos(angle), sin(angle), 0.0) * 0.375 + Vector3(0, 0, z)), color)
	if v["pattern"] == FADE:
		_torus(p, 0.31, 0.36, Vector3.ZERO, v["secondary"], Basis.from_scale(Vector3(1.0, 1.0, 0.62)) * axis, 26, 4)
		_torus(p, 0.345, 0.395, Vector3.ZERO, (v["primary"] as Color).lerp(v["secondary"], 0.5),
				Basis.from_scale(Vector3(1.0, 1.0, 0.6)) * axis, 26, 4)
	if v["detail"] == 2:
		for i: int in range(3):
			var angle := TAU * i / 3.0 + PI / 2.0
			p.box(Vector3(0.1, 0.3, 0.04), Transform3D(Basis(Vector3.BACK, angle - PI / 2.0),
					Vector3(cos(angle), sin(angle), 0.0) * 0.18), v["secondary"])
	else:
		var count := 16 if v["detail"] == 0 else 24
		for i: int in range(count):
			var angle := TAU * i / count
			p.box(Vector3(0.016, 0.28, 0.012), Transform3D(Basis(Vector3.BACK, angle - PI / 2.0),
					Vector3(cos(angle), sin(angle), 0.0) * 0.19 + Vector3(0, 0, 0.02 if i % 2 == 0 else -0.02)), METAL)
		p.cylinder(0.1, 0.1, 0.04, Vector3(0.0, 0.0, -0.075), METAL.darkened(0.35), 10, axis)
		names.append("Kassette")
	names.append("Speichen")
	p.cylinder(0.06, 0.06, 0.16, Vector3.ZERO, METAL, 8, axis)
	p.cylinder(0.035, 0.035, 0.2, Vector3.ZERO, v["trim"] if v["rank"] >= 1 else DARK, 8, axis)
	p.box(Vector3(0.03, 0.15, 0.02), Transform3D(Basis(Vector3.BACK, -0.8), Vector3(0.06, 0.03, 0.1)), v["trim"])
	names.append("Nabe")


static func _build_jersey(p: Parts, names: Array[String], v: Dictionary) -> void:
	var rows := 6
	var cols := 4
	var bottom := -0.4
	var top := 0.3
	for row: int in range(rows):
		var t := float(row) / (rows - 1)
		var width := lerpf(0.58, 0.64, t)
		var height := (top - bottom) / rows
		var y := top - (row + 0.5) * height
		for col: int in range(cols):
			var x := -width / 2.0 + (col + 0.5) * width / cols
			p.box(Vector3(width / cols + 0.002, height + 0.002, 0.2), Transform3D(Basis(), Vector3(x, y, 0.0)),
					_cell(v, row, rows, col))
	p.box(Vector3(0.56, 0.1, 0.2), Transform3D(Basis(), Vector3(0.0, 0.34, 0.0)), _cell(v, 0, rows, 1))
	names.append("Rumpf")
	for side in [-1.0, 1.0]:
		var sleeve := Transform3D(Basis(Vector3.BACK, side * -0.62), Vector3(side * 0.37, 0.25, 0.0))
		p.box(Vector3(0.32, 0.2, 0.18), sleeve, _cell(v, 0, rows, 0 if side < 0 else 3))
		p.box(Vector3(0.05, 0.21, 0.19), sleeve.translated_local(Vector3(side * 0.16, 0.0, 0.0)), v["accent"])
	names.append("Ärmel")
	_torus(p, 0.08, 0.13, Vector3(0.0, 0.4, 0.02), v["trim"] if v["rank"] >= 2 else v["secondary"],
			Basis(Vector3.RIGHT, 0.5), 14, 4)
	p.cylinder(0.08, 0.08, 0.04, Vector3(0.0, 0.39, 0.02), DARK, 10, Basis(Vector3.RIGHT, 0.5))
	names.append("Kragen")
	var band: Color = v["accent"] if v["pattern"] != FADE else v["secondary"]
	p.box(Vector3(0.66, 0.11, 0.215), Transform3D(Basis(), Vector3(0.0, 0.1, 0.0)), band)
	names.append("Brustband")
	if v["rank"] >= 3:
		p.box(Vector3(0.1, 0.07, 0.02), Transform3D(Basis(), Vector3(-0.17, 0.1, 0.11)), v["trim"])
	p.box(Vector3(0.028, 0.7, 0.02), Transform3D(Basis(), Vector3(0.0, -0.05, 0.106)), METAL.lightened(0.2))
	p.box(Vector3(0.05, 0.08, 0.02), Transform3D(Basis(), Vector3(0.0, 0.25, 0.118)), METAL)
	names.append("Reißverschluss")
	match v["detail"]:
		1:
			for side in [-1.0, 1.0]:
				p.box(Vector3(0.06, 0.5, 0.205), Transform3D(Basis(), Vector3(side * 0.28, -0.15, 0.0)),
						(v["primary"] as Color).darkened(0.35))
			names.append("Seitenteile")
		2:
			for side in [-1.0, 1.0]:
				p.box(Vector3(0.22, 0.06, 0.21), Transform3D(Basis(Vector3.BACK, side * -0.25), Vector3(side * 0.16, 0.3, 0.0)),
						v["accent"])
			names.append("Schulterpasse")


static func _build_helmet(p: Parts, names: Array[String], v: Dictionary) -> void:
	# Schlanker Aerohelm: flache, lange Schale (Tropfen), lange dünne Heckspitze, Schlitze in Längsrichtung, Visier vorn.
	var shell := Vector3(1.25, 1.45, 0.6)
	_blob(p, Vector3.ZERO, shell, v["primary"], 12, 5, true)
	_cone(p, Vector3(-0.4, 0.27, 0.0), Vector3(-1.02, 0.15, 0.0), 0.23,
			v["secondary"] if v["pattern"] == STRIPES else v["primary"], 7)
	names.append_array(["Schale", "Heckspitze"])
	match v["pattern"]:
		STRIPES:
			_blob(p, Vector3.ZERO, Vector3(shell.x * 1.012, shell.y * 1.012, 0.13), v["secondary"], 12, 5, true)
		CHECK:
			for i: int in range(4):
				for side in [-1.0, 1.0]:
					var at := _helmet_surface(shell, -0.22 + i * 0.16, side * (0.16 + (i % 2) * 0.04))
					p.box(Vector3(0.1, 0.07, 0.07), Transform3D(Basis(Vector3.BACK, at.w), Vector3(at.x, at.y, at.z)),
							v["secondary"] if i % 2 == 0 else v["accent"])
		FADE:
			_blob(p, Vector3.ZERO, Vector3(shell.x * 1.012, shell.y * 0.62, shell.z * 1.014),
					(v["primary"] as Color).lerp(v["secondary"], 0.5), 12, 5, true)
			_blob(p, Vector3.ZERO, Vector3(shell.x * 1.024, shell.y * 0.3, shell.z * 1.028), v["secondary"], 12, 5, true)
	var vents: int = 2 + v["detail"]
	for lane in [-0.12, 0.0, 0.12]:
		for i: int in range(vents):
			var at := _helmet_surface(shell, lerpf(-0.3, 0.3, float(i) / (vents - 1)), lane)
			_blob(p, Vector3(at.x, at.y, at.z), Vector3(0.15, 0.045, 0.055), DARK, 8, 3, false, Basis(Vector3.BACK, at.w))
	names.append("Lüftungsschlitze")
	_torus(p, 0.46, 0.51, Vector3(0.0, 0.015, 0.0), v["trim"] if v["rank"] >= 2 else DARK,
			Basis.from_scale(Vector3(shell.x, 0.6, shell.z)), 22, 4)
	p.box(Vector3(0.05, 0.045, 0.4), Transform3D(Basis(Vector3.BACK, -0.2), Vector3(0.6, 0.07, 0.0)), DARK)
	names.append("Visierkante")
	var visor := Color(0.95, 0.72, 0.3) if v["detail"] == 2 else Color(0.32, 0.5, 0.66)
	_blob(p, Vector3(0.56, 0.22, 0.0), Vector3(0.15, 0.38, 0.46), visor, 8, 4, false, Basis(Vector3.BACK, -0.25))
	names.append("Visier")
	for z in [-0.2, 0.2]:
		p.box(Vector3(0.03, 0.22, 0.02), Transform3D(Basis(Vector3.BACK, 0.35), Vector3(0.08, -0.09, z)), DARK)


## Punkt auf der Helmschale (Halbellipsoid `shell`, Mitte im Ursprung) über (x, z): xyz = Lage, w = Neigung in Längsrichtung.
static func _helmet_surface(shell: Vector3, x: float, z: float) -> Vector4:
	var a := shell.x * 0.5
	var c := shell.z * 0.5
	var y := shell.y * 0.5 * sqrt(maxf(1.0 - pow(x / a, 2.0) - pow(z / c, 2.0), 0.0))
	var y2 := shell.y * 0.5 * sqrt(maxf(1.0 - pow((x + 0.02) / a, 2.0) - pow(z / c, 2.0), 0.0))
	return Vector4(x, y, z, atan2(y2 - y, 0.02))


static func _build_shoe(p: Parts, names: Array[String], v: Dictionary) -> void:
	# Radschuh im Profil: flache, dunkle Sohle mit hellem Zwischenstreifen, hohe Ferse, niedrige Spitze, Drehverschluss seitlich,
	# Pedalplatte mit rotem Cleat unter dem Ballen. Starke Hell-Dunkel-Kontraste, damit er auch bei 64 px als Schuh lesbar bleibt.
	p.box(Vector3(1.0, 0.07, 0.3), Transform3D(Basis(), Vector3(0.0, 0.035, 0.0)), DARK)
	p.box(Vector3(0.26, 0.09, 0.3), Transform3D(Basis(), Vector3(-0.34, 0.045, 0.0)), DARK)
	p.box(Vector3(0.2, 0.06, 0.28), Transform3D(Basis(Vector3.BACK, 0.35), Vector3(0.5, 0.075, 0.0)), DARK)
	p.box(Vector3(0.98, 0.03, 0.305), Transform3D(Basis(), Vector3(0.0, 0.085, 0.0)), MIDSOLE)
	names.append("Sohle")
	p.box(Vector3(0.3, 0.38, 0.28), Transform3D(Basis(), Vector3(-0.3, 0.26, 0.0)), _band(v, 0, 3))
	p.box(Vector3(0.46, 0.15, 0.28), Transform3D(Basis(), Vector3(0.04, 0.16, 0.0)), _band(v, 1, 3))
	p.box(Vector3(0.5, 0.12, 0.28), Transform3D(Basis(Vector3.BACK, -0.4), Vector3(0.05, 0.26, 0.0)), _band(v, 1, 3))
	_blob(p, Vector3(0.36, 0.12, 0.0), Vector3(0.5, 0.17, 0.28), _band(v, 2, 3), 8, 4)
	p.box(Vector3(0.22, 0.05, 0.22), Transform3D(Basis(Vector3.BACK, 0.12), Vector3(-0.3, 0.45, 0.0)), DARK)
	p.box(Vector3(0.14, 0.15, 0.15), Transform3D(Basis(Vector3.BACK, -0.3), Vector3(-0.13, 0.44, 0.0)), v["accent"])
	names.append("Obermaterial")
	match v["pattern"]:
		STRIPES:
			for side in [-1.0, 1.0]:
				for k: int in range(2):
					p.box(Vector3(0.05, 0.28, 0.012), Transform3D(Basis(Vector3.BACK, -0.5),
							Vector3(-0.1 + k * 0.1, 0.2, side * 0.143)), v["secondary"])
		CHECK:
			for side in [-1.0, 1.0]:
				for k: int in range(4):
					p.box(Vector3(0.07, 0.07, 0.012), Transform3D(Basis(), Vector3(-0.38 + k * 0.08,
							0.18 + (k % 2) * 0.09, side * 0.143)), v["secondary"])
	p.box(Vector3(0.08, 0.34, 0.3), Transform3D(Basis(), Vector3(-0.46, 0.27, 0.0)), v["secondary"])
	p.box(Vector3(0.05, 0.14, 0.09), Transform3D(Basis(), Vector3(-0.5, 0.42, 0.0)),
			v["trim"] if v["rank"] >= 2 else DARK)
	names.append("Fersenkappe")
	p.box(Vector3(0.1, 0.1, 0.285), Transform3D(Basis(Vector3.BACK, 0.15), Vector3(0.56, 0.16, 0.0)), v["secondary"])
	var dials := [Vector3(-0.04, 0.27, 0.0)]
	if v["detail"] == 2:
		dials.append(Vector3(0.18, 0.21, 0.0))
	var face := Basis(Vector3.RIGHT, PI / 2.0)
	for at in dials:
		for side in [-1.0, 1.0]:
			var on: Vector3 = at + Vector3(0.0, 0.0, side * 0.145)
			p.cylinder(0.09, 0.09, 0.04, on, v["trim"] if v["rank"] >= 3 else METAL, 10, face)
			p.cylinder(0.04, 0.04, 0.055, on, v["accent"], 8, face)
	names.append("Drehverschluss")
	p.box(Vector3(0.05, 0.04, 0.29), Transform3D(Basis(Vector3.BACK, -0.45), Vector3(0.14, 0.235, 0.0)), DARK)
	if v["detail"] == 1:
		p.box(Vector3(0.09, 0.045, 0.3), Transform3D(Basis(Vector3.BACK, -0.45), Vector3(0.24, 0.2, 0.0)), v["accent"])
		names.append("Klettriemen")
	p.box(Vector3(0.3, 0.035, 0.22), Transform3D(Basis(), Vector3(0.22, -0.015, 0.0)), METAL)
	p.cylinder(0.12, 0.12, 0.05, Vector3(0.22, -0.06, 0.0), Color(0.88, 0.2, 0.16), 3)
	names.append("Pedalplatte")


## Anhänger mit Motiv; liefert die Maße (Breite des Anhängers und des Motivs, Modelleinheiten) für Tests und Meta `metrics`.
static func _build_talisman(p: Parts, names: Array[String], v: Dictionary) -> Dictionary:
	var cord := Color(0.42, 0.28, 0.16)
	if v["motif"] == STONE:
		_build_stone(p, names, v)
		return {}
	var face := Basis(Vector3.RIGHT, PI / 2.0)
	p.region_begin()
	p.cylinder(0.34, 0.34, 0.08, Vector3.ZERO, v["primary"], 14, face)
	_torus(p, 0.32, 0.4, Vector3.ZERO, v["trim"], face, 18, 4)
	var pendant := p.region_end()
	names.append("Anhänger")
	match v["pattern"]:
		STRIPES:
			_torus(p, 0.25, 0.28, Vector3(0, 0, 0.04), v["secondary"], face, 18, 3)
		CHECK:
			for i: int in range(8):
				var angle := TAU * i / 8.0
				p.box(Vector3(0.05, 0.05, 0.03), Transform3D(Basis(), Vector3(cos(angle), sin(angle), 0.0) * 0.28
						+ Vector3(0, 0, 0.04)), v["secondary"] if i % 2 == 0 else v["accent"])
		FADE:
			p.cylinder(0.26, 0.26, 0.09, Vector3.ZERO, (v["primary"] as Color).lerp(v["secondary"], 0.5), 14, face)
			p.cylinder(0.17, 0.17, 0.1, Vector3.ZERO, v["secondary"], 14, face)
	_torus(p, 0.04, 0.08, Vector3(0.0, 0.42, 0.0), v["trim"], Basis(), 10, 4)
	_tube(p, Vector3(0.0, 0.47, 0.0), Vector3(-0.22, 0.74, 0.0), 0.02, cord)
	_tube(p, Vector3(0.0, 0.47, 0.0), Vector3(0.22, 0.74, 0.0), 0.02, cord)
	names.append("Band")
	var z := 0.07
	p.region_begin()
	match v["motif"]:
		BossFigure.DRAC:
			# Drachenkopf im Profil, so groß wie die Fläche trägt: Schädel, Schnauze mit Zähnen, Auge, Hörner, Nackenstacheln
			# und Feuer aus dem Maul; auf einer dunklen Scheibe, damit er sich vom Muster des Anhängers abhebt.
			var scale_color := Color(0.3, 0.62, 0.26)
			p.cylinder(0.285, 0.285, 0.02, Vector3(0.0, 0.0, 0.048), (v["primary"] as Color).darkened(0.72), 14, face)
			p.box(Vector3(0.2, 0.24, 0.1), Transform3D(Basis(Vector3.BACK, 0.25), Vector3(-0.2, -0.1, z)),
					scale_color.darkened(0.3))
			_blob(p, Vector3(-0.07, 0.04, z), Vector3(0.4, 0.36, 0.14), scale_color, 8, 4)
			p.box(Vector3(0.3, 0.15, 0.1), Transform3D(Basis(Vector3.BACK, -0.12), Vector3(0.14, 0.0, z)), scale_color)
			p.box(Vector3(0.2, 0.04, 0.09), Transform3D(Basis(Vector3.BACK, 0.1), Vector3(0.14, -0.07, z)),
					Color(0.5, 0.06, 0.06))
			p.box(Vector3(0.26, 0.06, 0.09), Transform3D(Basis(Vector3.BACK, 0.2), Vector3(0.12, -0.12, z)),
					scale_color.darkened(0.3))
			for k: int in range(3):
				_cone(p, Vector3(0.08 + k * 0.07, -0.065, z + 0.02), Vector3(0.08 + k * 0.07, -0.125, z + 0.02), 0.022,
						Color(0.96, 0.94, 0.86), 4)
			p.box(Vector3(0.16, 0.04, 0.06), Transform3D(Basis(Vector3.BACK, -0.35), Vector3(0.0, 0.15, z + 0.04)),
					scale_color.darkened(0.45))
			p.sphere(0.05, Vector3(0.0, 0.09, z + 0.07), Color(1.0, 0.85, 0.2))
			p.sphere(0.024, Vector3(0.015, 0.09, z + 0.11), DARK)
			p.sphere(0.02, Vector3(0.27, 0.035, z + 0.06), DARK)
			_cone(p, Vector3(-0.1, 0.16, z), Vector3(-0.21, 0.26, z), 0.05, Color(0.92, 0.88, 0.74), 5)
			_cone(p, Vector3(0.0, 0.18, z), Vector3(-0.02, 0.29, z), 0.045, Color(0.92, 0.88, 0.74), 5)
			for k: int in range(3):
				_cone(p, Vector3(-0.2, 0.0 - k * 0.08, z), Vector3(-0.32, -0.03 - k * 0.09, z), 0.035,
						scale_color.darkened(0.45))
			_cone(p, Vector3(0.27, -0.06, z + 0.01), Vector3(0.39, 0.0, z + 0.01), 0.05, Color(1.0, 0.45, 0.08))
			_cone(p, Vector3(0.27, -0.07, z + 0.02), Vector3(0.4, -0.1, z + 0.02), 0.045, Color(1.0, 0.8, 0.2))
			_cone(p, Vector3(0.26, -0.08, z + 0.01), Vector3(0.35, -0.2, z + 0.01), 0.04, Color(0.95, 0.25, 0.08))
			names.append("Drachenkopf")
		BossFigure.TRAMUNTANA:
			for i: int in range(16):
				var angle := i * 0.55
				var radius := 0.03 + i * 0.0185
				p.box(Vector3(0.06, 0.055, 0.04), Transform3D(Basis(Vector3.BACK, angle), Vector3(cos(angle), sin(angle), 0.0)
						* radius + Vector3(0, 0, z)), Color(0.95, 0.97, 1.0).lerp(Color(0.55, 0.82, 1.0), i / 15.0))
			names.append("Windspirale")
		BossFigure.DIMONIS:
			var mask := Color(0.78, 0.13, 0.1)
			p.cylinder(0.285, 0.285, 0.02, Vector3(0.0, 0.0, 0.048), (v["primary"] as Color).darkened(0.65), 14, face)
			_blob(p, Vector3(0.0, -0.02, z), Vector3(0.46, 0.52, 0.14), mask, 8, 4)
			for side in [-1.0, 1.0]:
				_cone(p, Vector3(side * 0.12, 0.15, z), Vector3(side * 0.23, 0.3, z), 0.05, Color(0.16, 0.1, 0.08))
				p.box(Vector3(0.1, 0.04, 0.04), Transform3D(Basis(Vector3.BACK, side * 0.35), Vector3(side * 0.09, 0.06, z + 0.07)), DARK)
				p.sphere(0.022, Vector3(side * 0.09, 0.03, z + 0.09), Color(1.0, 0.85, 0.2))
			p.box(Vector3(0.16, 0.04, 0.04), Transform3D(Basis(), Vector3(0.0, -0.13, z + 0.07)), DARK)
			names.append("Hörnermaske")
	return {"pendant_width": pendant.size.x, "motif_width": p.region_end().size.x}


## Gewöhnlicher Talisman: Kiesel am Band, mit Draht umwickelt; Tönung, Neigung, Maserung und Perlen aus der Variante.
static func _build_stone(p: Parts, names: Array[String], v: Dictionary) -> void:
	var stone := Color(0.64, 0.61, 0.55).lerp(v["primary"], 0.3)
	var cord: Color = (v["secondary"] as Color).darkened(0.45)
	var tilt := Basis(Vector3.BACK, (int(v["seed"]) % 7 - 3) * 0.07)
	var middle := Vector3(0.0, -0.08, 0.0)
	_blob(p, middle, Vector3(0.66, 0.52, 0.38), stone, 7, 4, false, tilt)
	_blob(p, middle + tilt * Vector3(0.1, 0.05, 0.1), Vector3(0.32, 0.24, 0.22), stone.lightened(0.12), 5, 3, false, tilt)
	match v["pattern"]:
		STRIPES:
			_blob(p, middle, Vector3(0.68, 0.06, 0.4), stone.lightened(0.35), 7, 2, false, tilt * Basis(Vector3.BACK, 0.35))
		CHECK:
			for k: int in range(5):
				var at := Vector3(-0.18 + k * 0.09, -0.16 + (k % 2) * 0.12 + (k % 3) * 0.03, 0.18)
				p.box(Vector3(0.035, 0.035, 0.02), Transform3D(tilt, middle + tilt * at), stone.darkened(0.45))
		FADE:
			_blob(p, middle + tilt * Vector3(0.0, 0.07, 0.0), Vector3(0.6, 0.32, 0.395), stone.lightened(0.22), 7, 3,
					false, tilt)
	names.append("Stein")
	for angle in [-0.6, 0.6]:
		_torus(p, 0.9, 1.0, middle, cord, tilt * Basis(Vector3.BACK, angle)
				* Basis.from_scale(Vector3(0.36, 0.29, 0.2)) * Basis(Vector3.RIGHT, PI / 2.0), 14, 3)
	_torus(p, 0.035, 0.065, Vector3(0.0, 0.21, 0.0), cord, Basis(Vector3.RIGHT, PI / 2.0), 10, 4)
	_tube(p, Vector3(0.0, 0.26, 0.0), Vector3(-0.2, 0.62, 0.0), 0.02, cord)
	_tube(p, Vector3(0.0, 0.26, 0.0), Vector3(0.2, 0.62, 0.0), 0.02, cord)
	names.append("Band")
	if v["detail"] >= 1:
		p.sphere(0.045, Vector3(-0.09, 0.42, 0.0), v["accent"])
	if v["detail"] == 2:
		p.sphere(0.045, Vector3(0.09, 0.42, 0.0), v["accent"])


## Knoten, unter dem die Viewports hängen; baut je Bild die nächsten wartenden Symbole.
class Studio:
	extends Node

	func _process(_delta: float) -> void:
		ItemIcons._drain()


## Baukasten der Modelle (Schnittstelle wie IslandLandmarks.Parts): je Grundkörper eine eigene Fläche des ArrayMesh,
## Grunddaten je Form einmal erzeugt (Einheitsgröße, Maße über die Transformation) und in der Engine transformiert –
## keine Schleife über Eckpunkte in GDScript, damit ein neues Symbol schnell entsteht (Ziel < 5 ms).
class Parts:
	## Form → Arrays der Einheitsform (geteilt über alle Modelle).
	static var _shapes := {}
	## Form → Hüllquader der Einheitsform.
	static var _extents := {}
	var _mesh := ArrayMesh.new()
	var _region := AABB()
	var _region_open := false
	var _region_empty := true

	## Beginnt, die Hüllquader aller folgenden Teile zu vereinen (für Maße im Modell, z. B. Breite des Drachenkopfs).
	func region_begin() -> void:
		_region_open = true
		_region_empty = true
		_region = AABB()

	## Beendet die Messung und gibt den Hüllquader der Teile seit `region_begin` zurück (Modellraum, vor TURN; die Hülle eines
	## gedrehten Teils ist die seiner Box, also etwas weiter als das Teil selbst).
	func region_end() -> AABB:
		_region_open = false
		return _region

	## Form `key` (beim ersten Mal von `make` als PrimitiveMesh erzeugt) mit `transform` in `color`.
	func add(key: String, make: Callable, transform: Transform3D, color: Color) -> void:
		if not _shapes.has(key):
			var primitive := make.call() as PrimitiveMesh
			_shapes[key] = primitive.get_mesh_arrays()
			_extents[key] = primitive.get_aabb()
		if _region_open:
			var box: AABB = transform * (_extents[key] as AABB)
			_region = box if _region_empty else _region.merge(box)
			_region_empty = false
		var shape: Array = _shapes[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = transform * (shape[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		arrays[Mesh.ARRAY_NORMAL] = Transform3D(transform.basis.inverse().transposed(), Vector3.ZERO) \
				* (shape[Mesh.ARRAY_NORMAL] as PackedVector3Array)
		var colors := PackedColorArray()
		colors.resize((shape[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		colors.fill(color)
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = shape[Mesh.ARRAY_INDEX]
		if _mesh.get_surface_count() < RenderingServer.MAX_MESH_SURFACES:
			_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		else:
			push_error("ItemIcons: Modell hat mehr als %d Teile" % RenderingServer.MAX_MESH_SURFACES)

	## Box `size` mit Mittelpunkt/Lage `transform`.
	func box(size: Vector3, transform: Transform3D, color: Color) -> void:
		add("box", func(): return BoxMesh.new(), Transform3D(transform.basis * Basis.from_scale(size), transform.origin),
				color)

	## Kegelstumpf (Radius oben/unten, Höhe) mit Mittelpunkt `at`, optional gedreht.
	func cylinder(top: float, bottom: float, height: float, at: Vector3, color: Color, segments: int = 16,
			basis: Basis = Basis()) -> void:
		var base := maxf(top, bottom)
		var ratio_top := top / base
		var ratio_bottom := bottom / base
		add("cylinder|%d|%.3f|%.3f" % [segments, ratio_top, ratio_bottom], func():
			var mesh := CylinderMesh.new()
			mesh.top_radius = ratio_top
			mesh.bottom_radius = ratio_bottom
			mesh.height = 1.0
			mesh.radial_segments = segments
			mesh.rings = 1
			return mesh, Transform3D(basis * Basis.from_scale(Vector3(base, height, base)), at), color)

	func sphere(radius: float, at: Vector3, color: Color, basis: Basis = Basis()) -> void:
		add("sphere", func():
			var mesh := SphereMesh.new()
			mesh.radial_segments = 8
			mesh.rings = 4
			return mesh, Transform3D(basis * Basis.from_scale(Vector3.ONE * radius * 2.0), at), color)

	func commit() -> ArrayMesh:
		return _mesh
