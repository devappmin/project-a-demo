@tool
extends VBoxContainer

const SyncConfig = preload("res://tools/notion_sync/notion_sync_config.gd")
const SyncCli = preload("res://tools/notion_sync/notion_sync_cli.gd")
const Compiler = preload("res://tools/notion_sync/dialogue_compiler.gd")
const OUTPUT_DIRECTORY := "res://data/generated/dialogues"

@onready var sync_button: Button = $SyncButton
@onready var dry_run_button: Button = $DryRunButton
@onready var status_label: Label = $StatusLabel
@onready var counts_label: Label = $CountsLabel
@onready var issues: ItemList = $Issues

var _config_provider: Callable
var _sync_runner: Callable
var _scan_sources: Callable
var _source_opener: Callable
var _busy := false

func _ready() -> void:
	if not sync_button.pressed.is_connected(_on_sync_pressed):
		sync_button.pressed.connect(_on_sync_pressed)
	if not dry_run_button.pressed.is_connected(_on_dry_run_pressed):
		dry_run_button.pressed.connect(_on_dry_run_pressed)
	if not issues.item_activated.is_connected(_on_issue_activated):
		issues.item_activated.connect(_on_issue_activated)
	_set_busy(false)

func configure(config_provider: Callable = Callable(), sync_runner: Callable = Callable(), scan_sources: Callable = Callable(), source_opener: Callable = Callable()) -> void:
	_config_provider = config_provider
	_sync_runner = sync_runner
	_scan_sources = scan_sources
	_source_opener = source_opener

func is_busy() -> bool:
	return _busy

func start_sync(dry_run: bool) -> Dictionary:
	if _busy:
		return {"ok":false, "message":"A Notion dialogue sync is already active.", "issues":[], "counts":{}}
	_set_busy(true)
	status_label.text = "Notion 대화를 확인하는 중입니다…" if dry_run else "Notion 대화를 동기화하는 중입니다…"
	counts_label.text = ""
	issues.clear()
	var config: Dictionary = _config_provider.call() if _config_provider.is_valid() else SyncConfig.from_environment()
	var secrets := _secret_values(config)
	var result: Dictionary
	if not bool(config.get("ok", false)):
		result = {"ok":false, "message":String(config.get("message", "Notion sync configuration failed.")), "issues":[], "counts":{}}
	elif _sync_runner.is_valid():
		result = await _sync_runner.call(config, OUTPUT_DIRECTORY, dry_run)
	else:
		result = await SyncCli.sync(config, OUTPUT_DIRECTORY, dry_run)
	_display_result(result, dry_run, secrets)
	if bool(result.get("ok", false)) and not dry_run and _scan_sources.is_valid():
		_scan_sources.call()
	_set_busy(false)
	return result

func _display_result(result: Dictionary, dry_run: bool, secrets: PackedStringArray) -> void:
	var ok := bool(result.get("ok", false))
	var message := _redact(String(result.get("message", "")), secrets)
	if ok:
		status_label.text = "검사 완료" if dry_run else "동기화 완료"
		if not message.is_empty():
			status_label.text += "\n" + message
	else:
		status_label.text = "실패"
		if not message.is_empty():
			status_label.text += "\n" + message
	var counts: Dictionary = result.get("counts", {})
	var manifest_value: Variant = result.get("manifest", {})
	var manifest: Dictionary = manifest_value if typeof(manifest_value) == TYPE_DICTIONARY else {}
	var hash := Compiler.stable_json(manifest).sha256_text() if not manifest.is_empty() else "-"
	counts_label.text = "장면 %d · 블록 %d · 캐릭터 %d\nmanifest SHA-256: %s" % [
		int(counts.get("scenes", 0)),
		int(counts.get("blocks", 0)),
		int(counts.get("characters", 0)),
		hash
	]
	issues.clear()
	var issue_values: Variant = result.get("issues", [])
	if typeof(issue_values) != TYPE_ARRAY:
		return
	for issue_value: Variant in issue_values:
		if typeof(issue_value) != TYPE_DICTIONARY:
			continue
		var issue: Dictionary = issue_value
		var severity := String(issue.get("severity", "error"))
		var code := String(issue.get("code", "sync_failed"))
		var detail := _redact(String(issue.get("message", "")), secrets)
		var index := issues.add_item("%s [%s] %s" % [severity, code, detail])
		issues.set_item_metadata(index, String(issue.get("source_url", "")))

func _on_sync_pressed() -> void:
	await start_sync(false)

func _on_dry_run_pressed() -> void:
	await start_sync(true)

func _on_issue_activated(index: int) -> void:
	if index < 0 or index >= issues.item_count:
		return
	var url := String(issues.get_item_metadata(index))
	if (url.begins_with("https://") or url.begins_with("http://")) and _source_opener.is_valid():
		_source_opener.call(url)

func _set_busy(value: bool) -> void:
	_busy = value
	if is_instance_valid(sync_button):
		sync_button.disabled = value
	if is_instance_valid(dry_run_button):
		dry_run_button.disabled = value

func _secret_values(config: Dictionary) -> PackedStringArray:
	var values := PackedStringArray()
	for key: String in ["token", "scenes_data_source", "blocks_data_source", "characters_data_source"]:
		var value := String(config.get(key, ""))
		if not value.is_empty():
			values.append(value)
	return values

func _redact(text: String, secrets: PackedStringArray) -> String:
	var redacted := text
	for secret: String in secrets:
		redacted = redacted.replace(secret, "[REDACTED]")
	return redacted
