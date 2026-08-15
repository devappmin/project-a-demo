extends "res://tests/support/test_case.gd"

const NotionTransport = preload("res://tools/notion_sync/notion_transport.gd")

var _recorded_responses: Array[Dictionary] = []
var _requests: Array[Dictionary] = []

func run() -> void:
	_test_query_body()
	await _test_query_requires_explicit_headless_authorization()
	await _test_rejects_invalid_sorts_before_request()
	await _test_paginates_recorded_pages()
	await _test_rejects_malformed_list_envelopes_and_cursors()
	await _test_unauthorized_response_hides_token()
	await _test_access_and_service_errors_explain_remediation()
	await _test_rate_limit_response_is_actionable()
	await _test_malformed_json_is_reported()

func _test_query_body() -> void:
	var body := NotionTransport.build_query_body([{"property":"order", "direction":"ascending"}], "cursor-1")
	assert_eq(body["page_size"], 100, "query uses maximum page size")
	assert_eq(body["start_cursor"], "cursor-1", "next request carries cursor")
	assert_eq(body["sorts"][0]["property"], "order", "explicit order sort is retained")

func _test_query_requires_explicit_headless_authorization() -> void:
	_recorded_responses = [_response(200, {"object":"list", "results":[], "next_cursor":null, "has_more":false, "type":"page_or_data_source", "page_or_data_source":{}})]
	_requests = []
	var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"))
	var result: Dictionary = await transport.query_all("source-1", _valid_sorts())
	assert_false(result["ok"], "headless transport requires explicit authorization")
	assert_eq(_requests.size(), 0, "unauthorized headless transport never invokes the request executor")

func _test_rejects_invalid_sorts_before_request() -> void:
	_recorded_responses = [_response(200, {"object":"list", "results":[], "next_cursor":null, "has_more":false, "type":"page_or_data_source", "page_or_data_source":{}})]
	_requests = []
	var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
	var empty_result: Dictionary = await transport.query_all("source-1", [])
	assert_false(empty_result["ok"], "empty sorts are rejected")
	assert_eq(_requests.size(), 0, "empty sorts never invoke the request executor")
	_recorded_responses = [_response(200, {"object":"list", "results":[], "next_cursor":null, "has_more":false, "type":"page_or_data_source", "page_or_data_source":{}})]
	_requests = []
	transport = NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
	var malformed_result: Dictionary = await transport.query_all("source-1", [{"property":"", "direction":"ascending"}])
	assert_false(malformed_result["ok"], "malformed sorts are rejected")
	assert_eq(_requests.size(), 0, "malformed sorts never invoke the request executor")

func _test_paginates_recorded_pages() -> void:
	_recorded_responses = [
		_response(200, {"object":"list", "results":[{"id":"page-1"}], "next_cursor":"cursor-2", "has_more":true, "type":"page_or_data_source", "page_or_data_source":{}}),
		_response(200, {"object":"list", "results":[{"id":"page-2"}], "next_cursor":null, "has_more":false, "type":"page_or_data_source", "page_or_data_source":{}})
	]
	_requests = []
	var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
	var result: Dictionary = await transport.query_all("source-1", [{"property":"order", "direction":"ascending"}])
	assert_true(result["ok"], "two recorded pages query successfully")
	assert_eq(result["pages"], [{"id":"page-1"}, {"id":"page-2"}], "pages are decoded and combined")
	assert_eq(_requests.size(), 2, "pagination stops after the response without more pages")
	if _requests.size() == 2:
		var first_body: Dictionary = JSON.parse_string(String(_requests[0]["body"]))
		var second_body: Dictionary = JSON.parse_string(String(_requests[1]["body"]))
		assert_eq(first_body["sorts"], [{"property":"order", "direction":"ascending"}], "first request preserves explicit sorts")
		assert_eq(second_body["sorts"], [{"property":"order", "direction":"ascending"}], "pagination preserves explicit sorts")
		assert_eq(second_body["start_cursor"], "cursor-2", "second request uses decoded cursor")
		assert_eq(_requests[0]["url"], "https://api.notion.com/v1/data_sources/source-1/query", "request uses the current data-source query endpoint")
		assert_true(String(_requests[0]["headers"][0]).contains("Bearer test-token"), "request uses bearer authentication")
		assert_eq(_requests[0]["headers"][1], "Notion-Version: 2026-03-11", "request uses the pinned Notion API version")
		assert_eq(_requests[0]["headers"][2], "Content-Type: application/json", "request sends JSON content")

