extends SceneTree

## Rendering-stability benchmark harness (M17).
##
## Boots the real game scene, drives scripted activities, and records per-frame
## timings together with the streaming counters that could explain them.  The
## output is a JSON report plus M17_PERF_* lines so two runs can be compared
## under the same seed, camera path and settings.
##
## Usage (windowed; no --headless, the point is to render):
##   godot --path prototypes/m17/godot \
##     --script res://scripts/tests/run_perf.gd \
##     -- --straight-to-game --seed=17017 --scenario=walk --label=walk-before
##
## Scenarios:
##   settle  - record the initial streaming burst until the region is settled
##   look    - stand still while sweeping the camera through a full turn
##   walk    - walk forward inside the already-streamed region
##   cross   - walk forward long enough to cross several chunk boundaries
##   foliage - sweep the camera up into the dense spawn canopy
##   water   - stand at the shore and sweep the camera across the sea
##
## Exits 0 on success, 2 when the world never becomes usable.

const RESULTS_DIR := "../results/godot"
const PLAYING := 2

var _game: Node
var _player: Node
var _scenario := "look"
var _label := ""
var _sync_generation := false  # --sync-generation: A/B the background generator
var _api_edge := ""  # '' or a message from a failed precondition

# --- recording buffers ----------------------------------------------------
var _frames: Array = []          # per-frame dictionaries
var _phase_start_usec := 0
var _current_phase := "boot"
var _last_generated := 0
var _last_meshed := 0
var _last_generation_ms := 0.0
var _last_mesh_ms := 0.0
var _last_usec := 0


func _initialize() -> void:
	call_deferred("_main")


## Forces the measurement conditions: no vsync and no frame cap.  Called before
## the game boots *and* again after it boots, because the game applies its
## persisted display settings (including vsync) in `_ready`, which would
## otherwise silently cap every measured phase at the display refresh rate.
func _configure_display() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func _parse() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts := argument.split("=", true, 1)
		var key := parts[0]
		var value := parts[1] if parts.size() > 1 else ""
		match key:
			"--scenario":
				_scenario = value
			"--label":
				_label = value
			"--sync-generation":
				_sync_generation = true
	if _label.is_empty():
		_label = "perf-%s" % _scenario


func _begin_phase(name: String) -> void:
	# Re-assert the measurement conditions: whatever opened, closed or saved
	# settings during boot must not cap the frames this phase records.
	_configure_display()
	_current_phase = name
	_phase_start_usec = Time.get_ticks_usec()
	print("M17_PERF_PHASE_START %s" % name)


## One row per frame: frame interval, the CPU cost of the frame, and the
## streaming counters accumulated since the previous row.
func _sample() -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if _streamer() == null or _player == null:
		return
	var stats: Dictionary = _streamer().stats
	var generated := int(stats["generated"])
	var meshed := int(stats["meshed"])
	var generation_ms := float(stats["generation_ms"])
	var mesh_ms := float(stats["mesh_ms"])
	var attach_ms := float(stats.get("attach_ms", 0.0))
	_frames.append({
		"t": float(Time.get_ticks_msec() - _run_start_ms) / 1000.0,
		"phase": _current_phase,
		"frame_ms": frame_ms,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"gen": generated - _last_generated,
		"mesh": meshed - _last_meshed,
		"gen_ms": generation_ms - _last_generation_ms,
		"mesh_ms": mesh_ms - _last_mesh_ms,
		"attach_ms": attach_ms - _last_attach_ms,
		"queued": _streamer().queued_count(),
		"loaded": _streamer().loaded_count(),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"player": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
		"look": [_player.look_angles().x, _player.look_angles().y],
	})
	_last_generated = generated
	_last_meshed = meshed
	_last_generation_ms = generation_ms
	_last_mesh_ms = mesh_ms
	_last_attach_ms = attach_ms


var _run_start_ms := 0
var _last_attach_ms := 0.0


func _streamer() -> Node:
	return _game.streamer if _game != null and _game.streamer != null else null


