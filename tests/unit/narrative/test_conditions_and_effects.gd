extends "res://tests/support/test_case.gd"

const NarrativeState = preload("res://game/narrative/state/narrative_state.gd")
const ConditionEvaluator = preload("res://game/narrative/conditions/condition_evaluator.gd")
const EffectExecutor = preload("res://game/narrative/effects/effect_executor.gd")

func run() -> void:
	var state := NarrativeState.new()
	state.set_flag(&"sandwich_more", true)
	state.set_stat(&"corruption", 2.0)
	assert_true(ConditionEvaluator.matches({"kind":"flag", "key":"sandwich_more", "operator":"eq", "value":true}, state), "flag condition")
	assert_true(ConditionEvaluator.matches({"kind":"flag", "key":"sandwich_more", "operator":"neq", "value":false}, state), "flag inequality condition")
	assert_true(ConditionEvaluator.matches({"kind":"stat", "key":"corruption", "operator":"gte", "value":2}, state), "numeric condition")
	assert_true(ConditionEvaluator.matches({"kind":"stat", "key":"corruption", "operator":"gt", "value":1}, state), "numeric greater than condition")
	assert_true(ConditionEvaluator.matches({"kind":"stat", "key":"corruption", "operator":"lt", "value":3}, state), "numeric less than condition")
	assert_true(ConditionEvaluator.matches({"kind":"stat", "key":"corruption", "operator":"lte", "value":2}, state), "numeric less than or equal condition")
	assert_eq(EffectExecutor.apply({"kind":"stat_add", "key":"corruption", "value":1}, state), OK, "effect succeeds")
	assert_eq(state.get_stat(&"corruption"), 3.0, "effect mutates state")
	assert_eq(EffectExecutor.apply({"kind":"inventory_add", "key":"sandwich", "value":2}, state), OK, "inventory add succeeds")
	assert_true(ConditionEvaluator.matches({"kind":"inventory", "key":"sandwich", "operator":"gte", "value":2}, state), "inventory condition")
	assert_eq(EffectExecutor.apply({"kind":"inventory_remove", "key":"sandwich", "value":1}, state), OK, "inventory remove succeeds")
	assert_eq(state.inventory.get("sandwich", 0.0), 1.0, "inventory removal mutates quantity")
	assert_eq(EffectExecutor.apply({"kind":"quest_set", "key":"lunch", "value":"started"}, state), OK, "quest set succeeds")
	assert_true(ConditionEvaluator.matches({"kind":"quest", "key":"lunch", "operator":"eq", "value":"started"}, state), "quest condition")
	assert_eq(EffectExecutor.apply({"kind":"collectible_add", "key":"recipe", "value":1}, state), OK, "collectible add succeeds")
	assert_true(ConditionEvaluator.matches({"kind":"collectible", "key":"recipe", "operator":"contains", "value":true}, state), "collectible possession condition")
	assert_false(ConditionEvaluator.matches({"kind":"stat", "key":"corruption", "operator":"contains", "value":"2"}, state), "unsupported condition combination is rejected")
	_test_invalid_effects_do_not_mutate()

func _test_invalid_effects_do_not_mutate() -> void:
	var cases: Array[Dictionary] = [
		{"label":"missing shape", "effect":{"kind":"flag_set", "key":"flag"}},
		{"label":"empty kind", "effect":{"kind":"", "key":"flag", "value":true}},
		{"label":"empty key", "effect":{"kind":"flag_set", "key":"", "value":true}},
		{"label":"flag_set value", "effect":{"kind":"flag_set", "key":"flag", "value":1}},
		{"label":"stat_set value", "effect":{"kind":"stat_set", "key":"stat", "value":"1"}},
		{"label":"stat_add value", "effect":{"kind":"stat_add", "key":"stat", "value":"1"}},
		{"label":"stat_add corrupted state", "effect":{"kind":"stat_add", "key":"stat", "value":1}, "section":"stats", "corrupt":"bad"},
		{"label":"inventory_add negative", "effect":{"kind":"inventory_add", "key":"item", "value":-1}},
		{"label":"inventory_add corrupted state", "effect":{"kind":"inventory_add", "key":"item", "value":1}, "section":"inventory", "corrupt":"bad"},
		{"label":"inventory_remove negative", "effect":{"kind":"inventory_remove", "key":"item", "value":-1}},
		{"label":"inventory_remove corrupted state", "effect":{"kind":"inventory_remove", "key":"item", "value":1}, "section":"inventory", "corrupt":"bad"},
		{"label":"quest_set value", "effect":{"kind":"quest_set", "key":"quest", "value":&"started"}},
		{"label":"collectible_add negative", "effect":{"kind":"collectible_add", "key":"item", "value":-1}},
		{"label":"collectible_add corrupted state", "effect":{"kind":"collectible_add", "key":"item", "value":1}, "section":"collectibles", "corrupt":"bad"},
		{"label":"unknown kind", "effect":{"kind":"call", "key":"unsafe", "value":"run()"}},
	]
	for case: Dictionary in cases:
		var invalid_state := NarrativeState.new()
		var section := String(case.get("section", ""))
		if not section.is_empty():
			invalid_state.get(section)[String(case["effect"].get("key", ""))] = case.get("corrupt")
		var before: Dictionary = invalid_state.snapshot()
		assert_eq(EffectExecutor.apply(case["effect"], invalid_state), ERR_INVALID_DATA, "%s is rejected" % case["label"])
		assert_eq(invalid_state.snapshot(), before, "%s cannot mutate state" % case["label"])
	assert_eq(EffectExecutor.apply({"kind":"flag_set", "key":"flag", "value":true}, null), ERR_INVALID_DATA, "null narrative state is rejected")
