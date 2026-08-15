extends RefCounted
class_name NotionSchema

const SCENE_PROPERTIES := {"name":"Name", "scene_key":"scene_key", "location":"location", "status":"status", "start_flow":"start_flow"}
const BLOCK_PROPERTIES := {"text":"Text", "scene":"scene", "flow":"flow", "order":"order", "type":"type", "speaker":"speaker", "expression":"expression", "target_flow":"target_flow", "conditions":"conditions_json", "effects":"effects_json", "command":"command_json", "notes":"notes"}
const CHARACTER_PROPERTIES := {"name":"Name", "character_key":"character_key", "default_expression":"default_expression", "expressions":"expressions"}
const SCENE_STATUSES := ["Draft", "Review", "Final"]
const BLOCK_TYPES := ["line", "choice", "effect", "command", "jump", "end"]
