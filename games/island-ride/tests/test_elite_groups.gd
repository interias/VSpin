## Elite-Gruppen (#52) als reine Logik: Eigenschaften und Stufen als Daten, jede Eigenschaft verändert, was sie soll, und
## bleibt mit Kadenz allein lösbar (jeder Typ, jede Stufe, Champions und Seltene); Kadenzbereich-Wächter für jede Zone,
## auch die wandernde in jedem Augenblick (Positiv- und Gegenprobe über alle wählbaren Bereiche); Würfeln mit Seed
## (zufällig, reproduzierbar, eigener Würfel – die normalen Würfe bleiben, Bosse werden nie Elite); weiches Scheitern,
## Ausrüstung nur mit Kadenz; Elite-Beute besser als die normaler Herausforderungen.
extends GutTest

const DT := 0.25
const LONG := [{"name": "Lang", "start_m": 0.0, "end_m": 5000.0}]


func _group(base_id: String, rank: String, affixes: Array, tier: int = 1, range_: CadenceRange = CadenceRange.new(),
		gear: Dictionary = {}) -> EliteGroup:
	return Encounters.build(EliteGroups.make(Encounters.find(base_id), rank, affixes), tier, range_, gear) as EliteGroup


## Kadenz, die das Ziel der laufenden Phase trifft: Mitte der Zone, bei einer Schwelle (Durchbruch, Jagd, Sammeln) das
## obere Ende des Bereichs.
func _target(group: EliteGroup) -> float:
	var zone := group.zone()
	return zone.y if group.phase_definition().has("threshold_at") else (zone.x + zone.y) / 2.0


## Spielt die Gruppe mit der Kadenz, die dem Ziel folgt, bis sie zu Ende ist.
func _play(group: EliteGroup, limit_s: float = 900.0) -> void:
	var t := 0.0
	while not group.finished() and t < limit_s:
		group.update(_target(group), DT)
		t += DT


func _feed(block: ChallengeBlock, cadence: float, seconds: float) -> void:
	for i in range(roundi(seconds / DT)):
		block.update(cadence, DT)


## Fährt den Lauf (8 m/s) bis zum Ende der ersten Herausforderung; Kadenz folgt ihrem Ziel. Liefert ihr Ergebnis.
func _finish_first(run: ArcadeRun) -> Dictionary:
	var d := 0.0
	while run.results.is_empty() and d < 5000.0:
		var cadence := 90.0
		if not run.active.is_empty():
			var block: ChallengeBlock = run.active["block"]
			cadence = _target(block) if block is EliteGroup else (block.zone().x + block.zone().y) / 2.0
		d += 8.0 * DT
		run.advance(d, cadence, DT)
	return run.results[0]


func _rank_of(rarity: String) -> int:
	return Loot.RARITIES.keys().find(rarity)


# --- Daten -------------------------------------------------------------------------------------------------------


func test_affixes_and_ranks_are_data() -> void:
	assert_eq(EliteGroups.AFFIXES.values().map(func(a): return a["name"]),
			["Windschnell", "Wankelmütig", "Gegenwind", "Zäh", "Taktwechsel", "Rudelführer"])
	var known := ["key", "mul", "add", "max", "set", "retinue", "tempo"]
	for id in EliteGroups.AFFIXES:
		var affix: Dictionary = EliteGroups.AFFIXES[id]
		assert_false(affix["text"].is_empty(), id)
		for block in affix["changes"]:
			assert_true(block == "*" or EncounterRegistry.TYPES.has(block), "%s: Typ %s" % [id, block])
			for change in affix["changes"][block]:
				for key in change:
					assert_has(known, key, "%s: Änderung %s" % [id, key])
	# Jeder gewürfelte Typ kann bis zu drei Eigenschaften tragen.
	for definition in Encounters.CHALLENGES:
		assert_gte(EliteGroups.affixes_for(definition["block"]).size(), 3, definition["block"])
	assert_eq(EliteGroups.color_of(EliteGroups.CHAMPION), Loot.color_of(Loot.MAGIC), "Champions blau")
	assert_eq(EliteGroups.color_of(EliteGroups.RARE), Loot.color_of(Loot.RARE), "Seltene gelb")
	assert_eq(EliteGroups.RANKS[EliteGroups.CHAMPION]["affixes"], [1, 2])
	assert_eq(EliteGroups.RANKS[EliteGroups.RARE]["affixes"], [2, 3])
	assert_lt(EliteGroups.RANKS[EliteGroups.CHAMPION]["loot_quality"], EliteGroups.RANKS[EliteGroups.RARE]["loot_quality"])
	assert_true(EncounterRegistry.TYPES.has(EliteGroups.ID), "Typ `elite` angemeldet")
	assert_true(EncounterRegistry.TYPES[EliteGroups.ID].CHALLENGES.is_empty(), "nicht im Würfel-Pool")


