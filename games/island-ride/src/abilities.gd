## Fähigkeiten (#50, Spec #27): ein erkanntes Kadenzmuster (CadencePatterns) löst eine Fähigkeit aus, sofern sie bereit ist
## (Abklingzeit abgelaufen) und **eine Herausforderung läuft** – davor und danach passiert nichts, die Fähigkeit bleibt bereit.
## Reine Logik (nur Arcade, ADR-0010): `step` je Fahrschritt nach `ArcadeRun.advance`. Die Fähigkeiten verstärken oder
## schützen, ersetzen aber nie das Treten: jede Wirkung hängt an Fortschritt, der **mit Kadenz in der Zone** entsteht, oder
## nimmt einen Verlust zurück – eine Zielzone erzeugt keine, der Kadenzbereich bleibt unberührt.
##
##   Windböe  (Antritt)     „Rückenwind“: Faktor auf den Fortschritt mit Kadenz in der Zone, kurz und stark
##                          (`progress_factor` des laufenden Bausteins + `power`, 2,5 s)
##   Fokus    (Gleichmaß)   „Konzentration“: derselbe Faktor, schwächer, aber lang (8 s)
##   Schild   (Innehalten)  „Durchatmen“: solange es hält, wird jeder Schritt zurückgenommen, der den Fortschritt senkt
##                          (Durchbruch-Schwund, Jagd-Einholen); Zeit und Gewinne laufen weiter. Das Tempo kostet das
##                          Innehalten selbst – zwei Sekunden ohne Treten, das Fahrmodell läuft aus (`RideModel` bleibt
##                          unberührt); der Schritt, in dem ein Baustein schon endet, lässt sich nicht mehr zurücknehmen
##   Kombo    (Rhythmus)    Punkte sofort: `power` × (1 + Zahl der anderen Fähigkeiten, die in den letzten `chain_s`
##                          ausgelöst wurden) – eine Kette aus Mustern zahlt sich aus
##
## Alle Werte sind Daten (`DEFS`) und je Lauf als Kopie in `defs` veränderbar (Talente und legendäre Beute, #53: Wirkung
## `power`, Abklingzeit `cooldown_s`, Dauer `duration_s`). Fortschrittsfaktoren legt `step` jeden Schritt als Summe auf den
## Faktor, den der Baustein beim Start hatte (Ausrüstung #49) – sie sind nach Ablauf wieder weg.
class_name Abilities
extends RefCounted

## Wirkungsarten (`effect`).
const EFFECT_PROGRESS := "progress"
const EFFECT_SHIELD := "shield"
const EFFECT_POINTS := "points"

## Je Fähigkeit: `pattern` (Auslöser), `name`, `effect`, `power` (Stärke, je nach Wirkung), `duration_s` (Wirkdauer),
## `cooldown_s` (Abklingzeit ab Auslösung), `chain_s` (nur Kombo), `text` (Kurzbeschreibung).
const DEFS := {
	"windboe": {"pattern": CadencePatterns.ANTRITT, "name": "Windböe", "effect": EFFECT_PROGRESS, "power": 2.0,
		"duration_s": 2.5, "cooldown_s": 18.0, "text": "Rückenwind: Fortschritt in der Zone ×3"},
	"fokus": {"pattern": CadencePatterns.GLEICHMASS, "name": "Fokus", "effect": EFFECT_PROGRESS, "power": 0.5,
		"duration_s": 8.0, "cooldown_s": 25.0, "text": "Konzentration: Fortschritt in der Zone ×1,5"},
	"schild": {"pattern": CadencePatterns.INNEHALTEN, "name": "Schild", "effect": EFFECT_SHIELD, "power": 1.0,
		"duration_s": 6.0, "cooldown_s": 30.0, "text": "Durchatmen: kein Fortschrittsverlust"},
	"kombo": {"pattern": CadencePatterns.RHYTHMUS, "name": "Kombo", "effect": EFFECT_POINTS, "power": 30.0,
		"duration_s": 0.0, "cooldown_s": 15.0, "chain_s": 20.0, "text": "Punkte, mehr nach anderen Fähigkeiten"},
}
## Reihenfolge der Anzeige.
const IDS := ["windboe", "fokus", "schild", "kombo"]

## Die Fähigkeiten dieses Laufs (Kopie von `DEFS`, veränderbar).
var defs := {}
## Wie oft jede ausgelöst wurde, und die Punkte der Kombos.
var counts := {}
var combo_points := 0

var _cooldown := {}
var _active := {}
var _clock := 0.0
## Auslösungen für die Kette: [{id, t}].
var _recent: Array = []
var _block: ChallengeBlock = null
var _base_factor := 1.0
var _snapshot := {}


