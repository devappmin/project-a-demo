@tool
extends EditorPlugin

const DockScene = preload("res://tools/notion_sync/notion_sync_dock.tscn")

var dock: Control
var _dock_adder: Callable
var _dock_remover: Callable
var _scan_sources_override: Callable
var _source_opener_override: Callable

func _init(dock_adder: Callable = Callable(), dock_remover: Callable = Callable(), scan_sources_override: Callable = Callable(), source_opener_override: Callable = Callable()) -> void:
	_dock_adder = dock_adder
	_dock_remover = dock_remover
	_scan_sources_override = scan_sources_override
	_source_opener_override = source_opener_override

func _enter_tree() -> void:
	if dock != null:
		return
	dock = DockScene.instantiate()
	dock.configure(Callable(), Callable(), Callable(self, "_scan_sources"), Callable(self, "_open_source_url"))
	if _dock_adder.is_valid():
		_dock_adder.call(dock)
	else:
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	print_verbose("Notion dialogue sync dock registered.")

func _exit_tree() -> void:
	if dock == null:
		return
	if _dock_remover.is_valid():
		_dock_remover.call(dock)
	else:
		remove_control_from_docks(dock)
	dock.queue_free()
	dock = null
	print_verbose("Notion dialogue sync dock removed.")

func _scan_sources() -> void:
	if _scan_sources_override.is_valid():
		_scan_sources_override.call()
		return
	var filesystem := get_editor_interface().get_resource_filesystem()
	if filesystem != null:
		filesystem.scan_sources()

func _open_source_url(url: String) -> void:
	if _source_opener_override.is_valid():
		_source_opener_override.call(url)
		return
	OS.shell_open(url)
