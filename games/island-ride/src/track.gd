## Strecke als Path3D: der Fahrer folgt dem Pfad, keine Lenk-Physik (ADR-0006).
##
## Schnittstelle für Fahrmodell und spätere `set_grade`-Meldung (#12):
##   length_m()          Rundenlänge in Metern (Bogenlänge des Pfads)
##   grade_at(distance)  Steigung als Anteil (0.06 = 6 %, negativ = bergab) an einer Streckenposition
## Positionen jenseits der Rundenlänge werden umgerechnet (Rundkurs).
## Die Steigung wird aus der Geometrie des Pfads gelesen – jede Kurve (Graybox, später Insel #14) funktioniert.
class_name Track
extends Path3D

## Halber Abstand der beiden Messpunkte für die Steigung (Meter).
const GRADE_SAMPLE_HALF_M := 2.0


func length_m() -> float:
	return curve.get_baked_length() if curve != null else 0.0


## Streckenposition innerhalb einer Runde.
func wrap_distance(distance_m: float) -> float:
	var length := length_m()
	return fposmod(distance_m, length) if length > 0.0 else 0.0


## Steigung an der Streckenposition `distance_m`: Höhendifferenz / horizontale Distanz.
func grade_at(distance_m: float) -> float:
	var length := length_m()
	if length <= 0.0:
		return 0.0
	var a := curve.sample_baked(wrap_distance(distance_m - GRADE_SAMPLE_HALF_M))
	var b := curve.sample_baked(wrap_distance(distance_m + GRADE_SAMPLE_HALF_M))
	var horizontal := Vector2(b.x - a.x, b.z - a.z).length()
	if horizontal < 0.001:
		return 0.0
	return (b.y - a.y) / horizontal


## Weltposition (lokal zum Pfad) an der Streckenposition.
func position_at(distance_m: float) -> Vector3:
	return curve.sample_baked(wrap_distance(distance_m)) if curve != null else Vector3.ZERO
