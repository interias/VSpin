## Ausrüstungssymbole (#83): Variante deterministisch aus dem Inhalt (nicht aus der `id`, stabiler Hash), verschiedene
## Teile verschieden, jede Kombination Platz × Seltenheit erzeugt ein Bild mit den Bauteilen ihres Platzes, leerer Platz
## als Silhouette, Rahmen in der Seltenheitsfarbe, Cache, Talisman-Motive, Leuchten an/aus und das Control in Containern.
## Headless gibt es kein echtes Bild: geprüft werden Variante, Modellaufbau und Textur-Objekte, nicht Pixel.
extends GutTest

var _compatibility := ItemIcons.compatibility


func after_each() -> void:
	ItemIcons.clear_cache()
	ItemIcons.glow_enabled = true
	ItemIcons.compatibility = _compatibility


func _item(slot: String, rarity: String, stats: Dictionary, effect: String = "") -> Dictionary:
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": effect}


func _look(variant: Dictionary) -> Array:
	return [variant["palette"], variant["pattern"], variant["detail"], variant["motif"]]


func test_hash_is_standard_fnv1a() -> void:
	assert_eq(ItemIcons.fnv1a(""), 0x811C9DC5, "FNV-1a 32 Bit, leerer Text")
	assert_eq(ItemIcons.fnv1a("a"), 0xE40C292C, "FNV-1a 32 Bit, „a“ – fester Wert, kein hash() der Engine")


func test_same_content_gives_same_variant() -> void:
	var a := _item("helm", Loot.MAGIC, {"zone_width_rpm": 3, "points_pct": 6})
	var b := {"effect": "", "stats": {"points_pct": 6.0, "zone_width_rpm": 3.0}, "rarity": Loot.MAGIC, "slot": "helm",
		"id": 17}
	assert_eq(ItemIcons.key_of(a), ItemIcons.key_of(b), "Reihenfolge, 3 gegen 3.0 und id ändern nichts")
	assert_eq(ItemIcons.seed_of(a), ItemIcons.seed_of(b))
	assert_eq(ItemIcons.variant_of(a), ItemIcons.variant_of(b.duplicate(true)), "gleiche Variante")
	assert_same(ItemIcons.texture_for(a), ItemIcons.texture_for(b), "dasselbe Bild beim Fund (ohne id) und im Inventar")


func test_key_lists_content_in_stat_order() -> void:
	var item := _item("talisman", Loot.LEGENDARY, {"luck_pct": 21, "zone_width_rpm": 4}, "rueckstoss")
	assert_eq(ItemIcons.key_of(item), "talisman|legendaer|zone_width_rpm=4|luck_pct=21|rueckstoss")
	var plain := _item("talisman", Loot.MAGIC, {"luck_pct": 9}, "rueckstoss")
	assert_eq(ItemIcons.key_of(plain), "talisman|magisch|luck_pct=9|", "Effekt nur bei legendären Teilen (Loot.effect_of)")


func test_different_items_of_a_slot_vary() -> void:
	var looks := {}
	var patterns := {}
	var primaries := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	for i in range(30):
		var item := Loot.roll(rng)
		item["slot"] = "helm"
		var variant := ItemIcons.variant_of(item)
		looks[_look(variant)] = true
		patterns[variant["pattern"]] = true
		primaries[variant["primary"]] = true
	assert_gt(looks.size(), 18, "30 Helme: im Mittel verschiedene Varianten (%d)" % looks.size())
	assert_eq(patterns.size(), ItemIcons.PATTERNS.size(), "alle Muster kommen vor")
	assert_gt(primaries.size(), 5, "viele Grundfarben aus der Palette")
	for i in range(30):
		var variant := ItemIcons.variant_of(_item("trikot", Loot.RARE, {"points_pct": 10 + i}))
		assert_ne(variant["primary"], variant["secondary"], "Grund- und Zweitfarbe verschieden")
		assert_ne(variant["accent"], variant["primary"])
		assert_ne(variant["accent"], variant["secondary"])