func test_an_elite_group_is_a_pool_challenge_with_rank_affixes_and_retinue() -> void:
	var base := Encounters.find("jagd_verfolger")
	var champion := EliteGroups.make(base, EliteGroups.CHAMPION, ["windschnell"])
	assert_eq(champion["block"], EliteGroups.ID)
	assert_eq(champion["name"], "Champions: Jagd")
	assert_eq(champion["elite"], {"rank": "champion", "affixes": ["windschnell"], "base": "jagd_verfolger"})
	assert_eq(champion["phases"].size(), 1, "Champions ohne Gefolge")
	assert_eq(champion["points"], 210, "140 × 1,5")
	assert_eq(champion["loot_quality"], 1.5)
	var rare := EliteGroups.make(base, EliteGroups.RARE, ["gegenwind", "zaeh"])
	assert_eq(rare["name"], "Seltene: Jagd")
	assert_eq(rare["phases"].size(), 2, "Seltene mit Gefolge")
	assert_true(rare["phases"][1]["retinue"])
	assert_true(rare["phases"][1].has("threshold_at"), "Gefolge im Zielformat des Anführers (Schwelle)")
	assert_eq(rare["points"], 280 + 40)
	assert_eq(EliteGroups.make(Encounters.find("zone_mitte"), EliteGroups.RARE, ["zaeh"])["phases"][1]["id"],
			"gefolge_zone", "Gefolge einer Zone: Zone halten")
	assert_eq(EliteGroups.affix_names(rare), ["Gegenwind", "Zäh"])
	assert_eq(base, Encounters.find("jagd_verfolger"), "die Daten des Pools bleiben unverändert")
	var group := Encounters.build(rare, 1, CadenceRange.new()) as EliteGroup
	assert_not_null(group)
	assert_eq(group.rank, EliteGroups.RARE)
	assert_eq(group.affixes, ["gegenwind", "zaeh"])
	assert_true(group.phases[0] is Chase and group.phases[1] is ChallengeBlock)
	assert_eq(Encounters.zone_for(rare, 1, CadenceRange.new()), group.phases[0].zone(), "Ankündigung: Ziel des Anführers")