func _init() -> void:
	defs = DEFS.duplicate(true)
	for id in IDS:
		counts[id] = 0
		_cooldown[id] = 0.0
		_active[id] = 0.0


## Fähigkeit zum Muster `pattern` ("" = keine).
func ability_for(pattern: String) -> String:
	for id in IDS:
		if defs[id]["pattern"] == pattern:
			return id
	return ""


## Bereit: Abklingzeit abgelaufen.
func is_ready(id: String) -> bool:
	return _cooldown[id] <= 0.0


## Wirkt gerade (Wirkdauer läuft).
func is_active(id: String) -> bool:
	return _active[id] > 0.0


## Verbleibende Abklingzeit (s) und Wirkdauer (s).
func cooldown_left_s(id: String) -> float:
	return maxf(_cooldown[id], 0.0)


func active_left_s(id: String) -> float:
	return maxf(_active[id], 0.0)


## Zustand für die Anzeige: "ready", "active" oder "cooldown".
func state_of(id: String) -> String:
	if is_active(id):
		return "active"
	return "ready" if is_ready(id) else "cooldown"


## Auf den Anfang eines Laufs zurück.
func reset() -> void:
	defs = DEFS.duplicate(true)
	combo_points = 0
	_clock = 0.0
	_recent.clear()
	_block = null
	_snapshot = {}
	for id in IDS:
		counts[id] = 0
		_cooldown[id] = 0.0
		_active[id] = 0.0


## Ein Fahrschritt von `delta_s` nach `run.advance`: Zeiten laufen, ein Schritt unter Schild, der den Fortschritt senkte,
## wird zurückgenommen, die erkannten `patterns` lösen bereite Fähigkeiten aus (nur mit laufender Herausforderung), die
## Faktoren liegen für den nächsten Schritt auf dem Baustein. Liefert die ausgelösten Fähigkeiten (ids).
func step(run: ArcadeRun, patterns: Array, delta_s: float) -> Array:
	var block: ChallengeBlock = run.active["block"] if not run.active.is_empty() else null
	if block != _block:  # neue Herausforderung (oder keine): ihr Ausgangsfaktor gilt
		_block = block
		_snapshot = {}
		_base_factor = block.progress_factor if block != null else 1.0
	if block != null and not _snapshot.is_empty():
		_undo_loss(block)
	_clock += delta_s
	for id in IDS:
		_cooldown[id] -= delta_s
		_active[id] -= delta_s
	var triggered := []
	if block != null:
		for pattern in patterns:
			var id := ability_for(pattern)
			if id != "" and is_ready(id):
				_trigger(id, run)
				triggered.append(id)
	_snapshot = _take(block) if block != null and _shield_active() else {}
	if block != null:
		block.progress_factor = _base_factor + _factor_bonus()
	return triggered


func _shield_active() -> bool:
	for id in IDS:
		if defs[id]["effect"] == EFFECT_SHIELD and is_active(id):
			return true
	return false


func _factor_bonus() -> float:
	var bonus := 0.0
	for id in IDS:
		if defs[id]["effect"] == EFFECT_PROGRESS and is_active(id):
			bonus += float(defs[id]["power"])
	return bonus


func _trigger(id: String, run: ArcadeRun) -> void:
	var def: Dictionary = defs[id]
	counts[id] += 1
	_cooldown[id] = float(def["cooldown_s"])
	_active[id] = float(def["duration_s"])
	if def["effect"] == EFFECT_POINTS:
		var chain := _recent.filter(func(e): return e["id"] != id and _clock - e["t"] <= float(def.get("chain_s", 0.0))).size()
		var gained := roundi(float(def["power"]) * (1 + chain))
		run.points += gained
		combo_points += gained
	_recent.append({"id": id, "t": _clock})
	_recent = _recent.filter(func(e): return _clock - e["t"] <= 60.0)


## Zustand des Bausteins merken, um einen Schritt unter Schild zurücknehmen zu können (alle Skript-Variablen).
func _take(block: ChallengeBlock) -> Dictionary:
	var values := {}
	for property in block.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = block.get(property["name"])
			values[property["name"]] = value.duplicate() if value is Array or value is Dictionary else value
	return {"values": values, "progress": block.progress()}


## Hat der letzte Schritt den Fortschritt gesenkt, kehrt der Baustein auf den gemerkten Zustand zurück; die Zeit (und der
## Faktor, den `step` setzt) laufen weiter.
func _undo_loss(block: ChallengeBlock) -> void:
	if block.progress() >= float(_snapshot["progress"]) - 1e-9:
		return
	var elapsed := block.elapsed_s
	var values: Dictionary = _snapshot["values"]
	for key in values:
		var value = values[key]
		block.set(key, value.duplicate() if value is Array or value is Dictionary else value)
	block.elapsed_s = elapsed
