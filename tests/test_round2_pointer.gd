extends SceneTree

var failures := 0
var main: Control
var folder := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := find_button(child, text)
		if found != null:
			return found
	return null

func mouse_event(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func pointer_click(button: Button, label: String, allow_disabled: bool = false) -> void:
	check(button != null, "pointer target exists: " + label)
	if button == null:
		return
	check(allow_disabled or not button.disabled, "pointer target enabled: " + label)
	var centre := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = centre
	motion.global_position = centre
	main.get_viewport().push_input(motion, true)
	main.get_viewport().push_input(mouse_event(centre, true), true)
	main.get_viewport().push_input(mouse_event(centre, false), true)
	for i in range(2):
		await process_frame

func click(text: String) -> void:
	await pointer_click(find_button(main, text), text)

func cleanup() -> void:
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	folder = "user://round2-pointer-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	profile.ensure_round_one()
	# Navigation fixture only: materials make the first craft button clickable.
	profile.data.inventory.stacks.woodchip = 12
	profile.data.inventory.stacks.enhancement_dust = 12
	profile.save()
	main = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile
	root.add_child(main)
	for i in range(2):
		await process_frame

	check(main.current_page == "town", "isolated profile opens town")
	await click("远征板")
	check(main.current_page == "expedition", "viewport click opens expedition")
	await click("第二章 · 炽铜矿坑")
	check(main.selected_chapter == 2, "viewport click selects chapter two")
	var locked := find_button(main, "🔒 矿井入口")
	check(locked != null and locked.disabled, "locked mine entrance is visibly disabled")
	await pointer_click(locked, "locked mine entrance", true)
	check(main.current_page == "expedition" and main.selected_stage_id == "mine_entrance", "disabled mine entrance cannot enter battle")
	await click("←  风铃港")
	check(main.current_page == "town", "viewport click returns to town")
	await click("背包工坊")
	check(main.current_page == "inventory", "viewport click opens backpack")
	await click("工坊")
	check(main.current_page == "workshop", "viewport click opens workshop from backpack")
	await click("制作补给")
	check(main.current_page == "crafting", "viewport click opens crafting from workshop")
	await click("制作 1 份")
	check(is_instance_valid(main.modal), "viewport click opens crafting confirmation")
	await click("×")
	check(not is_instance_valid(main.modal), "viewport click cancels crafting confirmation")
	main.queue_free()
	await process_frame
	cleanup()
	print("ROUND2 POINTER FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
