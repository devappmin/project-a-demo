extends RefCounted
class_name NotionFixtureFactory

static func valid_dialogue_input() -> Dictionary:
	return {
		"scenes": [{"scene_key":"foundation.inspect", "status":"Final", "start_flow":"main", "notion_page_id":"scene1", "source_url":"https://notion.so/scene1"}],
		"blocks": [
			{"notion_page_id":"line1", "source_url":"https://notion.so/line1", "scene_key":"foundation.inspect", "flow":"main", "order":1.0, "type":"line", "speaker":"retti", "expression":"uneasy", "text":"낯선 거울이다.", "target_flow":"choice", "conditions":[], "effects":[], "command":{}},
			{"notion_page_id":"choice1", "source_url":"https://notion.so/choice1", "scene_key":"foundation.inspect", "flow":"choice", "order":1.0, "type":"choice", "speaker":"", "expression":"", "text":"자세히 본다", "target_flow":"end", "conditions":[], "effects":[{"kind":"flag_set", "key":"mirror_seen", "value":true}], "command":{}},
			{"notion_page_id":"end1", "source_url":"https://notion.so/end1", "scene_key":"foundation.inspect", "flow":"end", "order":1.0, "type":"end", "speaker":"", "expression":"", "text":"", "target_flow":"", "conditions":[], "effects":[], "command":{}}
		],
		"characters": [{"character_key":"retti", "default_expression":"neutral", "expressions":["neutral", "uneasy"], "notion_page_id":"char1", "source_url":"https://notion.so/char1"}]
	}
