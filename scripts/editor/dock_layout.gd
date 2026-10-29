# A bounded three-edge dock workspace. Original inspector/console paths stay intact.
extends Node

const Look = preload("res://scripts/editor/writing_style.gd")
const EDGES = ["left", "right", "bottom"]
const TITLES = {"workspace": "创作资源", "inspector": "属性与正文", "console": "剧情试玩"}
const GAP = 7.0
const HEADER = 36.0
const SNAP_DISTANCE = 64.0

var Main
var center:Control
var host:Control
var panels:Dictionary = {}
var states:Dictionary = {}
var groups:Dictionary = {}
var float_headers:Dictionary = {}
var float_handles:Dictionary = {}
var splitters:Dictionary = {}
var active:Dictionary = {"left": "workspace", "right": "inspector", "bottom": "console"}
var widths:Dictionary = {"left": 320.0, "right": 420.0, "bottom": 280.0}
var buttons:Dictionary = {}
var zone_rects:Dictionary = {}
var canvas_rect:Rect2
var preview:PanelContainer
var preview_label:Label
var popup:PopupMenu
var menu_panel:String = ""
var focused_panel:String = ""
var focus_canvas:bool = false
var pending:bool = false
var updating:bool = false
var drag_candidate:String = ""
var dragging:String = ""
var drag_origin:Vector2
var drag_offset:Vector2
var resizing:String = ""
var resize_origin:Rect2
var split_edge:String = ""
var drop_edge:String = ""

func _ready() -> void:
	Main = get_parent()
	center = Main.get_node("Editor/Center")
	host = Main.get_node("FloatingTools/Control")
	panels = {"workspace": Main.WritingWorkspace, "inspector": Main.Mind.Inspector, "console": Main.Mind.Console}
	Main.WritingWorkspace.reparent(host)
	states = default_states()
	restore_state(Main.Configs.CONFIRMED.get("writing_layout", {}))
	for key in panels:
		_register_panel(key)
	for edge in EDGES:
		_build_group(edge)
	_build_toolbar()
	_build_preview()
	center.resized.connect(queue_layout)
	Main.get_viewport().size_changed.connect(queue_layout)
	Main.Mind.Inspector.TheTabContainer.get_tab_bar().clip_tabs = true
	Main.Mind.Inspector.TheTabContainer.tab_changed.connect(func(_index): queue_layout())
	Main.Mind.Inspector.TheTabContainer.use_hidden_tabs_for_min_size = false
	Main.Grid.snapping_distance = 24
	queue_layout()

func default_states() -> Dictionary:
	return {
		"workspace": {"zone": "left", "open": true, "rect": [0.12, 0.08, 0.3, 0.85]},
		"inspector": {"zone": "right", "open": true, "rect": [0.4, 0.08, 0.4, 0.82]},
		"console": {"zone": "bottom", "open": false, "rect": [0.25, 0.35, 0.55, 0.55]},
	}

func restore_state(saved:Dictionary) -> void:
	# Only known panels/zones are accepted, including when loading older preferences.
	for key in states:
		var item = saved.get("panels", {}).get(key, {})
		if item.get("zone", "") in EDGES + ["floating"]:
			states[key].zone = item.zone
		if item.get("open") is bool:
			states[key].open = item.open
		var rect = item.get("rect", [])
		if rect is Array and rect.size() == 4:
			states[key].rect = rect
	for edge in EDGES:
		if saved.get("sizes", {}).get(edge) is float or saved.get("sizes", {}).get(edge) is int:
			widths[edge] = clampf(float(saved.sizes[edge]), 180.0, 900.0)
		var selected = saved.get("active", {}).get(edge, "")
		if states.has(selected):
			active[edge] = selected

func capture_state() -> Dictionary:
	return {"panels": states.duplicate(true), "sizes": widths.duplicate(), "active": active.duplicate()}

func save_layout() -> void:
	Main.Configs.save_configurations_and_confirm({"writing_layout": capture_state()}, null, false)