func _wait_frames(count: int) -> void:
	# yield to both loops so physics and rendering both advance
	for i in count:
		await process_frame
		_sample()


func _wait_until_playing(timeout_frames := 40000) -> bool:
	var guard := 0
	while (int(_game.state) != PLAYING or not _streamer().is_area_ready(_player.global_position, 2)) and guard < timeout_frames:
		await process_frame
		_sample()
		guard += 1
	return int(_game.state) == PLAYING


func _wait_until_settled(timeout_frames := 40000) -> bool:
	var guard := 0
	while not _streamer().is_settled() and guard < timeout_frames:
		await process_frame
		_sample()
		guard += 1
	return _streamer().is_settled()


# --- activities -----------------------------------------------------------

func _run_look_phase(duration: float, pitch: float, yaw_step_deg_per_second: float = 30.0) -> void:
	var started := Time.get_ticks_usec()
	var previous := started
	var yaw: float = _player.look_angles().x
	while float(Time.get_ticks_usec() - started) / 1000000.0 < duration:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_seconds := maxf(0.0001, float(now - previous) / 1000000.0)
		previous = now
		yaw += yaw_step_deg_per_second * frame_seconds
		_player.look_yaw(yaw)
		_player.look_pitch(pitch)
		_sample()


func _run_pitch_sweep_phase(duration: float, yaw: float, pitch_from: float, pitch_to: float) -> void:
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < duration:
		await process_frame
		var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
		var t := clampf(elapsed / duration, 0.0, 1.0)
		_player.look_yaw(yaw + 60.0 * sin(t * TAU))
		_player.look_pitch(lerpf(pitch_from, pitch_to, t))
		_sample()


func _run_walk_phase(duration: float, pitch: float) -> void:
	_player.look_pitch(pitch)
	Input.action_press("move_forward")
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < duration:
		await process_frame
		_sample()
	Input.action_release("move_forward")


# --- summary --------------------------------------------------------------

func _percentile(sorted_values: Array, fraction: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(round(fraction * float(sorted_values.size() - 1))), 0, sorted_values.size() - 1)
	return float(sorted_values[index])


func _stats_for(rows: Array) -> Dictionary:
	var frame_ms := []
	var process_ms := []
	for row: Dictionary in rows:
		frame_ms.append(float(row["frame_ms"]))
		process_ms.append(float(row["process_ms"]))
	if frame_ms.is_empty():
		return {"frames": 0}
	var sorted_frames: Array = frame_ms.duplicate()
	sorted_frames.sort()
	var total_ms := 0.0
	for value: float in frame_ms:
		total_ms += value
	var average_ms := total_ms / float(frame_ms.size())
	# 1% low: the mean of the slowest 1% of frames, expressed as an fps figure.
	var tail_count := maxi(1, int(ceil(float(frame_ms.size()) * 0.01)))
	var tail_total := 0.0
	for i in tail_count:
		tail_total += float(sorted_frames[sorted_frames.size() - 1 - i])
	var one_percent_low_fps := 1000.0 / maxf(0.0001, tail_total / float(tail_count))
	var work_rows := 0
	var work_frame_total := 0.0
	var idle_frame_total := 0.0
	var idle_rows := 0
	var queued_total := 0.0
	var draw_total := 0.0
	for row: Dictionary in rows:
		if int(row["gen"]) > 0 or int(row["mesh"]) > 0:
			work_rows += 1
			work_frame_total += float(row["frame_ms"])
		else:
			idle_rows += 1
			idle_frame_total += float(row["frame_ms"])
		queued_total += float(row["queued"])
		draw_total += float(row["draw_calls"])
	return {
		"frames": frame_ms.size(),
		"avg_fps": 1000.0 / maxf(0.0001, average_ms),
		"avg_frame_ms": average_ms,
		"p50_frame_ms": _percentile(sorted_frames, 0.50),
		"p95_frame_ms": _percentile(sorted_frames, 0.95),
		"p99_frame_ms": _percentile(sorted_frames, 0.99),
		"worst_frame_ms": float(sorted_frames[sorted_frames.size() - 1]),
		"one_percent_low_fps": one_percent_low_fps,
		"avg_process_ms": _average(process_ms),
		"stream_work_frames": work_rows,
		"stream_work_avg_frame_ms": work_frame_total / float(maxi(1, work_rows)),
		"idle_avg_frame_ms": idle_frame_total / float(maxi(1, idle_rows)),
		"avg_queued": queued_total / float(rows.size()),
		"avg_draw_calls": draw_total / float(rows.size()),
	}


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _phase_rows() -> Array:
	var seen := []
	for row: Dictionary in _frames:
		if not seen.has(row["phase"]):
			seen.append(row["phase"])
	var phases := []
	for phase: String in seen:
		var rows := []
		for row: Dictionary in _frames:
			if row["phase"] == phase:
				rows.append(row)
		phases.append({"phase": phase, "summary": _stats_for(rows)})
	return phases


