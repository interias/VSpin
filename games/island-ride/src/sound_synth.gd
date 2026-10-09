## Prozedurale Klänge der Inselfahrt (#44) – keine Klangdateien: jeder Klang entsteht hier als AudioStreamWAV (16 Bit,
## mono) aus Rauschen und Synthese, mit festem Zufalls-Seed (immer derselbe Klang). Endlosklänge sind nahtlose Schleifen
## (Ende in den Anfang übergeblendet), Einzelklänge spielen einmal. Erzeugt wird einmal beim Start, ein Klang je Frame
## (RideSound), damit kein großer Block das Bild stocken lässt.
##   wind       Fahrtwind: Rauschen, tiefpassgefiltert (Rauschen der Luft) plus ein schmaleres Band um ~600 Hz, dessen
##              Stärke langsam schwankt (Böen); 3 s, 11 025 Hz
##   sea        Meer: braunes Rauschen (Brandung) und Zischen der auslaufenden Welle, Lautstärke im Takt der Wellen
##              (zwei Wellen je 6 s); 11 025 Hz
##   rain       Regen: hochpassgefiltertes weißes Rauschen plus vereinzelte Tropfen (kurz abklingende Klicks); 2 s
##   freewheel  Freilauf: ein Klick (Rauschstoß + 3,2 kHz, wenige ms) je 1/20 s; die Tonhöhe (Abspieltempo) bestimmt die
##              Zahl der Klicks je Sekunde
##   sheep      Schafglocke: Blechglocke mit unharmonischen Teiltönen (1150 Hz × 1 · 2,31 · 3,89 · 5,6), kurz abklingend
##   church     Kirchenglocke: Teiltöne einer Glocke (Unterton 0,5, Prim 1, kleine Terz 1,19, Quinte 1,5, Oktave 2,
##              2,5, 3 über 220 Hz), lang abklingend, mit Anschlag; 11 025 Hz
##   gull       Möwe: zwei Rufe „kjau“, Grundton gleitet 1150 → 1500 → 900 Hz, obertonreich, mit leichtem Vibrato
##   click      UI-Klick: kurzer Sinus 1000 → 700 Hz
##   chime      Einblendung: zwei helle Töne (E6, A6) nacheinander
##   announce   Ansage im Training: ein weicher Ton (A5 mit Oktave)
class_name SoundSynth
extends RefCounted

const IDS := ["wind", "sea", "rain", "freewheel", "sheep", "church", "gull", "click", "chime", "announce"]
const RATE := 22050
const LOW_RATE := 11025
## Freilauf: Klicks je Sekunde beim Abspieltempo 1.
const FREEWHEEL_TICKS_PER_S := 20.0


## Klang `id` (IDS) als AudioStreamWAV.
static func build(id: String) -> AudioStreamWAV:
	match id:
		"wind":
			return _wind()
		"sea":
			return _sea()
		"rain":
			return _rain()
		"freewheel":
			return _freewheel()
		"sheep":
			return _bell(RATE, 0.9, 1150.0, [1.0, 2.31, 3.89, 5.6], [1.0, 0.6, 0.4, 0.25], [0.35, 0.22, 0.15, 0.1], 0.003)
		"church":
			return _bell(LOW_RATE, 3.5, 220.0, [0.5, 1.0, 1.19, 1.5, 2.0, 2.5, 3.0], [0.5, 0.7, 0.6, 0.3, 0.9, 0.4, 0.25],
					[3.5, 2.0, 1.6, 1.0, 1.2, 0.7, 0.5], 0.006)
		"gull":
			return _gull()
		"click":
			return _tone(0.03, [[0.0, 1000.0, 700.0, 1.0, 0.006]])
		"chime":
			return _tone(0.7, [[0.0, 1318.5, 1318.5, 0.6, 0.3], [0.12, 1760.0, 1760.0, 0.6, 0.35]])
		"announce":
			return _tone(0.5, [[0.0, 880.0, 880.0, 0.7, 0.3], [0.0, 1760.0, 1760.0, 0.2, 0.15]])
	push_warning("SoundSynth: unbekannter Klang '%s'" % id)
	return null


## Endlosklang? (Fahrtwind, Meer, Regen, Freilauf.)
static func loops(id: String) -> bool:
	return id in ["wind", "sea", "rain", "freewheel"]


static func _wind() -> AudioStreamWAV:
	var rng := _rng(4401)
	var n := LOW_RATE * 3
	var fade := LOW_RATE / 2
	var out := PackedFloat32Array()
	out.resize(n + fade)
	var low := 0.0
	var band_low := 0.0
	var band := 0.0
	for i in range(n + fade):
		var t := float(i) / LOW_RATE
		var white := rng.randf() * 2.0 - 1.0
		low += 0.05 * (white - low)
		band_low += 0.3 * (white - band_low)
		band += 0.35 * (band_low - band)  # Band um einige 100 Hz: Differenz zweier Tiefpässe
		var gust := 0.55 + 0.3 * sin(TAU * t / 3.0) + 0.15 * sin(TAU * t * 2.0 / 3.0 + 1.3)
		out[i] = low * 2.2 + (band_low - band) * gust * 1.4
	return _wav(_loop(out, n, fade), LOW_RATE, true)