func _small_button(parent:Node, kind:String, hint:String, action:Callable) -> Button:
	var button = Button.new()
	button.icon = Look.icon(kind)
	button.tooltip_text = hint
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28, 28)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _register_panel(key:String) -> void:
	var panel:Control = panels[key]
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var sections:VBoxContainer
	if key == "workspace":
		sections = Main.WritingWorkspace.panel_sections
	else:
		sections = panel.get_node("Sections")
		panel.get_node("Sections/Titlebar").hide()
	var header = HBoxContainer.new()
	header.name = "FloatingTitlebar"
	sections.add_child(header)
	sections.move_child(header, 0)
	var title = Button.new()
	title.text = TITLES[key]
	title.icon = Look.icon(key, Look.ACCENT)
	title.flat = true
	title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.focus_mode = Control.FOCUS_NONE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title.tooltip_text = "拖动标题栏浮动；靠近工作区边缘停靠；双击展开或还原"
	header.add_child(title)
	title.gui_input.connect(_title_input.bind(key))
	_small_button(header, "dock", "面板停靠选项", _show_panel_menu.bind(key, title))
	_small_button(header, "maximize", "展开或还原面板", toggle_maximize.bind(key))
	_small_button(header, "close", "关闭面板，可从顶部工具栏重新打开", _request_open.bind(key, false))
	float_headers[key] = header
	var handle = Button.new()
	handle.icon = Look.icon("maximize")
	handle.tooltip_text = "拖动调整浮动面板大小"
	handle.flat = true
	handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	host.add_child(handle)
	handle.gui_input.connect(_resize_input.bind(key))
	float_handles[key] = handle

func _build_group(edge:String) -> void:
	var shell = PanelContainer.new()
	shell.name = "DockHeader_" + edge
	shell.add_theme_stylebox_override("panel", Look.box(Color("202938"), Color("303b4e"), 5, 2))
	host.add_child(shell)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	shell.add_child(row)
	var tabs = TabBar.new()
	tabs.clip_tabs = true
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size.y = HEADER - 4
	tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	row.add_child(tabs)
	groups[edge] = {"shell": shell, "tabs": tabs, "ids": []}
	tabs.tab_changed.connect(_select_group.bind(edge))
	tabs.gui_input.connect(_group_input.bind(edge))
	_small_button(row, "more", "停靠 / 浮动 / 关闭", _group_menu.bind(edge))
	_small_button(row, "maximize", "展开或还原此面板", func(): toggle_maximize(active[edge]))
	_small_button(row, "close", "关闭当前面板", func(): _request_open(active[edge], false))
	var splitter = ColorRect.new()
	splitter.name = "DockSplitter_" + edge
	splitter.color = Color("252f40")
	splitter.mouse_default_cursor_shape = Control.CURSOR_VSPLIT if edge == "bottom" else Control.CURSOR_HSPLIT
	splitter.tooltip_text = "拖动分隔线调整面板大小"
	splitter.mouse_entered.connect(func(): splitter.color = Look.ACCENT)
	splitter.mouse_exited.connect(func(): splitter.color = Color("252f40"))
	host.add_child(splitter)
	splitter.gui_input.connect(_splitter_input.bind(edge))
	splitters[edge] = splitter

func _build_toolbar() -> void:
	var bar = Main.get_node("Editor/Top/Bar")
	var row = HBoxContainer.new()
	row.name = "WorkspaceViews"
	bar.add_child(row)
	bar.move_child(row, 2)
	for key in panels:
		var button = Button.new()
		button.text = {"workspace": "资源", "inspector": "属性", "console": "试玩"}[key]
		button.icon = Look.icon(key)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
		button.pressed.connect(_toggle_panel.bind(key))
		buttons[key] = button
	var menu = MenuButton.new()
	menu.text = "布局"
	menu.icon = Look.icon("dock")
	row.add_child(menu)
	var options = menu.get_popup()
	for label in ["恢复默认布局", "专注画布", "专注正文编辑"]:
		options.add_item(label)
	options.id_pressed.connect(_preset_selected)
	var top = Main.get_node("Editor/Top")
	top.add_theme_stylebox_override("panel", Look.box(Color("171e2a"), Color("303b4e"), 0, 8))
	Main.get_node("Editor/Bottom").add_theme_stylebox_override("panel", Look.box(Color("171e2a"), Color("303b4e"), 0, 6))
	Main.get_node("Editor/Bottom/Bar/SceneTitle").add_theme_color_override("font_color", Look.MUTED)
	Main.get_node("Editor/Top/Bar/AppMenu").text = "剧情工作台"
	Main.get_node("Editor/Top/Bar/ProjectTitle").add_theme_color_override("font_color", Color("dce4f1"))
	for item in ["Undo", "Redo"]:
		Main.get_node("Editor/Top/Bar/History/Tools/" + item).icon = Look.icon(item.to_lower())
	Main.get_node("Editor/Top/Bar/Save").icon = Look.icon("save", Look.ACCENT)
	Main.get_node("Editor/Top/Bar/Play/From/ProjectEntry").icon = Look.icon("play", Look.ACCENT)

