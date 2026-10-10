## Bühne des Arcade-Laufs (#63): alles Szenische des Arcade, das vorher in der Hauptszene (`scenes/main.gd`) stand – Lauf
## starten und beenden, HUD-Anbindung, Start- und Zieltor, Requisiten der Bausteine, Lichtsäule und Popups der Beute,
## Einblendungen, Zusammenfassung, Ausrüstung am Fahrer. Der Knoten ist Kind der Hauptszene und lebt so lange wie sie;
## er hält den reinen Lauf (`run`: ArcadeRun, RefCounted, null = kein Arcade). Die Hauptszene behält nur den Einhängepunkt:
## `begin` bei `start_ride`, `advance` je Fahrschritt, `update_view` je Anzeigeschritt, `save` beim Speichern der Fahrt,
## `result_text` für das Ergebnis. Reine Verschiebung: kein neues Verhalten, Rundfahrt und Training sehen die Bühne nie
## (ADR-0010); alles hier ist Anzeige oder Aufruf der reinen Logik.
##
## === Schnittstelle für neue Arcade-Bausteine (#50 Kadenzmuster/Fähigkeiten, #48 Takt-Tore/Sammeln, #51 Bosse,
## === #52 Elite-Gruppen, #53 Talente, #54 Stufen) – jedes Paket fügt eigene Dateien hinzu und höchstens eine Zeile in
## === eine Liste; `main.gd` bleibt unberührt ===
##
## (a) Baustein und Herausforderungen anmelden: Baustein `src/<name>.gd` (extends ChallengeBlock), Daten und `build` in
##     `src/challenges/<name>_challenges.gd`, eine Zeile in `EncounterRegistry.TYPES` (Anleitung im Kopf von
##     `src/encounter_registry.gd`). Zielzonen laufen weiter durch `Encounters.zone_for` und den Wächter (limit_zone).
## (b) Darstellung (Prop) je Bausteintyp: `src/<name>_prop.gd` (extends ArcadeProp, Anleitung im Kopf von
##     `src/arcade_prop.gd`) und eine Zeile in `PROPS` unten (Schlüssel = `block`-Id der Herausforderungen). Bausteine
##     ohne Eintrag brauchen keine: sie zeigen das Zieltor wie Zone halten.
## (c) Zeilen an die Zusammenfassung hängen: `stage.summary_providers.append(func(run: ArcadeRun) -> Array: …)`; jede
##     zurückgegebene Zeile (String) steht unter den Zeilen von `ArcadeRun.summary_lines()` (Reihenfolge der Anmeldung).
##     Eigene Funde/Bosse stehen im Lauf selbst: `ArcadeRun.summary_lines()` hängt Beute heute selbst an.
## (d) Auf Ereignisse reagieren (Signale dieser Stage, `connect` von außen oder aus einem Prop):
##       challenge_started(entry)       Herausforderung beginnt (`entry` wie `ArcadeRun.active`: definition, block, at_m, …)
##       challenge_ended(result)        beendet (`result` wie `ArcadeRun.results[i]`: id, name, succeeded, points, progress, loot)
##       loot_found(item, result)       Beute ist gefallen (Teil ohne id), unmittelbar nach `challenge_ended`
##       run_finished(run)              Fahrt gespeichert (Fahrtende, Beute im Inventar); `new_best` gilt dann
##     Einblendung und Popups der Stage (celebrate, +Punkte, Fund, Lichtsäule) laufen davor.
## (e) Werte von Ausrüstung, Talenten und Stufe einspeisen: `begin` legt den Lauf an und setzt `run.gear` aus
##     `Inventory.modifiers(save_game)` (die einzige Stelle, an der Ausrüstung in einen Lauf kommt, ADR-0010). Danach
##     läuft jede Funktion in `run_hooks` mit `(run: ArcadeRun, save_game: SaveGame)` – dort setzen #53/#54 weitere
##     Modifikatoren in `run.gear` (additiv, Schlüssel wie `Loot.STATS`) und `run.loot_quality` (Grundqualität der
##     Beute, #54/#52) und stellen Fähigkeiten (#50) bereit. Hooks gelten nur im Arcade (`begin` ruft sie nur dann).
##     Kadenz je Schritt: `bus` (BusClient, von der Hauptszene gesetzt) liefert `bus.cadence` (geglättet, gilt für Logik und
##     Anzeige) und `bus.cadence_raw` (ungeglättet, für Kadenzmuster, #50); `advance(ride_m, delta_s)` ist der Schritt,
##     `stepped(ride_m, cadence, cadence_raw, delta_s)` meldet ihn nach `ArcadeRun.advance` – daran hängen sich Muster
##     und Fähigkeiten, ihre Anzeige läuft über `hud` (RideHud) in einem `update_view`-Aufruf oder eigenen Signalhandler.
##     Pausen: die Hauptszene ruft `advance` nicht auf; kein Baustein läuft dann weiter.
## (f) Hooks, Zusammenfassungszeilen und Signalverbindungen **anmelden**: eine Erweiterung ist ein Skript `extends
##     RefCounted` mit `func attach(stage: ArcadeStage) -> void`, eine Zeile in `EXTENSIONS` unten
##     (`preload("res://src/<name>_arcade.gd"),`). `setup` legt sie einmal an und ruft `attach` – dort hängt sie ihre
##     `run_hooks`, `summary_providers` und Signalverbindungen an und baut, was sie sonst braucht (z. B. ein Control unter
##     `stage.hud`); `stage.bus` steht beim `attach` noch nicht, die Handler lesen ihn. Die Hauptszene weiß davon nichts.
##
## Tests und Prüfhilfen erreichen die Bühne über die Weiterleitungen der Hauptszene (`arcade`, `arcade_seed`, `arcade_pool`,
## `arcade_start_gate`, `arcade_finish_gate`, `arcade_gate_placement`, `arcade_bridge`, `arcade_pursuer`, `loot_beam`);
## neue Tests greifen direkt auf `game.arcade_stage` zu.
class_name ArcadeStage
extends Node

