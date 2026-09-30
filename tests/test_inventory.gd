extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: "+label)
	else:
		failures += 1
		printerr("FAIL: "+label)

func run() -> void:
	var folder := "user://inventory-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder + "/profile.json"
	var profile := PlayerProfile.new(path)
	var inventory := InventoryService.new(profile)
	var campaign := CampaignService.new(profile)
	var forge := ForgeService.new(profile)
	check(profile.data.version == PlayerProfile.CURRENT_VERSION and profile.data.inventory.equipment.size() == 4, "current schema keeps four migrated instances")
	check(inventory.stack_count("small_medkit") == 2 and inventory.stack_count("stamina_tonic") == 2, "starter supplies granted once")
	var reopened := PlayerProfile.new(path)
	var reopened_inventory := InventoryService.new(reopened)
	check(reopened_inventory.stack_count("small_medkit") == 2, "starter supplies are not duplicated after restart")
	check(not inventory.configure_supplies([{"item_id":"small_medkit","quantity":1},{"item_id":"small_medkit","quantity":1}]).ok, "duplicate supply slots reject")
	check(inventory.configure_supplies([{"item_id":"small_medkit","quantity":1},{"item_id":"stamina_tonic","quantity":1}]).ok, "valid supply loadout saves")
	check(not campaign.can_enter("forest_spore_corridor").ok, "locked stage rejects before start")
	var start := campaign.begin_run("forest_treebridge")
	check(start.ok and inventory.stack_count("small_medkit") == 2, "starting run snapshots supplies without deduction")
	var use: Dictionary = start.supply_commit.call("small_medkit")
	check(use.ok and int(use.remaining) == 0 and int(use.stock_remaining) == 1 and inventory.stack_count("small_medkit") == 1 and int(profile.data.active_run.consumed.small_medkit) == 1, "supply commits before battle effect")
	check(not start.supply_commit.call("small_medkit").ok, "run allocation blocks extra supply use")
	check(campaign.abandon_run(start.run_id).ok and inventory.stack_count("small_medkit") == 1, "quit retains committed supply loss")
	var win := campaign.begin_run("forest_treebridge")
	var settled := campaign.settle_run(win.run_id, "win")
	check(settled.ok and settled.rewards.first_clear and int(profile.data.gold) == 345, "first clear reward is saved atomically")
	check(campaign.settle_run(win.run_id, "win").code == "already_settled", "repeated settlement is idempotent")
	check(campaign.can_enter("forest_spore_corridor").ok, "first clear unlocks next stage")
	var fail_path := folder + "/settle.json"
	var fail_profile := PlayerProfile.new(fail_path)
	var fail_campaign := CampaignService.new(fail_profile)
	var fail_run := fail_campaign.begin_run("forest_treebridge")
	var reward_gold := int(fail_profile.data.gold)
	fail_profile.path = folder + "/no-directory/settle.json"
	var failed_settle := fail_campaign.settle_run(fail_run.run_id, "win")
	check(not failed_settle.ok and not bool(fail_profile.data.campaign.first_clears.get("forest_treebridge",false)) and int(fail_profile.data.gold) == reward_gold and not fail_profile.data.active_run.is_empty(), "failed settlement rolls back rewards and unlock")
	fail_profile.path = fail_path
	check(fail_campaign.settle_run(fail_run.run_id, "win").ok and int(fail_profile.data.gold) == reward_gold + 165 and fail_campaign.settle_run(fail_run.run_id, "win").code == "already_settled", "same run retries once after write recovery")
	profile.data.inventory.stacks.enhancement_dust = 0
	profile.data.inventory.stacks.woodchip = 0
	check(profile.save(), "test material drain persists")
	var before_dust := inventory.stack_count("enhancement_dust")
	var preview := forge.preview_upgrade("legacy-weapon-ember")
	check(not forge.upgrade("legacy-weapon-ember").ok and inventory.stack_count("enhancement_dust") == before_dust, "missing materials fails without partial debit")
	profile.data.inventory.stacks.enhancement_dust = 2
	profile.data.inventory.stacks.woodchip = 1
	check(profile.save(), "test material setup persists")
	var old_gold := int(profile.data.gold)
	check(forge.upgrade("legacy-weapon-ember").ok and int(profile.data.levels.ember) == 1 and int(profile.data.gold) == old_gold - 60, "forge consumes all costs and updates compatibility mirror")
	var corrupted := profile.data.duplicate(true)
	corrupted.active_run = {"run_id":"broken","stage_id":"forest_treebridge","status":"running","supplies":{"small_medkit":1},"consumed":{"small_medkit":2}}
	var corrupt_file := FileAccess.open(path,FileAccess.WRITE)
	corrupt_file.store_string(JSON.stringify(corrupted))
	corrupt_file.close()
	var recovered := PlayerProfile.new(path)
	check(recovered.notice.contains("备份") and recovered.data.active_run.is_empty(), "invalid v3 active run recovers from backup")
	var v1 := {"version":1,"gold":731,"xp":88,"wins":4,"matches":9,"weapon":"volt","charm":"moss","levels":{"ember":2,"volt":3},"ledger":["legacy"],"music":0.2,"sfx":0.8}
	var v1_file := FileAccess.open(folder + "/v1.json", FileAccess.WRITE)
	v1_file.store_string(JSON.stringify(v1))
	v1_file.close()
	var migrated_v1 := PlayerProfile.new(folder + "/v1.json")
	InventoryService.new(migrated_v1)
	check(migrated_v1.data.version == PlayerProfile.CURRENT_VERSION and int(migrated_v1.data.gold) == 731 and migrated_v1.data.weapon == "volt" and migrated_v1.data.charm == "moss" and int(migrated_v1.data.levels.volt) == 3 and int(migrated_v1.data.inventory.equipment["legacy-weapon-ember"].level) == 2, "v1 migration preserves legacy loadout, levels and currency")
	var v2 := {"version":2,"gold":542,"xp":61,"wins":3,"matches":7,"weapon":"volt","charm":"moss","levels":{"ember":2,"volt":3},"ledger":["legacy-v2"],"music":0.4,"sfx":0.7}
	var v2_file := FileAccess.open(folder + "/v2.json", FileAccess.WRITE)
	v2_file.store_string(JSON.stringify(v2))
	v2_file.close()
	var migrated_v2 := PlayerProfile.new(folder + "/v2.json")
	InventoryService.new(migrated_v2)
	check(migrated_v2.data.version == PlayerProfile.CURRENT_VERSION and int(migrated_v2.data.gold) == 542 and migrated_v2.data.weapon == "volt" and migrated_v2.data.charm == "moss" and int(migrated_v2.data.levels.volt) == 3 and int(migrated_v2.data.inventory.equipment["legacy-weapon-ember"].level) == 2, "v2 migration preserves legacy loadout, levels and currency")
	var unreachable := PlayerProfile.new(folder + "/missing/profile.json")
	var unavailable_inventory := InventoryService.new(unreachable)
	var before_failed := unavailable_inventory.stack_count("small_medkit")
	check(not unavailable_inventory.configure_supplies([{"item_id":"small_medkit","quantity":1}]).ok and unavailable_inventory.stack_count("small_medkit") == before_failed, "write failure rolls transaction back")
	profile.data.inventory.stacks.woodchip = 4
	profile.data.inventory.stacks.enhancement_dust = 4
	profile.data.inventory.stacks.copper_ore = 4
	profile.save()
	var crafted := inventory.craft("armor_breaker", 2)
	check(crafted.ok and inventory.stack_count("armor_breaker") == 2 and inventory.stack_count("copper_ore") == 0, "crafting is an atomic material transaction")
	check(not inventory.craft("armor_breaker", 1).ok and inventory.stack_count("armor_breaker") == 2, "insufficient craft cannot partially produce")
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("INVENTORY FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
