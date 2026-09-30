extends SceneTree
var failures := 0
func check(v: bool, label: String) -> void:
	if v: print("PASS: "+label)
	else: failures+=1; printerr("FAIL: "+label)
func find_all(node: Node, list: Array) -> void:
	for child in node.get_children():
		if child is CheckBox: list.append(child)
		find_all(child,list)
func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text==text: return child
		var found := find_button(child,text)
		if found: return found
	return null
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := "user://round2-lock-ui-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.profile=PlayerProfile.new(folder+"/profile.json")
	root.add_child(main)
	main.show_inventory()
	await process_frame
	var boxes: Array=[]
	find_all(main.screen,boxes)
	check(boxes.size()>=2,"equipment checkboxes visible")
	boxes[0].pressed.emit(); boxes[1].pressed.emit()
	await process_frame
	var lock := find_button(main.screen,"批量锁定")
	check(lock!=null and not lock.disabled,"batch lock enabled after checkbox selection")
	lock.pressed.emit(); await process_frame
	check(bool(main.profile.data.inventory.equipment["legacy-weapon-ember"].locked) and bool(main.profile.data.inventory.equipment["legacy-weapon-volt"].locked),"batch lock persists in profile")
	var restored := PlayerProfile.new(folder+"/profile.json")
	check(bool(restored.data.inventory.equipment["legacy-weapon-ember"].locked),"locked state reloads")
	main.show_inventory(); await process_frame; boxes=[]; find_all(main.screen,boxes)
	boxes[0].pressed.emit(); boxes[1].pressed.emit(); await process_frame
	var unlock := find_button(main.screen,"批量解锁"); unlock.pressed.emit(); await process_frame
	check(not bool(main.profile.data.inventory.equipment["legacy-weapon-ember"].locked),"batch unlock works")
	print("LOCKS UI FAILURES: %d"%failures)
	quit(0 if failures==0 else 1)