## Ein Anzeigeobjekt je Bausteintyp (Schlüssel = `block` der Herausforderung), eine Zeile je Typ. Die Reihenfolge ist die
## Reihenfolge der Kinder unter `Track` (und der Aufrufe).
const PROPS := {
	"breakthrough": preload("res://src/breakthrough_prop.gd"),
	"chase": preload("res://src/chase_prop.gd"),
	"rhythm_gates": preload("res://src/rhythm_gates_prop.gd"),
	"collect": preload("res://src/collect_prop.gd"),
	"boss": preload("res://src/boss_prop.gd"),
	"elite": preload("res://src/elite_prop.gd"),
}
## Erweiterungen (f): Skripte mit `attach(stage)`, eine Zeile je Erweiterung, in der Reihenfolge der Anmeldung.
const EXTENSIONS := [
	preload("res://src/ability_extension.gd"),
	preload("res://src/tier_arcade.gd"),
]
## Beute (#49): so weit vor dem Fahrer (m) steht die Lichtsäule eines Fundes.
const LOOT_AHEAD_M := 18.0

signal challenge_started(entry: Dictionary)
signal challenge_ended(result: Dictionary)
signal loot_found(item: Dictionary, result: Dictionary)
signal stepped(ride_m: float, cadence: float, cadence_raw: float, delta_s: float)
signal run_finished(run: ArcadeRun)

## Der Lauf der laufenden (oder zuletzt gefahrenen) Fahrt; null = kein Arcade.
var run: ArcadeRun = null
## Würfel des Laufs (< 0 = zufällig; Tests setzen ihn fest) und die Herausforderungen, aus denen er würfelt.
var seed_value := -1
var pool: Array = Encounters.CHALLENGES
## Neue beste Punktzahl der Stufe in diesem Lauf (nach `save`).
var new_best := false
## Erweiterungspunkte (c) und (e): Zusammenfassungszeilen und Lauf-Einstellung.
var summary_providers: Array[Callable] = []
var run_hooks: Array[Callable] = []
## Die angelegten Erweiterungen (`EXTENSIONS`, `add_extension`).
var extensions := []

## Von der Hauptszene gesetzt: Strecke (Eltern der Tore und Requisiten), HUD, Bus, Zeitformat, Standzeit durchfahrener Tore.
var track: Track
var hud: RideHud
var bus: BusClient
var format_time: Callable
var keep_behind_m := 20.0

## Start- und Zieltor der Herausforderungen (Kinder von `Track`) und die Lage des Zieltors.
var start_gate: CourseGate
var finish_gate: CourseGate
var gate_placement := GatePlacement.new()
## Lichtsäule des letzten Fundes (Kind von `Track`).
var loot_beam: LootBeam
## Darstellungen (ArcadeProp) je Bausteintyp.
var props := {}
## Fahrtposition des letzten Anzeigeschritts (die Darstellungen lesen sie).
var distance_m := 0.0

