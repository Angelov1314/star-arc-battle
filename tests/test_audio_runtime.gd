extends SceneTree

## Graphical runtime QA only.  It measures the final Master mix through an
## AudioEffectCapture; it must not be launched with --headless.
var failures := 0
var capture: AudioEffectCapture
var samples := 0
var peak := 0.0
var collecting := false
var window_samples := 0
var window_peak := 0.0
var discarded_at_start := 0
var observed_audio: GameAudio
var max_active_voices := 0

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func install_master_capture() -> void:
	var master := AudioServer.get_bus_index("Master")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(master, capture, 0)

func clear_capture() -> void:
	if capture != null:
		capture.get_buffer(capture.get_frames_available())

func drain_capture() -> void:
	if capture == null:
		return
	var frames := capture.get_buffer(capture.get_frames_available())
	for frame in frames:
		window_peak = maxf(window_peak, maxf(absf(frame.x), absf(frame.y)))
	window_samples += frames.size()

func _process(_delta: float) -> bool:
	if collecting:
		drain_capture()
	if observed_audio != null and is_instance_valid(observed_audio):
		max_active_voices = max(max_active_voices, int(observed_audio.diagnostics().active_voices))
	return false

func collect(seconds: float) -> Dictionary:
	clear_capture()
	window_samples = 0
	window_peak = 0.0
	discarded_at_start = capture.get_discarded_frames()
	collecting = true
	await create_timer(seconds).timeout
	drain_capture()
	collecting = false
	var discarded := capture.get_discarded_frames() - discarded_at_start
	samples += window_samples
	peak = maxf(peak, window_peak)
	return {"frames":window_samples, "peak":window_peak, "discarded":discarded}

func _keys_after(audio: GameAudio, keys: Array[String], before: Dictionary) -> bool:
	var events: Dictionary = audio.diagnostics().events
	for key in keys:
		if int(events.get(key, 0)) <= int(before.get(key, 0)):
			return false
	return true

