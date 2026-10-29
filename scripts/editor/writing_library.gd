# A local setting bible, linked to stable task and scene IDs.
extends VBoxContainer

const KINDS = ["人物", "地点", "阵营", "世界规则", "事件"]
var workspace
var entries:ItemList
var search:LineEdit
var filter_related:CheckBox
var detail:TextEdit
var edit_button:Button
var remove_button:Button
var dialog:ConfirmationDialog
var entry_title:LineEdit
var kind:OptionButton
var character:OptionButton
var notes:TextEdit
var facts:TextEdit
var plans:TextEdit
var tasks:ItemList
var scenes:ItemList
var editing_id:String = ""
var remove_dialog:ConfirmationDialog
var removing_id:String = ""

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	workspace._label("人物与世界观", self).add_theme_font_size_override("font_size", 17)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、设定与事实"
	search.clear_button_enabled = true
	add_child(search)
	search.text_changed.connect(func(_value): refresh())
	filter_related = CheckBox.new()
	filter_related.text = "仅显示关联资料"
	filter_related.tooltip_text = "筛选与任务页当前选中的任务或场景关联的资料"
	add_child(filter_related)
	filter_related.toggled.connect(func(_value): refresh())
	workspace._button("新建设定", self, _edit.bind("")).icon = workspace.Look.icon("plus")
	entries = ItemList.new()
	entries.fixed_icon_size = Vector2i(18, 18)
	entries.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries.custom_minimum_size.y = 130
	add_child(entries)
	entries.item_selected.connect(func(_index): _show_detail())
	entries.item_activated.connect(func(_index): _edit(_selected()))
	var row = HBoxContainer.new()
	add_child(row)
	edit_button = workspace._button("编辑设定", row, func(): _edit(_selected()))
	remove_button = workspace._button("移除资料…", row, _remove)
	detail = TextEdit.new()
	detail.editable = false
	detail.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = 0.7
	add_child(detail)
	_build_dialog()

func _selected() -> String:
	var selection = entries.get_selected_items()
	return entries.get_item_metadata(selection[0]) if not selection.is_empty() else ""

func entry_name(entry:Dictionary) -> String:
	if entry.kind == "人物" and entry.character_id >= 0:
		var source = workspace.Main.Mind.lookup_resource(entry.character_id, "characters", false)
		if source is Dictionary:
			return source.name
	return entry.name

func refresh() -> void:
	var selected = _selected()
	entries.clear()
	var lore:Dictionary = workspace.Main.Mind.get_writing_lore()
	for entry_kind in KINDS:
		var listed_header:bool = false
		for entry_id in lore:
			var entry:Dictionary = lore[entry_id]
			if entry.kind != entry_kind:
				continue
			var relevant:bool = entry.tasks.has(workspace.selected_task) or entry.scenes.has(workspace.selected_scene)
			if filter_related.button_pressed and not relevant:
				continue
			if not search.text.is_empty() and not (entry_name(entry) + entry.notes + entry.facts + entry.plans).containsn(search.text):
				continue
			if not listed_header:
				entries.add_item(entry_kind, workspace.Look.icon(entry_kind, Color(workspace.Look.COLORS[entry_kind])))
				entries.set_item_selectable(entries.item_count - 1, false)
				entries.set_item_custom_fg_color(entries.item_count - 1, workspace.Look.MUTED)
				listed_header = true
			entries.add_item("  " + entry_name(entry), workspace.Look.icon(entry_kind, Color(workspace.Look.COLORS[entry_kind])))
			var index = entries.item_count - 1
			entries.set_item_metadata(index, entry_id)
			if entry_id == selected:
				entries.select(index)
	_show_detail()

func _show_detail() -> void:
	var entry_id = _selected()
	var locked:bool = workspace.Main.Mind._SNAPSHOT_INDEX_OF_PREVIEW >= 0
	edit_button.disabled = entry_id.is_empty() or locked
	remove_button.disabled = entry_id.is_empty() or locked
	if entry_id.is_empty():
		detail.text = "选择一项资料查看详情。\n\n将已确定事实与待定构思分开记录，可关联到任务或场景。"
		return
	var entry:Dictionary = workspace.Main.Mind.get_writing_lore()[entry_id]
	detail.text = "%s\n\n%s\n\n已确定事实\n%s\n\n待定构思\n%s" % [entry_name(entry), entry.notes, entry.facts, entry.plans]
	var task_data:Dictionary = workspace.Main.Mind.get_writing_tasks()
	var related:Array[String] = []
	for task_id in entry.tasks:
		if task_data.has(task_id):
			related.append(task_data[task_id].name)
	for scene_id in entry.scenes:
		var scene = workspace.Main.Mind.lookup_resource(scene_id, "scenes", false)
		if scene is Dictionary:
			related.append(scene.name)
	detail.text += "\n\n关联剧情\n" + "\n".join(related)

