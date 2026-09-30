extends SceneTree

var failures := 0
var main: Control
var folder := ""

func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func has_text(node: Node, needle: String) -> bool:
	for child in node.get_children():
		if child is Label and child.text.contains(needle): return true
		if has_text(child, needle): return true
	return false

func snapshot_lines(prefix: String, snapshot: Dictionary) -> Array[String]:
	return [
		"%s：攻击 %s · 生命 %s" % [prefix, main.number_text(snapshot.get("base_attack", 0)), main.number_text(snapshot.get("max_hp", 0))],
		"减伤 %.0f%% · 战力 %s" % [float(snapshot.get("damage_reduction", 0.0)) * 100.0, main.number_text(snapshot.get("power", 0))],
	]

func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var result := find_button(child, text)
		if result != null: return result
	return null

func click(button: Button) -> void:
	check(button != null and not button.disabled, "mouse target is available")
	if button == null or button.disabled: return
	var point := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	folder = "user://power-ui-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	profile.ensure_round_one()
	profile.data.growth_exp = ProgressionData.exp_for_level(20)
	profile.data.campaign.first_clears = {"forest_treebridge":true,"forest_spore_corridor":true,"forest_moss_guardian":true,"mine_entrance":true,"mine_fracture":true,"mine_furnace":true,"sky_corridor":true,"sky_altar":true,"sky_lord":true}
	profile.data.inventory.stacks.echo_gem = 1
	profile.save()
	main = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile
	root.add_child(main)
	await process_frame
	# Explicit fixture state: this test sets cumulative experience directly, then
	# verifies that all UI reads production Profile/Campaign snapshots.
	var campaign := profile.combat_snapshot("campaign")
	var arena := profile.combat_snapshot("ai")
	check(int(campaign.power) > 1000 and int(campaign.max_hp) > int(arena.max_hp), "campaign snapshot uses permanent progression while arena remains legacy scale")
	check(has_text(main.screen, "Lv. 20") and has_text(main.screen, "战力"), "town exposes growth level and power")
	await click(find_button(main, "远征板"))
	await click(find_button(main, "第三章 · 天空遗址"))
	check(has_text(main.screen, "我的战力") and has_text(main.screen, "推荐"), "expedition shows real own and recommended power")
	main.start_campaign("sky_corridor", "normal"); await process_frame
	check(main.battle != null and int(main.battle.session.fighters[0].max_hp) == int(campaign.max_hp) and int(main.battle.session.fighters[1].max_hp) != int(campaign.max_hp), "Main forwards frozen campaign player and enemy snapshots into live session")
	main.leave_campaign(); await process_frame
	main.battle_mode = "ai"; main.start_battle(); await process_frame
	check(main.battle != null and int(main.battle.session.fighters[0].max_hp) == int(arena.max_hp) and int(main.battle.session.direct_hit_bonus) == int(arena.direct_hit_bonus), "Main AI session keeps legacy snapshot scale")
	main.battle_mode = "training"; main.start_battle(); await process_frame
	check(main.battle != null and int(main.battle.session.fighters[0].max_hp) == int(arena.max_hp) and int(main.battle.session.direct_hit_bonus) == int(arena.direct_hit_bonus), "Main training session keeps legacy snapshot scale")
	main.battle_mode = "local"; main.start_battle(); await process_frame
	check(main.battle != null and int(main.battle.session.fighters[0].max_hp) == int(arena.max_hp) and int(main.battle.session.direct_hit_bonus) == int(arena.direct_hit_bonus), "Main local session keeps legacy snapshot scale")
	main.show_town(); await process_frame
	await click(find_button(main, "角色小屋"))
	check(has_text(main.screen, "配装预览") and has_text(main.screen, "选择后"), "loadout uses preview snapshots before save")
	await click(find_button(main, "←  风铃港"))
	await click(find_button(main, "背包工坊"))
	await click(find_button(main, "工坊"))
	var upgrade_preview: Dictionary = main.forge.preview_upgrade(str(main.profile.data.loadout.weapon_instance_id))
	var before_lines := snapshot_lines("强化前", upgrade_preview.before_snapshot)
	var after_lines := snapshot_lines("强化后", upgrade_preview.after_snapshot)
	check(has_text(main.screen, before_lines[0]) and has_text(main.screen, before_lines[1]) and has_text(main.screen, after_lines[0]) and has_text(main.screen, after_lines[1]), "forge displays authoritative before and after snapshot values")
	await click(find_button(main, "镶嵌"))
	check(has_text(main.screen, "这把装备") and has_text(main.screen, "战力"), "socket screen displays power deltas")
	main.queue_free(); await process_frame
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("POWER UI FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
