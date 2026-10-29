# Task-first navigation for the offline writing edition of Arrow.
extends PanelContainer

const Look = preload("res://scripts/editor/writing_style.gd")

const KINDS = ["主线", "支线"]
const STATUSES = ["构思", "写作中", "待修订", "完成"]
const PANEL_WIDTH = 320.0

var Main
var task_tree:Tree
var search:LineEdit
var details:Label
var open_path:Label
var edit_task_button:Button
var remove_task_button:Button
var new_scene_button:Button
var rename_scene_button:Button
var move_scene_button:Button
var task_dialog:ConfirmationDialog
var task_name:LineEdit
var task_kind:OptionButton
var task_status:OptionButton
var task_summary:TextEdit
var task_prerequisites:TextEdit
var task_outcomes:TextEdit
var scene_dialog:ConfirmationDialog
var scene_name:LineEdit
var move_dialog:ConfirmationDialog
var move_target:OptionButton
var remove_dialog:ConfirmationDialog
var selected_task:String = ""
var selected_scene:int = -1
var editing_task:String = ""
var editing_scene:int = -1
var scene_target_task:String = ""
var moving_scene:int = -1
var removing_task:String = ""
var refresh_pending:bool = false
var tree_items:Dictionary = {}
var collapsed_tasks:Dictionary = {}
var collapsed_groups:Dictionary = {}
var tabs:TabContainer
var library
var versions
var panel_sections:VBoxContainer
var details_scroll:ScrollContainer

func _ready() -> void:
	Main = get_tree().root.get_node("Main")
	name = "WritingWorkspace"
	set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	offset_right = PANEL_WIDTH
	_build_panel()
	_build_dialogs()
	Main.Mind.writing_workspace_changed.connect(queue_refresh)
	refresh()

func _label(text:String, parent:Node) -> Label:
	var label = Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _button(text:String, parent:Node, action:Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.add_theme_constant_override("h_separation", 6)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _build_panel() -> void:
	var margin = MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 4)
	add_child(margin)
	panel_sections = VBoxContainer.new()
	margin.add_child(panel_sections)
	var scroll_content = ScrollContainer.new()
	scroll_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_sections.add_child(scroll_content)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_child(tabs)
	var column = VBoxContainer.new()
	column.name = "任务"
	column.add_theme_constant_override("separation", 8)
	tabs.add_child(column)
	open_path = _label("", column)
	open_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	open_path.add_theme_font_size_override("font_size", 12)
	open_path.add_theme_color_override("font_color", Look.MUTED)
	search = LineEdit.new()
	search.placeholder_text = "搜索任务、概要或场景名"
	search.clear_button_enabled = true
	column.add_child(search)
	search.text_changed.connect(func(_text): queue_refresh())
	var create_row = HBoxContainer.new()
	column.add_child(create_row)
	_button("主线", create_row, _edit_task.bind("", "主线")).icon = Look.icon("main", Color(Look.COLORS.main))
	_button("支线", create_row, _edit_task.bind("", "支线")).icon = Look.icon("side", Color(Look.COLORS.side))
	task_tree = Tree.new()
	task_tree.hide_root = true
	task_tree.columns = 2
	task_tree.set_column_expand(1, false)
	task_tree.set_column_custom_minimum_width(1, 60)
	task_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	task_tree.custom_minimum_size = Vector2(0, 140)
	column.add_child(task_tree)
	task_tree.item_selected.connect(_on_selected)
	task_tree.item_activated.connect(_on_activated)
	task_tree.item_collapsed.connect(_on_collapsed)
	var scene_row = HBoxContainer.new()
	column.add_child(scene_row)
	new_scene_button = _button("＋场景", scene_row, _new_scene)
	rename_scene_button = _button("改名", scene_row, _rename_scene)
	move_scene_button = _button("移动", scene_row, _move_scene)
	var task_row = HBoxContainer.new()
	column.add_child(task_row)
	edit_task_button = _button("任务设定", task_row, func(): _edit_task(selected_task))
	edit_task_button.icon = Look.icon("edit")
	remove_task_button = _button("移除…", task_row, _confirm_remove_task)
	var details_toggle = _button("任务概要与关联", column, func(): details_scroll.visible = not details_scroll.visible)
	details_toggle.flat = true
	details_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	details_toggle.icon = Look.icon("content")
	details_toggle.tooltip_text = "展开或收起任务概要，完整设定可在“任务设定”中编辑"
	details_scroll = ScrollContainer.new()
	details_scroll.custom_minimum_size.y = 130
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.hide()
	column.add_child(details_scroll)
	details = _label("", details_scroll)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var shortcuts = HBoxContainer.new()
	column.add_child(shortcuts)
	_button("人物", shortcuts, _show_inspector.bind("Characters"))
	_button("正文", shortcuts, _show_inspector.bind("Node"))
	_button("项目", shortcuts, _show_inspector.bind("Project"))
	_button("专注", shortcuts, _expand_inspector)
	_label("单击选中 · 双击场景进入画布", column).add_theme_font_size_override("font_size", 12)
	library = preload("res://scripts/editor/writing_library.gd").new()
	library.name = "设定"
	library.workspace = self
	tabs.add_child(library)
	versions = preload("res://scripts/editor/writing_versions.gd").new()
	versions.name = "版本"
	versions.workspace = self
	tabs.add_child(versions)
	for index in range(tabs.get_tab_count()):
		tabs.set_tab_icon(index, Look.icon(["main", "book", "history"][index]))

