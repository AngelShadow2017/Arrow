# Persistent, named project versions. Stored beside the user's project file.
extends VBoxContainer

var workspace
var version_name:LineEdit
var versions:ItemList
var status:Label
var compare_button:Button
var restore_button:Button
var preview:AcceptDialog
var comparison:TextEdit
var confirmation:ConfirmationDialog
var restore_path:String = ""
var listed_directory:String = ""
var listed_files:PackedStringArray = []

func _ready() -> void:
	workspace._label("命名版本", self).add_theme_font_size_override("font_size", 20)
	status = workspace._label("", self)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	version_name = LineEdit.new()
	version_name.placeholder_text = "例如：第一章对白修订前"
	add_child(version_name)
	workspace._button("保存当前内容为版本", self, _create)
	versions = ItemList.new()
	versions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(versions)
	versions.item_selected.connect(func(_index): _update_buttons())
	versions.item_activated.connect(func(_index): _compare())
	compare_button = workspace._button("查看与当前内容的差异", self, _compare)
	restore_button = workspace._button("恢复选中版本…", self, _confirm_restore)
	var help = workspace._label("命名版本保存在项目文件旁，重启后仍可使用。\n\n恢复前自动保留当前内容。\n\n撤销 / 重做是另外的会话历史，默认保留 50 步。", self)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview = AcceptDialog.new()
	preview.title = "正文与设定差异 · 版本 → 当前"
	preview.min_size = Vector2i(900, 650)
	preview.ok_button_text = "关闭"
	preview.exclusive = true
	add_child(preview)
	comparison = TextEdit.new()
	comparison.editable = false
	comparison.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	preview.add_child(comparison)
	confirmation = workspace._dialog("恢复命名版本", Vector2i(500, 180))
	confirmation.ok_button_text = "备份当前内容并恢复"
	confirmation.dialog_text = "当前内容会先保存为一个自动备份版本。\n随后恢复选中版本并保存到当前项目。\n任务、资料、节点和连线一起恢复。"
	confirmation.confirmed.connect(_restore)

func _directory() -> String:
	var manager = workspace.Main.Mind.ProMan
	if not manager.is_project_listed():
		return ""
	return manager.get_project_file_path(manager.get_active_project_id()) + ".versions"

func refresh() -> void:
	var directory = _directory()
	var saved:bool = workspace.Main.Mind.ProMan.is_project_saved()
	status.text = ("所有修改已保存。" if saved else "有未保存修改。") + "\n命名项目每 30 秒自动保存一次。"
	if directory.is_empty():
		status.text = "请先在任务页保存并命名项目，之后即可创建持久版本。"
	var files:PackedStringArray = DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	files.sort()
	files.reverse()
	if directory != listed_directory or files != listed_files:
		versions.clear()
		for filename in files:
			if not filename.ends_with(".json"):
				continue
			var path = directory.path_join(filename)
			var data:Dictionary = _read(path)
			if not data.is_empty():
				versions.add_item("%s\n%s UTC" % [data.label, data.created_utc])
				versions.set_item_metadata(versions.item_count - 1, path)
		listed_directory = directory
		listed_files = files
	_update_buttons()

func _update_buttons() -> void:
	var disabled:bool = versions.get_selected_items().is_empty()
	compare_button.disabled = disabled
	restore_button.disabled = disabled or workspace.Main.Mind._SNAPSHOT_INDEX_OF_PREVIEW >= 0

func _error(message:String) -> void:
	push_error(message)
	workspace.Main.Mind.show_error("版本操作失败", message)

