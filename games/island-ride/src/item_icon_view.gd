## Fertiges Ausrüstungssymbol (#83) für Charakterblatt, Inventarliste, Vergleich (#68/#49) und Beute-Einblendung: das
## Bild aus ItemIcons auf einem Hintergrund in der Seltenheitsfarbe, mit Rahmen in derselben Farbe (Loot.color_of);
## legendäre Teile leuchten (weicher Schein um den Rahmen, der langsam pulsiert, und ein Schimmer, der über das Bild
## zieht), solange `ItemIcons.glow_enabled` an ist – der Schalter wirkt auch auf schon gezeigte Symbole. Ein leerer
## Platz zeigt die graue Silhouette seiner Grundform auf dunklem Grund. Im Browser (Compatibility-Renderer) gleich, nur
## das 3D-Bild ohne MSAA.
##
## Gebrauch – nichts selbst rendern, nur einfügen:
##   var icon := ItemIconView.of_item(item, 96.0)   # Teil (mit oder ohne `id`), Kantenlänge in px
##   var empty := ItemIconView.of_slot("helm", 64.0) # leerer Platz
##   icon.show_item(other) / icon.show_empty("helm") # Inhalt wechseln; icon.icon_size = 128.0 – Größe wechseln
## Quadratisch mit `custom_minimum_size` = Kantenlänge, ohne feste Position; in Containern mittig (`SIZE_SHRINK_CENTER`,
## überschreibbar). Lässt die Maus durch (`MOUSE_FILTER_IGNORE`): für Klicks einen Button darumlegen.
class_name ItemIconView
extends PanelContainer

## Dauer eines Leucht-Zyklus (s): der Schimmer zieht im ersten Teil (SHIMMER_SHARE) über das Bild, der Schein pulsiert.
const GLOW_CYCLE_S := 2.8
const SHIMMER_SHARE := 0.45
## Rahmen und Grund eines leeren Platzes.
const EMPTY_BORDER := Color(0.36, 0.37, 0.4)
const EMPTY_BACKGROUND := Color(0.13, 0.14, 0.16)

## Kantenlänge (px).
var icon_size := 96.0:
	set = set_icon_size
## Gezeigtes Teil ({} = leerer Platz) und sein Platz.
var item := {}
var slot := ""

var _style: StyleBoxFlat
var _backdrop: TextureRect
var _image: TextureRect
var _shimmer: TextureRect
var _glowing := false
var _time := 0.0


## Symbol für `item` in `size` px.
static func of_item(shown: Dictionary, size: float = 96.0) -> ItemIconView:
	var view := ItemIconView.new()
	view.icon_size = size
	view.show_item(shown)
	return view


## Leerer Platz `slot_id` (graue Silhouette) in `size` px.
static func of_slot(slot_id: String, size: float = 96.0) -> ItemIconView:
	var view := ItemIconView.new()
	view.icon_size = size
	view.show_empty(slot_id)
	return view


func _init() -> void:
	name = "ItemIcon"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style = StyleBoxFlat.new()
	add_theme_stylebox_override("panel", _style)
	var stack := Control.new()
	stack.name = "Stack"
	stack.clip_contents = true
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	_backdrop = _layer(stack, "Backdrop")
	_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_image = _layer(stack, "Image")
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shimmer = TextureRect.new()
	_shimmer.name = "Shimmer"
	_shimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shimmer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shimmer.stretch_mode = TextureRect.STRETCH_SCALE
	_shimmer.texture = ItemIcons.shimmer_texture()
	_shimmer.rotation = 0.35
	_shimmer.visible = false
	stack.add_child(_shimmer)
	set_icon_size(icon_size)


func set_icon_size(px: float) -> void:
	icon_size = px
	custom_minimum_size = Vector2(px, px)
	var border := maxi(2, roundi(px / 36.0))
	_style.set_border_width_all(border)
	_style.set_content_margin_all(border)
	_style.set_corner_radius_all(maxi(3, roundi(px / 14.0)))
	_style.shadow_size = _glow_size() if _glowing else 0


## Zeigt `shown` (Loot-Teil): Bild, Hintergrund und Rahmen in der Seltenheitsfarbe, Leuchten bei „legendär“.
func show_item(shown: Dictionary) -> void:
	item = shown
	slot = str(shown.get("slot", ""))
	var color := Loot.color_of(str(shown.get("rarity", "")))
	_image.texture = ItemIcons.texture_for(shown)
	_backdrop.texture = ItemIcons.backdrop_for(str(shown.get("rarity", "")))
	_style.bg_color = color.darkened(0.8)
	_style.border_color = color
	_update_glow()


## Zeigt den leeren Platz `slot_id`: graue Silhouette, grauer Rahmen, kein Leuchten.
func show_empty(slot_id: String) -> void:
	item = {}
	slot = slot_id
	_image.texture = ItemIcons.silhouette_for(slot_id)
	_backdrop.texture = null
	_style.bg_color = EMPTY_BACKGROUND
	_style.border_color = EMPTY_BORDER
	_update_glow()


func is_empty() -> bool:
	return item.is_empty()


## Leuchtet das Symbol gerade (legendär und `ItemIcons.glow_enabled`)?
func is_glowing() -> bool:
	return _glowing


## Farbe von Rahmen bzw. Bild (für Tests und Nachbarn, z. B. den Namen in derselben Farbe).
func frame_color() -> Color:
	return _style.border_color


func texture() -> Texture2D:
	return _image.texture


func _process(delta: float) -> void:
	if _wants_glow() != _glowing:
		_update_glow()
	if not _glowing:
		return
	_time = fmod(_time + delta, GLOW_CYCLE_S)
	var phase := _time / GLOW_CYCLE_S
	_style.shadow_color = Color(_style.border_color, 0.45 + 0.25 * sin(phase * TAU))
	var area := (_shimmer.get_parent() as Control).size
	_shimmer.size = Vector2(area.x * 0.4, area.y * 1.6)
	var sweep := clampf(phase / SHIMMER_SHARE, 0.0, 1.0)
	_shimmer.position = Vector2(lerpf(-area.x * 0.6, area.x * 1.1, sweep), -area.y * 0.3)
	_shimmer.visible = sweep < 1.0


func _wants_glow() -> bool:
	return ItemIcons.glow_enabled and item.get("rarity") == Loot.LEGENDARY


func _update_glow() -> void:
	_glowing = _wants_glow()
	_style.shadow_size = _glow_size() if _glowing else 0
	_style.shadow_color = Color(_style.border_color, 0.55)
	_shimmer.visible = _glowing
	_time = 0.0


func _glow_size() -> int:
	return maxi(4, roundi(icon_size / 12.0))


static func _layer(parent: Control, node_name: String) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = node_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(layer)
	return layer