func _build_preview() -> void:
	preview = PanelContainer.new()
	preview.name = "DockDropPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override("panel", Look.box(Color(0.32, 0.52, 0.9, 0.24), Look.ACCENT, 7, 12))
	preview_label = Label.new()
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_child(preview_label)
	preview.hide()
	host.add_child(preview)
	popup = PopupMenu.new()
	for label in ["停靠到左侧", "停靠到右侧", "停靠到底部", "浮动面板", "展开 / 还原", "关闭面板"]:
		popup.add_item(label)
	popup.id_pressed.connect(_menu_selected)
	host.add_child(popup)

func _request_open(key:String, open:bool) -> void:
	if key == "workspace":
		set_panel_open(key, open)
	else:
		Main.UI.set_panel_visibility(key, open)

func _toggle_panel(key:String) -> void:
	_request_open(key, not panels[key].visible or not states[key].open)

func set_panel_open(key:String, open:bool) -> void:
	states[key].open = open
	if open:
		focus_canvas = false
		if not focused_panel.is_empty() and focused_panel != key:
			focused_panel = ""
		if states[key].zone in EDGES:
			active[states[key].zone] = key
		else:
			_raise_panel(key)
	elif focused_panel == key:
		focused_panel = ""
	queue_layout()
	save_layout()

func dock_panel(key:String, edge:String) -> void:
	assert(edge in EDGES + ["floating"])
	states[key].zone = edge
	states[key].open = true
	focused_panel = ""
	focus_canvas = false
	if edge in EDGES:
		active[edge] = key
	else:
		_raise_panel(key)
	queue_layout()
	save_layout()

func toggle_maximize(key:String) -> void:
	focus_canvas = false
	focused_panel = "" if focused_panel == key else key
	states[key].open = true
	queue_layout()

func toggle_canvas_focus() -> void:
	focused_panel = ""
	focus_canvas = not focus_canvas
	queue_layout()

func reset_layout() -> void:
	states = default_states()
	active = {"left": "workspace", "right": "inspector", "bottom": "console"}
	widths = {"left": 320.0, "right": 420.0, "bottom": 280.0}
	focused_panel = ""
	focus_canvas = false
	queue_layout()
	save_layout()

func queue_layout() -> void:
	if not pending:
		pending = true
		call_deferred("arrange")

func _area() -> Rect2:
	return center.get_global_rect().grow(-4)

func _set_rect(control:Control, rect:Rect2) -> void:
	if control.global_position != rect.position.round():
		control.global_position = rect.position.round()
	if control.size != rect.size.floor():
		control.size = rect.size.floor()

