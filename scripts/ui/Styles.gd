class_name Styles
extends RefCounted

static var click_sound := Callable()
static var hover_sound := Callable()

const INK := Color("163d40")
const CREAM := Color("fff3d9")
const MUTED := Color("a7c5bf")
const GOLD := Color("f1bc69")
const TEAL := Color("77d4c1")
const UI_ATLAS := "res://assets/art/ui/painted-ui-atlas.png"
const PAINTED_STYLE_BOX := preload("res://scripts/ui/PaintedStyleBox.gd")
const ATLAS_REGIONS := {
	"dark": Rect2(0,0,512,512), "light": Rect2(512,0,512,512),
	"banner": Rect2(1024,0,512,512), "primary": Rect2(0,512,512,512),
	"secondary": Rect2(512,512,512,512), "slot": Rect2(1024,512,512,512)
}

static func atlas_region(kind: String) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(UI_ATLAS) as Texture2D
	atlas.region = ATLAS_REGIONS.get(kind, ATLAS_REGIONS.dark)
	return atlas

static func painted_box(kind: String, margin: int = 12, tint: Color = Color.WHITE) -> StyleBox:
	var style: StyleBox = PAINTED_STYLE_BOX.new()
	style.set("texture", load(UI_ATLAS) as Texture2D)
	style.set("source_region", ATLAS_REGIONS.get(kind, ATLAS_REGIONS.dark))
	style.set("source_border", 80.0)
	style.set("target_border", margin)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.set("modulate_color", tint)
	return style

