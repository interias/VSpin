## Erfolge (#35, CONTEXT.md: einmaliger Meilenstein, z. B. „100 km gesamt“, „Nachtfahrt“, „im Regen gefahren“) –
## reine Logik ohne Szene und ohne Bus. Jeder Erfolg ist nur Daten (`LIST`): ID, Kategorie, Name, Text, das
## **Ereignis der Fahrt**, auf das er hört, und die Bedingung an dessen Felder. Ein neuer Erfolg ist ein neuer Eintrag,
## keine Sonderlogik. Eine Medaille gibt es nie für einen Erfolg (nur für Runden- und Segmentzeiten).
##
## Ereignisvertrag (Dictionary mit `type` und Feldern):
##   distance           {total_km, ride_km}       Strecke: gesamt (alle Fahrten, jeder Modus) und in dieser Fahrt
##   lap                {total_laps, ride_laps}   Runde fertig: volle Runden gesamt und in dieser Fahrt
##   weather            {state}                   Wetter beim Fahren (Weather.CLEAR, LIGHT_CLOUDS, OVERCAST, RAIN)
##   time_of_day        {hour}                    Ortszeit beim Fahren (Mallorca, 0–24, DayNight.local_hour())
##   season             {season}                  Jahreszeit beim Fahren (SEASONS) – sendet erst #39
##   training_finished  {total_trainings, score}  Training fertig: Einheiten gesamt, Treffer der Zielkadenz 0..1 –
##                                                sendet erst #37
##
## Bedingung (`when`): Feld → Regel; alle Regeln müssen gelten. Regeln: {"min": x} (Zahl ≥ x), {"is": v} (gleich),
## {"hours": [von, bis]} (Stunde im Bereich [von, bis), über Mitternacht, wenn von > bis).
class_name Achievements
extends RefCounted

const EVENT_DISTANCE := "distance"
const EVENT_LAP := "lap"
const EVENT_WEATHER := "weather"
const EVENT_TIME_OF_DAY := "time_of_day"
const EVENT_SEASON := "season"
const EVENT_TRAINING := "training_finished"
## Jahreszeiten im Ereignis `season` (#39).
const SEASONS := ["spring", "summer", "autumn", "winter"]
## Kategorien in Anzeige-Reihenfolge (Fahrtenbuch).
const CATEGORIES := {
	"distance": "Strecke",
	"laps": "Rundenzahl",
	"time_of_day": "Tageszeit",
	"weather": "Wetter",
	"season": "Jahreszeit",
	"training": "Training",
}

