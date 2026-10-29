# Shared visual language for the writing workspace; icons are code-native SVGs.
extends RefCounted

const ACCENT = Color("dddddd")
const MUTED = Color("999999")
const COLORS = {"main": "dddddd", "side": "bbbbbb", "scene": "dddddd", "人物": "cccccc", "地点": "cccccc", "阵营": "cccccc", "世界规则": "cccccc", "事件": "cccccc"}
const NODE_TYPES = ["condition", "content", "dialog", "entry", "frame", "generator", "hub", "interaction", "jump", "macro_use", "marker", "monolog", "randomizer", "sequencer", "tag_edit", "tag_match", "tag_pass", "user_input", "variable_update"]
static var icons:Dictionary = {}

static func box(background:Color, border:Color = Color.TRANSPARENT, radius:int = 6, padding:int = 8) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func icon(kind:String, color:Color = MUTED) -> Texture2D:
	var key = kind + color.to_html()
	if icons.has(key):
		return icons[key]
	var paths = {
		"book": '<path d="M3 4h7l2 2 2-2h7v16h-7l-2 1-2-1H3zM12 6v15M6 8h3M15 8h3M6 12h3M15 12h3"/>',
		"main": '<path d="M5 21V3m0 1h14l-3 4 3 4H5"/>',
		"side": '<path d="M6 3v12a4 4 0 0 0 4 4h8M6 9h8a4 4 0 0 0 4-4V3m-3 13 3 3-3 3"/>',
		"scene": '<rect x="3" y="5" width="18" height="15" rx="2"/><path d="M3 10h18M7 5l3 5m4-5 3 5M9 14h6"/>',
		"人物": '<circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
		"地点": '<path d="M19 10c0 6-7 11-7 11S5 16 5 10a7 7 0 0 1 14 0Z"/><circle cx="12" cy="10" r="2"/>',
		"阵营": '<circle cx="9" cy="7" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M16 4a3 3 0 0 1 0 6m2 3a6 6 0 0 1 3 5v2"/>',
		"世界规则": '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M5 7h14M5 17h14"/>',
		"事件": '<path d="m13 2-9 12h7l-1 8 10-13h-8Z"/>',
		"history": '<path d="M3 11a9 9 0 1 1 2 7M3 4v7h7m2-4v6l4 2"/>',
		"search": '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
		"close": '<path d="m6 6 12 12M6 18 18 6"/>',
		"float": '<rect x="4" y="8" width="12" height="12" rx="2"/><path d="M9 4h11v11M20 4 10 14"/>',
		"dock": '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M15 4v16"/>',
		"maximize": '<path d="M4 9V4h5m6 0h5v5M4 15v5h5m6 0h5v-5"/>',
		"more": '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
		"grip": '<path d="M9 5v.1M15 5v.1M9 12v.1M15 12v.1M9 19v.1M15 19v.1"/>',
		"play": '<path d="m8 4 13 8-13 8Z"/>',
		"save": '<path d="M4 3h13l4 4v14H3V3h1m3 0v7h10V3M7 21v-7h10v7"/>',
		"undo": '<path d="m8 4-5 5 5 5M3 9h10a7 7 0 0 1 0 14"/>',
		"redo": '<path d="m16 4 5 5-5 5m5-5H11a7 7 0 0 0 0 14"/>',
		"plus": '<path d="M12 4v16M4 12h16"/>',
		"edit": '<path d="m4 16 12-12 4 4L8 20H4Zm10-10 4 4"/>',
		"folder": '<path d="M3 6h7l2 3h9v12H3Z"/>',
		"content": '<path d="M5 3h10l4 4v14H5ZM14 3v5h5M8 12h8M8 16h6"/>',
		"dialog": '<path d="M4 4h16v12H9l-5 4ZM8 8h8M8 12h5"/>',
		"interaction": '<path d="M4 12h7m0 0V5h8m-8 7v7h8M16 2l3 3-3 3m0 8 3 3-3 3"/>',
		"condition": '<path d="m12 2 10 10-10 10L2 12ZM12 7v5m0 4v.1"/>',
		"variable_update": '<path d="m8 5-5 7 5 7m8-14 5 7-5 7M13 3l-2 18"/>',
		"jump": '<path d="M4 20v-5a6 6 0 0 1 6-6h10m-5-5 5 5-5 5"/>',
	}
	var aliases = {"entry": "play", "monolog": "dialog", "macro_use": "book", "frame": "folder", "marker": "地点", "generator": "事件", "randomizer": "interaction", "sequencer": "side", "hub": "interaction", "tag_edit": "edit", "tag_match": "search", "tag_pass": "condition", "user_input": "edit", "inspector": "dock", "console": "play", "workspace": "book"}
	var shape:String = aliases.get(kind, kind)
	var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#%s" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [color.to_html(false), paths.get(shape, paths.content)]
	var image = Image.new()
	var error = image.load_svg_from_string(svg)
	assert(error == OK, "Invalid workspace icon: " + kind)
	var texture = ImageTexture.create_from_image(image)
	icons[key] = texture
	return texture

