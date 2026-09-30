extends SceneTree

var failures := 0
var folder := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func instance_count(profile: PlayerProfile, template_id: String) -> int:
	var count := 0
	for instance_id in profile.data.inventory.equipment:
		if str(profile.data.inventory.equipment[instance_id].get("template_id", "")) == template_id:
			count += 1
	return count

func fixture_unlocked_mine(profile: PlayerProfile) -> void:
	for stage_id in ["forest_treebridge", "forest_spore_corridor", "forest_moss_guardian", "mine_entrance", "mine_fracture"]:
		profile.data.campaign.first_clears[stage_id] = true

func cleanup() -> void:
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)

func run() -> void:
	folder = "user://round2-integrity-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)

	# A new profile has every definition available to the UI, but owns only the four
	# legacy instances and no Round 2 weapon or material grants.
	var fresh := PlayerProfile.new(folder + "/fresh.json")
	var fresh_inventory := InventoryService.new(fresh)
	check(ItemData.DEFINITIONS.size() == 14, "all fourteen item definitions are registered")
	check(fresh.data.inventory.equipment.size() == 4 and instance_count(fresh, "rockcore") == 0, "new profile owns only four initial instances and no rockcore")
	check(fresh_inventory.stack_count("copper_ore") == 0 and fresh_inventory.stack_count("armor_breaker") == 0, "new profile receives no Round 2 material or supply")
	check(not fresh_inventory.equip_instance("missing-rockcore").ok, "cannot equip an unowned rockcore instance")

	# v1/v2 upgrade into the v3 schema; a native v3 file retains resources, level,
	# and equipment exactly through reload.
	for version in [1, 2]:
		var legacy := {"version":version, "gold":731, "xp":88, "wins":4, "matches":9, "weapon":"volt", "charm":"moss", "levels":{"ember":2, "volt":3}, "ledger":["legacy"], "music":0.2, "sfx":0.8}
		var legacy_path := folder + "/v%d.json" % version
		write_json(legacy_path, legacy)
		var migrated := PlayerProfile.new(legacy_path)
		InventoryService.new(migrated)
		check(migrated.data.version == PlayerProfile.CURRENT_VERSION and int(migrated.data.gold) == 731 and int(migrated.data.inventory.equipment["legacy-weapon-volt"].level) == 3 and str(migrated.data.loadout.weapon_instance_id) == "legacy-weapon-volt", "v%d migration preserves resources, level, equipment, and loadout" % version)
	var v3_path := folder + "/v3.json"
	var v3 := PlayerProfile.new(v3_path)
	InventoryService.new(v3)
	v3.data.gold = 444
	v3.data.inventory.stacks.woodchip = 17
	v3.data.inventory.equipment["legacy-weapon-ember"].level = 4
	v3.data.inventory.equipment["legacy-weapon-ember"].invested_materials = {"woodchip":10, "enhancement_dust":20}
	check(v3.save(), "native v3 fixture writes")
	var v3_reloaded := PlayerProfile.new(v3_path)
	check(int(v3_reloaded.data.gold) == 444 and int(v3_reloaded.data.inventory.stacks.woodchip) == 17 and int(v3_reloaded.data.inventory.equipment["legacy-weapon-ember"].level) == 4 and int(v3_reloaded.data.inventory.equipment["legacy-weapon-ember"].invested_materials.enhancement_dust) == 20, "native v3 reload preserves resources, level, and equipment")

	var crafting := PlayerProfile.new(folder + "/crafting.json")
	var crafting_inventory := InventoryService.new(crafting)
	crafting.data.inventory.stacks.copper_ore = 2
	crafting.data.inventory.stacks.enhancement_dust = 2
	check(crafting.save(), "crafting fixture writes")
	check(crafting_inventory.craft("armor_breaker", 1).ok and crafting_inventory.stack_count("armor_breaker") == 1, "craft quantity one succeeds atomically")
	var before_invalid: Dictionary = crafting.data.inventory.stacks.duplicate(true)
	check(not crafting_inventory.craft("armor_breaker", 0).ok and not crafting_inventory.craft("armor_breaker", 100).ok and crafting.data.inventory.stacks == before_invalid, "craft quantities zero and one hundred reject without changes")
	check(not crafting_inventory.craft("armor_breaker", 1).ok and crafting_inventory.stack_count("armor_breaker") == 1 and crafting_inventory.stack_count("copper_ore") == 0, "insufficient craft makes no partial debit or output")
	crafting.data.inventory.stacks.copper_ore = 2
	crafting.data.inventory.stacks.enhancement_dust = 2
	check(crafting.save(), "craft rollback fixture writes")
	var craft_disk_gold := int(crafting.data.gold)
	crafting.path = folder + "/missing-craft/profile.json"
	check(not crafting_inventory.craft("armor_breaker", 1).ok and crafting_inventory.stack_count("armor_breaker") == 1 and crafting_inventory.stack_count("copper_ore") == 2, "craft save failure rolls memory back")
	crafting.path = folder + "/crafting.json"
	var craft_reloaded := PlayerProfile.new(crafting.path)
	check(craft_reloaded.data.inventory.stacks.get("armor_breaker", 0) == 1 and craft_reloaded.data.inventory.stacks.get("copper_ore", 0) == 2 and int(craft_reloaded.data.gold) == craft_disk_gold, "craft write failure leaves persisted profile unchanged")

	var locks := PlayerProfile.new(folder + "/locks.json")
	var locks_inventory := InventoryService.new(locks)
	check(locks.save(), "lock fixture writes")
	check(not locks_inventory.set_locked(["legacy-weapon-ember", "invalid-instance"], true).ok, "batch lock rejects a selection containing an invalid instance")
	var locks_reloaded := PlayerProfile.new(locks.path)
	check(not bool(locks_reloaded.data.inventory.equipment["legacy-weapon-ember"].locked), "invalid batch lock reload shows no partial lock")

	var forge_profile := PlayerProfile.new(folder + "/forge.json")
	var forge := ForgeService.new(forge_profile)
	forge_profile.data.inventory.equipment["legacy-weapon-ember"].level = 5
	forge_profile.data.gold = 1700
	forge_profile.data.inventory.stacks.enhancement_dust = 48
	forge_profile.data.inventory.stacks.copper_ore = 27
	check(forge_profile.save(), "forge fixture writes")
	check(forge.upgrade("legacy-weapon-ember").code == "locked" and int(forge_profile.data.inventory.equipment["legacy-weapon-ember"].level) == 5, "actual plus-five upgrade rejects before furnace clear")
	forge_profile.data.campaign.first_clears.mine_furnace = true
	check(forge_profile.save(), "furnace unlock fixture writes")
	for target_level in [6, 7, 8]:
		var before_gold := int(forge_profile.data.gold)
		var before_dust := int(forge_profile.data.inventory.stacks.enhancement_dust)
		var before_copper := int(forge_profile.data.inventory.stacks.copper_ore)
		var costs: Dictionary = {6:{"gold":420,"dust":12,"copper":6}, 7:{"gold":560,"dust":16,"copper":9}, 8:{"gold":720,"dust":20,"copper":12}}[target_level]
		check(forge.upgrade("legacy-weapon-ember").ok, "actual plus-%d upgrade succeeds" % target_level)
		var forged_reload := PlayerProfile.new(forge_profile.path)
		var forged: Dictionary = forged_reload.data.inventory.equipment["legacy-weapon-ember"]
		check(int(forged.level) == target_level and int(forged_reload.data.gold) == before_gold - int(costs.gold) and int(forged_reload.data.inventory.stacks.enhancement_dust) == before_dust - int(costs.dust) and int(forged_reload.data.inventory.stacks.copper_ore) == before_copper - int(costs.copper) and int(forged.invested_materials.enhancement_dust) == 12 + (16 if target_level >= 7 else 0) + (20 if target_level >= 8 else 0) and int(forged.invested_materials.copper_ore) == 6 + (9 if target_level >= 7 else 0) + (12 if target_level >= 8 else 0), "plus-%d cost and invested materials persist after reload" % target_level)
		forge_profile = forged_reload
		forge = ForgeService.new(forge_profile)
	check(forge.upgrade("legacy-weapon-ember").code == "max_level", "actual plus-eight cap rejects another upgrade")

	var empty_rewards := PlayerProfile.new(folder + "/empty-rewards.json")
	var empty_campaign := CampaignService.new(empty_rewards)
	var empty_run := empty_campaign.begin_run("forest_treebridge")
	var empty_result := empty_campaign.settle_run(empty_run.run_id, "win", {})
	check(empty_result.ok and empty_result.rewards.get("objectives", []).is_empty(), "empty battle stats grant no objective rewards")
	var eight_rewards := PlayerProfile.new(folder + "/eight-rewards.json")
	var eight_campaign := CampaignService.new(eight_rewards)
	var eight_run := eight_campaign.begin_run("forest_treebridge")
	var eight_result := eight_campaign.settle_run(eight_run.run_id, "win", {"medkits_used":0, "player_actions":8})
	check(eight_result.ok and eight_result.rewards.get("objectives", []).size() == 2 and int(eight_result.rewards.gold) == 285, "eight actions and no medkit grant both first-time objectives")
	var nine_rewards := PlayerProfile.new(folder + "/nine-rewards.json")
	var nine_campaign := CampaignService.new(nine_rewards)
	var nine_run := nine_campaign.begin_run("forest_treebridge")
	var nine_result := nine_campaign.settle_run(nine_run.run_id, "win", {"medkits_used":1, "player_actions":9})
	check(nine_result.ok and nine_result.rewards.get("objectives", []).is_empty(), "nine actions and a medkit grant no objectives")

	var history_rewards := PlayerProfile.new(folder + "/history-rewards.json")
	var history_inventory := InventoryService.new(history_rewards)
	var history_campaign := CampaignService.new(history_rewards)
	check(history_inventory.configure_supplies([{"item_id":"small_medkit","quantity":1}]).ok, "medkit history fixture configures supply")
	var history_run := history_campaign.begin_run("forest_treebridge")
	check(history_run.supply_commit.call("small_medkit").ok, "medkit consumption is persisted before settlement")
	var history_result := history_campaign.settle_run(history_run.run_id, "win", {"medkits_used":0, "player_actions":9})
	check(not ("forest_treebridge:no_medkit" in history_result.rewards.get("objectives", [])), "persisted medkit consumption blocks no-medkit reward even with stale stats")

	var recovery := PlayerProfile.new(folder + "/reward-recovery.json")
	var recovery_campaign := CampaignService.new(recovery)
	var recovery_run := recovery_campaign.begin_run("forest_treebridge")
	var recovery_gold := int(recovery.data.gold)
	recovery.path = folder + "/missing-reward/profile.json"
	var failed_reward := recovery_campaign.settle_run(recovery_run.run_id, "win", {"medkits_used":0, "player_actions":8})
	check(not failed_reward.ok and int(recovery.data.gold) == recovery_gold and not bool(recovery.data.campaign.first_clears.get("forest_treebridge", false)) and not recovery.data.active_run.is_empty(), "normal, first, and objective rewards roll back together on write failure")
	recovery.path = folder + "/reward-recovery.json"
	var recovered_reward := recovery_campaign.settle_run(recovery_run.run_id, "win", {"medkits_used":0, "player_actions":8})
	var recovery_reload := PlayerProfile.new(recovery.path)
	check(recovered_reward.ok and int(recovery_reload.data.gold) == recovery_gold + 285 and int(recovery_reload.data.inventory.stacks.enhancement_dust) == 6 and bool(recovery_reload.data.campaign.first_clears.get("forest_treebridge", false)), "reward recovery writes normal, first, and objective rewards once")
	check(recovery_campaign.settle_run(recovery_run.run_id, "win", {"medkits_used":0, "player_actions":8}).code == "already_settled", "retried reward settlement is idempotent")
	var recovery_again := PlayerProfile.new(recovery.path)
	check(int(recovery_again.data.gold) == recovery_gold + 285 and int(recovery_again.data.inventory.stacks.enhancement_dust) == 6, "idempotent retry does not duplicate persisted rewards")

	var rock_profile := PlayerProfile.new(folder + "/rockcore.json")
	fixture_unlocked_mine(rock_profile)
	check(rock_profile.save(), "rockcore fixture writes")
	var rock_campaign := CampaignService.new(rock_profile)
	var rock_run := rock_campaign.begin_run("mine_furnace")
	check(rock_campaign.settle_run(rock_run.run_id, "win", {}).ok, "first furnace clear settles")
	var rock_after_first := PlayerProfile.new(rock_profile.path)
	check(instance_count(rock_after_first, "rockcore") == 1, "first furnace clear grants one rockcore after restart")
	var rock_repeat_campaign := CampaignService.new(rock_after_first)
	var rock_repeat_run := rock_repeat_campaign.begin_run("mine_furnace")
	check(rock_repeat_campaign.settle_run(rock_repeat_run.run_id, "win", {}).ok, "repeat furnace win settles")
	var rock_after_repeat := PlayerProfile.new(rock_after_first.path)
	check(instance_count(rock_after_repeat, "rockcore") == 1 and int(rock_after_repeat.data.campaign.boss_repeat_wins.get("mine_furnace", 0)) == 1, "restarted repeat boss clear never grants a second rockcore")

	cleanup()
	print("ROUND2 INTEGRITY FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