func _dialog(title_text:String, dialog_size:Vector2i) -> ConfirmationDialog:
	var dialog = ConfirmationDialog.new()
	dialog.title = title_text
	dialog.min_size = dialog_size
	dialog.ok_button_text = "保存"
	dialog.cancel_button_text = "取消"
	# Main's graph shortcuts must not receive typing in a modal dialog.
	dialog.exclusive = true
	add_child(dialog)
	return dialog

func _line(caption:String, parent:Node) -> LineEdit:
	_label(caption, parent)
	var line = LineEdit.new()
	parent.add_child(line)
	return line

func _text(caption:String, parent:Node) -> TextEdit:
	_label(caption, parent)
	var edit = TextEdit.new()
	edit.custom_minimum_size.y = 72
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(edit)
	return edit

func _build_dialogs() -> void:
	task_dialog = _dialog("任务设定", Vector2i(580, 590))
	var form = VBoxContainer.new()
	task_dialog.add_child(form)
	task_name = _line("任务名称", form)
	var row = HBoxContainer.new()
	form.add_child(row)
	_label("类型", row)
	task_kind = OptionButton.new()
	for kind in KINDS:
		task_kind.add_item(kind)
	row.add_child(task_kind)
	_label("进度", row)
	task_status = OptionButton.new()
	for status in STATUSES:
		task_status.add_item(status)
	row.add_child(task_status)
	task_summary = _text("概要与戏剧冲突", form)
	task_prerequisites = _text("前置条件（玩家已做什么、人物已知什么）", form)
	task_outcomes = _text("结果与后续影响（分支分别记录）", form)
	task_name.text_changed.connect(func(value): task_dialog.get_ok_button().disabled = value.strip_edges().is_empty())
	task_dialog.confirmed.connect(_save_task)
	scene_dialog = _dialog("场景名称", Vector2i(460, 130))
	var scene_form = VBoxContainer.new()
	scene_dialog.add_child(scene_form)
	scene_name = _line("名称", scene_form)
	scene_name.text_changed.connect(func(value): scene_dialog.get_ok_button().disabled = value.strip_edges().is_empty())
	scene_name.text_submitted.connect(func(_value):
		if not scene_dialog.get_ok_button().disabled:
			_save_scene()
			scene_dialog.hide())
	scene_dialog.confirmed.connect(_save_scene)
	move_dialog = _dialog("移动场景", Vector2i(460, 150))
	var move_form = VBoxContainer.new()
	move_dialog.add_child(move_form)
	_label("选择归属任务（场景内容和连线保留）", move_form)
	move_target = OptionButton.new()
	move_form.add_child(move_target)
	move_dialog.confirmed.connect(_save_move)
	remove_dialog = _dialog("移除任务分组", Vector2i(460, 170))
	remove_dialog.ok_button_text = "移除分组，保留场景"
	remove_dialog.confirmed.connect(func():
		Main.Mind.central_event_dispatcher("writing_task_remove", removing_task)
		selected_task = "")