func arrange() -> void:
	pending = false
	updating = true
	var area = _area()
	if area.size.x <= 0 or area.size.y <= 0:
		updating = false
		return
	var zone_ids:Dictionary = {}
	for edge in EDGES:
		zone_ids[edge] = []
	for key in panels:
		if states[key].open and states[key].zone in EDGES:
			zone_ids[states[key].zone].append(key)
	for edge in EDGES:
		if not zone_ids[edge].has(active[edge]):
			active[edge] = zone_ids[edge][0] if not zone_ids[edge].is_empty() else ""
	var left = clampf(widths.left, 280, area.size.x * 0.33) if not zone_ids.left.is_empty() else 0.0
	var right = clampf(widths.right, 360, area.size.x * 0.42) if not zone_ids.right.is_empty() else 0.0
	var budget = area.size.x - 340 - GAP * 2
	if left + right > budget:
		var excess = left + right - budget
		left -= minf(excess * 0.4, maxf(0, left - 270))
		right = minf(right, budget - left)
	var bottom = 0.0
	if not zone_ids.bottom.is_empty():
		var minimum = panels[active.bottom].get_combined_minimum_size().y + HEADER
		bottom = minf(maxf(widths.bottom, minimum), area.size.y - 180)
	zone_rects = {
		"left": Rect2(area.position, Vector2(left, area.size.y)),
		"right": Rect2(Vector2(area.end.x - right, area.position.y), Vector2(right, area.size.y)),
		"bottom": Rect2(Vector2(area.position.x + left + (GAP if left > 0 else 0), area.end.y - bottom), Vector2(area.size.x - left - right - (GAP if left > 0 else 0) - (GAP if right > 0 else 0), bottom)),
	}
	canvas_rect = Rect2(Vector2(area.position.x + left + (GAP if left > 0 else 0), area.position.y), Vector2(zone_rects.bottom.size.x, area.size.y - bottom - (GAP if bottom > 0 else 0)))
	if focus_canvas or not focused_panel.is_empty():
		canvas_rect = area
	Main.Grid.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_set_rect(Main.Grid, canvas_rect)
	Main.Grid.visible = focused_panel.is_empty()
	var minimap = Main.get_node("Editor/Center/MiniMap")
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_set_rect(minimap, Rect2(canvas_rect.position + Vector2(16, canvas_rect.size.y - 112), Vector2(minf(210, canvas_rect.size.x * 0.28), 94)))
	minimap.visible = focused_panel.is_empty() and Settings.CLASSIC_MINIMAP_ENABLED
	for edge in EDGES:
		var group:Dictionary = groups[edge]
		var show:bool = not zone_ids[edge].is_empty() and focused_panel.is_empty() and not focus_canvas
		group.shell.visible = show
		splitters[edge].visible = show
		group.ids = zone_ids[edge]
		group.tabs.set_block_signals(true)
		group.tabs.clear_tabs()
		for key in group.ids:
			group.tabs.add_tab(TITLES[key], Look.icon(key, Look.ACCENT if active[edge] == key else Look.MUTED))
		if not group.ids.is_empty():
			group.tabs.current_tab = group.ids.find(active[edge])
		group.tabs.set_block_signals(false)
		if show:
			var rect:Rect2 = zone_rects[edge]
			_set_rect(group.shell, Rect2(rect.position, Vector2(rect.size.x, HEADER)))
			var sash = Rect2(Vector2(rect.end.x, rect.position.y), Vector2(GAP, rect.size.y))
			if edge == "right":
				sash.position.x = rect.position.x - GAP
			elif edge == "bottom":
				sash = Rect2(rect.position - Vector2(0, GAP), Vector2(rect.size.x, GAP))
			_set_rect(splitters[edge], sash)
	for key in panels:
		var state:Dictionary = states[key]
		var floating:bool = state.zone == "floating"
		var visible:bool = state.open and not focus_canvas and (focused_panel == key if not focused_panel.is_empty() else (floating or active.get(state.zone, "") == key))
		panels[key].visible = visible
		float_headers[key].visible = floating or focused_panel == key
		float_handles[key].visible = visible and floating and focused_panel.is_empty()
		buttons[key].set_pressed_no_signal(state.open)
		if visible:
			var rect:Rect2
			if focused_panel == key:
				rect = area
			elif floating:
				rect = floating_rect(key)
			else:
				rect = zone_rects[state.zone]
				rect.position.y += HEADER
				rect.size.y -= HEADER
			_set_rect(panels[key], rect)
			if floating:
				_set_rect(float_handles[key], Rect2(panels[key].get_global_rect().end - Vector2(24, 24), Vector2(24, 24)))
	Main.UI.MAIN_UI.inspector_view_toggle.set_pressed_no_signal(states.inspector.open)
	Main.Mind._CONSOLE_CURRENT_VISIBILITY = states.console.open
	for key in ["inspector", "console"]:
		if Main.UI.is_panel_open(key) != states[key].open:
			Main.UI.track_open_panels(key, states[key].open)
	updating = false

func floating_rect(key:String) -> Rect2:
	var area = _area()
	var saved:Array = states[key].rect
	var minimum:Vector2 = panels[key].get_combined_minimum_size().max(Vector2(300, 220))
	var size = Vector2(float(saved[2]), float(saved[3])) * area.size
	size = size.max(minimum).min(area.size)
	var position = area.position + Vector2(float(saved[0]), float(saved[1])) * area.size
	position.x = clampf(position.x, area.position.x, area.end.x - size.x)
	position.y = clampf(position.y, area.position.y, area.end.y - size.y)
	return Rect2(position, size)

func _store_float(key:String, rect:Rect2) -> void:
	var area = _area()
	var position = (rect.position - area.position) / area.size
	var size = rect.size / area.size
	states[key].rect = [position.x, position.y, size.x, size.y]

func _select_group(index:int, edge:String) -> void:
	if not updating and index >= 0 and index < groups[edge].ids.size():
		active[edge] = groups[edge].ids[index]
		queue_layout()
		save_layout()