static func _sea() -> AudioStreamWAV:
	var rng := _rng(4402)
	var n := LOW_RATE * 6
	var fade := LOW_RATE
	var out := PackedFloat32Array()
	out.resize(n + fade)
	var brown := 0.0
	var low := 0.0
	var hiss_low := 0.0
	for i in range(n + fade):
		var t := float(i) / LOW_RATE
		var white := rng.randf() * 2.0 - 1.0
		brown = brown * 0.995 + white * 0.05
		low += 0.08 * (brown - low)
		hiss_low += 0.5 * (white - hiss_low)
		var swell := sin(PI * t / 3.0)
		var wave := 0.3 + 0.7 * swell * swell  # zwei Wellen je 6 s
		var wash := sin(PI * (t - 0.6) / 3.0)
		out[i] = low * 3.0 * wave + (white - hiss_low) * 0.25 * wash * wash
	return _wav(_loop(out, n, fade), LOW_RATE, true)


static func _rain() -> AudioStreamWAV:
	var rng := _rng(4403)
	var n := RATE * 2
	var fade := RATE / 4
	var out := PackedFloat32Array()
	out.resize(n + fade)
	var low := 0.0
	var drop := 0.0
	var ring := 0.0
	for i in range(n + fade):
		var white := rng.randf() * 2.0 - 1.0
		low += 0.25 * (white - low)
		if rng.randf() < 0.0015:
			drop = rng.randf_range(0.4, 1.0)
		drop *= 0.992
		ring = sin(float(i) * 0.9) * drop
		out[i] = (white - low) * 0.5 + ring * 0.5
	return _wav(_loop(out, n, fade), RATE, true)


static func _freewheel() -> AudioStreamWAV:
	var rng := _rng(4404)
	var n := roundi(RATE / FREEWHEEL_TICKS_PER_S)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		out[i] = (rng.randf() * 2.0 - 1.0) * exp(-t / 0.0012) * 0.6 + sin(TAU * 3200.0 * t) * exp(-t / 0.002) * 0.5
	return _wav(out, RATE, true)


## Glocke aus Teiltönen `ratios` × `base` (Hz) mit Stärken `amps` und Abklingzeiten `decays` (s), Länge `length_s`;
## dazu ein Anschlag (Rauschstoß, `strike_s`).
static func _bell(rate: int, length_s: float, base: float, ratios: Array, amps: Array, decays: Array,
		strike_s: float) -> AudioStreamWAV:
	var rng := _rng(4405 + roundi(base))
	var n := roundi(rate * length_s)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in range(ratios.size()):
		var step: float = TAU * base * ratios[k] / rate
		var amp: float = amps[k]
		var fall: float = exp(-1.0 / (decays[k] * rate))
		var level := amp
		for i in range(n):
			out[i] += sin(step * i) * level
			level *= fall
	for i in range(mini(n, roundi(strike_s * rate * 4.0))):
		out[i] += (rng.randf() * 2.0 - 1.0) * exp(-float(i) / (strike_s * rate)) * 0.6
	return _wav(out, rate, false)


static func _gull() -> AudioStreamWAV:
	var n := roundi(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var call_t := t if t < 0.4 else t - 0.45  # zwei Rufe
		if call_t < 0.0 or call_t > 0.36:
			continue
		var u := call_t / 0.36
		var freq := lerpf(1150.0, 1500.0, smoothstep(0.0, 0.12, u)) * lerpf(1.0, 0.6, smoothstep(0.15, 1.0, u))
		freq *= 1.0 + 0.03 * sin(TAU * 24.0 * call_t)
		phase += TAU * freq / RATE
		var env := smoothstep(0.0, 0.05, u) * (1.0 - smoothstep(0.55, 1.0, u))
		out[i] = (sin(phase) + 0.5 * sin(2.0 * phase) + 0.35 * sin(3.0 * phase) + 0.2 * sin(4.0 * phase)) * env
	return _wav(out, RATE, false)


## Einfache Töne: je Eintrag [Beginn s, Frequenz von, Frequenz bis (Hz), Stärke, Abklingzeit s], Länge `length_s`.
static func _tone(length_s: float, notes: Array) -> AudioStreamWAV:
	var n := roundi(RATE * length_s)
	var out := PackedFloat32Array()
	out.resize(n)
	for note in notes:
		var start := roundi(note[0] * RATE)
		var phase := 0.0
		for i in range(start, n):
			var t := float(i - start) / RATE
			var freq: float = lerpf(note[1], note[2], minf(t / length_s, 1.0))
			phase += TAU * freq / RATE
			out[i] += sin(phase) * note[3] * exp(-t / note[4]) * smoothstep(0.0, 0.002, t)
	return _wav(out, RATE, false)


## Nahtlose Schleife der Länge `n` aus `samples` (n + `fade`): das Ende wird in den Anfang übergeblendet.
static func _loop(samples: PackedFloat32Array, n: int, fade: int) -> PackedFloat32Array:
	for i in range(fade):
		var a := float(i) / fade
		samples[i] = samples[i] * a + samples[n + i] * (1.0 - a)
	samples.resize(n)
	return samples


## 16-Bit-WAV, auf 0,9 der Vollaussteuerung normiert.
static func _wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var peak := 0.0001
	for v in samples:
		peak = maxf(peak, absf(v))
	var scale := 0.9 * 32767.0 / peak
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, roundi(samples[i] * scale))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