func queue_refresh() -> void:
	if not refresh_pending:
		refresh_pending = true
		call_deferred("refresh")

func _scene_task(scene:Dictionary, tasks:Dictionary) -> String:
	var task_id:String = scene.get("writing_task", "")
	return task_id if tasks.has(task_id) else ""

func refresh() -> void:
	refresh_pending = false
	var tasks:Dictionary = Main.Mind.get_writing_tasks()
	var scenes:Dictionary = Main.Mind.get_writing_scenes()
	var query = search.text.strip_edges()
	var current_scene:int = Main.Mind.get_current_open_scene_id()
	var selection_key = "scene:%s" % selected_scene if selected_scene >= 0 else "task:" + selected_task
	task_tree.clear()
	tree_items.clear()
	var root = task_tree.create_item()
	var scenes_by_task:Dictionary = {"": []}
	for task_id in tasks:
		scenes_by_task[task_id] = []
	for scene_id in scenes:
		scenes_by_task[_scene_task(scenes[scene_id], tasks)].append(scene_id)
	for kind in KINDS:
		var group = task_tree.create_item(root)
		group.set_text(0, kind)
		group.set_icon(0, Look.icon("main" if kind == "主线" else "side", Color(Look.COLORS.main if kind == "主线" else Look.COLORS.side)))
		group.set_custom_color(0, Look.MUTED)
		group.set_custom_font_size(0, 12)
		group.set_selectable(0, false)
		group.set_selectable(1, false)
		group.set_metadata(0, {"task": "", "scene": -1, "group": kind})
		group.collapsed = collapsed_groups.get(kind, false) and query.is_empty()
		for task_id in tasks:
			var task:Dictionary = tasks[task_id]
			if task.kind != kind:
				continue
			var matching_scenes:Array = []
			var task_matches:bool = query.is_empty() or (task.name + " " + task.summary).containsn(query)
			for scene_id in scenes_by_task[task_id]:
				if task_matches or scenes[scene_id].name.containsn(query):
					matching_scenes.append(scene_id)
			if not task_matches and matching_scenes.is_empty():
				continue
			var item = task_tree.create_item(group)
			item.set_text(0, task.name)
			item.set_text(1, task.status)
			item.set_custom_color(1, Color("7dcbb0") if task.status == "完成" else Look.MUTED)
			item.set_custom_font_size(1, 12)
			item.set_selectable(1, false)
			item.set_icon(0, Look.icon("folder"))
			item.set_metadata(0, {"task": task_id, "scene": -1})
			item.set_tooltip_text(0, task.summary)
			item.collapsed = collapsed_tasks.get(task_id, false) and query.is_empty()
			tree_items["task:" + task_id] = item
			for scene_id in matching_scenes:
				_add_scene_item(item, scene_id, scenes[scene_id], task_id, current_scene)
	var unassigned = task_tree.create_item(root)
	unassigned.set_text(0, "未归属任务")
	unassigned.set_icon(0, Look.icon("folder"))
	unassigned.set_custom_color(0, Look.MUTED)
	unassigned.set_selectable(1, false)
	unassigned.set_metadata(0, {"task": "", "scene": -1})
	tree_items["task:"] = unassigned
	for scene_id in scenes:
		if _scene_task(scenes[scene_id], tasks).is_empty():
			if query.is_empty() or scenes[scene_id].name.containsn(query):
				_add_scene_item(unassigned, scene_id, scenes[scene_id], "", current_scene)
	if tree_items.has(selection_key):
		tree_items[selection_key].select(0)
	elif selected_scene >= 0 and not scenes.has(selected_scene):
		selected_scene = -1
	if selected_scene >= 0 and scenes.has(selected_scene):
		selected_task = _scene_task(scenes[selected_scene], tasks)
	elif not tasks.has(selected_task):
		selected_task = ""
	var current:Dictionary = scenes.get(current_scene, {})
	var current_task:String = _scene_task(current, tasks)
	open_path.text = "当前：%s / %s" % [tasks[current_task].name if tasks.has(current_task) else "未归属", current.get("name", "宏")]
	_update_details()
	library.refresh()
	versions.refresh()