func test_each_affix_changes_what_it_should() -> void:
	var range_ := CadenceRange.new()  # 60–120 rpm, Stufe 1
	var plain := _group("zone_mitte", EliteGroups.CHAMPION, [])
	var plain_zone: ZoneHold = plain.phases[0]
	assert_eq(plain_zone.zone(), Vector2(80, 100))
	# Windschnell: weniger Zeit; der Verfolger holt schneller auf und ist schwerer abzuhängen; engere Takt-Fenster.
	assert_almost_eq(_group("zone_mitte", "champion", ["windschnell"]).phases[0].window_s, 24.0, 0.001)
	assert_almost_eq(_group("durchbruch_bruecke", "champion", ["windschnell"]).phases[0].window_s, 14.4, 0.001)
	var chase: Chase = _group("jagd_verfolger", "champion", ["windschnell"]).phases[0]
	assert_almost_eq(chase.escape_s, 15.0, 0.001)
	assert_almost_eq(chase.catch_s, 9.6, 0.001)
	assert_almost_eq(_group("takt_ruhig", "champion", ["windschnell"]).phases[0].tolerance_s, 0.7, 0.001)
	# Gegenwind: Zone bzw. Schwelle höher.
	assert_eq(_group("zone_mitte", "champion", ["gegenwind"]).zone(), Vector2(86, 106), "Lage 0,5 → 0,6")
	assert_eq(_group("durchbruch_bruecke", "champion", ["gegenwind"]).zone().x, 112.0, "Schwelle 108 → 112")
	assert_eq(_group("jagd_verfolger", "champion", ["gegenwind"]).zone().x, 98.0, "Schwelle 93 → 98")
	assert_eq(_group("sammeln_wiese", "champion", ["gegenwind"]).zone().x, 81.0, "Rampe ab 75 → 81")
	# Zäh: länger halten, mehr Balken, weniger Vorsprung, ein Treffer bzw. ein Objekt mehr.
	assert_almost_eq(_group("zone_mitte", "champion", ["zaeh"]).phases[0].hold_s, 19.5, 0.001)
	assert_almost_eq(_group("durchbruch_bruecke", "champion", ["zaeh"]).phases[0].fill_s, 7.8, 0.001)
	assert_almost_eq(_group("jagd_verfolger", "champion", ["zaeh"]).phases[0].start_gap, 0.3, 0.001)
	assert_eq(_group("takt_ruhig", "champion", ["zaeh"]).phases[0].need, 5)
	assert_eq(_group("sammeln_wiese", "champion", ["zaeh"]).phases[0].need, 6)
	# Taktwechsel: die Takt-Tore in zwei Phasen, die zweite schneller; zusammen gleich viele Tore und Treffer.
	var takt := _group("takt_ruhig", "champion", ["taktwechsel"])
	assert_eq(takt.phase_count(), 2)
	var first: RhythmGates = takt.phases[0]
	var second: RhythmGates = takt.phases[1]
	assert_eq([first.beats, second.beats], [3, 2])
	assert_eq(first.need + second.need, 4)
	assert_almost_eq(first.interval_s, 5.0, 0.001)
	assert_almost_eq(second.interval_s, 3.5, 0.001, "der Takt wird schneller")
	# Rudelführer: ein Gefolge mehr.
	assert_eq(_group("zone_mitte", "champion", ["rudelfuehrer"]).retinue_count(), 1, "Champions mit Gefolge")
	assert_eq(_group("zone_mitte", "selten", ["rudelfuehrer"]).retinue_count(), 2, "Seltene mit zweitem Gefolge")
	# Wankelmütig: die Zone beginnt an ihrem Platz und wandert dann (Ausschlag 0,2 des Bereichs = 12 rpm).
	var fickle := _group("zone_mitte", "champion", ["wankelmuetig"], 1, range_)
	assert_eq(fickle.zone(), Vector2(80, 100), "zu Beginn an ihrem Platz")
	var quarter: float = EliteGroups.WANDER["period_s"] / 4.0
	_feed(fickle, 90.0, quarter)
	assert_eq(fickle.zone(), Vector2(92, 112), "nach einer Viertelschwingung 12 rpm höher")
	_feed(fickle, 102.0, 2.0 * quarter)
	assert_eq(fickle.zone(), Vector2(68, 88), "eine halbe Schwingung später 12 rpm tiefer")
	assert_eq(_group("durchbruch_bruecke", "champion", ["wankelmuetig"]).zone().x, 108.0,
			"keine Wirkung auf eine Schwelle (nicht gewürfelt)")
	assert_false(EliteGroups.affixes_for("breakthrough").has("wankelmuetig"))