static func box(color: Color, border: Color = Color.TRANSPARENT, radius: int = 14, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Noto Sans CJK SC", "sans-serif"])
	result.default_font = font
	result.default_font_size = 16
	result.set_color("font_color", "Label", CREAM)
	# Regular wood buttons keep their pale lettering in every interactive state.
	# Gold is reserved for explicit primary actions, which receive INK lettering below.
	result.set_stylebox("normal", "Button", painted_box("secondary", 8))
	result.set_stylebox("hover", "Button", painted_box("secondary", 8, Color(1.16, 1.16, 1.08)))
	result.set_stylebox("pressed", "Button", painted_box("secondary", 8, Color(0.78, 0.82, 0.79)))
	result.set_stylebox("disabled", "Button", painted_box("secondary", 8, Color(0.42, 0.48, 0.46)))
	result.set_stylebox("focus", "Button", box(Color(0,0,0,0), GOLD, 10, 2))
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", CREAM)
	result.set_color("font_pressed_color", "Button", CREAM)
	result.set_color("font_disabled_color", "Button", Color("6f8986"))
	result.set_stylebox("normal", "LineEdit", painted_box("light", 12))
	result.set_stylebox("focus", "LineEdit", painted_box("light", 12, Color(1.08, 1.05, 0.96)))
	result.set_color("font_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", Color("6d624a"))
	result.set_stylebox("normal", "CheckBox", painted_box("slot", 10))
	result.set_stylebox("hover", "CheckBox", painted_box("slot", 10, Color(1.14, 1.14, 1.06)))
	result.set_stylebox("pressed", "CheckBox", painted_box("slot", 10, Color(0.78, 0.82, 0.79)))
	result.set_stylebox("disabled", "CheckBox", painted_box("slot", 10, Color(0.42, 0.48, 0.46)))
	result.set_stylebox("normal", "SpinBox", painted_box("light", 10))
	result.set_stylebox("normal", "OptionButton", painted_box("light", 10))
	result.set_stylebox("hover", "OptionButton", painted_box("light", 10, Color(1.08, 1.05, 0.96)))
	result.set_stylebox("pressed", "OptionButton", painted_box("light", 10, Color(0.86, 0.83, 0.75)))
	result.set_color("font_color", "OptionButton", INK)
	result.set_color("font_hover_color", "OptionButton", INK)
	result.set_color("font_pressed_color", "OptionButton", INK)
	result.set_stylebox("panel", "PopupMenu", painted_box("light", 14))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_stylebox("panel", "TooltipPanel", painted_box("dark", 10))
	var track := box(Color("102c31"), Color("42645d"), 5)
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	result.set_stylebox("background", "ProgressBar", track)
	result.set_stylebox("fill", "ProgressBar", box(TEAL, Color.TRANSPARENT, 5, 0))
	return result

static func panel(parent: Node, rect: Rect2, color: Color = Color("143b3deb"), border: Color = Color("56746d"), radius: int = 16) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	# Only scene-wide dimmers and tiny connector/tag marks stay procedural.  A
	# translucent information card should still receive the painted panel skin.
	var is_mask := (rect.size.x >= 1000 and rect.size.y >= 600) or (rect.size.x <= 20 and rect.size.y <= 20)
	var is_light := color.r > 0.7 and color.g > 0.65
	node.add_theme_stylebox_override("panel", box(color, border, radius) if is_mask else painted_box("light" if is_light else "dark", 16 if rect.size.x > 300 else 10))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.set_deferred("size", rect.size)
	return node

static func label(parent: Node, text: String, rect: Rect2, font_size: int = 18, color: Color = CREAM) -> Label:
	var node := Label.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.set_deferred("size", rect.size)
	return node

static func button(parent: Node, text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.focus_mode = Control.FOCUS_ALL
	if primary:
		node.add_theme_stylebox_override("normal", painted_box("primary", 8))
		node.add_theme_stylebox_override("hover", painted_box("primary", 8, Color(1.14, 1.10, 1.02)))
		node.add_theme_stylebox_override("pressed", painted_box("primary", 8, Color(0.80, 0.78, 0.70)))
		node.add_theme_color_override("font_color", INK)
		node.add_theme_color_override("font_hover_color", INK)
		node.add_theme_color_override("font_pressed_color", INK)
	node.pressed.connect(func():
		if click_sound.is_valid(): click_sound.call())
	node.mouse_entered.connect(func():
		if not node.disabled and hover_sound.is_valid(): hover_sound.call())
	node.pressed.connect(callback)
	parent.add_child(node)
	node.set_deferred("size", rect.size)
	return node

static func slot_button(parent: Node, rect: Rect2, callback: Callable) -> Button:
	var node := button(parent, "", rect, callback)
	node.add_theme_stylebox_override("normal", painted_box("slot", 10))
	node.add_theme_stylebox_override("hover", painted_box("slot", 10, Color(1.14, 1.14, 1.06)))
	node.add_theme_stylebox_override("pressed", painted_box("slot", 10, Color(0.78, 0.82, 0.79)))
	node.add_theme_stylebox_override("disabled", painted_box("slot", 10, Color(0.48, 0.52, 0.48)))
	return node

static func banner_button(parent: Node, text: String, rect: Rect2, callback: Callable) -> Button:
	var node := button(parent, text, rect, callback)
	node.add_theme_stylebox_override("normal", painted_box("banner", 8))
	node.add_theme_stylebox_override("hover", painted_box("banner", 8, Color(1.15, 1.15, 1.07)))
	node.add_theme_stylebox_override("pressed", painted_box("banner", 8, Color(0.78, 0.82, 0.79)))
	node.add_theme_stylebox_override("disabled", painted_box("banner", 8, Color(0.42, 0.48, 0.46)))
	node.add_theme_color_override("font_color", CREAM)
	node.add_theme_color_override("font_hover_color", CREAM)
	node.add_theme_color_override("font_pressed_color", CREAM)
	return node

static func banner(parent: Node, text: String, rect: Rect2, font_size: int = 24) -> Label:
	var node := label(parent, text, rect, font_size, CREAM)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_stylebox_override("normal", painted_box("banner", 8))
	return node

static func image(parent: Node, path: String, rect: Rect2, tint: Color = Color.WHITE) -> TextureRect:
	var node := TextureRect.new()
	node.texture = load(path) as Texture2D
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.position = rect.position
	node.size = rect.size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.modulate = tint
	parent.add_child(node)
	node.set_deferred("size", rect.size)
	return node

static func hero(parent: Node, index: int, rect: Rect2) -> TextureRect:
	var texture := load("res://assets/art/heroes.png") as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	var cell := texture.get_size() / 2.0
	atlas.region = Rect2(Vector2(index % 2, index / 2) * cell, cell)
	var node := TextureRect.new()
	node.texture = atlas
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.position = rect.position
	node.size = rect.size
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.set_deferred("size", rect.size)
	return node

static func portrait(parent: Node, index: int, rect: Rect2) -> TextureRect:
	var node := hero(parent,index,rect)
	var atlas := node.texture as AtlasTexture
	var cell := atlas.atlas.get_size()/2.0
	atlas.region = Rect2(Vector2(index%2,index/2)*cell+cell*Vector2(0.17,0.02),cell*Vector2(0.56,0.56))
	return node