func run() -> void:
	check(not OS.has_feature("headless") and DisplayServer.get_name() != "headless", "graphical audio driver is required")
	if failures > 0:
		quit(1)
		return
	install_master_capture()
	var audio := GameAudio.new()
	observed_audio = audio
	root.add_child(audio)
	await process_frame
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "separate Music and SFX buses exist")
	check(audio.diagnostics().music_bus == "Music" and audio.diagnostics().sfx_bus == "SFX", "players report separate buses")
	var town_mix := await collect(36.2)
	check(int(town_mix.frames) > 1000000 and int(town_mix.discarded) == 0 and float(town_mix.peak) > 0.0001, "actual Master capture covers a 32+ second town loop without dropped capture frames")

	audio.set_context("battle")
	await create_timer(0.35).timeout
	var fade := audio.diagnostics()
	print("AUDIO_FADE diagnostics=%s" % str(fade))
	check(float(fade.transition) > 0.0 and float(fade.transition) < 1.0 and bool(fade.music_playing) and bool(fade.music_next_playing), "two music players overlap during crossfade")
	var battle_mix := await collect(1.10)
	var settled := audio.diagnostics()
	check(settled.context == "battle" and float(settled.transition) >= 1.0 and bool(settled.music_playing) and not bool(settled.music_next_playing), "crossfade settles on battle music")
	check(int(battle_mix.frames) > 0 and float(battle_mix.peak) > 0.0001, "actual Master capture receives battle music")

	var before: Dictionary = audio.diagnostics().events.duplicate()
	for key in ["guard", "stamina", "armor_break", "phase"]:
		audio.play(key)
	await create_timer(0.12).timeout
	check(_keys_after(audio, ["guard", "stamina", "armor_break", "phase"], before), "guard, stamina, armor-break and phase feedback are audible semantic events")
	var view := BattleView.new()
	view.sound = audio
	root.add_child(view)
	await process_frame
	var mapped_before: Dictionary = audio.diagnostics().events.duplicate()
	for kind in ["guard", "stamina", "armor_break", "phase"]:
		view.on_feedback(kind, Vector2.ZERO, 1.0)
		await create_timer(0.20).timeout
	check(int(audio.diagnostics().events.get("power", 0)) >= int(mapped_before.get("power", 0)) + 3 and int(audio.diagnostics().events.get("heal", 0)) >= int(mapped_before.get("heal", 0)) + 1, "BattleView maps guard/stamina/armor-break/phase feedback without silent loss")
	view.queue_free()
	await process_frame

	# This first records the code-budget behavior (four low/medium events per
	# frame). The second burst uses long priority-3 tails to reach the actual
	# 12-voice pool, then adds combat impacts while the pool is occupied.
	audio.volumes(1.0, 1.0)
	for key in ["click", "hover", "select", "cancel", "slider", "lock", "unlock", "equip", "craft", "heal", "turn", "step"]:
		audio.play(key)
	audio.play("explosion")
	audio.play("damage")
	await process_frame
	for key in ["win", "lose", "level_up", "upgrade", "socket", "fire", "explosion", "damage", "power", "hazard", "armor_break", "phase"]:
		audio.play(key)
	var load_mix := await collect(0.35)
	var dense := audio.diagnostics()
	check(max_active_voices == int(dense.voice_limit) and int(dense.voice_limit) == 12, "maximum observed dense SFX concurrency reaches but never exceeds the 12-voice pool")
	check(int(dense.events.get("explosion", 0)) > int(before.get("explosion", 0)) and int(dense.events.get("damage", 0)) > int(before.get("damage", 0)), "dense SFX preserves explosion and damage priority")
	check(int(load_mix.frames) > 0 and int(load_mix.discarded) == 0 and float(load_mix.peak) > 0.0001 and float(load_mix.peak) < 0.98, "maximum-volume dense mix has measured peak headroom without capture overflow")
	var clicks := int(dense.events.get("click", 0)); audio.play("click"); audio.play("click")
	check(int(audio.diagnostics().events.get("click", 0)) <= clicks + 1 and int(audio.diagnostics().dropped.get("click", 0)) >= 1, "same-event cooldown drops a dense duplicate")

	# Pause is temporary: configured volumes remain and music resumes, then a
	# town context change works after returning from battle.
	audio.volumes(0.37, 0.61)
	audio.set_paused(true)
	await create_timer(0.08).timeout
	check(audio.diagnostics().paused and is_equal_approx(audio.music_volume, 0.37) and is_equal_approx(audio.sfx_volume, 0.61), "pause keeps configured settings while applying temporary pause")
	audio.set_paused(false)
	audio.set_context("town")
	await create_timer(1.25).timeout
	check(not audio.diagnostics().paused and audio.diagnostics().context == "town" and is_equal_approx(audio.music_volume, 0.37), "resume and return-to-town restore configured music state")

	# Capture the final mix after each independent zero-volume operation.
	audio.volumes(0.0, 0.0); clear_capture(); audio.play("explosion")
	var silent := await collect(0.25)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero values mute both independent buses")
	check(float(silent.peak) <= 0.0001, "actual final-mix capture is silent at zero volumes")
	print("AUDIO_CAPTURE frames=%d peak=%.6f town_peak=%.6f battle_peak=%.6f load_peak=%.6f silent_peak=%.6f max_active_voices=%d town_discarded=%d battle_discarded=%d load_discarded=%d silent_discarded=%d" % [samples, peak, float(town_mix.peak), float(battle_mix.peak), float(load_mix.peak), float(silent.peak), max_active_voices, int(town_mix.discarded), int(battle_mix.discarded), int(load_mix.discarded), int(silent.discarded)])

	audio.shutdown(); audio.shutdown()
	check(audio.voices.is_empty() and audio.effects.is_empty() and audio.music.stream == null and audio.music_next.stream == null, "idempotent shutdown releases streams and voice references")
	audio.queue_free()
	await process_frame
	print("AUDIO RUNTIME FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
