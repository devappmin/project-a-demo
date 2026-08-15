@tool
extends RefCounted
class_name NotionTransport

const API_VERSION := "2026-03-11"
const API_ROOT := "https://api.notion.com/v1/data_sources/"

var _token: String
var _request_executor: Callable

func _init(token: String, request_executor: Callable = Callable()) -> void:
	_token = token
	_request_executor = request_executor

static func build_query_body(sorts: Array[Dictionary], cursor: String = "") -> Dictionary:
	var body: Dictionary = {"page_size": 100, "sorts": sorts.duplicate(true)}
	if not cursor.is_empty():
		body["start_cursor"] = cursor
	return body

func query_all(data_source_id: String, sorts: Array[Dictionary]) -> Dictionary:
	if not _is_editor_or_headless():
		return _failure(0, "Notion sync transport is only available in editor or headless tooling.")
	if data_source_id.strip_edges().is_empty():
		return _failure(0, "A Notion data source ID is required before querying.")
	if _token.strip_edges().is_empty():
		return _failure(0, "Notion credentials are missing. Set PROJECT_A_NOTION_TOKEN.")
	var pages: Array = []
	var cursor := ""
	while true:
		var request_body := build_query_body(sorts, cursor)
		var response := await _send_query(data_source_id, request_body)
		if not response["ok"]:
			return _failure(int(response["status_code"]), String(response["message"]))
		var parsed_response := _parse_page_response(int(response["status_code"]), String(response["body"]))
		if not parsed_response["ok"]:
			return parsed_response
		pages.append_array(parsed_response["results"])
		if not parsed_response["has_more"]:
			return {"ok": true, "pages": pages, "status_code": int(response["status_code"]), "message": ""}
		cursor = String(parsed_response["next_cursor"])
		if cursor.is_empty():
			return _failure(int(response["status_code"]), "Notion reported more query pages without a next cursor.")
	return _failure(0, "Notion pagination ended unexpectedly.")

func _headers(token: String) -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + token,
		"Notion-Version: " + API_VERSION,
		"Content-Type: application/json"
	])

func _send_query(data_source_id: String, body: Dictionary) -> Dictionary:
	var url := API_ROOT + data_source_id.uri_encode() + "/query"
	var headers := _headers(_token)
	var encoded_body := JSON.stringify(body)
	if _request_executor.is_valid():
		var recorded_response: Variant = _request_executor.call(url, headers, encoded_body)
		if typeof(recorded_response) != TYPE_DICTIONARY:
			return {"ok": false, "status_code": 0, "message": "Notion request transport returned an invalid response."}
		return _normalize_response(recorded_response)
	return await _send_http_request(url, headers, encoded_body)

func _send_http_request(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return {"ok": false, "status_code": 0, "message": "Notion sync requires an active editor or headless scene tree."}
	var request := HTTPRequest.new()
	tree.root.add_child(request)
	var request_error := request.request(url, headers, HTTPClient.METHOD_POST, body)
	if request_error != OK:
		request.queue_free()
		return {"ok": false, "status_code": 0, "message": "Unable to start the Notion request. Check network access and retry."}
	var completed: Array = await request.request_completed
	request.queue_free()
	if int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status_code": int(completed[1]), "message": "Unable to reach Notion. Check network access and retry."}
	return _normalize_response({"status_code": int(completed[1]), "body": PackedByteArray(completed[3]).get_string_from_utf8()})

func _normalize_response(response: Dictionary) -> Dictionary:
	var status_code := int(response.get("status_code", 0))
	if status_code == 401:
		return {"ok": false, "status_code": status_code, "message": "Notion rejected the credentials (401). Verify PROJECT_A_NOTION_TOKEN and the integration."}
	if status_code == 403:
		return {"ok": false, "status_code": status_code, "message": "Notion denied access (403). Share each data source with the integration, then retry."}
	if status_code == 404:
		return {"ok": false, "status_code": status_code, "message": "Notion could not find the data source (404). Verify its ID and that it is shared with the integration."}
	if status_code == 429:
		return {"ok": false, "status_code": status_code, "message": "Notion rate limited this sync (429). Wait briefly, then retry."}
	if status_code >= 500 and status_code <= 599:
		return {"ok": false, "status_code": status_code, "message": "Notion service error (%d). Retry the sync shortly." % status_code}
	if status_code < 200 or status_code >= 300:
		return {"ok": false, "status_code": status_code, "message": "Notion query failed with HTTP status %d. Verify the integration and data source sharing." % status_code}
	if typeof(response.get("body")) != TYPE_STRING:
		return {"ok": false, "status_code": status_code, "message": "Notion returned a malformed response body."}
	return {"ok": true, "status_code": status_code, "body": String(response["body"]), "message": ""}

func _parse_page_response(status_code: int, body: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(body) != OK:
		return _failure(status_code, "Notion returned malformed JSON. Retry the sync, then check the integration if it persists.")
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure(status_code, "Notion returned malformed JSON. Retry the sync, then check the integration if it persists.")
	if typeof(parsed.get("results")) != TYPE_ARRAY or typeof(parsed.get("has_more")) != TYPE_BOOL:
		return _failure(status_code, "Notion returned malformed JSON for a data source query.")
	var next_cursor: Variant = parsed.get("next_cursor")
	if bool(parsed["has_more"]) and typeof(next_cursor) != TYPE_STRING:
		return _failure(status_code, "Notion returned malformed JSON with no next cursor for an additional page.")
	return {"ok": true, "results": parsed["results"], "has_more": bool(parsed["has_more"]), "next_cursor": next_cursor}

func _failure(status_code: int, message: String) -> Dictionary:
	return {"ok": false, "pages": [], "status_code": status_code, "message": message}

func _is_editor_or_headless() -> bool:
	return Engine.is_editor_hint() or OS.has_feature("headless") or DisplayServer.get_name() == "headless"
