## Fund-Karte der Beute (#83, Story 6): fällt im Arcade-Lauf ein Teil, schiebt rechts im HUD eine Karte ein – das
## Ausrüstungssymbol (ItemIconView, legendäre Teile leuchten), der Name in der Farbe der Seltenheit, Seltenheit (bei
## legendären mit Effekt) und die Werte des Teils. Sie steht `hold_s` und blendet aus. Der Text-Popup des HUDs bleibt
## daneben unverändert; die Karte ist ein eigenes Element unter dem HUD (`RideHud` selbst bleibt unberührt).
##
## Lage: die rechte Spalte unter der Minikarte bis über das untere Panel (`column`). Dort liegt sonst nichts: Kadenz und
## Tempo stehen links oben, Arcade-Zeile und Zonenbalken unten, die Popups in der Bildmitte. Im schmalen Fenster (Halbbild
## 960×1040) bleibt links der Karte Platz für die Popups: die Karte wird dann schmaler (kleineres Symbol, Name in zwei
## Zeilen). Höchstens MAX_CARDS stehen untereinander, weitere warten, bis Platz ist – so reichen sie nie in die Mitte
## hinunter, wo die Einblendung des Ergebnisses steht. Größe wie die HUD-Schrift: mit der Fensterhöhe
## (`RideHud.text_scale`), das Symbol nie unter MIN_ICON_PX. Die Karte fängt keine Maus und braucht keine Bedienung. Nur
## Anzeige (ADR-0010).
##
## Gebrauch: `LootToast.attach(hud)`; `show_item(item)` je Fund, `clear()` bei Menü, Ergebnis und neuer Fahrt.
class_name LootToast
extends Control

## Einschieben (s, von rechts) und Ausblenden (s); Halten (s) ist einstellbar.
const SLIDE_S := 0.35
const OUT_S := 0.6
## Karten gleichzeitig.
const MAX_CARDS := 2
## Symbol (px bei Fensterhöhe 1080, nie darunter), Textbreite, Abstände (skalieren mit der Schrift).
const ICON_PX := 96.0
const MIN_ICON_PX := 64.0
const TEXT_PX := 210.0
const MIN_TEXT_PX := 96.0
const MIN_FULL_TEXT_PX := 170.0
const PAD_PX := 10.0
const GAP_PX := 10.0
const EDGE_PX := 16.0
const NAME_FONT_PX := 20
const LINE_FONT_PX := 15
const MIN_NAME_FONT_PX := 15
const MIN_LINE_FONT_PX := 12
## Platz links der Karte für die Mitte des Fensters (Popups, bei 1080 px Höhe): halbe Breite des längsten Namens
## („Gewöhnlicher Talisman“) samt Rand.
const CENTER_RESERVE_PX := 240.0
const COLOR_STATS := Color(0.72, 0.82, 1.0)
const COLOR_CARD := Color(0.05, 0.05, 0.07, 0.9)

var hold_s := 5.0

var _hud: Node
var _cards: Array = []  # {node, item, age}
var _waiting: Array = []  # Funde ohne Platz


## Karte an `hud` hängen (einmal, beim Aufbau der Bühne).
static func attach(hud: Node) -> LootToast:
	var toast := LootToast.new()
	hud.add_child(toast)
	toast._hud = hud
	return toast


func _init() -> void:
	name = "LootToast"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)


## Fund `item` (Loot-Teil, noch ohne `id`) einblenden.
func show_item(item: Dictionary) -> void:
	_waiting.append(item)
	_admit()
	set_process(true)


## Gezeigte Teile (für Tests), älteste zuerst.
func items() -> Array:
	return _cards.map(func(c): return c["item"])


## Die Karten selbst (für Tests), älteste zuerst.
func cards() -> Array:
	return _cards.map(func(c): return c["node"])


## Anzahl wartender Funde.
func waiting() -> int:
	return _waiting.size()


## Alles sofort weg (Menü, Ergebnis, neue Fahrt).
func clear() -> void:
	for card in _cards:
		card["node"].queue_free()
	_cards.clear()
	_waiting.clear()
	set_process(false)


## Fläche der Karten: rechter Rand des Fensters, von unter der Minikarte bis über das untere Panel des HUDs; so breit,
## wie die Karte in voller Größe wird, höchstens bis zur Mitte abzüglich der Popups.
func column() -> Rect2:
	var view := get_viewport_rect().size
	var top := EDGE_PX
	var bottom := view.y - EDGE_PX
	var map := _control("MapPanel")
	if map != null:
		top = map.get_global_rect().end.y + GAP_PX + 2.0
	var panel := _control("Bottom")
	if panel != null:
		bottom = panel.get_global_rect().position.y - GAP_PX - 2.0
	var width := minf(_full_width(), view.x * 0.5 - EDGE_PX - CENTER_RESERVE_PX * _scale())
	return Rect2(view.x - EDGE_PX - width, top, width, maxf(bottom - top, 0.0))


