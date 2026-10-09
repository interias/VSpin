## Bosse des Arcade (#51, Spec #27 Story 11) als Daten: Sagengestalten der Insel an festen Orten des Rundkurses, jede eine
## Folge von Phasen aus vorhandenen Bausteinen (Baustein BossFight, src/boss_fight.gd). Eintrag in der Liste
## `EncounterRegistry.TYPES`; Format der Phasen wie jede Herausforderung (Kopf von `encounters.gd`), dazu je Boss:
##   section       Abschnitt (Station des Rundkurses, `Track.ride_stations`), in dem er jede Runde wartet
##   phases        Phasen in Kampfreihenfolge – `Encounters.build` baut jede (Wächter, Stufe, Ausrüstung)
##   points        Punkte für den Sieg (× Punktefaktor der Stufe, wie jede Herausforderung)
##   loot_quality  Faktor auf die Grundqualität der Beute (ArcadeRun.loot_quality) – Boss-Beute ist seltener
##   boss          true: im Ergebnis und in der Zusammenfassung als Boss geführt
## Bosse werden **nicht gewürfelt** (`CHALLENGES` leer): `ArcadeRun` plant `FIXED` je Runde in ihrem Abschnitt ein, statt
## dort zu würfeln. Die Lage der Zone (`zone_at`) und der Schwelle (`threshold_at`) ist wie überall relativ zum
## persönlichen Kadenzbereich; Werte unten für Stufe 1 und 60–120 rpm.
extends RefCounted

const ID := "boss"
const CHALLENGES := []
const FIXED := [
	# Tramuntana: der Nordwind als Sturmgeist auf der Küstenstraße – Böen von vorn, die Zone gegen den Wind halten.
	{"id": "tramuntana", "block": ID, "boss": true, "name": "Tramuntana", "section": "Küstenstraße", "points": 400,
		"loot_quality": 2.0, "phases": [
			# 80–100 rpm 10 s in 20 s
			{"id": "tramuntana_gegenwind", "block": "zone_hold", "name": "Gegenwind", "zone_at": 0.5, "hold_s": 10.0,
				"window_s": 20.0},
			# ab 105 rpm, Balken in 5 s, Fenster 15 s
			{"id": "tramuntana_boee", "block": "breakthrough", "name": "Böe", "threshold_at": 0.75, "fill_s": 5.0,
				"window_s": 15.0, "decay": 0.5},
			# 86–106 rpm 12 s in 24 s
			{"id": "tramuntana_sturmfront", "block": "zone_hold", "name": "Sturmfront", "zone_at": 0.6, "hold_s": 12.0,
				"window_s": 24.0},
		]},
	# Drac de na Coca: der Drache aus Palmas Sage in den Serpentinen – der große Kampf, vier Phasen.
	{"id": "drac", "block": ID, "boss": true, "name": "Drac de na Coca", "section": "Serpentinen", "points": 600,
		"loot_quality": 2.5, "phases": [
			# 77–97 rpm 12 s in 24 s
			{"id": "drac_feueratem", "block": "zone_hold", "name": "Feueratem", "zone_at": 0.45, "hold_s": 12.0,
				"window_s": 24.0},
			# ab 108 rpm, Balken in 6 s, Fenster 18 s
			{"id": "drac_fluegelschlag", "block": "breakthrough", "name": "Flügelschlag", "threshold_at": 0.8,
				"fill_s": 6.0, "window_s": 18.0, "decay": 0.5},
			# 86–106 rpm 12 s in 24 s
			{"id": "drac_schuppenpanzer", "block": "zone_hold", "name": "Schuppenpanzer", "zone_at": 0.6, "hold_s": 12.0,
				"window_s": 24.0},
			# ab 111 rpm, Balken in 5 s, Fenster 16 s
			{"id": "drac_ansturm", "block": "breakthrough", "name": "Letzter Ansturm", "threshold_at": 0.85,
				"fill_s": 5.0, "window_s": 16.0, "decay": 0.5},
		]},
	# Dimonis: die Teufel der Dorffeste im Bergdorf – eine Jagd durch die Gassen, sie laufen voraus und wollen entwischen.
	{"id": "dimonis", "block": ID, "boss": true, "name": "Dimonis", "section": "Bergdorf", "points": 450,
		"loot_quality": 2.0, "phases": [
			# ab 93 rpm: in 10 s eingeholt, unter der Schwelle in 12 s entwischt, Fenster 25 s, Vorsprung 0,4
			{"id": "dimonis_gassen", "block": "chase", "name": "Durch die Gassen", "threshold_at": 0.55, "escape_s": 10.0,
				"catch_s": 12.0, "window_s": 25.0, "start_gap": 0.4},
			# ab 105 rpm, Balken in 5 s, Fenster 15 s
			{"id": "dimonis_dorfplatz", "block": "breakthrough", "name": "Über den Dorfplatz", "threshold_at": 0.75,
				"fill_s": 5.0, "window_s": 15.0, "decay": 0.5},
			# ab 99 rpm: in 8 s eingeholt, in 10 s entwischt, Fenster 22 s, Vorsprung 0,35
			{"id": "dimonis_hinaus", "block": "chase", "name": "Hinaus aus dem Dorf", "threshold_at": 0.65, "escape_s": 8.0,
				"catch_s": 10.0, "window_s": 22.0, "start_gap": 0.35},
		]},
]


## Boss `id` aus `FIXED` ({} = unbekannt).
static func find(id: String) -> Dictionary:
	for definition in FIXED:
		if definition["id"] == id:
			return definition
	return {}


## Ein Boss braucht Phasen: `Encounters.build` ruft für Definitionen mit `phases` `build_phases` auf. Ohne Phasen kein Baustein.
static func build(definition: Dictionary, _level: Dictionary, _zone: Vector2) -> ChallengeBlock:
	push_warning("Boss %s ohne Phasen" % definition.get("id"))
	return null


## Bosskampf aus den schon gebauten Phasen `phases` (Encounters.build: Wächter, Stufe, Ausrüstung) – null, wenn eine Phase
## einen unbekannten Baustein hat. Nur über `Encounters.build` aufrufen.
static func build_phases(definition: Dictionary, phases: Array) -> ChallengeBlock:
	if phases.is_empty() or phases.has(null):
		return null
	return BossFight.new(definition["id"], definition["name"], phases, definition["phases"])
