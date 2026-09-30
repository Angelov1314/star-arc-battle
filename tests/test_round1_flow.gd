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

func press(text: String) -> void:
	var button := find_button(main, text)
	check(button != null and not button.disabled, "enabled control: " + text)
	if button != null and not button.disabled:
		button.pressed.emit()
		await process_frame

func run() -> void:
	folder = "user://round1-flow-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	var inventory := InventoryService.new(profile)
	profile.data.inventory.stacks.enhancement_dust = 20
	profile.data.inventory.stacks.woodchip = 20
	check(profile.save(), "isolated fixture persists")
	check(inventory.configure_supplies([{"item_id":"small_medkit","quantity":1},{"item_id":"stamina_tonic","quantity":1}]).ok, "two supply slots configured")
	main = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile # Must happen before _ready, so no real profile is read.
	root.add_child(main)
	await process_frame

	await press("远征板")
	var locked := find_button(main, "🔒 孢子回廊")
	check(locked != null and locked.disabled, "locked expedition node is visibly disabled")
	await press("进入普通副本   →")
	check(main.current_page == "battle" and not main.active_campaign_run.is_empty(), "expedition starts isolated campaign run")
	check(main.inventory.stack_count("small_medkit") == 2, "entering campaign does not deduct carried stock")
	main.battle.session.fighters[0].hp = 500.0 # Fixture injury; combat simulation is covered separately.
	main.battle.session.changed.emit()
	await process_frame
	await press("急救 1")
	check(main.battle.session.fighters[0].hp == 750.0 and main.inventory.stack_count("small_medkit") == 1, "injured player uses UI medkit after saved debit")
	main.battle.session.finish(0) # Fixture result; this is a UI/save flow test, not a combat balance test.
	for i in range(3): await process_frame
	check(main.current_page == "campaign_result" and bool(profile.data.campaign.first_clears.get("forest_treebridge", false)), "campaign win saves first clear and opens result")
	check(main.inventory.stack_count("enhancement_dust") >= 22 and main.inventory.stack_count("woodchip") >= 21, "campaign reward enters inventory")
	await press("回到远征")
	check(main.campaign.can_enter("forest_spore_corridor").ok, "first clear unlocks spore corridor")

	main.show_inventory()
	await process_frame
	# Select by direct UI selection after confirming the inventory board is displayed;
	# it mirrors a material-card click without depending on card order.
	main.select_inventory_item(ItemData.definition("enhancement_dust"))
	await process_frame
	check(main.selected_item_id == "enhancement_dust" and main.current_page == "inventory", "material detail selection is rendered")
	var search: LineEdit = null
	for child in main.screen.get_children():
		if child is LineEdit: search = child
	check(search != null, "inventory search control exists")
	if search != null:
		search.text = "不存在的多字物品"
		search.text_changed.emit(search.text)
		for i in range(2): await process_frame
	var next_page := find_button(main, "下一页")
	check(main.inventory_search == "不存在的多字物品" and next_page != null and next_page.disabled, "multi-character zero-match search disables pagination")
	await press("前往远征")
	check(main.current_page == "expedition", "inventory source action returns to expedition")

	main.show_workshop()
	await process_frame
	var gold := int(profile.data.gold)
	var dust: int = main.inventory.stack_count("enhancement_dust")
	var wood: int = main.inventory.stack_count("woodchip")
	await press("强化 · 60 金币")
	await press("确认强化")
	check(int(profile.data.levels.ember) == 1 and int(profile.data.gold) == gold - 60 and main.inventory.stack_count("enhancement_dust") == dust - 2 and main.inventory.stack_count("woodchip") == wood - 1, "forge control debits gold and both materials")

	main.queue_free()
	await process_frame
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("ROUND1 FLOW FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