func test_every_slot_and_rarity_builds_an_icon() -> void:
	for slot in Loot.SLOTS:
		for rarity in Loot.RARITIES:
			var item := _item(slot, rarity, {Loot.SLOTS[slot]["stat"]: 3}, "im_fluss" if rarity == Loot.LEGENDARY else "")
			var texture := ItemIcons.texture_for(item)
			assert_true(texture is ViewportTexture, "%s/%s: Bild" % [slot, rarity])
			var viewport := ItemIcons.viewport_for(item)
			assert_eq(viewport.transparent_bg, not ItemIcons.compatibility,
					"Forward+: schon wartend durchsichtig (kein schwarzes Quadrat)")
			ItemIcons.flush()
			assert_eq(viewport.size, Vector2i(ItemIcons.SIZE, ItemIcons.SIZE))
			assert_true(viewport.transparent_bg, "Hintergrund zeichnet das Control")
			assert_eq(viewport.render_target_update_mode, SubViewport.UPDATE_ONCE, "rendert einmal")
			var mesh: MeshInstance3D = viewport.get_node("Model/Mesh")
			assert_gt(mesh.mesh.get_faces().size(), 100, "%s/%s: Modell aus Grundkörpern" % [slot, rarity])
			assert_true(viewport.find_children("*", "Camera3D", false, false).size() == 1, "feste Kamera")
			assert_eq((viewport.find_children("*", "Camera3D", false, false)[0] as Camera3D).projection,
					Camera3D.PROJECTION_ORTHOGONAL)
	assert_eq(ItemIcons.cache_size(), Loot.SLOTS.size() * Loot.RARITIES.size())


func test_models_have_the_parts_of_their_slot() -> void:
	var expected := {
		"rahmen": ["Oberrohr", "Unterrohr", "Sattel", "Lenker"],
		"laufraeder": ["Reifen", "Felgenflanke", "Speichen", "Nabe"],
		"trikot": ["Ärmel", "Kragen", "Reißverschluss", "Brustband"],
		"helm": ["Schale", "Lüftungsschlitze", "Visierkante"],
		"schuhe": ["Sohle", "Drehverschluss", "Pedalplatte"],
		"talisman": ["Anhänger", "Band"],
	}
	for slot in expected:
		for detail in range(ItemIcons.DETAILS):
			for pattern in ItemIcons.PATTERNS:
				var variant := ItemIcons.variant_of(_item(slot, Loot.RARE, {"luck_pct": 5}))
				variant["detail"] = detail
				variant["pattern"] = pattern
				var model := ItemIcons.build_model(variant)
				var names: Array = model.get_meta("parts")
				for part in expected[slot]:
					assert_has(names, part, "%s (Detail %d, %s): %s" % [slot, detail, pattern, part])
				model.free()
	var frame := ItemIcons.variant_of(_item("rahmen", Loot.MAGIC, {"progress_pct": 4}))
	frame["detail"] = 0
	var plain := ItemIcons.build_model(frame)
	frame["detail"] = 2
	var bottles := ItemIcons.build_model(frame)
	assert_does_not_have(plain.get_meta("parts"), "Trinkflasche", "Detail 0 ohne Flasche")
	assert_has(bottles.get_meta("parts"), "Trinkflasche", "Detailteile unterscheiden die Varianten")
	plain.free()
	bottles.free()


