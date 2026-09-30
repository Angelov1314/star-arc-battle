extends SceneTree

var failures := 0

func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func screen_has(node: Node, needle: String) -> bool:
	for child in node.get_children():
		if child is Label and needle in child.text: return true
		if child is Button and needle in child.text: return true
		if screen_has(child, needle): return true
	return false

func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var match := find_button(child, text)
		if match != null: return match
	return null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var folder := "user://round2-flow-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.profile = PlayerProfile.new(folder + "/profile.json")
	root.add_child(main)
	await process_frame

	main.show_expedition()
	await process_frame
	check(screen_has(main.screen,"不使用急救包") and screen_has(main.screen,"8 次行动内"),"first chapter shows both optional goals")
	check(not main.campaign.can_enter("mine_entrance").ok,"mine entrance remains locked before first chapter boss")
	main.selected_chapter = 2
	main.selected_stage_id = "mine_entrance"
	main.show_expedition()
	await process_frame
	check(screen_has(main.screen,"完成「苔甲守卫」后解锁") and screen_has(main.screen,"进入副本"),"locked mine chapter explains the required clear")

	for stage_id in ["forest_treebridge","forest_spore_corridor","forest_moss_guardian","mine_entrance","mine_fracture"]:
		main.profile.data.campaign.first_clears[stage_id] = true
	main.profile.data.inventory.stacks.copper_ore = 6
	main.profile.data.inventory.stacks.enhancement_dust = 12
	main.profile.data.gold = 600
	main.profile.save()
	main.campaign = CampaignService.new(main.profile)
	var furnace: Dictionary = main.campaign.begin_run("mine_furnace")
	var rewards: Dictionary = main.campaign.settle_run(str(furnace.run_id),"win",{})
	check(rewards.ok and rewards.rewards.groups.size() == 2 and int(rewards.rewards.stacks.get("rockcore",0)) == 1,"furnace first clear shows normal and first-clear rockcore rewards")
	var rock_id := ""
	for instance_id in main.profile.data.inventory.equipment:
		if str(main.profile.data.inventory.equipment[instance_id].template_id) == "rockcore": rock_id = str(instance_id)
	check(not rock_id.is_empty(),"rockcore is granted as a weapon")
	main.profile.data.inventory.equipment[rock_id].level = 5
	main.profile.data.campaign.first_clears.erase("mine_furnace")
	main.profile.save()
	main.show_character()
	await process_frame
	check(screen_has(main.screen,"雷光弩") and screen_has(main.screen,"岩芯炮"),"character screen lists only owned weapons, including the first-clear rockcore")
	main.selected_weapon = "rockcore"
	main.render_character()
	await process_frame
	var save_loadout := find_button(main.screen,"保存配装")
	save_loadout.pressed.emit()
	await process_frame
	check(main.profile.data.weapon == "rockcore","character screen saves the rockcore loadout")
	main.workshop_instance_id = rock_id
	main.show_workshop()
	await process_frame
	check(screen_has(main.screen,"岩芯炮  +5") and screen_has(main.screen,"完成熔炉核心后开放 +6～+8"),"workshop reads the selected weapon level and gives high-level unlock reason")

	main.profile.data.campaign.first_clears.erase("forest_treebridge")
	main.profile.data.campaign.objectives.erase("forest_treebridge:no_medkit")
	main.profile.data.campaign.objectives.erase("forest_treebridge:six_actions")
	main.profile.save()
	main.campaign = CampaignService.new(main.profile)
	var forest_run: Dictionary = main.campaign.begin_run("forest_treebridge")
	main.active_campaign_run = forest_run
	main.show_campaign_result({"winner":0,"medkits_used":0,"player_actions":6})
	await process_frame
	check(screen_has(main.screen,"普通通关") and screen_has(main.screen,"首次通关") and screen_has(main.screen,"挑战·不用急救包") and screen_has(main.screen,"挑战·8次行动内") and screen_has(main.screen,"以上各项奖励已保存"),"result screen presents normal, first-clear, and named objective rewards separately")

	main.selected_item_id = "armor_breaker"
	main.go_material_source()
	await process_frame
	check(main.selected_chapter == 2 and main.selected_stage_id == "mine_furnace","armor breaker source opens its mine stage")
	check(main.inventory.inventory_items("all","","quality","forest").size() > 0 and main.inventory.inventory_items("all","","quality","mine").size() > 0,"forest and mine source filters are backed by item source data")
	main.inventory_source = "crafting"
	main.show_inventory()
	await process_frame
	check(main.inventory.inventory_items("all","","quality","crafting").size() == 3 and screen_has(main.screen,"来源筛选"),"crafting source filter lists all three craftable supplies")
	main.inventory_source = "starter"
	main.show_inventory()
	await process_frame
	check(main.inventory.inventory_items("all","","quality","starter").size() == 6 and screen_has(main.screen,"来源筛选"),"starter source filter uses item source data")

	check(main.inventory.configure_supplies([{"item_id":"small_medkit","quantity":1},{"item_id":"armor_breaker","quantity":1}]).ok,"two supply types save for expedition")
	main.show_expedition()
	await process_frame
	check(screen_has(main.screen,"小型急救包 ×1") and screen_has(main.screen,"破甲药剂 ×1"),"expedition displays configured supplies")
	print("ROUND2 FLOW FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
