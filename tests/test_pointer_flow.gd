extends SceneTree

var failures := 0
var main: Control
var folder := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var found := find_button(child, text)
		if found != null: return found
	return null

func mouse_event(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func click(text: String) -> void:
	var button := find_button(main, text)
	check(button != null and not button.disabled, "pointer target available: " + text)
	if button == null or button.disabled: return
	var centre := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = centre
	move.global_position = centre
	main.get_viewport().push_input(move, true)
	main.get_viewport().push_input(mouse_event(centre, true), true)
	main.get_viewport().push_input(mouse_event(centre, false), true)
	for i in range(2): await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	folder = "user://pointer-flow-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	main = load("res://scenes/Main.tscn").instantiate()
	main.profile = PlayerProfile.new(folder + "/profile.json") # Inject before _ready.
	root.add_child(main)
	for i in range(2): await process_frame
	check(main.current_page == "town", "isolated Main opens at town")
	await click("远征板")
	check(main.current_page == "expedition", "viewport pointer opens expedition from town")
	await click("←  风铃港")
	check(main.current_page == "town", "viewport pointer returns to town")
	await click("背包工坊")
	check(main.current_page == "inventory", "viewport pointer opens inventory from town")
	main.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("POINTER FLOW FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
