## Beute des Arcade-Modus (#49, Spec #27; CONTEXT.md „Beute“): Ausrüstung auf sechs Plätzen in vier Seltenheiten als
## **Daten** und der **Würfel** dafür – reine Logik, mit Seed reproduzierbar (die Balancing-Simulation #55 treibt sie ohne
## Grafik). Verwaltet wird sie im Inventar (Inventory, im Spielstand), gefunden im Arcade-Lauf (ArcadeRun).
##
## Ein Teil: {id, slot, rarity, stats: {<wert>: Zahl}, effect}. `id` vergibt das Inventar (0 = noch nicht abgelegt);
## `effect` ist der Spezialeffekt **legendärer** Teile (#53, `EFFECTS`): der Würfel vergibt ihn nur bei „legendär“, alle
## anderen Teile und ältere legendäre Teile ohne Eintrag behalten `""` und bleiben gültig – ohne Wirkung.
##
## **Ausrüstung ersetzt nie das Treten** (Implementation Decisions #27): Die Werte machen nachsichtiger (breitere
## Zielzone), wirkungsvoller (Fortschritt in der Zone) und lohnender (Punkte, Beute-Glück). Sie wirken als
## Modifikatoren (`modifiers`) auf Bausteine und Belohnung – nie auf Fahrmodell, Rundfahrt oder Training (ADR-0010).
## Eine verbreiterte Zone läuft weiter durch den Wächter des Kadenzbereichs (Encounters.zone_for), und Fortschritt
## entsteht nur mit Kadenz in der Zone: der Faktor vervielfacht ihn, aus null macht er nichts.
##
## Würfel: Platz gleichverteilt; Seltenheit nach Gewicht, ein **Qualitätsfaktor** (≥ 1, z. B. aus Beute-Glück, später
## Stufe #54 und Elite-Gruppe #52) hebt die selteneren (Gewicht × Qualität^Rang); Werte: der Hauptwert des Platzes und
## je Seltenheit weitere, verschiedene Werte, jeder im Bereich des Werts × Faktor der Seltenheit.
class_name Loot
extends RefCounted

## Plätze in Reihenfolge des Inventars: Name, Adjektiv-Endung (Genus/Numerus für „Magischer Helm“) und Hauptwert.
const SLOTS := {
	"rahmen": {"name": "Rahmen", "ending": "er", "stat": "progress_pct"},
	"laufraeder": {"name": "Laufräder", "ending": "e", "stat": "progress_pct"},
	"trikot": {"name": "Trikot", "ending": "es", "stat": "points_pct"},
	"helm": {"name": "Helm", "ending": "er", "stat": "zone_width_rpm"},
	"schuhe": {"name": "Schuhe", "ending": "e", "stat": "zone_width_rpm"},
	"talisman": {"name": "Talisman", "ending": "er", "stat": "luck_pct"},
}
## Seltenheiten vom häufigsten zum seltensten (Diablo-Farbcode): Wortstamm, Farbe, Gewicht beim Würfeln, Zahl der Werte,
## Faktor auf die Werte und Splitter beim Verwerten.
const COMMON := "gewoehnlich"
const MAGIC := "magisch"
const RARE := "selten"
const LEGENDARY := "legendaer"
const RARITIES := {
	COMMON: {"name": "Gewöhnlich", "color": Color(0.86, 0.86, 0.84), "weight": 60.0, "stats": 1, "factor": 1.0,
		"shards": 1},
	MAGIC: {"name": "Magisch", "color": Color(0.36, 0.52, 1.0), "weight": 28.0, "stats": 2, "factor": 1.5, "shards": 3},
	RARE: {"name": "Selten", "color": Color(1.0, 0.86, 0.2), "weight": 10.0, "stats": 3, "factor": 2.2, "shards": 8},
	LEGENDARY: {"name": "Legendär", "color": Color(1.0, 0.55, 0.1), "weight": 2.0, "stats": 4, "factor": 3.0,
		"shards": 20},
}
## Werte: Name, Einheit, Bereich je Wert bei „gewöhnlich“ (ganze Zahlen) und Obergrenze der Summe aller angelegten Teile.
const STATS := {
	"zone_width_rpm": {"name": "Zonenbreite", "unit": "rpm", "min": 1, "max": 2, "cap": 10},
	"progress_pct": {"name": "Fortschritt in der Zone", "unit": "%", "min": 3, "max": 6, "cap": 60},
	"points_pct": {"name": "Punkte", "unit": "%", "min": 5, "max": 10, "cap": 100},
	"luck_pct": {"name": "Beute-Glück", "unit": "%", "min": 5, "max": 10, "cap": 100},
}
## Spezialeffekte legendärer Teile (#53) als **Daten**: Name, Beschreibung und `changes` – Änderungen an Fähigkeiten,
## Mustern und Ausrüstungswerten des Arcade-Laufs (Vokabular und Anwendung: BuildEffects). Wirken nur im Arcade-Lauf
## (ADR-0010), nur auf angelegten legendären Teilen, und ersetzen nie das Treten: sie verändern Wirkung, Dauer und
## Abklingzeit der Fähigkeiten (Abilities.DEFS), die selbst nur mit Kadenz in der Zone Fortschritt bringen.
const EFFECTS := {
	"rueckstoss": {"name": "Rückstoß", "text": "Windböe wirft Gegner zurück: Jagd +15 % Abstand, Durchbruch +10 % Balken",
		"changes": [{"knockback": {"chase_gap": 0.15, "breakthrough_fill": 0.10}}]},
	"tiefer_atem": {"name": "Tiefer Atem", "text": "Schild hält 4 s länger",
		"changes": [{"ability": "schild", "key": "duration_s", "add": 4.0}]},
	"kombo_ernte": {"name": "Kombo-Ernte", "text": "Kombo gibt doppelt so viele Punkte",
		"changes": [{"ability": "kombo", "key": "power", "mul": 2.0}]},
	"im_fluss": {"name": "Im Fluss", "text": "Fokus doppelt so stark und 4 s länger",
		"changes": [{"ability": "fokus", "key": "power", "mul": 2.0}, {"ability": "fokus", "key": "duration_s", "add": 4.0}]},
	"auf_dem_sprung": {"name": "Auf dem Sprung", "text": "Windböe lädt 8 s schneller",
		"changes": [{"ability": "windboe", "key": "cooldown_s", "add": -8.0}]},
}
## Chance auf Beute: nach einer geschafften Herausforderung sicher; nach einer verfehlten FAILED_CHANCE × erreichter
## Fortschritt – knapp verfehlt gibt manchmal etwas, ohne Kadenz in der Zone (Fortschritt 0) nie.
const SUCCEEDED_CHANCE := 1.0
const FAILED_CHANCE := 0.5