func _read(path:String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error("无法读取版本：%s\n%s" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var parser = JSON.new()
	var error = parser.parse(file.get_as_text())
	file.close()
	if error != OK:
		_error("版本 JSON 无效：%s\n第 %s 行：%s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	var data = parser.data
	if not data is Dictionary or not data.has_all(["label", "created_utc", "project"]):
		_error("版本结构无效：" + path)
		return {}
	data.project = workspace.Main.Mind.ProMan.refactor_parsed_json_project_data(data.project)
	if not workspace.Main.Mind.ProMan.validate_project_data(data.project):
		_error("版本内的剧本未通过 Arrow 项目校验：" + path)
		return {}
	return data

func save_version(label_text:String) -> String:
	var directory = _directory()
	if directory.is_empty():
		workspace.Main.Mind.save_project()
		return ""
	var error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_error("无法创建版本目录：%s\n%s" % [directory, error_string(error)])
		return ""
	var now = Time.get_datetime_string_from_system(true)
	var filename = "%s_%s.json" % [now.replace(":", "-").replace("T", "_"), Time.get_ticks_usec()]
	var path = directory.path_join(filename)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_error("无法写入版本：%s\n%s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	var mind = workspace.Main.Mind
	var data = {"label": label_text, "created_utc": now, "project": mind._PROJECT.duplicate(true), "open_scene": mind.get_current_open_scene_id(), "view": mind.get_current_view_state()}
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		_error("版本写入未完成：%s\n%s" % [path, error_string(error)])
		return ""
	refresh()
	return path

func _create() -> void:
	var label_text = version_name.text.strip_edges()
	if label_text.is_empty():
		label_text = "手动版本"
	if not save_version(label_text).is_empty():
		version_name.clear()

func _selected_path() -> String:
	var selection = versions.get_selected_items()
	return versions.get_item_metadata(selection[0]) if not selection.is_empty() else ""

func _compare() -> void:
	var data = _read(_selected_path())
	if data.is_empty():
		return
	comparison.text = compare_projects(data.project, workspace.Main.Mind._PROJECT)
	preview.popup_centered()

func _confirm_restore() -> void:
	restore_path = _selected_path()
	confirmation.popup_centered()

func _restore() -> void:
	restore_version(restore_path)

func restore_version(path:String) -> bool:
	var data = _read(path)
	if data.is_empty():
		return false
	# Restoration stops if the current content cannot first be backed up.
	if save_version("恢复前自动备份").is_empty():
		return false
	var mind = workspace.Main.Mind
	mind.load_project(data.project)
	var open_scene:int = int(data.get("open_scene", -1))
	if mind._PROJECT.resources.scenes.has(open_scene):
		mind.scene_editorial_open(open_scene, false)
		if data.has("view"):
			mind.go_to_grid_view(data.view)
	mind.reset_project_save_status(false)
	mind.save_project()
	refresh()
	return mind.ProMan.is_project_saved()

func _readable(value) -> String:
	if value is Dictionary:
		var lines:Array[String] = []
		var captions = {"name": "名称", "kind": "类别", "status": "进度", "summary": "概要", "prerequisites": "前置条件", "outcomes": "结果", "notes": "设定/备注", "facts": "已确定事实", "plans": "待定构思", "content": "正文", "title": "标题", "lines": "对白", "monolog": "独白", "options": "选项"}
		for key in value:
			if key in ["character_id", "tasks", "scenes", "character", "ref", "use", "map"]:
				continue
			lines.append("%s：%s" % [captions.get(key, key), _readable(value[key])])
		return "\n".join(lines)
	if value is Array:
		var lines:Array[String] = []
		for item in value:
			lines.append(_readable(item))
		return "\n" + "\n".join(lines)
	return str(value)

func compare_projects(previous:Dictionary, current:Dictionary) -> String:
	var result:Array[String] = []
	var datasets = [
		["任务", previous.meta.get("writing_tasks", {}), current.meta.get("writing_tasks", {})],
		["设定", previous.meta.get("writing_lore", {}), current.meta.get("writing_lore", {})],
		["人物", previous.resources.characters, current.resources.characters],
		["场景", previous.resources.scenes, current.resources.scenes],
		["节点正文", previous.resources.nodes, current.resources.nodes],
	]
	for dataset in datasets:
		var ids:Array = dataset[1].keys()
		for id in dataset[2]:
			if not ids.has(id):
				ids.append(id)
		for id in ids:
			var before:Dictionary = dataset[1].get(id, {})
			var after:Dictionary = dataset[2].get(id, {})
			# Scene layout is not prose, but membership changes still appear.
			var old_text:String = _readable(before)
			var new_text:String = _readable(after)
			if old_text != new_text:
				result.append("【%s】%s\n\n版本内容：\n%s\n\n当前内容：\n%s\n%s" % [dataset[0], after.get("name", before.get("name", "")), old_text if not before.is_empty() else "（尚不存在）", new_text if not after.is_empty() else "（已移除）", "─".repeat(36)])
	return "\n\n".join(result) if not result.is_empty() else "正文与设定未发生变化。节点位置与连线布局不在此文本比较中；恢复版本时仍会一同恢复。"