const LIST := [
	{"id": "km_1", "category": "distance", "name": "Erster Kilometer", "text": "1 km gefahren",
		"event": EVENT_DISTANCE, "when": {"total_km": {"min": 1.0}}},
	{"id": "km_10", "category": "distance", "name": "Eingerollt", "text": "10 km gesamt",
		"event": EVENT_DISTANCE, "when": {"total_km": {"min": 10.0}}},
	{"id": "km_100", "category": "distance", "name": "Hundert", "text": "100 km gesamt",
		"event": EVENT_DISTANCE, "when": {"total_km": {"min": 100.0}}},
	{"id": "km_500", "category": "distance", "name": "Inselkenner", "text": "500 km gesamt",
		"event": EVENT_DISTANCE, "when": {"total_km": {"min": 500.0}}},
	{"id": "km_1000", "category": "distance", "name": "Tausender", "text": "1000 km gesamt",
		"event": EVENT_DISTANCE, "when": {"total_km": {"min": 1000.0}}},
	{"id": "ride_km_20", "category": "distance", "name": "Ausfahrt", "text": "20 km in einer Fahrt",
		"event": EVENT_DISTANCE, "when": {"ride_km": {"min": 20.0}}},
	{"id": "ride_km_50", "category": "distance", "name": "Langstrecke", "text": "50 km in einer Fahrt",
		"event": EVENT_DISTANCE, "when": {"ride_km": {"min": 50.0}}},
	{"id": "laps_1", "category": "laps", "name": "Erste Runde", "text": "Eine Runde zu Ende gefahren",
		"event": EVENT_LAP, "when": {"total_laps": {"min": 1}}},
	{"id": "laps_10", "category": "laps", "name": "Zehn Runden", "text": "10 Runden gesamt",
		"event": EVENT_LAP, "when": {"total_laps": {"min": 10}}},
	{"id": "laps_50", "category": "laps", "name": "Stammgast", "text": "50 Runden gesamt",
		"event": EVENT_LAP, "when": {"total_laps": {"min": 50}}},
	{"id": "ride_laps_3", "category": "laps", "name": "Drei am Stück", "text": "3 Runden in einer Fahrt",
		"event": EVENT_LAP, "when": {"ride_laps": {"min": 3}}},
	{"id": "ride_laps_10", "category": "laps", "name": "Sitzfleisch", "text": "10 Runden in einer Fahrt",
		"event": EVENT_LAP, "when": {"ride_laps": {"min": 10}}},
	{"id": "morning", "category": "time_of_day", "name": "Frühaufsteher", "text": "Zwischen 5 und 8 Uhr gefahren",
		"event": EVENT_TIME_OF_DAY, "when": {"hour": {"hours": [5.0, 8.0]}}},
	{"id": "noon", "category": "time_of_day", "name": "Mittagssonne", "text": "Zwischen 12 und 15 Uhr gefahren",
		"event": EVENT_TIME_OF_DAY, "when": {"hour": {"hours": [12.0, 15.0]}}},
	{"id": "evening", "category": "time_of_day", "name": "Feierabendrunde", "text": "Zwischen 18 und 21 Uhr gefahren",
		"event": EVENT_TIME_OF_DAY, "when": {"hour": {"hours": [18.0, 21.0]}}},
	{"id": "night", "category": "time_of_day", "name": "Nachtfahrt", "text": "Zwischen 22 und 5 Uhr gefahren",
		"event": EVENT_TIME_OF_DAY, "when": {"hour": {"hours": [22.0, 5.0]}}},
	{"id": "clear", "category": "weather", "name": "Kaiserwetter", "text": "Bei klarem Himmel gefahren",
		"event": EVENT_WEATHER, "when": {"state": {"is": Weather.CLEAR}}},
	{"id": "clouds", "category": "weather", "name": "Wolkenspiel", "text": "Bei leichter Bewölkung gefahren",
		"event": EVENT_WEATHER, "when": {"state": {"is": Weather.LIGHT_CLOUDS}}},
	{"id": "overcast", "category": "weather", "name": "Grauer Tag", "text": "Bei bedecktem Himmel gefahren",
		"event": EVENT_WEATHER, "when": {"state": {"is": Weather.OVERCAST}}},
	{"id": "rain", "category": "weather", "name": "Regenfahrer", "text": "Im Regen gefahren",
		"event": EVENT_WEATHER, "when": {"state": {"is": Weather.RAIN}}},
	{"id": "spring", "category": "season", "name": "Mandelblüte", "text": "Im Frühling gefahren",
		"event": EVENT_SEASON, "when": {"season": {"is": "spring"}}},
	{"id": "summer", "category": "season", "name": "Sommerhitze", "text": "Im Sommer gefahren",
		"event": EVENT_SEASON, "when": {"season": {"is": "summer"}}},
	{"id": "autumn", "category": "season", "name": "Herbstlicht", "text": "Im Herbst gefahren",
		"event": EVENT_SEASON, "when": {"season": {"is": "autumn"}}},
	{"id": "winter", "category": "season", "name": "Winterrunde", "text": "Im Winter gefahren",
		"event": EVENT_SEASON, "when": {"season": {"is": "winter"}}},
	{"id": "training_1", "category": "training", "name": "Erste Einheit", "text": "Ein Training beendet",
		"event": EVENT_TRAINING, "when": {"total_trainings": {"min": 1}}},
	{"id": "training_10", "category": "training", "name": "Trainingsfleiß", "text": "10 Trainings beendet",
		"event": EVENT_TRAINING, "when": {"total_trainings": {"min": 10}}},
	{"id": "training_precise", "category": "training", "name": "Punktlandung",
		"text": "Ein Training mit mindestens 90 % Treffer der Zielkadenz beendet",
		"event": EVENT_TRAINING, "when": {"score": {"min": 0.9}}},
]


## Erfolge, die `event` neu erfüllt – ohne die schon freigeschalteten (`unlocked`: ID → Datum). Reihenfolge wie LIST.
static func check(event: Dictionary, unlocked: Dictionary) -> Array:
	var result := []
	for achievement in LIST:
		if not unlocked.has(achievement["id"]) and met(achievement, event):
			result.append(achievement)
	return result


## Erfüllt `event` die Bedingung von `achievement`?
static func met(achievement: Dictionary, event: Dictionary) -> bool:
	if event.get("type") != achievement["event"]:
		return false
	var when: Dictionary = achievement["when"]
	for field in when:
		if not _rule_met(when[field], event.get(field)):
			return false
	return true


## Erfolg mit `id` ({} = unbekannt).
static func find(id: String) -> Dictionary:
	for achievement in LIST:
		if achievement["id"] == id:
			return achievement
	return {}


static func _rule_met(rule: Dictionary, value) -> bool:
	var number := value is float or value is int
	if rule.has("min") and not (number and value >= rule["min"]):
		return false
	if rule.has("is") and not (typeof(value) == typeof(rule["is"]) and value == rule["is"]):
		return false
	if rule.has("hours"):
		if not number:
			return false
		var hour := fposmod(float(value), 24.0)
		var from: float = rule["hours"][0]
		var to: float = rule["hours"][1]
		var inside := (hour >= from and hour < to) if from <= to else (hour >= from or hour < to)
		if not inside:
			return false
	return true
