extends Node
class_name TestCase

var failures: Array[String] = []

func run() -> void:
	pass

func assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func assert_false(value: bool, message: String) -> void:
	assert_true(not value, message)

func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])

func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	if abs(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [message, expected, tolerance, actual])

func assert_not_null(value: Variant, message: String) -> void:
	assert_true(value != null, message)
