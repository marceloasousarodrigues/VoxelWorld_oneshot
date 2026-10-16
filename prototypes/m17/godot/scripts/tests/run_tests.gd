extends SceneTree

## Headless test entry point.
##
## Usage:
##   godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd
##
## Every module is a RefCounted script exposing `name()` and `run(harness)`.
## The process exits non-zero when any assertion fails, and a watchdog guarantees
## the process cannot hang forever if a module aborts mid-run.

const MODULES := [
	"res://scripts/tests/test_coordinates.gd",
	"res://scripts/tests/test_block_db.gd",
	"res://scripts/tests/test_textures.gd",
	"res://scripts/tests/test_generation.gd",
	"res://scripts/tests/test_mesher.gd",
	"res://scripts/tests/test_mesh_winding.gd",
	"res://scripts/tests/test_fixture_contract.gd",
	"res://scripts/tests/test_edits.gd",
	"res://scripts/tests/test_persistence.gd",
	"res://scripts/tests/test_raycast.gd",
	"res://scripts/tests/test_fluid.gd",
	"res://scripts/tests/test_day_night.gd",
	"res://scripts/tests/test_determinism.gd",
]

const WATCHDOG_SECONDS := 300.0

var harness := TestHarness.new()
var finished := false


func _initialize() -> void:
	var watchdog := create_timer(WATCHDOG_SECONDS, true, false)
	watchdog.timeout.connect(_on_watchdog)
	call_deferred("_run_all")


func _on_watchdog() -> void:
	if finished:
		return
	finished = true
	push_error("M17_TESTS_TIMEOUT the suite exceeded %d seconds" % int(WATCHDOG_SECONDS))
	print("M17_TESTS_TIMEOUT %d passes, %d failures before the watchdog fired" % [harness.passed, harness.failures.size()])
	quit(2)


func _run_all() -> void:
	for path: String in MODULES:
		var script: Variant = load(path)
		if script == null:
			harness.check(false, "loads %s" % path)
			continue
		var module: Variant = (script as GDScript).new()
		if module == null:
			harness.check(false, "instantiates %s" % path)
			continue
		harness.section(str(module.name()))
		harness.begin_module()
		module.run(harness)
		if not harness.module_completed:
			harness.check(false, "the module reached its end (a script error aborted it)")
	finished = true
	# One idle frame lets deferred frees run, so a test that builds scene nodes
	# cannot make the exit logs claim leaked instances -- those warnings would
	# otherwise hide real script errors in CI output.
	await process_frame
	if harness.failures.is_empty():
		print("M17_TESTS_PASS %d assertions" % harness.passed)
		quit(0)
	else:
		for failure: String in harness.failures:
			print("M17_TEST_FAILURE %s" % failure)
		print("M17_TESTS_FAIL %d failures, %d passes" % [harness.failures.size(), harness.passed])
		quit(1)
