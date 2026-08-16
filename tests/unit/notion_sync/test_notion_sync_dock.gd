extends "res://tests/support/test_case.gd"

const DOCK_SCENE_PATH := "res://tools/notion_sync/notion_sync_dock.tscn"
const NotionSyncCli = preload("res://tools/notion_sync/notion_sync_cli.gd")

var _dock: Control
var _sync_calls: Array[Dictionary] = []
var _opened_urls: Array[String] = []
var _scan_count := 0
var _saw_busy_during_call := false
var _delayed_runner_count := 0
var _release_delayed_runner := false

func run() -> void:
	assert_true(ResourceLoader.exists(DOCK_SCENE_PATH, "PackedScene"), "Notion sync dock scene exists")
	if not ResourceLoader.exists(DOCK_SCENE_PATH, "PackedScene"):
		return
	var packed := load(DOCK_SCENE_PATH) as PackedScene
	assert_not_null(packed, "Notion sync dock scene loads")
	if packed == null:
		return
	_dock = packed.instantiate()
	add_child(_dock)
	await get_tree().process_frame
	_test_controls_exist()
	await _test_button_wiring_busy_state_counts_hash_and_rescan()
	_test_source_url_activation()
	await _test_dry_run_does_not_rescan()
	await _test_missing_secret_fails_closed()
	await _test_timeout_failure_restores_idle_state()
	await _test_delayed_runner_rejects_reentry()
	_dock.queue_free()
	await get_tree().process_frame

func _test_controls_exist() -> void:
	assert_not_null(_dock.get_node_or_null("SyncButton"), "dock exposes the Sync Dialogues button")
	assert_not_null(_dock.get_node_or_null("DryRunButton"), "dock exposes the Dry Run button")
	assert_not_null(_dock.get_node_or_null("StatusLabel"), "dock exposes status text")
	assert_not_null(_dock.get_node_or_null("CountsLabel"), "dock exposes page counts and manifest hash")
	assert_not_null(_dock.get_node_or_null("Issues"), "dock exposes source-linked diagnostics")

func _test_button_wiring_busy_state_counts_hash_and_rescan() -> void:
	_reset_observations()
	_dock.configure(Callable(self, "_valid_config"), Callable(self, "_successful_sync"), Callable(self, "_record_scan"), Callable(self, "_record_open"))
	var sync_button := _dock.get_node("SyncButton") as Button
	sync_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(_sync_calls.size(), 1, "Sync Dialogues invokes one sync request")
	if not _sync_calls.is_empty():
		assert_false(_sync_calls[0]["dry_run"], "Sync Dialogues requests a snapshot write")
	assert_true(_saw_busy_during_call, "dock disables both actions while a request is active")
	assert_false(_dock.is_busy(), "dock clears busy state after completion")
	assert_false(sync_button.disabled, "sync button is restored after completion")
	assert_false((_dock.get_node("DryRunButton") as Button).disabled, "dry-run button is restored after completion")
	assert_eq(_scan_count, 1, "successful write asks the editor filesystem to scan sources")
	var counts_text := (_dock.get_node("CountsLabel") as Label).text
	assert_true(counts_text.contains("2") and counts_text.contains("6") and counts_text.contains("1"), "dock displays scene, block, and character page counts")
	var expected_manifest := {"files":{"foundation_inspect.json":"abc"}, "scenes":["foundation.inspect"]}
	var expected_hash := JSON.stringify(expected_manifest, "\t", true, true).sha256_text()
	assert_true(counts_text.contains(expected_hash), "dock displays the deterministic manifest SHA-256")
	assert_false(_visible_text().contains("test-secret"), "dock never renders the configured bearer token")
	assert_true(_visible_text().contains("unknown_expression"), "successful sync retains validation diagnostics")

func _test_dry_run_does_not_rescan() -> void:
	_reset_observations()
	_dock.configure(Callable(self, "_valid_config"), Callable(self, "_successful_sync"), Callable(self, "_record_scan"), Callable(self, "_record_open"))
	var dry_run_button := _dock.get_node("DryRunButton") as Button
	dry_run_button.pressed.emit()
	await get_tree().process_frame
	assert_eq(_sync_calls.size(), 1, "Dry Run invokes one sync request")
	if not _sync_calls.is_empty():
		assert_true(_sync_calls[0]["dry_run"], "Dry Run requests validation without replacement")
	assert_eq(_scan_count, 0, "successful dry run never scans generated sources")

func _test_missing_secret_fails_closed() -> void:
	_reset_observations()
	_dock.configure(Callable(self, "_missing_config"), Callable(self, "_successful_sync"), Callable(self, "_record_scan"), Callable(self, "_record_open"))
	await _dock.start_sync(false)
	assert_eq(_sync_calls.size(), 0, "missing configuration never starts Notion transport")
	assert_true((_dock.get_node("StatusLabel") as Label).text.contains("PROJECT_A_NOTION_TOKEN"), "missing-secret status names the required environment variable")
	assert_false(_dock.is_busy(), "missing configuration restores the dock to idle")
	assert_eq(_scan_count, 0, "failed configuration never scans generated sources")