func test_talisman_motifs_follow_the_rules() -> void:
	for i in range(20):
		assert_eq(ItemIcons.motif_of(_item("talisman", Loot.COMMON, {"luck_pct": i})), ItemIcons.STONE,
				"gewöhnlich = Stein")
	var stone := ItemIcons.build_model(ItemIcons.variant_of(_item("talisman", Loot.COMMON, {"luck_pct": 5})))
	assert_has(stone.get_meta("parts"), "Stein")
	assert_does_not_have(stone.get_meta("parts"), "Anhänger", "der Stein ist kein Anhänger")
	stone.free()
	var by_effect := {"rueckstoss": BossFigure.TRAMUNTANA, "auf_dem_sprung": BossFigure.TRAMUNTANA,
		"tiefer_atem": BossFigure.DRAC, "im_fluss": BossFigure.DRAC, "kombo_ernte": BossFigure.DIMONIS}
	assert_eq(by_effect.keys().size(), Loot.EFFECTS.size(), "jeder Effekt hat ein Motiv")
	for effect in Loot.EFFECTS:
		for i in range(5):
			var legendary := _item("talisman", Loot.LEGENDARY, {"luck_pct": 20 + i}, effect)
			assert_eq(ItemIcons.motif_of(legendary), by_effect[effect], "legendär mit %s" % effect)
	var seen := {}
	for rarity in [Loot.MAGIC, Loot.RARE]:
		for i in range(30):
			var motif := ItemIcons.motif_of(_item("talisman", rarity, {"luck_pct": i}))
			assert_has(ItemIcons.MOTIFS, motif, "magisch/selten: eine Sagengestalt, nie Stein")
			seen[motif] = true
	assert_eq(seen.size(), ItemIcons.MOTIFS.size(), "alle drei Motive kommen aus dem Seed vor")
	assert_has(ItemIcons.MOTIFS, ItemIcons.motif_of(_item("talisman", Loot.LEGENDARY, {"luck_pct": 30})),
			"legendär ohne Effekt (alter Stand): aus dem Seed")
	assert_eq(ItemIcons.motif_of(_item("helm", Loot.RARE, {"zone_width_rpm": 2})), "", "nur Talismane haben Motive")
	var parts_by_motif := {BossFigure.DRAC: "Drachenkopf", BossFigure.TRAMUNTANA: "Windspirale",
		BossFigure.DIMONIS: "Hörnermaske"}
	for effect in Loot.EFFECTS:
		var model := ItemIcons.build_model(ItemIcons.variant_of(_item("talisman", Loot.LEGENDARY, {"luck_pct": 25}, effect)))
		assert_has(model.get_meta("parts"), parts_by_motif[by_effect[effect]], "Motiv %s gebaut" % by_effect[effect])
		model.free()


func test_cache_builds_each_icon_once() -> void:
	ItemIcons.clear_cache()
	var before := ItemIcons.built
	var item := _item("schuhe", Loot.RARE, {"zone_width_rpm": 4, "luck_pct": 12, "points_pct": 9})
	var first := ItemIcons.texture_for(item)
	assert_eq(ItemIcons.built, before + 1, "erstes Anzeigen erzeugt das Bild")
	assert_same(ItemIcons.texture_for(item), first, "zweiter Aufruf: aus dem Cache")
	assert_same(ItemIcons.texture_for(item.duplicate(true)), first, "auch mit neu erzeugtem Dictionary")
	assert_eq(ItemIcons.built, before + 1, "nichts neu erzeugt")
	var silhouette := ItemIcons.silhouette_for("schuhe")
	assert_same(ItemIcons.silhouette_for("schuhe"), silhouette)
	assert_eq(ItemIcons.built, before + 2, "Silhouette einmal")
	ItemIcons.clear_cache()
	assert_eq(ItemIcons.cache_size(), 0)
	assert_not_same(ItemIcons.texture_for(item), first, "nach dem Leeren neu")


func test_empty_slot_shows_gray_silhouette() -> void:
	for slot in Loot.SLOTS:
		var view := ItemIconView.of_slot(slot)
		add_child_autofree(view)
		assert_true(view.is_empty())
		assert_same(view.texture(), ItemIcons.silhouette_for(slot), "%s: Silhouette des Platzes" % slot)
		assert_eq(view.frame_color(), ItemIconView.EMPTY_BORDER, "grauer Rahmen, keine Seltenheit")
		var mesh := _mesh_of(view.texture() as ViewportTexture)
		var material := mesh.material_override as StandardMaterial3D
		assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "flach, ohne Licht")
		assert_eq(material.albedo_color, ItemIcons.SILHOUETTE, "grau")
		assert_false(material.vertex_color_use_as_albedo, "keine Farben der Variante")
	var variant := ItemIcons.silhouette_variant("talisman")
	assert_true(variant["silhouette"])
	var model := ItemIcons.build_model(variant)
	assert_has(model.get_meta("parts"), "Anhänger", "leerer Talisman: schlichter Anhänger")
	model.free()


