## Baustein „Elite-Gruppe“ (#52): die Phasenfolge einer Elite-Gruppe – der Anführer (die durch ihre Eigenschaften
## veränderte Herausforderung), bei *Taktwechsel* in zwei Phasen, danach das Gefolge. Die Mechanik ist die der Bosse
## (BossFight, #51): Phasen nacheinander, jede mit eigener Zeit ab 0; alle geschafft → geschafft; scheitert eine, ist die
## Gruppe verfehlt (weich, die Fahrt geht weiter). Ausrüstung und Fähigkeiten wirken über `progress_factor` wie beim Boss.
##
## *Wankelmütig*: Phasen mit `wander` bekommen nach jedem Schritt die Zone für ihre jetzige Zeit – aus `zone_path`
## (Encounters.zone_for mit der Phasenzeit, also durch den Wächter des Kadenzbereichs); die gilt für den nächsten Schritt
## und für die Anzeige. Gebaut nur über `Encounters.build` (src/challenges/elite_challenges.gd).
class_name EliteGroup
extends BossFight

## Elite-Stufe (EliteGroups.CHAMPION / RARE) und Eigenschaften (Ids aus EliteGroups.AFFIXES).
var rank := ""
var affixes: Array = []
## Zone der Phase `index` zur Phasenzeit `at_s` (Callable(index, at_s) -> Vector2); setzt Encounters.build.
var zone_path: Callable


func _init(id: String, title: String, rank_id: String, affix_ids: Array, phase_blocks: Array,
		phase_definitions: Array) -> void:
	super(id, title, phase_blocks, phase_definitions)
	rank = rank_id
	affixes = affix_ids


## Ist die laufende Phase Gefolge (nicht der Anführer)?
func in_retinue() -> bool:
	return bool(phase_definition().get("retinue", false))


## Gefolgs-Phasen insgesamt und die Nummer der laufenden (1..n; 0 beim Anführer).
func retinue_count() -> int:
	return definitions.filter(func(d): return d.get("retinue", false)).size()


func retinue_number() -> int:
	if not in_retinue():
		return 0
	return mini(index, definitions.size() - 1) - (definitions.size() - retinue_count()) + 1


## Beschriftung des Fortschritts wie die laufende Phase („Fortschritt“, „Balken“, „Abstand“ …).
func score_caption() -> String:
	var phase := current_phase()
	return phase.score_caption() if phase != null else super()


func _step(cadence_rpm: float, delta_s: float) -> void:
	super(cadence_rpm, delta_s)
	follow_zone()


## Wankelmütig: die Zone der laufenden Phase für ihre jetzige Zeit (Wächter in Encounters.zone_for).
func follow_zone() -> void:
	if finished() or not zone_path.is_valid() or not phase_definition().has("wander"):
		return
	var phase := current_phase()
	var zone: Vector2 = zone_path.call(mini(index, phases.size() - 1), phase.elapsed_s)
	phase.set("zone_min", zone.x)
	phase.set("zone_max", zone.y)