func _add_scene_item(parent:TreeItem, scene_id:int, scene:Dictionary, task_id:String, current:int) -> void:
	var item = task_tree.create_item(parent)
	item.set_text(0, scene.name)
	item.set_icon(0, Look.icon("scene", Color(Look.COLORS.scene) if scene_id == current else Look.MUTED))
	item.set_selectable(1, false)
	if scene_id == current:
		item.set_custom_color(0, Color(Look.COLORS.scene))
	item.set_metadata(0, {"task": task_id, "scene": scene_id})
	item.set_tooltip_text(0, "双击打开场景画布")
	tree_items["scene:%s" % scene_id] = item

func _on_collapsed(item:TreeItem) -> void:
	var meta = item.get_metadata(0)
	if meta is Dictionary:
		if meta.has("group"):
			collapsed_groups[meta.group] = item.collapsed
		elif meta.scene < 0 and not meta.task.is_empty():
			collapsed_tasks[meta.task] = item.collapsed

func _on_selected() -> void:
	var item = task_tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta is Dictionary:
		selected_task = meta.task
		selected_scene = meta.scene
		_update_details()
		library.refresh()

func _on_activated() -> void:
	if selected_scene >= 0:
		Main.Mind.central_event_dispatcher("switch_scene", selected_scene)
	elif not selected_task.is_empty():
		_edit_task(selected_task)

func _update_details() -> void:
	var tasks:Dictionary = Main.Mind.get_writing_tasks()
	var has_task:bool = tasks.has(selected_task)
	var locked:bool = Main.Mind._SNAPSHOT_INDEX_OF_PREVIEW >= 0
	edit_task_button.disabled = not has_task or locked
	remove_task_button.disabled = not has_task or locked
	new_scene_button.disabled = locked
	rename_scene_button.disabled = selected_scene < 0 or locked
	move_scene_button.disabled = selected_scene < 0 or locked
	if has_task:
		var task:Dictionary = tasks[selected_task]
		details.text = "%s · %s\n\n%s\n\n前置条件\n%s\n\n结果与后续影响\n%s" % [task.kind, task.status, task.summary, task.prerequisites, task.outcomes]
		var related:Array[String] = []
		for entry in Main.Mind.get_writing_lore().values():
			if entry.tasks.has(selected_task) or (selected_scene >= 0 and entry.scenes.has(selected_scene)):
				related.append("%s：%s" % [entry.kind, library.entry_name(entry)])
		if not related.is_empty():
			details.text += "\n\n关联设定\n" + "\n".join(related)
	else:
		details.text = "从主线或支线开始组织任务。\n\n已有场景保留在“未归属任务”，可选中后移动到任务中。\n\n任务设定用于记录冲突、前置条件和分支影响。"

func _edit_task(task_id:String, initial_kind:String = "主线") -> void:
	if Main.Mind._SNAPSHOT_INDEX_OF_PREVIEW >= 0:
		return
	editing_task = task_id
	var task:Dictionary = Main.Mind.get_writing_tasks().get(task_id, {})
	task_name.text = task.get("name", "")
	task_kind.select(KINDS.find(task.get("kind", initial_kind)))
	task_status.select(STATUSES.find(task.get("status", "构思")))
	task_summary.text = task.get("summary", "")
	task_prerequisites.text = task.get("prerequisites", "")
	task_outcomes.text = task.get("outcomes", "")
	task_dialog.get_ok_button().disabled = task_name.text.strip_edges().is_empty()
	task_dialog.popup_centered()
	task_name.grab_focus()

