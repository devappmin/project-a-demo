extends RefCounted
class_name DialogueIdentity

const RESERVED_KEYS := ["manifest", "events", "source_map"]
const WINDOWS_DEVICE_NAMES := ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]

static func stable_key(kind: String, source_id: String, retained_key := "") -> String:
	if _is_safe_key(retained_key):
		return retained_key
	if kind.is_empty() or source_id.strip_edges().is_empty():
		return ""
	return "%s_%s" % [kind, (kind + ":" + source_id).sha256_text().left(12)]

static func node_id(event_key: String, flow_key: String, block_key: String) -> String:
	return "%s.%s.%s" % [event_key, flow_key, block_key]

static func _is_safe_key(value: String) -> bool:
	if value.is_empty() or value.to_lower() in RESERVED_KEYS or value.to_lower() in WINDOWS_DEVICE_NAMES:
		return false
	for character: String in value:
		if not (character >= "a" and character <= "z") and not (character >= "0" and character <= "9") and character not in ["_", ".", "-"]:
			return false
	return true