var _gate_block: ChallengeBlock = null
var _prop_block: ChallengeBlock = null
var _prop_id := ""
var _announced: ChallengeBlock = null


## Tore, Requisiten und Lichtsäule an die Strecke hängen (einmal, beim Aufbau der Hauptszene).
func setup(track_node: Track, hud_node: RideHud, format: Callable, keep_behind: float) -> void:
	name = "ArcadeStage"
	track = track_node
	hud = hud_node
	format_time = format
	keep_behind_m = keep_behind
	start_gate = _new_gate("ArcadeStartGate")
	finish_gate = _new_gate("ArcadeFinishGate")
	for id in PROPS:
		var prop: ArcadeProp = PROPS[id].new()
		prop.attach(self)
		props[id] = prop
	loot_beam = LootBeam.new()
	loot_beam.visible = false
	track.add_child(loot_beam)
	for script in EXTENSIONS:
		add_extension(script)


## Erweiterung (f) anlegen und anbinden: `script.new()`, dann `attach(self)`. `bus` ist beim Aufbau noch nicht gesetzt (die
## Hauptszene baut den Bus später) – Erweiterungen lesen ihn erst in ihren Handlern.
func add_extension(script: GDScript) -> Object:
	var extension = script.new()
	extension.attach(self)
	extensions.append(extension)
	return extension


## Zugbrücke und Verfolger für Tests und Prüfhilfen (null, wenn der Typ nicht angemeldet ist).
var bridge: Drawbridge:
	get:
		return props["breakthrough"].bridge if props.has("breakthrough") else null
var pursuer: Pursuer:
	get:
		return props["chase"].pursuer if props.has("chase") else null


## Läuft ein Arcade-Lauf (auch noch nach der Fahrt bis zur nächsten)?
func is_active() -> bool:
	return run != null


## Gibt es etwas zu zeigen/zu speichern (der Lauf hat Zeit gesammelt)?
func has_result() -> bool:
	return run != null and run.elapsed_s > 0.0


## Neue Fahrt: bei `arcade_mode` einen Lauf der Stufe `tier` im Kadenzbereich des Spielstands ab `start_m` anlegen
## (sonst keiner), alles Szenische zurücksetzen.
func begin(arcade_mode: bool, tier: int, save_game: SaveGame, start_m: float) -> void:
	run = null
	if arcade_mode:
		run = ArcadeRun.new(tier, CadenceRange.selection(save_game),
				ArcadeRun.sections_from_stations(track.ride_stations(), track.length_m()), track.length_m(),
				start_m, seed_value, pool)
		run.gear = Inventory.modifiers(save_game)  # angelegte Ausrüstung wirkt nur hier (ADR-0010)
		for hook in run_hooks:
			hook.call(run, save_game)
	loot_beam.visible = false
	loot_beam.ride_m = NAN
	hud.clear_popups()
	_gate_block = null
	_prop_block = null
	_prop_id = ""
	_announced = null
	new_best = false
	start_gate.ride_m = NAN
	finish_gate.ride_m = NAN
	for prop in props.values():
		prop.clear()


## Der Fahrer trägt im Arcade-Lauf die angelegte Ausrüstung über der Garderobe (#49); sonst nichts.
func dress(rider_model: RiderModel, save_game: SaveGame) -> void:
	if run != null:
		rider_model.wear(Loot.appearance(Inventory.equipped(save_game)))


## Ein Fahrschritt (nicht in Pausen): der Lauf rechnet, beendete Herausforderungen werden eingeblendet.
func advance(ride_m: float, delta_s: float) -> void:
	if run == null:
		return
	for result in run.advance(ride_m, bus.cadence, delta_s):
		hud.celebrate(result_popup_text(result))
		show_loot(result, ride_m)
		challenge_ended.emit(result)
		var item: Dictionary = result.get("loot", {})
		if not item.is_empty():
			loot_found.emit(item, result)
	var block: ChallengeBlock = run.active["block"] if not run.active.is_empty() else null
	if block != _announced:
		_announced = block
		if block != null:
			challenge_started.emit(run.active)
	stepped.emit(ride_m, bus.cadence, bus.cadence_raw, delta_s)


