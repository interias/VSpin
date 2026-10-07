## Tageszeit und Sonnenstand (G6): die Insel liegt auf Mallorca (Palma, ≈ 39,6° N, 2,65° O), die Uhr läuft in
## echter Ortszeit dort (Europe/Madrid: MEZ = UTC+1, MESZ = UTC+2 nach EU-Regel). Die Uhr zählt UTC-Sekunden
## (`unix_s`) – die Systemuhr liefert sie unabhängig von der Zeitzone des Rechners; Ortszeit braucht es nur für die
## feste Stunde und die Anzeige. Sonnenstand nach der NOAA-Näherung (Deklination, Zeitgleichung, Stundenwinkel;
## Genauigkeit ≈ 1–2 min bei Auf-/Untergang).
##
## Modi (`mode`):
##   realtime   Echtzeit (Standard): Systemuhr
##   fixed      feste Ortszeit `fixed_hour` am heutigen Tag, die Uhr steht
##   timelapse  Zeitraffer ab der aktuellen Zeit: ein Tag in `timelapse_day_min` Minuten
## Alle Rechnungen sind reine (statische) Funktionen; die Uhr selbst rückt nur mit `advance()` vor.
class_name DayNight
extends RefCounted

const MODE_REALTIME := "realtime"
const MODE_FIXED := "fixed"
const MODE_TIMELAPSE := "timelapse"
const MODES := [MODE_REALTIME, MODE_FIXED, MODE_TIMELAPSE]
## Palma de Mallorca.
const LATITUDE_DEG := 39.57
const LONGITUDE_DEG := 2.65
## Sonnenhöhe bei Auf-/Untergang (Mittelpunkt, mit Refraktion und Sonnenradius).
const HORIZON_DEG := -0.833

var mode := MODE_REALTIME
## Ortszeit (Stunden, 0–24) im Modus `fixed`.
var fixed_hour := 13.0
## Zeitraffer: Minuten echter Zeit je simuliertem Tag.
var timelapse_day_min := 24.0
## Simulierte Zeit in UTC-Sekunden seit 1970.
var unix_s := 0.0


func _init(start_mode: String = MODE_REALTIME, hour: float = 13.0, day_min: float = 24.0,
		now_s: float = Time.get_unix_time_from_system()) -> void:
	fixed_hour = hour
	timelapse_day_min = maxf(day_min, 0.1)
	unix_s = now_s
	set_mode(start_mode, NAN, now_s)


## Modus wechseln (unbekannt → Echtzeit). `hour` (Ortszeit) setzt die feste Stunde, falls angegeben; der Zeitraffer
## beginnt bei der festen Stunde, wenn eine angegeben ist, sonst bei der aktuellen Zeit.
func set_mode(new_mode: String, hour: float = NAN, now_s: float = Time.get_unix_time_from_system()) -> void:
	if new_mode not in MODES:
		push_warning("DayNight: unbekannter Modus '%s', nutze '%s'" % [new_mode, MODE_REALTIME])
		new_mode = MODE_REALTIME
	mode = new_mode
	if not is_nan(hour):
		fixed_hour = fposmod(hour, 24.0)
	if mode == MODE_FIXED or (mode == MODE_TIMELAPSE and not is_nan(hour)):
		unix_s = at_local_hour(now_s, fixed_hour)
	elif mode == MODE_REALTIME:
		unix_s = now_s


## Uhr um `seconds` echte Zeit vorrücken.
func advance(seconds: float, now_s: float = Time.get_unix_time_from_system()) -> void:
	match mode:
		MODE_REALTIME:
			unix_s = now_s
		MODE_TIMELAPSE:
			unix_s += seconds * 1440.0 / timelapse_day_min


## Ortszeit (Stunden 0–24) der Uhr.
func local_hour() -> float:
	return local_hour_of(unix_s)


## Sonnenstand jetzt: Vector2(Höhe, Azimut) in Grad (Azimut ab Norden im Uhrzeigersinn).
func sun() -> Vector2:
	return sun_position(unix_s)


## Abstand zu UTC in Stunden für Mallorca/Madrid: MESZ (+2) vom letzten Sonntag im März 01:00 UTC bis zum letzten
## Sonntag im Oktober 01:00 UTC, sonst MEZ (+1).
static func madrid_utc_offset_h(utc_s: float) -> int:
	var year: int = Time.get_datetime_dict_from_unix_time(int(floor(utc_s)))["year"]
	var start := _last_sunday_utc(year, 3) + 3600.0
	var end := _last_sunday_utc(year, 10) + 3600.0
	return 2 if utc_s >= start and utc_s < end else 1