## Modell hinter dem Bild `texture` (über den Cache-Eintrag; das Studio hängt erst am Ende des Bildes an der Wurzel).
func _mesh_of(texture: ViewportTexture) -> MeshInstance3D:
	ItemIcons.flush()
	for entry in ItemIcons._cache.values():
		if entry["texture"] == texture:
			return entry["viewport"].get_node("Model/Mesh")
	return null


func test_frame_shows_rarity_color() -> void:
	for rarity in Loot.RARITIES:
		var view := ItemIconView.of_item(_item("rahmen", rarity, {"progress_pct": 5}))
		add_child_autofree(view)
		assert_eq(view.frame_color(), Loot.color_of(rarity), "%s: Rahmen in der Seltenheitsfarbe" % rarity)
		assert_same(view._backdrop.texture, ItemIcons.backdrop_for(rarity), "Hintergrund in der Seltenheitsfarbe")
		var colors := ItemIcons.backdrop_colors(rarity)
		if ItemIcons.BACKDROPS.has(rarity):
			assert_eq(colors, ItemIcons.BACKDROPS[rarity], "selten und legendär: eigene Hintergrundfarben")
			var texture := ItemIcons.backdrop_for(rarity)
			if rarity == Loot.LEGENDARY:
				# Strahlenbild: Mitte nahe der Mittelfarbe, Ecke nahe der Randfarbe (Strahlen heben sie höchstens um ~0,22).
				var image := texture.get_image()
				var middle := image.get_pixel(ItemIcons.RAY_SIZE / 2, int(ItemIcons.RAY_SIZE * 0.42))
				var corner := image.get_pixel(0, 0)
				assert_lt(Vector3(middle.r - colors[0].r, middle.g - colors[0].g, middle.b - colors[0].b).length(), 0.1,
						"legendär: Bildmitte in der Mittelfarbe")
				assert_lt(Vector3(corner.r - colors[1].r, corner.g - colors[1].g, corner.b - colors[1].b).length(), 0.25,
						"legendär: Bildecke in der Randfarbe")
			else:
				var gradient := (texture as GradientTexture2D).gradient
				assert_eq(gradient.get_color(0), colors[0], "selten: Verlauf aus den Hintergrundfarben")
				assert_eq(gradient.get_color(1), colors[1])
		else:
			var gradient := (ItemIcons.backdrop_for(rarity) as GradientTexture2D).gradient
			assert_eq(gradient.get_color(0), Loot.color_of(rarity).darkened(0.42), "gewöhnlich, magisch: Rahmenfarbe abgedunkelt")
			assert_eq(gradient.get_color(1), Loot.color_of(rarity).darkened(0.84))
		assert_same(view.texture(), ItemIcons.texture_for(view.item))


func test_glow_on_shows_and_off_hides_it() -> void:
	var legendary := ItemIconView.of_item(_item("helm", Loot.LEGENDARY, {"zone_width_rpm": 6}, "rueckstoss"))
	var rare := ItemIconView.of_item(_item("helm", Loot.RARE, {"zone_width_rpm": 5}))
	add_child_autofree(legendary)
	add_child_autofree(rare)
	await wait_process_frames(2)
	assert_true(legendary.is_glowing(), "an: legendäres Teil leuchtet")
	assert_gt(legendary.get_theme_stylebox("panel").shadow_size, 0, "Schein um den Rahmen")
	assert_false(rare.is_glowing(), "nur legendäre Teile leuchten")
	assert_eq(rare.get_theme_stylebox("panel").shadow_size, 0)
	ItemIcons.glow_enabled = false
	await wait_process_frames(2)
	assert_false(legendary.is_glowing(), "aus: kein Leuchten – auch auf einem schon gezeigten Symbol")
	assert_eq(legendary.get_theme_stylebox("panel").shadow_size, 0, "kein Schein")
	assert_false(legendary._shimmer.visible, "kein Schimmer")
	var fresh := ItemIconView.of_item(_item("schuhe", Loot.LEGENDARY, {"zone_width_rpm": 6}, "im_fluss"))
	add_child_autofree(fresh)
	assert_false(fresh.is_glowing(), "aus: auch neue Symbole leuchten nicht")
	ItemIcons.glow_enabled = true
	await wait_process_frames(2)
	assert_true(legendary.is_glowing(), "wieder an")
	assert_true(fresh.is_glowing())
	var empty := ItemIconView.of_slot("helm")
	add_child_autofree(empty)
	assert_false(empty.is_glowing(), "leerer Platz leuchtet nie")