# Reuse the original theme's fills, borders, selection and text colors.
# Only spacing, corner geometry and typography belong to this workspace layer.
static func spaced_style(base:Theme, key:String, type:String, padding:int, radius:int = 5) -> StyleBox:
	var source:StyleBox
	if base.has_stylebox(key, type):
		source = base.get_stylebox(key, type)
	elif ThemeDB.get_default_theme().has_stylebox(key, type):
		source = ThemeDB.get_default_theme().get_stylebox(key, type)
	else:
		return null
	var style:StyleBox = source.duplicate(true)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	if style is StyleBoxFlat:
		style.set_corner_radius_all(radius)
	return style

static func make_theme(base:Theme, _light:bool = false) -> Theme:
	var theme:Theme = base.duplicate(true)
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 400
	theme.default_font = font
	theme.default_font_size = 14
	var styles = {
		"Button": ["normal", "hover", "pressed", "disabled", "focus"],
		"OptionButton": ["normal", "hover", "pressed", "disabled", "focus"],
		"MenuButton": ["normal", "hover", "pressed", "disabled", "focus"],
		"LineEdit": ["normal", "read_only", "focus"],
		"TextEdit": ["normal", "read_only", "focus"],
		"Tree": ["panel", "selected", "selected_focus", "cursor", "cursor_unfocused"],
		"ItemList": ["panel", "selected", "selected_focus", "cursor", "cursor_unfocused"],
		"TabBar": ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"],
		"TabContainer": ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"],
		"PanelContainer": ["panel"],
		"PopupMenu": ["panel", "hover"],
		"GraphNode": ["panel", "panel_selected", "titlebar", "titlebar_selected"],
		"SaveButton": ["normal", "hover", "pressed", "disabled", "focus"],
	}
	for type in styles:
		for key in styles[type]:
			var padding = 6 if type in ["Button", "OptionButton", "MenuButton"] else 8
			if type == "GraphNode":
				padding = 12 if key.begins_with("panel") else 7
			elif type == "SaveButton":
				padding = 7
			var style = spaced_style(base, key, type, padding)
			if style != null:
				theme.set_stylebox(key, type, style)
	for type in ["Button", "OptionButton", "MenuButton", "TabBar", "TabContainer"]:
		theme.set_constant("h_separation", type, 6)
	for type in ["Button", "OptionButton", "MenuButton"]:
		theme.set_constant("icon_max_width", type, 18)
	for type in ["HBoxContainer", "VBoxContainer"]:
		theme.set_constant("separation", type, 8)
	theme.set_constant("line_spacing", "TextEdit", 6)
	for type in ["Tree", "ItemList", "PopupMenu"]:
		theme.set_constant("v_separation", type, 8)
		theme.set_constant("h_separation", type, 8)
		theme.set_constant("icon_margin", type, 8)
	theme.set_constant("inner_item_margin_top", "Tree", 5)
	theme.set_constant("inner_item_margin_bottom", "Tree", 5)
	theme.set_constant("item_margin", "Tree", 18)
	theme.set_constant("draw_guides", "Tree", 1)
	theme.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	theme.set_font_size("title_font_size", "GraphNode", 13)
	for size in [1, 2, 3]:
		theme.set_font_size("font_size", "LabelH%s" % size, 20 - size * 2)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		theme.set_font_size(key, "RichTextLabelH3", 15)
	return theme
