extends RefCounted
class_name DialogueBundleFixtureFactory

static func valid_bundle() -> Dictionary:
	return {
		"schema_version":1,
		"source_id":"notion-page-foundation",
		"source_url":"https://www.notion.so/foundation",
		"bundle_key":"foundation.inspect",
		"title":"기초 방",
		"comments":[{"text":"이 메모는 출력에 영향을 주지 않는다"}],
		"triggers":[{
			"source_id":"notion-heading-mirror",
			"trigger_key":"mirror.inspect",
			"name":"거울 조사",
			"events":[
				{"source_id":"notion-event-seen", "event_key":"seen", "name":"이미 본 거울", "conditions":[_condition("거울을 자세히 봄", "flag", "mirror_seen", "eq", true)], "effects":[], "flows":[_seen_flow()]},
				{"source_id":"notion-event-default", "event_key":"default", "name":"그 외", "conditions":[], "effects":[_effect("젤리뽀의 신뢰", "stat_add", "jellyppo_trust", 1)], "flows":[_default_start(), _inspect_flow(), _leave_flow(), _rejoin_flow()]}
			]
		}]
	}

static func _condition(term_name: String, kind: String, key: String, operator_name: String, value: Variant) -> Dictionary:
	return {"source_text":term_name, "term_name":term_name, "mapping_status":"exact", "kind":kind, "key":key, "operator":operator_name, "value":value}

static func _effect(term_name: String, kind: String, key: String, value: Variant) -> Dictionary:
	return {"source_text":term_name, "term_name":term_name, "mapping_status":"exact", "kind":kind, "key":key, "value":value}

static func _line(source_id: String, text: String) -> Dictionary:
	return {"type":"line", "source_id":source_id, "speaker":"retti", "expression":"neutral", "text":text}

static func _seen_flow() -> Dictionary:
	return {"source_id":"notion-flow-seen", "flow_key":"start", "name":"흐름 · 시작", "effects":[], "blocks":[_line("notion-block-seen", "이미 거울을 살폈다."), {"type":"end", "source_id":"notion-block-seen-end"}]}

static func _default_start() -> Dictionary:
	return {"source_id":"notion-flow-start", "flow_key":"start", "name":"흐름 · 시작", "effects":[], "blocks":[_line("notion-block-start-1", "거울이 희미하게 빛난다."), _line("notion-block-start-2", "무엇을 할까?"), {"type":"choice", "source_id":"notion-block-choice-1", "items":[{"source_id":"notion-choice-inspect", "text":"자세히 본다", "conditions":[], "effects":[], "target_kind":"flow", "target_key":"inspect"}, {"source_id":"notion-choice-leave", "text":"떠난다", "conditions":[], "effects":[], "target_kind":"flow", "target_key":"leave"}]}]}

static func _inspect_flow() -> Dictionary:
	return {"source_id":"notion-flow-inspect", "flow_key":"inspect", "name":"거울 자세히 보기", "effects":[], "blocks":[_line("notion-block-inspect", "거울 속에 낯선 방이 보인다."), {"type":"command", "source_id":"notion-block-command", "command_key":"dialogue.advance", "arguments":{"speed":2}}, {"type":"choice", "source_id":"notion-block-choice-2", "items":[{"source_id":"notion-choice-rejoin", "text":"다시 생각한다", "conditions":[], "effects":[], "target_kind":"flow", "target_key":"rejoin"}, {"source_id":"notion-choice-finish", "text":"그만둔다", "conditions":[], "effects":[], "target_kind":"flow", "target_key":"leave"}]}]}

static func _leave_flow() -> Dictionary:
	return {"source_id":"notion-flow-leave", "flow_key":"leave", "name":"방을 떠남", "effects":[], "blocks":[_line("notion-block-leave", "발걸음을 돌린다."), {"type":"jump", "source_id":"notion-block-jump", "target_kind":"flow", "target_key":"rejoin"}]}

static func _rejoin_flow() -> Dictionary:
	return {"source_id":"notion-flow-rejoin", "flow_key":"rejoin", "name":"다시 만남", "effects":[_effect("거울을 자세히 봄", "flag_set", "mirror_seen", true)], "blocks":[_line("notion-block-rejoin", "거울은 조용해졌다."), {"type":"end", "source_id":"notion-block-end"}]}