func _process(delta: float) -> void:
	var area := column()
	var y := area.position.y
	var left := false
	for card in _cards.duplicate():
		card["age"] += delta
		var node: Control = card["node"]
		var life: float = SLIDE_S + hold_s + OUT_S
		if card["age"] >= life:
			node.queue_free()
			_cards.erase(card)
			left = true
			continue
		var slide := 1.0 - clampf(card["age"] / SLIDE_S, 0.0, 1.0)
		slide *= slide * slide
		node.modulate.a = 1.0 if card["age"] < life - OUT_S else (life - card["age"]) / OUT_S
		node.position = Vector2(area.end.x - node.size.x + slide * (node.size.x + EDGE_PX), y)
		y += node.size.y + GAP_PX * _scale()
	if left:  # nur wenn Platz frei wurde: ein Versuch baut die Karte, das ist nicht jedes Bild nötig
		_admit()
	if _cards.is_empty() and _waiting.is_empty():
		set_process(false)


## Wartende Funde aufnehmen, solange es Platz gibt: höchstens MAX_CARDS, und die Karte muss unter die anderen in die
## Fläche passen (die erste immer).
func _admit() -> void:
	while not _waiting.is_empty() and _cards.size() < MAX_CARDS:
		var area := column()
		var node := _build(_waiting[0], area.size.x)
		add_child(node)
		node.size = node.get_combined_minimum_size()
		var used := 0.0
		for card in _cards:
			used += (card["node"] as Control).size.y + GAP_PX * _scale()
		if not _cards.is_empty() and used + node.size.y > area.size.y:
			node.free()
			return
		_cards.append({"node": node, "item": _waiting.pop_front(), "age": 0.0})
		node.position = Vector2(area.end.x + EDGE_PX, area.position.y + used)
		node.modulate.a = 0.0


func _control(node_name: String) -> Control:
	return _hud.find_child(node_name, true, false) as Control if _hud != null else null


func _scale() -> float:
	return RideHud.text_scale(get_viewport_rect().size.y)


## Breite einer Karte in voller Größe.
func _full_width() -> float:
	return _chrome(maxf(MIN_ICON_PX, roundf(ICON_PX * _scale()))) + _full_text_width()


## Textbreite in voller Größe: mit der Schrift skaliert, aber nie schmaler als die kleinste Schrift braucht.
func _full_text_width() -> float:
	return maxf(TEXT_PX * _scale(), MIN_FULL_TEXT_PX)


## Breite von Symbol, Rand, Innenabstand und Lücke einer Karte ohne Text (Symbol `icon_px`).
func _chrome(icon_px: float) -> float:
	var s := _scale()
	return icon_px + (2.0 * PAD_PX + GAP_PX) * s + maxf(4.0, roundf(6.0 * s)) + 2.0


## Karte für `item`, höchstens `max_width` breit (schmaler: kleineres Symbol und Schrift, Name in zwei Zeilen).
func _build(item: Dictionary, max_width: float) -> PanelContainer:
	var s := _scale()
	var color := Loot.color_of(str(item.get("rarity", "")))
	var compact := max_width < _full_width() - 0.5
	var icon_px := MIN_ICON_PX if compact else maxf(MIN_ICON_PX, roundf(ICON_PX * s))
	var name_px := MIN_NAME_FONT_PX if compact else maxi(MIN_NAME_FONT_PX, roundi(NAME_FONT_PX * s))
	var line_px := MIN_LINE_FONT_PX if compact else maxi(MIN_LINE_FONT_PX, roundi(LINE_FONT_PX * s))
	var text_px := clampf(max_width - _chrome(icon_px), MIN_TEXT_PX, _full_text_width())
	var card := PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD
	style.border_color = color.darkened(0.15)
	style.set_border_width_all(2)
	style.border_width_left = maxi(4, roundi(6.0 * s))
	style.set_corner_radius_all(roundi(8.0 * s))
	style.set_content_margin_all(roundi(PAD_PX * s))
	style.shadow_color = Color(color, 0.35 if item.get("rarity") == Loot.LEGENDARY else 0.18)
	style.shadow_size = roundi(10.0 * s)
	card.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(GAP_PX * s))
	card.add_child(row)
	var icon := ItemIconView.of_item(item, icon_px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	_line(text, "Name", Loot.item_name(item), color, name_px, text_px)
	var kind := str(Loot.RARITIES.get(item.get("rarity"), Loot.RARITIES[Loot.COMMON])["name"])
	if Loot.effect_name(item) != "":
		kind += " · " + Loot.effect_name(item)
	_line(text, "Rarity", kind, color.lightened(0.25), line_px, text_px)
	for part in Loot.stats_text(item).split(" · ", false):
		_line(text, "Stat", part, COLOR_STATS, line_px, text_px)
	return card


## Eine Textzeile in `width`; ist sie (mit der echten Schrift gemessen) breiter, bricht sie um und hält die Höhe für die
## Zeilen vor, nie mehr als zwei – bleibt der Rest, kürzt „…“.
func _line(parent: Control, node_name: String, content: String, color: Color, px: int, width: float) -> void:
	var label := Label.new()
	label.name = node_name
	label.text = content
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.custom_minimum_size.x = roundf(width)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	var font := label.get_theme_font("font")
	if font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		label.custom_minimum_size.y = ceilf(font.get_height(px)) * 2.0
	parent.add_child(label)