## Fahrt in den Spielstand: Lauf im Fahrteintrag, beste Punktzahl der Stufe, Beute ins Inventar (#49).
func save(entry: Dictionary, save_game: SaveGame) -> void:
	if run == null:
		return
	entry["arcade"] = run.to_entry()
	new_best = save_game.record_arcade_points(run.tier, run.points)
	for item in run.found:
		Inventory.add(save_game, item)
	run_finished.emit(run)


## Zurück ins Startmenü: Popups, Lichtsäule, Tore und Requisiten weg.
func enter_menu() -> void:
	hud.clear_popups()
	loot_beam.visible = false
	_update_gates(0.0, true)


## Ein Anzeigeschritt: HUD-Zeile und Zonenbalken, Tore, Requisiten, Lichtsäule. `ride_m`/`speed_mps` des Fahrers;
## `in_menu`: Startmenü; `finished`: Ergebnis.
func update_view(ride_m: float, speed_mps: float, in_menu: bool, finished: bool) -> void:
	distance_m = ride_m
	_show_hud(finished)
	_update_gates(speed_mps, in_menu)
	_update_loot_beam(in_menu)


## Zusammenfassung eines Arcade-Laufs (#46): Stufe, Zeit, Runden, Strecke, Punkte (mit neuer Bestpunktzahl der Stufe),
## Herausforderungen geschafft/verfehlt und je Herausforderung, z. B. „Arcade beendet · Stufe 1\nZeit: 12:04.3 · Runden: 1
## · Strecke: 5.21 km\nPunkte: 340 – neue Bestpunktzahl!\nHerausforderungen: 3 geschafft · 1 verfehlt\nZone halten 3/4 …“.
## `rewards` = Erfolge/Level der Fahrt (Hauptszene), dazu Zeit, Runden, Strecke (km) und Durchschnitte der Fahrt.
func result_text(rewards: String, time_text: String, laps: int, distance_km: float, avg_cadence: int,
		avg_speed_kmh: float) -> String:
	var lines: Array = run.summary_lines()
	if new_best:
		lines[0] += " – neue Bestpunktzahl!"
	for provider in summary_providers:
		lines.append_array(provider.call(run))
	return "Arcade beendet · %s%s\nZeit: %s · Runden: %d · Strecke: %.2f km\n%s\nØ Kadenz: %d rpm · Ø Tempo: %.1f km/h\n%s" % [
			ArcadeTiers.get_tier(run.tier)["name"], " · " + rewards if not rewards.is_empty() else "",
			time_text, laps, distance_km, "\n".join(lines), avg_cadence, avg_speed_kmh,
			"Enter: zurück ins Menü · Esc: Einstellungen"]


## Einblendung, wenn eine Herausforderung endet: „Zone halten geschafft! +100 Punkte“ oder „Zone halten verfehlt –
## weiter geht's“ (weich: die Fahrt geht weiter).
static func result_popup_text(result: Dictionary) -> String:
	if result["succeeded"]:
		return "%s geschafft!  +%d Punkte" % [result["name"], result["points"]]
	return "%s verfehlt – weiter geht's" % result["name"]


## Feedback einer beendeten Herausforderung (#49): Punkte als Popup, ein Fund als Popup in der Farbe seiner Seltenheit
## und als Lichtsäule LOOT_AHEAD_M vor dem Fahrer (`ride_m`).
func show_loot(result: Dictionary, ride_m: float) -> void:
	if result["points"] > 0:
		hud.popup("+%d" % result["points"])
	var item: Dictionary = result.get("loot", {})
	if item.is_empty():
		return
	hud.popup(Loot.item_name(item), Loot.color_of(item["rarity"]))
	loot_beam.set_rarity(item["rarity"])
	loot_beam.place(track, ride_m + LOOT_AHEAD_M)


## Arcade-Zeile und Zonenbalken im HUD (#46): während einer Herausforderung ihr Name, die Zielzone, die Restzeit, die
## Punkte und der Zonenbalken mit dem Fortschritt; davor die nächste Herausforderung mit dem Weg bis zu ihrem Start.
## Ohne Arcade und im Ergebnis aus (den Zonenbalken blendet dann schon die Hauptszene mit dem Training aus).
func _show_hud(finished: bool) -> void:
	if run == null or finished:
		hud.show_arcade("", "", "", "")
		return
	var points := str(run.points)
	if not run.active.is_empty():
		var block: ChallengeBlock = run.active["block"]
		var zone := block.zone()
		hud.show_arcade(run.active["definition"]["name"], Encounters.target_text(run.active["definition"], zone),
				format_time.call(ceilf(block.remaining_s())), points)
		hud.show_zone(zone.x, zone.y, bus.cadence, Training.percent_text(block.progress()), block.score_caption())
		return
	var next := run.next_challenge()
	if next.is_empty():
		hud.show_arcade("Arcade", "–", "–", points)
		return
	var zone := run.zone_of(next)
	hud.show_arcade("Nächste: %s" % next["definition"]["name"], Encounters.target_text(next["definition"], zone),
			"%d m" % maxi(ceili(next["at_m"] - distance_m), 0), points)