## Mitternacht UTC des letzten Sonntags im Monat `month`.
static func _last_sunday_utc(year: int, month: int) -> float:
	var next_first := Time.get_unix_time_from_datetime_dict({"year": year + (1 if month == 12 else 0),
			"month": 1 if month == 12 else month + 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var last_day := next_first - 86400
	var weekday: int = Time.get_datetime_dict_from_unix_time(last_day)["weekday"]  # 0 = Sonntag
	return float(last_day - weekday * 86400)


## UTC-Sekunden für Ortszeit `hour` (Stunden) am Datum `year-month-day` auf Mallorca.
static func local_to_unix(year: int, month: int, day: int, hour: float) -> float:
	var midnight := float(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day,
			"hour": 0, "minute": 0, "second": 0}))
	var guess := midnight + hour * 3600.0 - 3600.0
	return midnight + hour * 3600.0 - madrid_utc_offset_h(guess) * 3600.0


## Ortszeit `hour` am selben Ortsdatum wie `utc_s`.
static func at_local_hour(utc_s: float, hour: float) -> float:
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(int(floor(utc_s + madrid_utc_offset_h(utc_s) * 3600.0)))
	return local_to_unix(local["year"], local["month"], local["day"], hour)


## Ortszeit (Stunden 0–24) auf Mallorca zu `utc_s`.
static func local_hour_of(utc_s: float) -> float:
	return fposmod(utc_s / 3600.0 + madrid_utc_offset_h(utc_s), 24.0)


## Sonnenstand zu `utc_s` an (lat, lon): Vector2(Höhe, Azimut) in Grad, Azimut ab Norden im Uhrzeigersinn.
## NOAA-Näherung: Jahresbruchteil → Zeitgleichung und Deklination → wahre Ortszeit → Stundenwinkel.
static func sun_position(utc_s: float, lat_deg: float = LATITUDE_DEG, lon_deg: float = LONGITUDE_DEG) -> Vector2:
	var date: Dictionary = Time.get_datetime_dict_from_unix_time(int(floor(utc_s)))
	var day_start := float(Time.get_unix_time_from_datetime_dict({"year": date["year"], "month": date["month"],
			"day": date["day"], "hour": 0, "minute": 0, "second": 0}))
	var hour_utc := (utc_s - day_start) / 3600.0
	var year_start := float(Time.get_unix_time_from_datetime_dict({"year": date["year"], "month": 1, "day": 1,
			"hour": 0, "minute": 0, "second": 0}))
	var day_of_year := floorf((day_start - year_start) / 86400.0) + 1.0
	var days_in_year := 366.0 if (date["year"] % 4 == 0 and (date["year"] % 100 != 0 or date["year"] % 400 == 0)) else 365.0
	var g := TAU / days_in_year * (day_of_year - 1.0 + (hour_utc - 12.0) / 24.0)
	var eqtime := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) + 0.000907 * sin(2.0 * g) \
			- 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	var true_solar_min := hour_utc * 60.0 + eqtime + 4.0 * lon_deg
	var hour_angle := deg_to_rad(true_solar_min / 4.0 - 180.0)
	var lat := deg_to_rad(lat_deg)
	var cos_zenith := clampf(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hour_angle), -1.0, 1.0)
	var elevation := 90.0 - rad_to_deg(acos(cos_zenith))
	var azimuth := rad_to_deg(atan2(sin(hour_angle), cos(hour_angle) * sin(lat) - tan(decl) * cos(lat))) + 180.0
	return Vector2(elevation, fposmod(azimuth, 360.0))


## Sonnenauf- und -untergang (Ortszeit in Stunden) am Datum auf Mallorca: Suche im Minutenraster, dann halbiert.
static func sun_times(year: int, month: int, day: int, lat_deg: float = LATITUDE_DEG, lon_deg: float = LONGITUDE_DEG) -> Vector2:
	var result := Vector2(NAN, NAN)
	var start := local_to_unix(year, month, day, 0.0)
	var prev := sun_position(start, lat_deg, lon_deg).x - HORIZON_DEG
	for minute in range(1, 24 * 60 + 1):
		var t := start + minute * 60.0
		var now := sun_position(t, lat_deg, lon_deg).x - HORIZON_DEG
		if signf(now) != signf(prev):
			var a := t - 60.0
			var b := t
			for i in range(12):
				var mid := (a + b) / 2.0
				if signf(sun_position(mid, lat_deg, lon_deg).x - HORIZON_DEG) == signf(prev):
					a = mid
				else:
					b = mid
			var hour := local_hour_of(a)  # nicht ab Mitternacht gezählt: am Umstellungstag hat der Tag 23/25 h
			if now > 0.0:
				result.x = hour
			else:
				result.y = hour
		prev = now
	return result


## Richtung zur Sonne in Weltkoordinaten (Norden = −z, Osten = +x) aus Höhe und Azimut (Grad).
static func sun_direction(elevation_deg: float, azimuth_deg: float) -> Vector3:
	var e := deg_to_rad(elevation_deg)
	var a := deg_to_rad(azimuth_deg)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
