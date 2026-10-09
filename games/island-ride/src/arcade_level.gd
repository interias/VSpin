## Arcade-Level (#53, Spec #27; CONTEXT.md „Arcade“): das eigene Level des Arcade-Modus – **getrennt vom Fahrerlevel**
## (DriverLevel wächst mit Kilometern und schaltet nur Kosmetik frei, ADR-0010). Das Arcade-Level wächst mit den
## **Punkten der Arcade-Läufe** (jede gespeicherte Fahrt zählt ihre Punkte dazu; Punkte entstehen nur durch Herausforderungen
## mit Kadenz in der Zone) und liefert **Talentpunkte**: ab Level 2 einen je Level (Talents). Reine Logik über dem
## Spielstand (Bereich `arcade`, additiv, Formatversion bleibt 1):
##
##   arcade.points_total   Summe der Punkte aller gespeicherten Arcade-Läufe (ganze Zahl)
##
## Kurve: Level 1 ab 0 Punkten, der Schritt von Level n zu n + 1 kostet FIRST_STEP_POINTS + (n − 1) · STEP_GROWTH_POINTS,
## also Level 2 ab 400, 3 ab 1000, 4 ab 1800, 12 ab 15 400 Punkten; höchstens MAX_LEVEL. Ein Lauf auf Stufe 1 bringt rund
## 300–800 Punkte – das erste Talent ist nach ein oder zwei Fahrten da, die 11 Punkte des Höchstlevels füllen den Baum
## (15 Knoten) nie ganz: Build-Entscheidungen.
## Wirkt nur im Arcade (ADR-0010): nichts hiervon fließt in Rundfahrt, Training, Bestzeiten oder Fahrerlevel.
class_name ArcadeLevel
extends RefCounted

const MAX_LEVEL := 12
const FIRST_STEP_POINTS := 400
const STEP_GROWTH_POINTS := 200


## Gesamtpunkte, ab denen `level` erreicht ist (Level 1: 0).
static func points_for(level: int) -> int:
	var n := clampi(level, 1, MAX_LEVEL) - 1
	return FIRST_STEP_POINTS * n + STEP_GROWTH_POINTS * n * (n - 1) / 2


## Level bei `total` Gesamtpunkten.
static func level_for(total: int) -> int:
	var level := 1
	while level < MAX_LEVEL and total >= points_for(level + 1):
		level += 1
	return level


## Punkte bis zum nächsten Level (0 auf MAX_LEVEL).
static func points_to_next(total: int) -> int:
	var level := level_for(total)
	return 0 if level >= MAX_LEVEL else points_for(level + 1) - total


## Talentpunkte, die `level` insgesamt gibt (Level 1: keiner).
static func talent_points_for(level: int) -> int:
	return clampi(level, 1, MAX_LEVEL) - 1


## Gesamtpunkte im Spielstand (ungeprüfter Stand: Nicht-Zahlen und negative Werte zählen 0).
static func total_points(save: SaveGame) -> int:
	var stored = save.arcade().get("points_total")
	return maxi(int(stored), 0) if stored is float or stored is int else 0


## Arcade-Level des Spielstands.
static func level(save: SaveGame) -> int:
	return level_for(total_points(save))


## Zählt `points` (Punkte eines Arcade-Laufs) dazu; Werte ≤ 0 ändern nichts. Liefert die neuen Gesamtpunkte. Schreibt nicht
## auf die Platte.
static func add_points(save: SaveGame, points: int) -> int:
	var total := total_points(save)
	if points > 0:
		total += points
		save.arcade()["points_total"] = total
	return total