func _test_rejects_malformed_list_envelopes_and_cursors() -> void:
	for response_case: Dictionary in [
		{"name":"wrong object", "body":{"object":"page", "results":[], "next_cursor":null, "has_more":false, "type":"page_or_data_source", "page_or_data_source":{}}},
		{"name":"outdated type", "body":{"object":"list", "results":[], "next_cursor":null, "has_more":false, "type":"page_or_database", "page_or_database":{}}},
		{"name":"non-boolean has more", "body":{"object":"list", "results":[], "next_cursor":null, "has_more":"false", "type":"page_or_data_source", "page_or_data_source":{}}},
		{"name":"missing next cursor", "body":{"object":"list", "results":[], "has_more":true, "type":"page_or_data_source", "page_or_data_source":{}}},
		{"name":"non-string next cursor", "body":{"object":"list", "results":[], "next_cursor":7, "has_more":true, "type":"page_or_data_source", "page_or_data_source":{}}},
		{"name":"empty next cursor", "body":{"object":"list", "results":[], "next_cursor":"", "has_more":true, "type":"page_or_data_source", "page_or_data_source":{}}}
	]:
		_recorded_responses = [_response(200, response_case["body"])]
		_requests = []
		var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
		var result: Dictionary = await transport.query_all("source-1", _valid_sorts())
		assert_false(result["ok"], "%s response is rejected" % response_case["name"])
		assert_true(String(result["message"]).contains("Notion"), "%s response has an actionable diagnostic" % response_case["name"])
		assert_false(String(result["message"]).contains("test-token"), "%s response never leaks the token" % response_case["name"])
		assert_eq(_requests.size(), 1, "%s response terminates without another request" % response_case["name"])

func _test_unauthorized_response_hides_token() -> void:
	_recorded_responses = [_response(401, {"object":"error", "status":401, "code":"unauthorized", "message":"invalid token"})]
	_requests = []
	var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
	var result: Dictionary = await transport.query_all("source-1", _valid_sorts())
	assert_false(result["ok"], "401 fails the query")
	assert_true(String(result["message"]).contains("credentials"), "401 explains how to fix credentials")
	assert_false(String(result["message"]).contains("test-token"), "401 diagnostics never expose the configured token")

func _test_access_and_service_errors_explain_remediation() -> void:
	for response_case: Dictionary in [
		{"status_code":403, "body":{"object":"error", "status":403, "code":"restricted_resource", "message":"forbidden"}, "expected":"Share"},
		{"status_code":404, "body":{"object":"error", "status":404, "code":"object_not_found", "message":"missing"}, "expected":"Verify"},
		{"status_code":503, "body":{"object":"error", "status":503, "code":"service_unavailable", "message":"unavailable"}, "expected":"Retry"}
	]:
		_recorded_responses = [_response(int(response_case["status_code"]), response_case["body"])]
		_requests = []
		var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
		var result: Dictionary = await transport.query_all("source-1", _valid_sorts())
		assert_false(result["ok"], "HTTP %d fails the query" % response_case["status_code"])
		assert_true(String(result["message"]).contains(String(response_case["expected"])), "HTTP %d explains remediation" % response_case["status_code"])

func _test_rate_limit_response_is_actionable() -> void:
	_recorded_responses = [_response(429, {"object":"error", "status":429, "code":"rate_limited", "message":"slow down"})]
	_requests = []
	var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
	var result: Dictionary = await transport.query_all("source-1", _valid_sorts())
	assert_false(result["ok"], "429 fails the query")
	assert_true(String(result["message"]).contains("rate limited"), "429 tells the editor to retry after throttling")

func _test_malformed_json_is_reported() -> void:
	_recorded_responses = [{"status_code":200, "body":"{not-json"}]
	_requests = []
	var transport := NotionTransport.new("test-token", Callable(self, "_request_recording"), true)
	var result: Dictionary = await transport.query_all("source-1", _valid_sorts())
	assert_false(result["ok"], "malformed JSON fails the query")
	assert_true(String(result["message"]).contains("malformed JSON"), "malformed JSON explains the response problem")

func _request_recording(url: String, headers: PackedStringArray, body: String) -> Dictionary:
	_requests.append({"url":url, "headers":headers, "body":body})
	return _recorded_responses.pop_front()

func _response(status_code: int, body: Dictionary) -> Dictionary:
	return {"status_code":status_code, "body":JSON.stringify(body)}

func _valid_sorts() -> Array[Dictionary]:
	return [{"property":"order", "direction":"ascending"}]