func _write_report() -> void:
	var directory := ProjectSettings.globalize_path(RESULTS_DIR)
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var report := {
		"scenario": _scenario,
		"label": _label,
		"seed": _game.world.world_seed,
		"render_distance": int(_game._options["render_radius"]),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"threaded_generation": _streamer().threaded_generation,
		"threaded_meshing": _streamer().threaded_meshing,
		"godot": Engine.get_version_info(),
		"overall": _stats_for(_frames),
		"phases": _phase_rows(),
		"frames": _frames,
	}
	var path := directory.path_join("%s.json" % _label)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report))
		file.close()
	print("M17_PERF_REPORT %s frames=%d" % [path, _frames.size()])


func _print_summary() -> void:
	var overall := _stats_for(_frames)
	var top := _frames.duplicate()
	top.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["frame_ms"]) > float(b["frame_ms"]))
	print("M17_PERF %s" % JSON.stringify({
		"scenario": _scenario, "label": _label, "overall": overall, "phases": _phase_rows(),
	}))
	var printed := 0
	for row: Dictionary in top:
		if printed >= 8:
			break
		print("M17_PERF_TOP %s" % JSON.stringify(row))
		printed += 1


func _main() -> void:
	_parse()
	_configure_display()
	_run_start_ms = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/game.tscn")
	_game = scene.instantiate()
	root.add_child(_game)
	_player = _game.player
	# The game applies its persisted vsync setting in `_ready`; force the
	# measurement conditions back on now that boot is over.
	_configure_display()
	if _sync_generation and _streamer() != null:
		# A/B control: run the same workload with the background generator off.
		_streamer().threaded_generation = false
	if not await _wait_until_playing():
		print("M17_PERF_FAIL never reached PLAYING")
		_print_summary()
		quit(2)
		return
	_begin_phase("settle")
	var settled := await _wait_until_settled()
	if not settled:
		print("M17_PERF_WARN never settled")
		_begin_phase(_scenario)
		await _wait_frames(180)
		_print_summary()
		_write_report()
		quit(2)
		return
	await _wait_frames(120)  # one stable second before the measured activity
	match _scenario:
		"settle":
			await _wait_frames(180)
		"look":
			_begin_phase("look")
			await _run_look_phase(10.0, -10.0)
		"walk":
			_begin_phase("walk")
			await _run_walk_phase(20.0, -5.0)
		"cross":
			_begin_phase("cross")
			await _run_walk_phase(45.0, -5.0)
		"foliage":
			_player.spawn_on_column(8, 8)
			_begin_phase("foliage")
			await _run_pitch_sweep_phase(12.0, 38.0, -5.0, 55.0)
		"water":
			_player.spawn_on_column(8, 8)
			_begin_phase("water")
			await _run_look_phase(12.0, -12.0, 24.0)
		_:
			_begin_phase("settle")
			await _wait_frames(180)
	_print_summary()
	_write_report()
	print("M17_PERF_DONE scenario=%s" % _scenario)
	quit(0)