# --- Spielbar mit Kadenz allein ------------------------------------------------------------------------------------


func test_every_affix_is_playable_with_cadence_alone() -> void:
	for range_ in [CadenceRange.new(), CadenceRange.new(80.0, 100.0), CadenceRange.new(40.0, 150.0)]:
		for definition in Encounters.CHALLENGES:
			var sets: Array = EliteGroups.affixes_for(definition["block"]).map(func(id): return [id])
			sets.append(EliteGroups.affixes_for(definition["block"]))  # alle zusammen: die schwerste Gruppe
			for affixes in sets:
				for rank in EliteGroups.RANKS:
					for tier in [1, 2, 3]:
						var label := "%s %s %s Stufe %d %s" % [definition["id"], rank, affixes, tier, range_.text()]
						var group := _group(definition["id"], rank, affixes, tier, range_)
						_play(group)
						assert_eq(group.state, ChallengeBlock.SUCCEEDED, "mit Kadenz im Ziel geschafft: " + label)
						# Gegenprobe: ohne Treten nichts – weich verfehlt, kein Fortschritt für die Beute.
						var idle := _group(definition["id"], rank, affixes, tier, range_)
						_feed(idle, 0.0, 400.0)
						assert_eq(idle.state, ChallengeBlock.FAILED, "ohne Kadenz verfehlt: " + label)
						assert_eq(idle.loot_progress(), 0.0, "ohne Kadenz nichts erarbeitet: " + label)


# --- Kadenzbereich-Wächter -----------------------------------------------------------------------------------------


func test_every_elite_zone_stays_in_the_personal_range_at_every_moment() -> void:
	var period: float = EliteGroups.WANDER["period_s"]
	var moments := range(9).map(func(k): return k * period / 8.0)
	var checked := 0
	for lower in CadenceRange.MIN_CHOICES:
		for upper in CadenceRange.MAX_CHOICES:
			var range_ := CadenceRange.new(lower, upper)
			for definition in Encounters.CHALLENGES:
				var sets: Array = EliteGroups.affixes_for(definition["block"]).map(func(id): return [id])
				sets.append(EliteGroups.affixes_for(definition["block"]))
				for affixes in sets:
					for rank in EliteGroups.RANKS:
						for tier in [1, 2, 3]:
							for gear in [{}, {"zone_width_rpm": 10}]:
								var group := _group(definition["id"], rank, affixes, tier, range_, gear)
								for i in range(group.phase_count()):
									var zone: Vector2 = group.phases[i].zone()
									assert_true(range_.contains_zone(zone.x, zone.y), "%s %s %s %s Stufe %d: %s" % [
											definition["id"], rank, affixes, range_.text(), tier, zone])
									if group.definitions[i].has("wander"):
										for at in moments:
											zone = group.zone_path.call(i, at)
											checked += 1
											assert_true(range_.contains_zone(zone.x, zone.y), "wandernd %s %s %.1f s: %s" % [
													definition["id"], range_.text(), at, zone])
	assert_gt(checked, 1000, "wandernde Zonen in jedem Augenblick geprüft")