func _build_dialog() -> void:
	dialog = workspace._dialog("人物与世界观设定", Vector2i(880, 620))
	var columns = HBoxContainer.new()
	dialog.add_child(columns)
	var form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(form)
	entry_title = workspace._line("名称", form)
	kind = OptionButton.new()
	for title in KINDS:
		kind.add_item(title)
	form.add_child(kind)
	character = OptionButton.new()
	form.add_child(character)
	kind.item_selected.connect(func(index): character.visible = index == 0)
	notes = workspace._text("设定、动机与人物关系", form)
	facts = workspace._text("已确定事实（可注明适用分支与时间）", form)
	plans = workspace._text("待定构思（尚未成为正式设定）", form)
	var references = VBoxContainer.new()
	references.custom_minimum_size.x = 255
	columns.add_child(references)
	workspace._label("关联任务（可多选）", references)
	tasks = ItemList.new()
	tasks.select_mode = ItemList.SELECT_MULTI
	tasks.size_flags_vertical = Control.SIZE_EXPAND_FILL
	references.add_child(tasks)
	workspace._label("关联场景（可多选）", references)
	scenes = ItemList.new()
	scenes.select_mode = ItemList.SELECT_MULTI
	scenes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	references.add_child(scenes)
	workspace._label("Ctrl + 单击增减选择", references)
	entry_title.text_changed.connect(func(value): dialog.get_ok_button().disabled = value.strip_edges().is_empty())
	dialog.confirmed.connect(_save)
	remove_dialog = workspace._dialog("移除设定资料", Vector2i(450, 170))
	remove_dialog.dialog_text = "仅移除这条设定资料。\n关联场景、对白及原有角色资源均保留。\n可用撤销恢复。"
	remove_dialog.confirmed.connect(func(): workspace.Main.Mind.central_event_dispatcher("writing_lore_remove", removing_id))

func _edit(entry_id:String) -> void:
	if workspace.Main.Mind._SNAPSHOT_INDEX_OF_PREVIEW >= 0:
		return
	editing_id = entry_id
	var entry:Dictionary = workspace.Main.Mind.get_writing_lore().get(entry_id, {})
	entry_title.text = entry_name(entry) if not entry.is_empty() else ""
	kind.select(KINDS.find(entry.get("kind", "人物")))
	character.clear()
	character.add_item("新建角色资源")
	character.set_item_metadata(0, -1)
	# A character may have one bible entry, to keep its established facts in one place.
	var used:Array = []
	for other_id in workspace.Main.Mind.get_writing_lore():
		var other:Dictionary = workspace.Main.Mind.get_writing_lore()[other_id]
		if other_id != entry_id and other.kind == "人物":
			used.append(other.character_id)
	var characters:Dictionary = workspace.Main.Mind.clone_dataset_of("characters")
	for char_id in characters:
		if used.has(char_id):
			continue
		character.add_item("关联角色：" + characters[char_id].name)
		character.set_item_metadata(character.item_count - 1, char_id)
		if char_id == entry.get("character_id", -1):
			character.select(character.item_count - 1)
	# Keep existing character identity fixed when editing its bible entry.
	character.disabled = not entry.is_empty() and entry.get("character_id", -1) >= 0 and characters.has(entry.character_id)
	kind.disabled = not entry.is_empty()
	character.visible = kind.selected == 0
	notes.text = entry.get("notes", "")
	facts.text = entry.get("facts", "")
	plans.text = entry.get("plans", "")
	tasks.clear()
	var task_data:Dictionary = workspace.Main.Mind.get_writing_tasks()
	for task_id in task_data:
		tasks.add_item(task_data[task_id].name)
		tasks.set_item_metadata(tasks.item_count - 1, task_id)
		if entry.get("tasks", []).has(task_id) or (entry.is_empty() and workspace.selected_task == task_id):
			tasks.select(tasks.item_count - 1, false)
	scenes.clear()
	var scene_data:Dictionary = workspace.Main.Mind.get_writing_scenes()
	for scene_id in scene_data:
		scenes.add_item(scene_data[scene_id].name)
		scenes.set_item_metadata(scenes.item_count - 1, scene_id)
		if entry.get("scenes", []).has(scene_id) or (entry.is_empty() and workspace.selected_scene == scene_id):
			scenes.select(scenes.item_count - 1, false)
	dialog.get_ok_button().disabled = entry_title.text.strip_edges().is_empty()
	dialog.popup_centered()
	entry_title.grab_focus()

func _save() -> void:
	var task_ids:Array = []
	for index in tasks.get_selected_items():
		task_ids.append(tasks.get_item_metadata(index))
	var scene_ids:Array = []
	for index in scenes.get_selected_items():
		scene_ids.append(scenes.get_item_metadata(index))
	workspace.Main.Mind.central_event_dispatcher("writing_lore_save", {
		"id": editing_id, "name": entry_title.text.strip_edges(),
		"kind": KINDS[kind.selected], "character_id": character.get_item_metadata(character.selected),
		"notes": notes.text, "facts": facts.text, "plans": plans.text,
		"tasks": task_ids, "scenes": scene_ids,
	})

func _remove() -> void:
	removing_id = _selected()
	remove_dialog.popup_centered()