func _test_timeout_failure_restores_idle_state() -> void:
	_reset_observations()
	_dock.configure(Callable(self, "_valid_config"), Callable(self, "_timeout_sync"), Callable(self, "_record_scan"), Callable(self, "_record_open"))
	var result: Dictionary = await _dock.start_sync(false)
	assert_false(result["ok"], "timeout result fails the dock sync")
	assert_true((_dock.get_node("StatusLabel") as Label).text.contains("timed out"), "dock displays the actionable timeout diagnostic")
	assert_false(_dock.is_busy(), "timeout restores the dock to idle")
	assert_false((_dock.get_node("SyncButton") as Button).disabled, "timeout restores the sync button")
	assert_false((_dock.get_node("DryRunButton") as Button).disabled, "timeout restores the dry-run button")
	assert_eq(_scan_count, 0, "timeout never scans generated sources")

func _test_delayed_runner_rejects_reentry() -> void:
	_reset_observations()
	_delayed_runner_count = 0
	_release_delayed_runner = false
	_dock.configure(Callable(self, "_valid_config"), Callable(self, "_delayed_sync"), Callable(self, "_record_scan"), Callable(self, "_record_open"))
	_dock.start_sync(false)
	await get_tree().process_frame
	assert_true(_dock.is_busy(), "first delayed request remains busy while pending")
	var second: Dictionary = await _dock.start_sync(true)
	assert_false(second["ok"], "second request is rejected while the first is pending")
	assert_true(String(second["message"]).contains("already active"), "reentry diagnostic explains the active request")
	assert_eq(_delayed_runner_count, 1, "reentry never starts a second runner")
	_release_delayed_runner = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(_dock.is_busy(), "first delayed request restores idle state after completion")
	assert_false((_dock.get_node("SyncButton") as Button).disabled, "delayed completion restores the sync button")
	assert_false((_dock.get_node("DryRunButton") as Button).disabled, "delayed completion restores the dry-run button")

func _test_source_url_activation() -> void:
	_opened_urls.clear()
	var issues := _dock.get_node("Issues") as ItemList
	assert_true(issues.item_count > 0, "diagnostic list retains the latest source-linked issue")
	if issues.item_count == 0:
		return
	issues.item_activated.emit(0)
	assert_eq(_opened_urls, ["https://notion.so/source-row"], "activating a diagnostic opens its Notion source URL")

func _valid_config() -> Dictionary:
	return {
		"ok":true,
		"token":"test-secret",
		"scenes_data_source":"scene-source",
		"blocks_data_source":"block-source",
		"characters_data_source":"character-source",
		"message":""
	}

func _missing_config() -> Dictionary:
	return {
		"ok":false,
		"token":"",
		"scenes_data_source":"",
		"blocks_data_source":"",
		"characters_data_source":"",
		"message":"Missing required environment variable PROJECT_A_NOTION_TOKEN."
	}

func _successful_sync(config: Dictionary, _output_dir: String, dry_run: bool) -> Dictionary:
	_sync_calls.append({"dry_run":dry_run, "token":config["token"]})
	_saw_busy_during_call = _dock.is_busy() \
		and (_dock.get_node("SyncButton") as Button).disabled \
		and (_dock.get_node("DryRunButton") as Button).disabled
	return {
		"ok":true,
		"message":"Completed with test-secret safely hidden.",
		"counts":{"scenes":2, "blocks":6, "characters":1},
		"manifest":{"files":{"foundation_inspect.json":"abc"}, "scenes":["foundation.inspect"]},
		"issues":[{"severity":"warning", "code":"unknown_expression", "message":"test-secret is not allowed", "source_url":"https://notion.so/source-row"}]
	}

func _timeout_sync(config: Dictionary, output_dir: String, dry_run: bool) -> Dictionary:
	await get_tree().process_frame
	return await NotionSyncCli.sync(config, output_dir, dry_run, Callable(self, "_timeout_response"))

func _timeout_response(_url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
	return {"request_result":HTTPRequest.RESULT_TIMEOUT, "status_code":0, "body":""}

func _delayed_sync(config: Dictionary, output_dir: String, dry_run: bool) -> Dictionary:
	_delayed_runner_count += 1
	while not _release_delayed_runner:
		await get_tree().process_frame
	return _successful_sync(config, output_dir, dry_run)

func _record_scan() -> void:
	_scan_count += 1

func _record_open(url: String) -> void:
	_opened_urls.append(url)

func _reset_observations() -> void:
	_sync_calls.clear()
	_scan_count = 0
	_saw_busy_during_call = false

func _visible_text() -> String:
	var issues := _dock.get_node("Issues") as ItemList
	var issue_texts: Array[String] = []
	for index: int in issues.item_count:
		issue_texts.append(issues.get_item_text(index))
	return "\n".join([
		(_dock.get_node("StatusLabel") as Label).text,
		(_dock.get_node("CountsLabel") as Label).text,
		"\n".join(issue_texts)
	])
