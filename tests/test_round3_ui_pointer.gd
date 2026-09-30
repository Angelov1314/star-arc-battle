extends SceneTree

var failures := 0
var main: Control
var folder := ""

func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var found := find_button(child, text)
		if found != null: return found
	return null

func find_enabled_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text and not child.disabled: return child
		var found := find_enabled_button(child, text)
		if found != null: return found
	return null

func screen_has(node: Node, text: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text.contains(text): return true
		if screen_has(child, text): return true
	return false

func click_button(button: Button, label: String) -> void:
	check(button != null and not button.disabled, "enabled mouse target: " + label)
	if button == null or button.disabled: return
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	var down := InputEventMouseButton.new()
	down.position = point; down.global_position = point; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true
	var up := InputEventMouseButton.new()
	up.position = point; up.global_position = point; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	root.push_input(motion, true); root.push_input(down, true); root.push_input(up, true)
	await process_frame
	await process_frame

func click(text: String) -> void:
	await click_button(find_button(main, text), text)

func double_click_button(button: Button, label: String) -> void:
	check(button != null and not button.disabled, "double-submit mouse target: " + label)
	if button == null or button.disabled: return
	var point := button.get_global_rect().get_center()
	for _i in range(2):
		var down := InputEventMouseButton.new()
		down.position = point; down.global_position = point; down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true
		var up := InputEventMouseButton.new()
		up.position = point; up.global_position = point; up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
		root.push_input(down, true); root.push_input(up, true)
	await process_frame
	await process_frame

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	folder = "user://round3-ui-pointer-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	profile.ensure_round_one()
	profile.data.campaign.first_clears = {"forest_treebridge":true,"forest_spore_corridor":true,"forest_moss_guardian":true,"mine_entrance":true,"mine_fracture":true,"mine_furnace":true,"sky_corridor":true,"sky_altar":true,"sky_lord":true}
	profile.data.gold = 1000
	profile.data.inventory.stacks.relic_shard = 24
	profile.data.inventory.stacks.enhancement_dust = 20
	profile.data.inventory.stacks.echo_gem = 1
	profile.data.inventory.stacks.pierce_gem = 1
	profile.save()
	main = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile
	root.add_child(main)
	await process_frame
	await click("远征板")
	await click("第三章 · 天空遗址")
	check(main.selected_chapter == 3, "mouse path selects third chapter")
	await click("精英")
	check(main.selected_difficulty == "elite", "mouse path toggles elite difficulty")
	await click("←  风铃港")
	await click("背包工坊")
	await click("工坊")
	await click("镶嵌")
	check(main.workshop_tab == "socket", "mouse path opens gem socket tab")
	var socket := find_button(main, "镶嵌 回响晶")
	check(socket != null and not socket.disabled, "socket action is enabled for owned gem")
	var baseline_player_snapshot: Dictionary = main.profile.combat_snapshot("campaign")
	if socket != null: await click_button(socket, "镶嵌 回响晶")
	await process_frame
	var confirm := find_button(main, "确认镶嵌")
	check(confirm != null, "socket opens confirmation")
	if confirm != null: await click_button(confirm, "确认镶嵌")
	await process_frame
	check(str(main.profile.data.inventory.equipment["legacy-weapon-ember"].get("gem_item_id", "")) == "echo_gem", "confirmed socket persists per-instance gem")
	var echo_player_snapshot: Dictionary = main.profile.combat_snapshot("campaign")
	var echo_enemy_snapshot: Dictionary = main.campaign.stage_status("sky_corridor", "normal").enemy_snapshot
	main.start_campaign("sky_corridor", "normal"); await process_frame
	check(int(echo_player_snapshot.max_hp) > int(baseline_player_snapshot.max_hp) and int(main.battle.session.fighters[0].max_hp) == int(echo_player_snapshot.max_hp) and int(main.battle.session.fighters[1].max_hp) == int(echo_enemy_snapshot.max_hp), "campaign snapshot applies echo max HP only to player")
	main.leave_campaign(); await process_frame
	main.workshop_tab = "socket"; main.show_workshop(); await process_frame
	var replace_socket := find_button(main, "镶嵌 贯穿晶")
	check(replace_socket != null and not replace_socket.disabled, "replacement gem action is enabled")
	if replace_socket != null: await click_button(replace_socket, "镶嵌 贯穿晶")
	var replace_confirm := find_button(main, "确认镶嵌")
	if replace_confirm != null: await click_button(replace_confirm, "确认镶嵌")
	var pierce_player_snapshot: Dictionary = main.profile.combat_snapshot("campaign")
	var pierce_enemy_snapshot: Dictionary = main.campaign.stage_status("sky_corridor", "normal").enemy_snapshot
	main.start_campaign("sky_corridor", "normal"); await process_frame
	check(int(pierce_player_snapshot.max_hp) < int(echo_player_snapshot.max_hp) and int(pierce_player_snapshot.direct_hit_bonus) > int(echo_player_snapshot.direct_hit_bonus) and int(main.battle.session.fighters[0].max_hp) == int(pierce_player_snapshot.max_hp) and int(main.battle.session.direct_hit_bonus) == int(pierce_player_snapshot.direct_hit_bonus) and int(pierce_enemy_snapshot.max_hp) == int(echo_enemy_snapshot.max_hp) and int(main.battle.session.fighters[1].max_hp) == int(pierce_enemy_snapshot.max_hp), "replacement snapshot removes HP, adds direct hit, and leaves enemy unchanged")
	main.leave_campaign(); await process_frame
	main.show_workshop(); await process_frame
	var unsocket := find_button(main, "拆卸并返还宝石")
	check(unsocket != null and not unsocket.disabled, "unsocket action is enabled")
	if unsocket != null: await click_button(unsocket, "拆卸并返还宝石")
	var remove_confirm := find_button(main, "确认拆卸")
	check(remove_confirm != null, "unsocket opens confirmation")
	if remove_confirm != null: await click_button(remove_confirm, "确认拆卸")
	await process_frame
	check(main.profile.data.inventory.equipment["legacy-weapon-ember"].get("gem_item_id", null) == null and main.inventory.stack_count("echo_gem") == 1, "unsocket returns the gem exactly once")
	main.show_workshop(); await process_frame
	main.profile.data.inventory.equipment["pointer-duplicate-volt"] = {"template_id":"volt","level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0}
	main.profile.save()
	await click("分解")
	check(main.workshop_tab == "dismantle", "mouse path opens dismantle tab")
	var equipped := find_button(main, "爆炎炮 +0")
	check(equipped != null and equipped.disabled, "equipped weapon is visibly disabled for dismantle")
	var duplicate := find_enabled_button(main, "雷光弩 +0")
	check(duplicate != null and not duplicate.disabled, "duplicate weapon is eligible for dismantle")
	if duplicate != null: await click_button(duplicate, "雷光弩 +0")
	var dismantle_preview := find_button(main, "预览并进入二次确认")
	if dismantle_preview != null: await click_button(dismantle_preview, "预览并进入二次确认")
	check(main.modal != null, "dismantle opens a second confirmation")
	var cancel_dismantle := find_button(main, "×")
	if cancel_dismantle != null: await click_button(cancel_dismantle, "×")
	check(main.modal == null, "dismantle confirmation can be cancelled")
	dismantle_preview = find_button(main, "预览并进入二次确认")
	if dismantle_preview != null: await click_button(dismantle_preview, "预览并进入二次确认")
	var final_dismantle := find_button(main, "确认永久分解")
	if final_dismantle != null: await double_click_button(final_dismantle, "确认永久分解")
	var remaining_volt := 0
	for instance_id in main.profile.data.inventory.equipment:
		if str(main.profile.data.inventory.equipment[instance_id].get("template_id", "")) == "volt": remaining_volt += 1
	check(remaining_volt == 1 and main.inventory.stack_count("enhancement_dust") >= 21, "double-submit dismantle removes one instance and grants one return")
	main.start_campaign("sky_corridor", "normal"); await process_frame
	var loss := {"id":"round3-ui-loss","winner":1,"mode":"campaign","rounds":4,"stats":[{"hits":1,"damage":120},{"hits":3,"damage":900}],"seconds":100.0,"stage_id":"sky_corridor","player_actions":4,"medkits_used":0,"supply_uses":{}}
	main.show_campaign_result(loss); await process_frame
	check(screen_has(main.screen, "金币 +17"), "campaign loss result displays its actual saved gold")
	main.queue_free(); await process_frame
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("ROUND3 UI POINTER FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