func _save_task() -> void:
	Main.Mind.central_event_dispatcher("writing_task_save", {
		"id": editing_task, "name": task_name.text,
		"kind": task_kind.get_item_text(task_kind.selected),
		"status": task_status.get_item_text(task_status.selected),
		"summary": task_summary.text, "prerequisites": task_prerequisites.text,
		"outcomes": task_outcomes.text,
	})
	# The newest task is appended to the dictionary, including after a save/load.
	if editing_task.is_empty():
		selected_task = Main.Mind.get_writing_tasks().keys().back()
	else:
		selected_task = editing_task
	selected_scene = -1
	search.clear()
	queue_refresh()

func _new_scene() -> void:
	editing_scene = -1
	scene_target_task = selected_task
	scene_name.text = ""
	scene_dialog.title = "新建场景 · " + Main.Mind.get_writing_tasks().get(selected_task, {"name": "未归属任务"}).name
	scene_dialog.get_ok_button().disabled = true
	scene_dialog.popup_centered()
	scene_name.grab_focus()

func _rename_scene() -> void:
	editing_scene = selected_scene
	scene_name.text = Main.Mind.lookup_resource(selected_scene, "scenes", false).name
	scene_dialog.title = "场景改名"
	scene_dialog.get_ok_button().disabled = false
	scene_dialog.popup_centered()
	scene_name.grab_focus()

func _save_scene() -> void:
	if editing_scene < 0:
		Main.Mind.central_event_dispatcher("writing_scene_create", {"name": scene_name.text, "task_id": scene_target_task})
		selected_scene = Main.Mind.get_current_open_scene_id()
	else:
		var name_text = scene_name.text.strip_edges()
		var current:Dictionary = Main.Mind.lookup_resource(editing_scene, "scenes", false)
		while name_text != current.name and Main.Mind.is_resource_name_duplicate(name_text, "scenes"):
			name_text += Settings.REUSED_SCENE_OR_MACRO_NAMES_AUTO_POSTFIX
		Main.Mind.central_event_dispatcher("update_resource", {"id": editing_scene, "field": "scenes", "modification": {"name": name_text}})
	search.clear()
	queue_refresh()

func _move_scene() -> void:
	moving_scene = selected_scene
	move_target.clear()
	move_target.add_item("未归属任务")
	move_target.set_item_metadata(0, "")
	var tasks:Dictionary = Main.Mind.get_writing_tasks()
	for task_id in tasks:
		move_target.add_item("%s / %s" % [tasks[task_id].kind, tasks[task_id].name])
		move_target.set_item_metadata(move_target.item_count - 1, task_id)
		if task_id == selected_task:
			move_target.select(move_target.item_count - 1)
	move_dialog.popup_centered()

func _save_move() -> void:
	selected_task = move_target.get_item_metadata(move_target.selected)
	Main.Mind.central_event_dispatcher("writing_scene_move", {"scene_id": moving_scene, "task_id": selected_task})
	queue_refresh()

func _confirm_remove_task() -> void:
	removing_task = selected_task
	remove_dialog.dialog_text = "移除“%s”的任务分组？\n其中的场景和对白会保留在“未归属任务”。\n可用撤销恢复。" % Main.Mind.get_writing_tasks()[selected_task].name
	remove_dialog.popup_centered()

func _show_inspector(tab:String) -> void:
	Main.UI.set_panel_visibility("inspector", true)
	Main.Mind.Inspector.show_tab_of_title(tab)

func _expand_inspector() -> void:
	Main.DockLayout.toggle_maximize("inspector")