func test_view_fits_into_containers() -> void:
	var box := HBoxContainer.new()
	add_child_autofree(box)
	var small := ItemIconView.of_item(_item("trikot", Loot.MAGIC, {"points_pct": 8}), 64.0)
	var large := ItemIconView.of_slot("trikot")
	box.add_child(small)
	box.add_child(large)
	await wait_process_frames(2)
	assert_eq(small.custom_minimum_size, Vector2(64, 64))
	assert_eq(large.custom_minimum_size, Vector2(96, 96), "Standard 96 px (Halbbild)")
	assert_eq(small.size, Vector2(64, 64), "quadratisch im Container")
	assert_gt(large.position.x, small.position.x, "der Container ordnet an, keine feste Position")
	assert_eq(small.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Klicks gehen an den Button darum")
	small.icon_size = 128.0
	assert_eq(small.custom_minimum_size, Vector2(128, 128), "Größe umstellbar")
	small.show_item(_item("helm", Loot.LEGENDARY, {"zone_width_rpm": 6}, "rueckstoss"))
	assert_eq(small.slot, "helm", "Inhalt umstellbar")
	assert_eq(small.frame_color(), Loot.color_of(Loot.LEGENDARY))


func test_compatibility_renderer_builds_without_msaa() -> void:
	ItemIcons.compatibility = true
	var item := _item("laufraeder", Loot.LEGENDARY, {"progress_pct": 12}, "kombo_ernte")
	assert_true(ItemIcons.texture_for(item) is ViewportTexture, "Browser: das Symbol erscheint auch")
	assert_eq(ItemIcons.viewport_for(item).msaa_3d, Viewport.MSAA_DISABLED, "einfacher: ohne MSAA")
	ItemIcons.compatibility = false
	var desktop := _item("laufraeder", Loot.LEGENDARY, {"progress_pct": 13}, "kombo_ernte")
	assert_eq(ItemIcons.viewport_for(desktop).msaa_3d, Viewport.MSAA_4X)


## Ein Inventar mit vielen neuen Teilen: Texturen sofort, Modelle über die Bilder verteilt (höchstens PER_FRAME je Bild).
func test_new_icons_are_built_a_few_per_frame() -> void:
	var textures := []
	for i in range(20):
		textures.append(ItemIcons.texture_for(_item("trikot", Loot.MAGIC, {"points_pct": 5 + i})))
	assert_eq(textures.filter(func(t): return t is ViewportTexture).size(), 20, "jede Textur sofort da")
	assert_eq(ItemIcons.pending(), 20, "Modelle warten")
	var start := Engine.get_process_frames()
	while ItemIcons.pending() > 0 and Engine.get_process_frames() - start < 60:
		await wait_process_frames(1)
		var frames := Engine.get_process_frames() - start
		assert_true(20 - ItemIcons.pending() <= frames * ItemIcons.PER_FRAME,
				"höchstens PER_FRAME je Bild (%d gebaut in %d Bildern)" % [20 - ItemIcons.pending(), frames])
	assert_eq(ItemIcons.pending(), 0, "nach wenigen Bildern alle gebaut")
	assert_true(Engine.get_process_frames() - start >= ceili(20.0 / ItemIcons.PER_FRAME), "über mehrere Bilder verteilt")


func test_studio_hangs_at_root_after_the_frame() -> void:
	ItemIcons.texture_for(_item("helm", Loot.COMMON, {"zone_width_rpm": 1}))
	await wait_process_frames(1)
	var studio := get_tree().root.get_node_or_null("ItemIconStudio")
	assert_not_null(studio, "Viewports hängen unter einem eigenen Knoten an der Wurzel")
	assert_eq(studio.get_child_count(), 1)


## Selten und legendär liegen als Rahmenfarbe nah beieinander (Gelb, Orange; kommen aus Loot und färben auch Lichtsäule und
## Schrift). Im Symbol selbst trennen Hintergrund und Zier sie: selten hell goldgelb, legendär tief Glutorange bis Rot. Schwellen:
## Der RGB-Abstand der Rahmenfarben beträgt 0,22; die alten Hintergründe (Rahmenfarbe abgedunkelt) lagen bei 0,19 (Mitte) und
## 0,05 (Rand) auseinander. Jetzt verlangen wir mindestens 0,3 an beiden Stellen, einen Farbtonabstand von 0,05 und einen hellen
## Rand bei selten gegen einen dunklen bei legendär.
func test_rare_and_legendary_backdrops_differ_clearly() -> void:
	var rare := ItemIcons.backdrop_colors(Loot.RARE)
	var legendary := ItemIcons.backdrop_colors(Loot.LEGENDARY)
	var distance := func(a: Color, b: Color) -> float:
		return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
	assert_gt(distance.call(rare[0], legendary[0]), 0.3, "Mitte weit auseinander")
	assert_gt(distance.call(rare[1], legendary[1]), 0.3, "Rand weit auseinander")
	assert_gt((rare[0] as Color).h - (legendary[0] as Color).h, 0.05, "selten gelber, legendär röter")
	assert_gt((rare[1] as Color).v, 0.4, "selten: heller Rand")
	assert_lt((legendary[1] as Color).v, 0.3, "legendär: dunkler, roter Rand")
	assert_gt((rare[0] as Color).s, 0.0)
	# Die Rahmenfarben bleiben (Loot).
	assert_eq(Loot.color_of(Loot.RARE), Color(1.0, 0.86, 0.2))
	assert_eq(Loot.color_of(Loot.LEGENDARY), Color(1.0, 0.55, 0.1))
	# Zier: selten blasses Silbergold, legendär sattes Gold.
	var trims := ItemIcons.TRIMS
	assert_gt((trims[3] as Color).s - (trims[2] as Color).s, 0.4, "legendäre Zier viel satter als die seltene")
	assert_gt((trims[2] as Color).v, 0.85, "seltene Zier hell")
	assert_gt(distance.call(trims[2], trims[3]), 0.3, "Zierfarben weit auseinander")
	var variants := {}
	for rarity in [Loot.RARE, Loot.LEGENDARY]:
		variants[rarity] = ItemIcons.variant_of(_item("helm", rarity, {"zone_width_rpm": 3}))
	assert_eq(variants[Loot.RARE]["trim"], trims[2])
	assert_eq(variants[Loot.LEGENDARY]["trim"], trims[3])


## Legendär: Strahlenkranz im Hintergrund – auf gleichem Abstand von der Mitte wechseln Strahl und Lücke; bei selten ist der
## Verlauf glatt. Das Bild ist geteilt und rendert ohne Leuchten (der Schalter berührt es nicht).
func test_legendary_backdrop_has_rays_and_rare_does_not() -> void:
	var rays := ItemIcons.backdrop_for(Loot.LEGENDARY)
	assert_same(rays, ItemIcons.backdrop_for(Loot.LEGENDARY), "einmal gezeichnet, geteilt")
	var image := rays.get_image()
	var middle := Vector2(0.5, 0.42) * ItemIcons.RAY_SIZE
	var radius := ItemIcons.RAY_SIZE * 0.3
	var low := 1.0
	var high := 0.0
	for i in range(96):
		var at := middle + Vector2.from_angle(TAU * i / 96.0) * radius
		var green := image.get_pixel(clampi(roundi(at.x), 0, ItemIcons.RAY_SIZE - 1), clampi(roundi(at.y), 0, ItemIcons.RAY_SIZE - 1)).g
		low = minf(low, green)
		high = maxf(high, green)
	assert_gt(high - low, 0.08, "Strahlen: Helligkeit wechselt um den Kranz (%.3f bis %.3f)" % [low, high])
	var rare := (ItemIcons.backdrop_for(Loot.RARE) as GradientTexture2D)
	assert_eq(rare.fill, GradientTexture2D.FILL_RADIAL, "selten: glatter Verlauf ohne Strahlen")
	ItemIcons.glow_enabled = false
	assert_same(ItemIcons.backdrop_for(Loot.LEGENDARY), rays, "Leuchten aus ändert den Hintergrund nicht")


## Aerohelm (#83 Feinschliff): schmal in Querrichtung gegenüber seiner Länge (Tropfen mit Heckspitze, vorher 0,6), mit
## Lüftungsschlitzen, Visierkante und Visier.
func test_helmet_is_slim_with_vents_and_visor() -> void:
	for detail in range(ItemIcons.DETAILS):
		var variant := ItemIcons.variant_of(_item("helm", Loot.RARE, {"zone_width_rpm": 3}))
		variant["detail"] = detail
		var model := ItemIcons.build_model(variant)
		var box: AABB = (model.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
		assert_lt(box.size.z / box.size.x, 0.42, "Detail %d: Breite zur Länge %.2f" % [detail, box.size.z / box.size.x])
		for part in ["Heckspitze", "Lüftungsschlitze", "Visierkante", "Visier"]:
			assert_has(model.get_meta("parts"), part)
		model.free()


## Radschuh: lang und flach, mit Pedalplatte samt Cleat unter der Sohle (Länge zur Höhe 1,85, vorher 1,87: der Wächter
## sichert die Bauteile und den Cleat, die Lesbarkeit bei 64 px zeigen die Bilder), Fersenkappe, Drehverschluss; Klettriemen nur bei Detail 1.
func test_shoe_is_long_and_flat_with_cleat_and_dial() -> void:
	for detail in range(ItemIcons.DETAILS):
		var variant := ItemIcons.variant_of(_item("schuhe", Loot.LEGENDARY, {"zone_width_rpm": 3}, "im_fluss"))
		variant["detail"] = detail
		var model := ItemIcons.build_model(variant)
		var box: AABB = (model.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
		assert_gt(box.size.x / box.size.y, 1.8, "Detail %d: Länge zur Höhe %.2f" % [detail, box.size.x / box.size.y])
		assert_lt(box.position.y, -0.05, "Cleat ragt unter die Sohle")
		for part in ["Sohle", "Obermaterial", "Fersenkappe", "Drehverschluss", "Pedalplatte"]:
			assert_has(model.get_meta("parts"), part)
		assert_eq((model.get_meta("parts") as Array).has("Klettriemen"), detail == 1)
		model.free()


## Talisman-Motive füllen den Anhänger: der Drachenkopf (Schnauze, Hörner, Auge, Feuer) mindestens 88 % seiner Breite (jetzt 94 %, der
## alte Kopf kam in dieser Messung auf 81 %; die Hülle zählt Hörner und Feuer mit), Windspirale und Hörnermaske mindestens 55 % (Windspirale vorher 49 %). Gemessen an den Bauteilen im Modell (`metrics`).
func test_talisman_motifs_fill_the_pendant() -> void:
	var minimum := {BossFigure.DRAC: 0.88, BossFigure.TRAMUNTANA: 0.55, BossFigure.DIMONIS: 0.55}
	var effects := {BossFigure.DRAC: "tiefer_atem", BossFigure.TRAMUNTANA: "rueckstoss", BossFigure.DIMONIS: "kombo_ernte"}
	for motif in minimum:
		for pattern in ItemIcons.PATTERNS:
			var variant := ItemIcons.variant_of(_item("talisman", Loot.LEGENDARY, {"luck_pct": 25}, effects[motif]))
			variant["pattern"] = pattern
			var model := ItemIcons.build_model(variant)
			var metrics: Dictionary = model.get_meta("metrics")
			var share: float = metrics["motif_width"] / metrics["pendant_width"]
			assert_gt(share, minimum[motif], "%s (%s): Motiv %.0f %% der Anhängerbreite" % [motif, pattern, share * 100.0])
			assert_lt(share, 1.0, "%s: das Motiv bleibt im Anhänger" % motif)
			model.free()
	var stone := ItemIcons.build_model(ItemIcons.variant_of(_item("talisman", Loot.COMMON, {"luck_pct": 5})))
	assert_eq(stone.get_meta("metrics"), {}, "Stein: kein Motiv zu messen")
	stone.free()
