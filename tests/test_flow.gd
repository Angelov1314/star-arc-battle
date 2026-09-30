extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(condition: bool, text: String) -> void:
	if not condition:
		failures+=1
		printerr("FAIL: "+text)
	else: print("PASS: "+text)
func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text==text: return child
		var found := find_button(child,text)
		if found: return found
	return null
func find_button_prefix(node: Node, prefix: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text.begins_with(prefix): return child
		var found := find_button_prefix(child,prefix)
		if found: return found
	return null
func press(main: Node,text: String) -> void:
	var button := find_button(main.screen,text)
	check(button!=null and not button.disabled,"button available: "+text)
	if button and not button.disabled: button.pressed.emit()
	await process_frame
func press_prefix(main: Node,prefix: String) -> void:
	var button := find_button_prefix(main.screen,prefix)
	check(button!=null and not button.disabled,"button available: "+prefix)
	if button and not button.disabled: button.pressed.emit()
	await process_frame
func run() -> void:
	var main=load("res://scenes/Main.tscn").instantiate()
	var folder := "user://flow-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	main.profile=PlayerProfile.new(folder+"/profile.json")
	main.profile.ensure_round_one()
	main.profile.data.inventory.stacks.enhancement_dust = 2
	main.profile.data.inventory.stacks.woodchip = 1
	main.profile.save()
	root.add_child(main)
	main.show_town()
	await press(main,"角色小屋")
	await press(main,"选择武器")
	check(main.selected_weapon=="volt","weapon preview selection")
	await press(main,"保存配装")
	check(main.profile.data.weapon=="volt","save loadout")
	await press(main,"←  风铃港")
	await press(main,"背包工坊")
	await press(main,"工坊")
	await press_prefix(main,"雷光弩")
	await press(main,"强化 · 60 金币")
	check(is_instance_valid(main.modal),"upgrade confirmation")
	await press(main,"确认强化")
	check(main.profile.data.gold==120 and main.profile.data.levels.volt==1,"upgrade debits once")
	main.show_lobby()
	main.battle_mode="ai"
	await press(main,"进入竞技场   →")
	check(main.current_page=="battle" and main.battle.session.fighters[0].weapon=="volt","battle takes saved loadout")
	var battle: BattleView = main.battle
	battle.set_physics_process(false)
	battle.set_process(false)
	battle.session.paused=false
	var s: BattleSession=battle.session
	var frames:=0
	while s.phase!=BattleSession.Phase.COMPLETE and frames<30000:
		if s.phase==BattleSession.Phase.AIM and s.turn==0: s.advance_ai()
		s.tick()
		frames+=1
	await process_frame
	await process_frame
	check(main.current_page=="result","combat reaches result screen")
	check(main.profile.data.matches==1,"result reward persisted")
	var gold: int=main.profile.data.gold
	await press(main,"返回风铃港")
	check(main.current_page=="town","result returns to town")
	var restored := PlayerProfile.new(folder+"/profile.json")
	check(restored.data.gold==gold and restored.data.weapon=="volt","restart preserves earned resources and loadout")
	main.start_battle()
	await process_frame
	main.battle.set_paused(true)
	check(main.battle.session.paused and is_instance_valid(main.battle.pause_layer),"pause UI connected")
	await press(main,"重新挑战")
	await process_frame
	check(main.battle.session.round_number==1 and main.battle.session.shots.is_empty(),"restart resets all match state")
	main.battle.set_paused(true)
	await press(main,"返回风铃港")
	await process_frame
	check(main.profile.data.gold==gold and main.profile.data.matches==1,"abandoned match grants no reward")
	main.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder+"/"+name)
	DirAccess.remove_absolute(folder)
	print("FLOW FAILURES: %d"%failures)
	quit(0 if failures==0 else 1)
