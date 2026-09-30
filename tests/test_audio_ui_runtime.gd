extends SceneTree

## Graphical fixture for the real Settings modal and Pause-menu leave callback.
var failures := 0
var fixture := "user://audio-ui-runtime"

func check(ok: bool, label: String) -> void:
	if ok: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func descendants(node: Node, type_name: String, result: Array = []) -> Array:
	if node.get_class() == type_name: result.append(node)
	for child in node.get_children(): descendants(child, type_name, result)
	return result

func button_named(node: Node, text: String) -> Button:
	for candidate in descendants(node, "Button"):
		if candidate.text == text: return candidate
	return null

func _initialize() -> void: call_deferred("run")

func run() -> void:
	check(not OS.has_feature("headless") and DisplayServer.get_name() != "headless", "graphical UI fixture is required")
	DirAccess.make_dir_recursive_absolute(fixture)
	var profile := PlayerProfile.new(fixture + "/profile.json")
	profile.ensure_round_one(); profile.data.music = 0.55; profile.data.sfx = 0.65; profile.save()
	var main: Variant = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile; root.add_child(main)
	await process_frame; await process_frame
	main.show_settings(); await process_frame
	var sliders := descendants(main.modal, "HSlider")
	check(sliders.size() == 2, "Settings modal exposes both real volume sliders")
	if sliders.size() == 2:
		sliders[0].value = 0.37; sliders[1].value = 0.61
		var save := button_named(main.modal, "保存设置")
		check(save != null, "Settings modal exposes save action")
		if save != null: save.pressed.emit()
		await process_frame; await process_frame
		check(is_equal_approx(main.profile.data.music, 0.37) and is_equal_approx(main.profile.data.sfx, 0.61) and is_equal_approx(main.audio.music_volume, 0.37) and is_equal_approx(main.audio.sfx_volume, 0.61), "saved Settings values reach GameAudio")
	main.start_battle(); await process_frame; await process_frame
	check(main.battle != null and main.audio.diagnostics().target_context == "battle", "actual battle entry starts battle audio transition")
	if main.battle != null:
		main.battle.set_paused(true); await process_frame
		check(main.audio.diagnostics().paused, "actual pause menu temporarily pauses audio")
		main.battle.leave_requested.emit(); await process_frame; await process_frame
		check(main.current_page == "town" and not main.audio.diagnostics().paused and main.audio.diagnostics().target_context == "town", "pause-menu return to town resumes configured audio")
	main.audio.shutdown(); main.queue_free(); await process_frame
	for name in DirAccess.get_files_at(fixture): DirAccess.remove_absolute(fixture + "/" + name)
	DirAccess.remove_absolute(fixture)
	print("AUDIO UI RUNTIME FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
