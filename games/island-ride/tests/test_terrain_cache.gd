## Gelände-Cache (#19): ein Treffer liefert dasselbe Gelände wie die Erzeugung, ein anderer Schlüssel
## (geänderte Quellen/Parameter) erzeugt neu, ein kaputter Cache stört nicht.
extends GutTest

const PATH := "user://test_terrain_cache.bin"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


## Dieselbe Strecke 50 m höher – erzeugt ein anderes Gelände.
func _raised(road: PackedVector3Array) -> PackedVector3Array:
	var raised := PackedVector3Array()
	for p in road:
		raised.append(p + Vector3(0.0, 50.0, 0.0))
	return raised


func test_cache_hit_returns_identical_terrain() -> void:
	var road := IslandCourse.samples()
	var fresh := IslandTerrain.cached_generate(road, "key-a", PATH)
	assert_true(FileAccess.file_exists(PATH), "erste Erzeugung schreibt den Cache")
	# Andere Strecke, gleicher Schlüssel: ein Treffer liest den Cache, statt neu zu erzeugen.
	var hit := IslandTerrain.cached_generate(_raised(road), "key-a", PATH)
	assert_eq(hit.columns, fresh.columns)
	assert_eq(hit.rows, fresh.rows)
	assert_true(hit.heights == fresh.heights, "Höhen identisch")
	assert_true(hit.road_distance == fresh.road_distance, "Straßenabstand identisch")


func test_changed_key_regenerates() -> void:
	var road := IslandCourse.samples()
	var first := IslandTerrain.cached_generate(road, "key-a", PATH)
	var second := IslandTerrain.cached_generate(_raised(road), "key-b", PATH)
	assert_false(second.heights == first.heights, "anderer Schlüssel → neu erzeugt")
	var p := road[road.size() / 2]
	assert_almost_eq(second.height_at(p.x, p.z), p.y + 50.0, 0.5, "Gelände folgt der neuen Strecke")
	var again := IslandTerrain.cached_generate(road, "key-b", PATH)
	assert_true(again.heights == second.heights, "Cache trägt jetzt den neuen Schlüssel")


func test_corrupt_cache_regenerates() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("kaputt")
	file.close()
	var road := IslandCourse.samples()
	var terrain := IslandTerrain.cached_generate(road, "key-a", PATH)
	var p := road[0]
	assert_almost_eq(terrain.height_at(p.x, p.z), p.y, 0.5, "trotz kaputtem Cache richtiges Gelände")


func test_course_key_depends_on_sources() -> void:
	assert_eq(IslandTerrain.cache_key(["a", "b"]), IslandTerrain.cache_key(["a", "b"]))
	assert_ne(IslandTerrain.cache_key(["a", "b"]), IslandTerrain.cache_key(["a", "c"]), "geänderte Quelle")
	assert_ne(IslandTerrain.cache_key(["ab", "c"]), IslandTerrain.cache_key(["a", "bc"]), "Grenzen zählen")
	assert_false(IslandTerrain.course_cache_key().is_empty(), "Quellen im Projekt lesbar")
	assert_eq(IslandTerrain.cache_key([]), "", "ohne Quellen kein Cache")
	assert_eq(IslandTerrain.cache_key(["a", ""]), "", "Quelle nicht lesbar (Export) → kein Cache")