## Ein neues Teil (ohne `id`), gewürfelt mit `rng`. `quality` ≥ 1 hebt die Seltenheit (1 = Grundverteilung).
static func roll(rng: RandomNumberGenerator, quality: float = 1.0) -> Dictionary:
	var slot: String = SLOTS.keys()[rng.randi_range(0, SLOTS.size() - 1)]
	var rarity := roll_rarity(rng, quality)
	var level: Dictionary = RARITIES[rarity]
	var names: Array = [SLOTS[slot]["stat"]]
	var others := STATS.keys().filter(func(s): return s != names[0])
	while names.size() < mini(level["stats"], STATS.size()):
		names.append(others.pop_at(rng.randi_range(0, others.size() - 1)))
	var stats := {}
	for stat in names:
		var value := rng.randf_range(STATS[stat]["min"], STATS[stat]["max"]) * float(level["factor"])
		stats[stat] = maxi(roundi(value), 1)
	var effect := ""
	if rarity == LEGENDARY:  # zuletzt gewürfelt: die Würfe aller anderen Teile bleiben, wie sie waren
		effect = EFFECTS.keys()[rng.randi_range(0, EFFECTS.size() - 1)]
	return {"id": 0, "slot": slot, "rarity": rarity, "stats": stats, "effect": effect}


## Seltenheit nach Gewicht; `quality` multipliziert das Gewicht der Seltenheit mit Rang r (0 = gewöhnlich) mit
## quality^r – höhere Qualität, seltenere Funde.
static func roll_rarity(rng: RandomNumberGenerator, quality: float = 1.0) -> String:
	var weights := rarity_weights(quality)
	var pick: float = rng.randf() * weights.values().reduce(func(a, b): return a + b, 0.0)
	for rarity in weights:
		pick -= weights[rarity]
		if pick < 0.0:
			return rarity
	return RARITIES.keys()[-1]


## Gewicht je Seltenheit bei Qualität `quality` (für Würfel und Tests).
static func rarity_weights(quality: float = 1.0) -> Dictionary:
	var result := {}
	var rank := 0
	for rarity in RARITIES:
		result[rarity] = float(RARITIES[rarity]["weight"]) * pow(maxf(quality, 1.0), rank)
		rank += 1
	return result


## Chance auf Beute nach einer Herausforderung: geschafft oder verfehlt mit erreichtem Fortschritt (0..1).
static func drop_chance(succeeded: bool, progress: float) -> float:
	return SUCCEEDED_CHANCE if succeeded else FAILED_CHANCE * clampf(progress, 0.0, 1.0)


## Qualität des Würfels aus den Modifikatoren der angelegten Ausrüstung (Beute-Glück) und einem Grundfaktor `base`
## (Stufe, Elite-Gruppe – später).
static func quality_for(gear: Dictionary, base: float = 1.0) -> float:
	return base * (1.0 + float(gear.get("luck_pct", 0)) / 100.0)


## Name zur Anzeige, z. B. „Magischer Helm“, „Seltene Laufräder“, „Legendäres Trikot“.
static func item_name(item: Dictionary) -> String:
	var slot: Dictionary = SLOTS.get(item.get("slot"), {"name": "?", "ending": "es"})
	var rarity: Dictionary = RARITIES.get(item.get("rarity"), RARITIES[COMMON])
	return "%s%s %s" % [rarity["name"], slot["ending"], slot["name"]]