func test_the_guard_catches_what_the_affixes_would_push_out() -> void:
	# Gegenprobe: Gegenwind und Wankelmütig schieben die Zone von Zone halten zügig (0,62 + 0,1 + 0,2) über 120 rpm –
	# ohne Wächter läge sie bei 105–125. Der Wächter (zone_for → limit_zone) rückt sie mit gleicher Breite hinein.
	var range_ := CadenceRange.new()
	var quarter: float = EliteGroups.WANDER["period_s"] / 4.0
	var group := _group("zone_zuegig", "champion", ["wankelmuetig", "gegenwind"], 1, range_)
	var leader: Dictionary = group.definitions[0]
	var center := roundf(range_.at(float(leader["zone_at"]) + Encounters.wander_shift(leader, quarter)))
	assert_eq(Vector2(center - 10.0, center + 10.0), Vector2(105, 125), "ohne Wächter außerhalb")
	assert_eq(group.zone_path.call(0, quarter), Vector2(100, 120), "mit Wächter hineingeschoben, Breite bleibt")
	var low := _group("zone_ruhig", "champion", ["wankelmuetig"], 1, range_)
	var bottom: Dictionary = low.definitions[0]
	center = roundf(range_.at(float(bottom["zone_at"]) + Encounters.wander_shift(bottom, 3.0 * quarter)))
	assert_lt(center - 10.0, 60.0, "ohne Wächter unter dem Bereich")
	assert_eq(low.zone_path.call(0, 3.0 * quarter), Vector2(60, 80))
	# Im Lauf des Bausteins: die Zone, nach der er wertet, liegt in jedem Schritt im Bereich und erreicht dessen Ende.
	var seen := {}
	while not group.finished():
		group.update(_target(group), DT)
		var zone := group.zone()
		assert_true(range_.contains_zone(zone.x, zone.y), "Schritt: %s" % zone)
		seen[zone] = true
	assert_gt(seen.size(), 5, "die Zone wandert")
	assert_true(seen.has(Vector2(100, 120)), "bis an den Rand des Bereichs, nicht darüber")
	# Ein enger Bereich (so breit wie die Zone): nichts zu wandern, die Zone ist der ganze Bereich.
	var narrow := CadenceRange.new(80.0, 100.0)
	var tight := _group("zone_mitte", "champion", ["wankelmuetig", "gegenwind"], 1, narrow)
	for at in [0.0, quarter, 3.0 * quarter]:
		assert_eq(tight.zone_path.call(0, at), Vector2(80, 100))


# --- Würfeln ---------------------------------------------------------------------------------------------------------


func test_elite_groups_appear_at_random_and_reproducibly() -> void:
	var total := 0
	var elites := 0
	var ranks := {}
	var affixes := {}
	for seed_value in range(1, 200):
		var run := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, seed_value)
		for entry in run.planned:
			total += 1
			var definition: Dictionary = entry["definition"]
			if definition["block"] != EliteGroups.ID:
				continue
			elites += 1
			var rank := EliteGroups.rank_of(definition)
			ranks[rank] = true
			var span: Array = EliteGroups.RANKS[rank]["affixes"]
			assert_between(definition["elite"]["affixes"].size(), span[0], span[1], definition["id"])
			assert_true(definition["name"].begins_with(EliteGroups.RANKS[rank]["name"] + ": "), "sichtbarer Name")
			for id in definition["elite"]["affixes"]:
				affixes[id] = true
				assert_has(EliteGroups.affixes_for(definition["phases"][0]["block"]), id, "passt zum Typ")
	assert_between(float(elites) / total, 0.08, 0.24, "Chance %.2f je Herausforderung" % EliteGroups.CHANCE)
	assert_eq(ranks.size(), 2, "Champions und Seltene")
	assert_eq(affixes.size(), EliteGroups.AFFIXES.size(), "jede Eigenschaft kommt vor")
	var a := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, 17)
	var b := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, 17)
	assert_eq(a.planned.map(func(e): return e["definition"]), b.planned.map(func(e): return e["definition"]),
			"gleicher Seed → gleiche Elite-Gruppen")


