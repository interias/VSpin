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
		var gradient := (ItemIcons.backdrop_for(rarity) as GradientTexture2D).gradient
		assert_eq(gradient.get_color(0), Loot.color_of(rarity).darkened(0.42))
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