## Lichtsäule (#49): zu sehen, bis sie `keep_behind_m` hinter dem Fahrer liegt; ohne Arcade und im Menü nie.
func _update_loot_beam(in_menu: bool) -> void:
	var at := loot_beam.ride_m
	loot_beam.visible = run != null and not in_menu and not is_nan(at) and at > distance_m - keep_behind_m


## Tore der Arcade-Herausforderungen (#46): das Starttor („Start“ und Zielzone auf dem Banner, wie im Training) am Startpunkt
## der laufenden oder nächsten Herausforderung, bis es `keep_behind_m` hinter dem Fahrer liegt; das Zieltor während einer
## Herausforderung dort, wo der Fahrer beim aktuellen Tempo das Ende ihres Zeitfensters erreicht (GatePlacement wie im
## Training). Nach dem Ende bleibt ein durchfahrenes Zieltor kurz stehen, ein noch vorausliegendes verschwindet. Nur
## Anzeige (ADR-0010).
func _update_gates(speed_mps: float, in_menu: bool) -> void:
	if run == null or in_menu:
		start_gate.visible = false
		finish_gate.visible = false
		for prop in props.values():
			prop.hide()
		return
	var d := distance_m
	var start := run.active if not run.active.is_empty() else run.next_challenge()
	if start.is_empty():
		start_gate.visible = false
	else:
		if start_gate.ride_m != start["at_m"]:
			var zone := run.zone_of(start)
			start_gate.configure(CourseGate.KIND_START, "Start  %s" % Encounters.target_text(start["definition"], zone))
			start_gate.place(track, start["at_m"])
		start_gate.visible = start["at_m"] > d - keep_behind_m \
				and start["at_m"] - d < track.length_m() - keep_behind_m
	if run.active.is_empty():
		var at := finish_gate.ride_m
		finish_gate.visible = not is_nan(at) and at <= d + 1.0 and at > d - keep_behind_m
		_end_props(finish_gate.visible)
		return
	var block: ChallengeBlock = run.active["block"]
	if block != _gate_block:
		_gate_block = block
		gate_placement.reset()
		finish_gate.configure(CourseGate.KIND_FINISH, "Ziel")
	var at := gate_placement.update(d, block.remaining_s(), speed_mps)
	finish_gate.place(track, at)
	finish_gate.visible = gate_placement.shown(d)
	_update_props(run.active["definition"].get("block", ""), block, at)


## Darstellung der Bausteine während der Herausforderung (ArcadeProp je Typ aus PROPS): die vorige Herausforderung kann im
## selben Schritt geendet haben, in dem diese begann – dann wird sie zuerst freigegeben.
func _update_props(id: String, block: ChallengeBlock, finish_at: float) -> void:
	if block != _prop_block:
		_release_props()
		_prop_block = block
		_prop_id = id
		if props.has(id):
			props[id].begin(block)
	for key in props:
		if key == id:
			if props[key].follow(block, finish_at):
				finish_gate.visible = false  # die Darstellung ist das Ziel
		else:
			props[key].idle()


## Nach dem Ende der Herausforderung: Darstellungen schließen ab (Brücke öffnet, Verfolger zieht ab). Sie bleiben wie ein
## durchfahrenes Zieltor kurz stehen (`keep`).
func _end_props(keep: bool) -> void:
	_release_props()
	var covered := false
	for prop in props.values():
		prop.idle()
		covered = covered or prop.covers_finish_gate()
	finish_gate.visible = keep and finish_gate.visible and not covered


func _release_props() -> void:
	if _prop_block == null:
		return
	var ended := _prop_block
	var id := _prop_id
	_prop_block = null
	_prop_id = ""
	if props.has(id):
		props[id].end(ended)


func _new_gate(node_name: String) -> CourseGate:
	var gate := CourseGate.new()
	gate.name = node_name
	gate.visible = false
	track.add_child(gate)
	return gate
