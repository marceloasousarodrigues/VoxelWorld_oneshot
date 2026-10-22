class_name TestHarness
extends RefCounted

## Minimal assertion harness for the M17 Godot headless test suite.

var passed := 0
var failures: Array[String] = []
var section_name := ""
## Set by `finish()` at the end of every module.  A GDScript runtime error aborts
## the function it happens in and the caller carries on, so without this an
## aborted module would silently report a smaller number of passing assertions.
var module_completed := false


func section(name: String) -> void:
	section_name = name
	print("M17_TEST_SECTION %s" % name)


func begin_module() -> void:
	module_completed = false


## Called as the last statement of a module so the runner can prove it reached
## the end instead of aborting on a script error.
func finish() -> void:
	module_completed = true


func check(condition: bool, description: String) -> bool:
	if condition:
		passed += 1
		print("M17_ASSERT_PASS %s" % description)
	else:
		failures.append("%s: %s" % [section_name, description])
		print("M17_ASSERT_FAIL %s" % description)
	return condition


func eq(actual: Variant, expected: Variant, description: String) -> bool:
	var ok: bool = actual == expected
	return check(ok, description if ok else "%s (expected %s, got %s)" % [description, expected, actual])


func approx(actual: float, expected: float, tolerance: float, description: String) -> bool:
	var ok: bool = absf(actual - expected) <= tolerance
	return check(ok, description if ok else "%s (expected %f +/- %f, got %f)" % [description, expected, tolerance, actual])


func greater(actual: float, threshold: float, description: String) -> bool:
	return check(actual > threshold, description if actual > threshold else "%s (value %f not > %f)" % [description, actual, threshold])


func less(actual: float, threshold: float, description: String) -> bool:
	return check(actual < threshold, description if actual < threshold else "%s (value %f not < %f)" % [description, actual, threshold])