## Farbe der Seltenheit (Lichtsäule, Schrift, Fahrer).
static func color_of(rarity: String) -> Color:
	return RARITIES.get(rarity, RARITIES[COMMON])["color"]


## Ein Wert als Text, z. B. „+4 rpm Zonenbreite“, „+12 % Punkte“.
static func stat_text(stat: String, value: float) -> String:
	var info: Dictionary = STATS.get(stat, {"name": stat, "unit": ""})
	return ("%+d %s %s" % [roundi(value), info["unit"], info["name"]]).replace("  ", " ")


## Alle Werte eines Teils in Reihenfolge von STATS, z. B. „+4 rpm Zonenbreite · +6 % Punkte“.
static func stats_text(item: Dictionary) -> String:
	var parts := []
	for stat in STATS:
		if item.get("stats", {}).has(stat):
			parts.append(stat_text(stat, item["stats"][stat]))
	return " · ".join(parts)


## Spezialeffekt von `item` (Schlüssel aus `EFFECTS`; "" = keiner): nur legendäre Teile, nur bekannte Effekte – ältere
## legendäre Teile ohne Effekt und Teile mit unbekanntem Eintrag haben keinen.
static func effect_of(item: Dictionary) -> String:
	var effect = item.get("effect", "")
	return effect if item.get("rarity") == LEGENDARY and effect is String and EFFECTS.has(effect) else ""


## Name des Effekts („Rückstoß“), "" ohne Effekt.
static func effect_name(item: Dictionary) -> String:
	var effect := effect_of(item)
	return EFFECTS[effect]["name"] if effect != "" else ""


## Beschreibung des Effekts, "" ohne Effekt.
static func effect_text(item: Dictionary) -> String:
	var effect := effect_of(item)
	return EFFECTS[effect]["text"] if effect != "" else ""


## Ist `item` ein gültiges Teil (bekannter Platz und Seltenheit, nur bekannte Werte als Zahlen)? Für Stände von der
## Platte.
static func valid(item) -> bool:
	if not (item is Dictionary) or not SLOTS.has(item.get("slot")) or not RARITIES.has(item.get("rarity")):
		return false
	if not (item.get("stats") is Dictionary):
		return false
	for stat in item["stats"]:
		var value = item["stats"][stat]
		if not STATS.has(stat) or not (value is float or value is int) or value < 0.0:
			return false
	return true


## Summe der Werte aller `items` je Wert, begrenzt auf die Obergrenze (STATS.cap); jeder Wert ist da (0 = keiner).
static func modifiers(items: Array) -> Dictionary:
	var result := {}
	for stat in STATS:
		result[stat] = 0
	for item in items:
		if not valid(item):
			continue
		for stat in item["stats"]:
			result[stat] += roundi(item["stats"][stat])
	for stat in STATS:
		result[stat] = mini(result[stat], STATS[stat]["cap"])
	return result


## Vergleich des Kandidaten mit dem angelegten Teil desselben Platzes (`current`, {} = keins): je Wert, den eins von
## beiden hat, {stat, candidate, current, delta} in Reihenfolge von STATS.
static func compare(candidate: Dictionary, current: Dictionary) -> Array:
	var rows := []
	var mine: Dictionary = candidate.get("stats", {})
	var worn: Dictionary = current.get("stats", {})
	for stat in STATS:
		if not mine.has(stat) and not worn.has(stat):
			continue
		var a := roundi(mine.get(stat, 0))
		var b := roundi(worn.get(stat, 0))
		rows.append({"stat": stat, "candidate": a, "current": b, "delta": a - b})
	return rows


## Splitter beim Verwerten.
static func shards_for(item: Dictionary) -> int:
	return RARITIES.get(item.get("rarity"), RARITIES[COMMON])["shards"]


## Aussehen am Fahrer (RiderModel.wear): Farben je Material für die angelegten Teile `equipped` (Platz → Teil) in der
## Farbe ihrer Seltenheit – Rahmen, Laufräder (Felgen), Trikot (mit dunklerem Brustband), Helm (mit dunklerem
## Streifen), Schuhe, Talisman (am Sattel, nur sichtbar, wenn angelegt). Plätze ohne Teil fehlen (dort gilt die
## Garderobe).
static func appearance(equipped: Dictionary) -> Dictionary:
	var colors := {}
	for slot in equipped:
		var item: Dictionary = equipped[slot]
		if not valid(item):
			continue
		var color := color_of(item["rarity"])
		match slot:
			"rahmen":
				colors["frame"] = color
			"laufraeder":
				colors["rim"] = color
			"trikot":
				colors["jersey"] = color
				colors["jersey_band"] = color.darkened(0.55)
			"helm":
				colors["helmet"] = color
				colors["helmet_stripe"] = color.darkened(0.55)
			"schuhe":
				colors["shoe"] = color
			"talisman":
				colors["talisman"] = color
	return colors