func test_the_normal_rolls_stay_the_same() -> void:
	var sections := ArcadeRun.sections_from_stations(IslandCourse.stations(), IslandCourse.curve().get_baked_length())
	var length := IslandCourse.curve().get_baked_length()
	var base_of := func(run: ArcadeRun) -> Array:
		return run.planned.map(func(e): return [e["definition"].get("elite", {}).get("base", e["definition"]["id"]),
				e["at_m"], e["section"], e["lap"]])
	var any_elite := false
	for seed_value in [1, 2, 3, 7, 11]:
		var with_elites := ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, seed_value)
		var without := ArcadeRun.new(1, CadenceRange.new(), sections, length, 0.0, seed_value, Encounters.CHALLENGES,
				null, 0.0)
		assert_eq(base_of.call(with_elites), base_of.call(without),
				"Seed %d: gleiche Herausforderungen am gleichen Ort" % seed_value)
		assert_false(without.planned.any(func(e): return e["definition"]["block"] == EliteGroups.ID), "Chance 0: keine")
		any_elite = any_elite or with_elites.planned.any(func(e): return e["definition"]["block"] == EliteGroups.ID)
	assert_true(any_elite, "im Standard-Pool kommen Elite-Gruppen")
	# Ein eigener Pool (erzwungene Herausforderung) bekommt keine – außer mit eigener Chance.
	var pool := [Encounters.find("zone_mitte")]
	for seed_value in range(1, 40):
		var forced := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, seed_value, pool)
		assert_false(forced.planned.any(func(e): return e["definition"]["block"] == EliteGroups.ID))
	var all := ArcadeRun.new(1, CadenceRange.new(), [], 1000.0, 0.0, 1, pool, [], 1.0)
	assert_true(all.planned.all(func(e): return e["definition"]["block"] == EliteGroups.ID), "Chance 1: alle")


func test_bosses_never_become_elite() -> void:
	var bosses := preload("res://src/challenges/boss_challenges.gd")
	var rng := RandomNumberGenerator.new()
	for boss in bosses.FIXED:
		assert_false(EliteGroups.eligible(boss), boss["id"])
		assert_eq(EliteGroups.roll(rng, boss, 1.0), boss, "%s bleibt ein Boss" % boss["id"])
	var group := EliteGroups.make(Encounters.find("zone_mitte"), "selten", ["zaeh"])
	assert_eq(EliteGroups.roll(rng, group, 1.0), group, "keine Elite-Gruppe aus einer Elite-Gruppe")
	var sections := ArcadeRun.sections_from_stations(IslandCourse.stations(), IslandCourse.curve().get_baked_length())
	var run := ArcadeRun.new(1, CadenceRange.new(), sections, IslandCourse.curve().get_baked_length(), 0.0, 3,
			Encounters.CHALLENGES, null, 1.0)
	for entry in run.planned:
		var places: Array = bosses.FIXED.map(func(b): return b["section"])
		var expected: String = bosses.ID if places.has(entry["section"]) else EliteGroups.ID
		assert_eq(entry["definition"]["block"], expected, "%s Runde %d" % [entry["section"], entry["lap"]])


# --- Im Lauf: weich, Ausrüstung, Beute -----------------------------------------------------------------------------


func test_the_group_runs_its_phases_and_fails_softly() -> void:
	var rare := EliteGroups.make(Encounters.find("zone_mitte"), EliteGroups.RARE, ["zaeh"])
	var run := ArcadeRun.new(1, CadenceRange.new(), LONG, 5000.0, 0.0, 2, [rare], [])
	var d := 0.0
	while run.active.is_empty():
		d += 2.0
		run.advance(d, 90.0, DT)
	var group: EliteGroup = run.active["block"]
	assert_false(group.in_retinue())
	while not group.in_retinue():
		d += 2.0
		run.advance(d, 90.0, DT)
	assert_eq(group.retinue_number(), 1, "nach dem Anführer das Gefolge")
	var before := [group.elapsed_s, group.progress()]
	run.advance(d, 90.0, 0.0)
	assert_eq([group.elapsed_s, group.progress()], before, "Pause: nichts läuft weiter")
	while run.results.is_empty():
		d += 2.0
		run.advance(d, 0.0, DT)  # das Gefolge ohne Treten
	assert_false(run.results[0]["succeeded"], "Gefolge entkommen: die Gruppe ist verfehlt")
	assert_eq(run.points, 0, "weich: keine Punkte")
	assert_eq(run.results[0]["name"], "Seltene: Zone halten")
	assert_false(run.planned.is_empty(), "die Fahrt geht weiter")
	var champion := ArcadeRun.new(2, CadenceRange.new(), LONG, 5000.0, 0.0, 2,
			[EliteGroups.make(Encounters.find("zone_mitte"), EliteGroups.CHAMPION, ["gegenwind"])], [])
	assert_true(_finish_first(champion)["succeeded"])
	assert_eq(champion.points, 300, "100 × 1,5 × Stufe 2")