func _title_input(event:InputEvent, key:String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			toggle_maximize(key)
		else:
			_seed_drag(key, event.global_position)

func _group_input(event:InputEvent, edge:String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var index:int = groups[edge].tabs.get_tab_idx_at_point(event.position)
		if index >= 0:
			var key:String = groups[edge].ids[index]
			if event.double_click:
				toggle_maximize(key)
			else:
				_seed_drag(key, event.global_position)

func _seed_drag(key:String, position:Vector2) -> void:
	drag_candidate = key
	drag_origin = position
	_raise_panel(key)

func _raise_panel(key:String) -> void:
	host.move_child(panels[key], host.get_child_count() - 1)
	host.move_child(float_handles[key], host.get_child_count() - 1)

func _resize_input(event:InputEvent, key:String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		resizing = key
		drag_origin = event.global_position
		resize_origin = panels[key].get_global_rect()

func _splitter_input(event:InputEvent, edge:String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		split_edge = edge

func drop_zone_at(position:Vector2) -> String:
	var area = _area()
	if not area.has_point(position):
		return ""
	for edge in EDGES:
		if groups[edge].shell.visible and groups[edge].shell.get_global_rect().has_point(position):
			return edge
	if position.y > area.end.y - SNAP_DISTANCE:
		return "bottom"
	if position.x < area.position.x + SNAP_DISTANCE:
		return "left"
	if position.x > area.end.x - SNAP_DISTANCE:
		return "right"
	return ""

func _input(event:InputEvent) -> void:
	if event is InputEventMouseMotion:
		var position = event.position
		if not split_edge.is_empty():
			var area = _area()
			widths[split_edge] = {"left": position.x - area.position.x, "right": area.end.x - position.x, "bottom": area.end.y - position.y}[split_edge]
			arrange()
		elif not resizing.is_empty():
			var rect = resize_origin
			rect.size += position - drag_origin
			_store_float(resizing, rect)
			arrange()
		elif not drag_candidate.is_empty():
			if dragging.is_empty() and position.distance_to(drag_origin) > 6:
				dragging = drag_candidate
				focused_panel = ""
				states[dragging].zone = "floating"
				var rect = floating_rect(dragging)
				drag_offset = Vector2(minf(rect.size.x * 0.4, 140), 18)
			if not dragging.is_empty():
				var rect = floating_rect(dragging)
				rect.position = position - drag_offset
				_store_float(dragging, rect)
				arrange()
				drop_edge = drop_zone_at(position)
				preview.visible = not drop_edge.is_empty()
				if preview.visible:
					var target = zone_rects[drop_edge]
					var area = _area()
					if target.size.x < 100 or target.size.y < 100:
						target = Rect2(Vector2(area.position.x, area.end.y - 260), Vector2(area.size.x, 260)) if drop_edge == "bottom" else Rect2(Vector2(area.position.x if drop_edge == "left" else area.end.x - 340, area.position.y), Vector2(340, area.size.y))
					_set_rect(preview, target)
					preview_label.text = "松开停靠到" + {"left": "左侧", "right": "右侧", "bottom": "底部"}[drop_edge] + " · 同一区域合并为标签"
					host.move_child(preview, host.get_child_count() - 1)
		if not dragging.is_empty() or not resizing.is_empty() or not split_edge.is_empty():
			Main.get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not dragging.is_empty():
			if not drop_edge.is_empty():
				dock_panel(dragging, drop_edge)
			else:
				save_layout()
		if not resizing.is_empty() or not split_edge.is_empty():
			save_layout()
		drag_candidate = ""
		dragging = ""
		resizing = ""
		split_edge = ""
		drop_edge = ""
		preview.hide()

func _group_menu(edge:String) -> void:
	_show_panel_menu(active[edge], groups[edge].shell)

func _show_panel_menu(key:String, source:Control) -> void:
	menu_panel = key
	popup.position = Vector2i(source.get_global_rect().position + Vector2(0, source.size.y))
	popup.popup()

func _menu_selected(id:int) -> void:
	match id:
		0, 1, 2: dock_panel(menu_panel, EDGES[id])
		3: dock_panel(menu_panel, "floating")
		4: toggle_maximize(menu_panel)
		5: _request_open(menu_panel, false)

func _preset_selected(id:int) -> void:
	match id:
		0: reset_layout()
		1: toggle_canvas_focus()
		2:
			Main.Mind.Inspector.show_tab_of_title("Node")
			toggle_maximize("inspector")
