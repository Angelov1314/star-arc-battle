extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("AUDIO TEST FAILED: " + message)

func _init() -> void:
	var audio := GameAudio.new()
	root.add_child(audio)
	await process_frame
	check(audio.semantic_keys().has("armor_break"), "armor_break mapping")
	check(audio.semantic_keys().has("level_up"), "level_up mapping")
	audio.volumes(0.0, 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music mute at zero")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX mute at zero")
	audio.volumes(0.55, 0.65)
	audio.set_context("battle")
	await create_timer(0.35).timeout
	check(audio.diagnostics().music_playing and audio.diagnostics().music_next_playing, "overlapping music crossfade")
	audio.set_context("town")
	audio.set_context("battle") # rapid reversal must leave the final target audible.
	for key in ["click", "hover", "fire", "explosion", "damage", "level_up", "armor_break"]: audio.play(key)
	await create_timer(1.35).timeout
	var report := audio.diagnostics()
	check(report.context == "battle", "battle context settles")
	check(report.voice_limit == 12, "voice limit")
	check(report.music_bus == "Music" and report.sfx_bus == "SFX", "independent buses")
	audio.set_paused(true); check(audio.diagnostics().paused, "pause state")
	audio.set_context("town") # starts paused and resumes without requiring a fresh context call.
	audio.set_paused(false); check(not audio.diagnostics().paused, "resume state")
	await create_timer(1.35).timeout
	check(audio.diagnostics().context == "town", "paused context resumes")
	audio.shutdown(); audio.shutdown()
	check(audio.voices.is_empty(), "idempotent shutdown")
	print("audio engine checks: ", "PASS" if failures == 0 else "FAIL %d" % failures, " ", report)
	audio.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