func test_gear_and_abilities_only_help_with_cadence() -> void:
	var range_ := CadenceRange.new()
	var gear := {"progress_pct": 50}
	var geared := _group("durchbruch_bruecke", "selten", ["zaeh", "gegenwind"], 1, range_, gear)
	var bare := _group("durchbruch_bruecke", "selten", ["zaeh", "gegenwind"], 1, range_)
	_feed(geared, 0.0, 4.0)
	_feed(bare, 0.0, 4.0)
	assert_eq(geared.progress(), 0.0, "ohne Kadenz auch mit Ausrüstung nichts")
	_feed(geared, 115.0, 2.0)
	_feed(bare, 115.0, 2.0)
	assert_almost_eq(geared.current_phase().progress(), 1.5 * bare.current_phase().progress(), 0.001,
			"mit Kadenz über der Schwelle × 1,5")
	assert_eq(geared.zone(), bare.zone(), "die Ausrüstung ändert nur, was die Kadenz erarbeitet (Breite 0)")


func test_elite_loot_is_better_than_normal_loot() -> void:
	# Gleicher Seed, gleiche Würfel: dieselbe Herausforderung normal und als Elite-Gruppe geschafft – der Fund der
	# Elite-Gruppe ist nie gewöhnlicher, oft seltener (Qualität 1 / 1,5 / 2 auf denselben Würfelwurf).
	var plain := Encounters.find("zone_mitte")
	var mean := {"normal": 0.0, EliteGroups.CHAMPION: 0.0, EliteGroups.RARE: 0.0}
	var better := {EliteGroups.CHAMPION: 0, EliteGroups.RARE: 0}
	var seeds := 240
	for seed_value in range(1, seeds + 1):
		var normal := _finish_first(ArcadeRun.new(1, CadenceRange.new(), LONG, 5000.0, 0.0, seed_value, [plain], []))
		assert_true(normal["succeeded"])
		assert_false(normal["loot"].is_empty(), "geschafft: sicher Beute")
		mean["normal"] += _rank_of(normal["loot"]["rarity"])
		for rank in [EliteGroups.CHAMPION, EliteGroups.RARE]:
			var elite := _finish_first(ArcadeRun.new(1, CadenceRange.new(), LONG, 5000.0, 0.0, seed_value,
					[EliteGroups.make(plain, rank, [])], []))
			assert_true(elite["succeeded"])
			assert_eq(elite["loot"]["slot"], normal["loot"]["slot"], "derselbe Würfelwurf")
			assert_gte(_rank_of(elite["loot"]["rarity"]), _rank_of(normal["loot"]["rarity"]), "Seed %d %s" % [seed_value, rank])
			if _rank_of(elite["loot"]["rarity"]) > _rank_of(normal["loot"]["rarity"]):
				better[rank] += 1
			mean[rank] += _rank_of(elite["loot"]["rarity"])
	assert_gt(better[EliteGroups.CHAMPION], 0, "Champions: manchmal seltener")
	assert_gt(better[EliteGroups.RARE], better[EliteGroups.CHAMPION], "Seltene: öfter seltener als Champions")
	assert_lt(mean["normal"], mean[EliteGroups.CHAMPION], "im Mittel: normal < Champions")
	assert_lt(mean[EliteGroups.CHAMPION], mean[EliteGroups.RARE], "Champions < Seltene")
