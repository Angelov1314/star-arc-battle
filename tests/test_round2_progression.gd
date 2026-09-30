extends SceneTree

const STAGES := ["forest_treebridge", "forest_spore_corridor", "forest_moss_guardian", "mine_entrance", "mine_fracture", "mine_furnace"]
const MAX_ATTEMPTS_PER_STAGE := 5
const MAX_MATCHES := 30

var failures := 0
var folder := ""
var rows: Array[String] = []
var match_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func stack_summary(profile: PlayerProfile) -> String:
	var values: Array[String] = []
	for item_id in ["woodchip", "enhancement_dust", "copper_ore", "small_medkit", "stamina_tonic", "armor_breaker"]:
		values.append("%s=%d" % [item_id, int(profile.data.inventory.stacks.get(item_id, 0))])
	return ",".join(values)

func equipment_summary(profile: PlayerProfile) -> String:
	var values: Array[String] = []
	var ids: Array = profile.data.inventory.equipment.keys()
	ids.sort()
	for instance_id in ids:
		var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
		values.append("%s:+%d" % [str(equipment.template_id), int(equipment.level)])
	return ",".join(values)

func supply_slots(inventory: InventoryService) -> Array:
	var slots: Array = []
	for item_id in ["small_medkit", "stamina_tonic"]:
		var owned := inventory.stack_count(item_id)
		if owned > 0:
			slots.append({"item_id":item_id, "quantity":mini(2, owned)})
	return slots

func same_stacks(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size(): return false
	for item_id in left:
		if not right.has(item_id) or int(left[item_id]) != int(right[item_id]): return false
	return true

func same_equipment(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size(): return false
	for instance_id in left:
		if not right.has(instance_id): return false
		var original: Dictionary = left[instance_id]
		var loaded: Dictionary = right[instance_id]
		if str(original.template_id) != str(loaded.template_id) or int(original.level) != int(loaded.level) or bool(original.locked) != bool(loaded.locked) or bool(original.is_new) != bool(loaded.is_new): return false
		if not same_stacks(original.invested_materials, loaded.invested_materials): return false
	return true

func same_loadout(left: Dictionary, right: Dictionary) -> bool:
	if str(left.weapon_instance_id) != str(right.weapon_instance_id) or str(left.charm_instance_id) != str(right.charm_instance_id) or left.supplies.size() != right.supplies.size(): return false
	for index in range(left.supplies.size()):
		if str(left.supplies[index].item_id) != str(right.supplies[index].item_id) or int(left.supplies[index].quantity) != int(right.supplies[index].quantity): return false
	return true

func upgrade_owned_weapons(profile: PlayerProfile) -> Array[String]:
	var events: Array[String] = []
	var forge := ForgeService.new(profile)
	var progressed := true
	while progressed:
		progressed = false
		var ids: Array = profile.data.inventory.equipment.keys()
		ids.sort()
		for instance_id in ids:
			var preview := forge.preview_upgrade(str(instance_id))
			if not bool(preview.get("ok", false)):
				continue
			var affordable := int(profile.data.gold) >= int(preview.costs.get("gold", 0))
			for item_id in preview.costs:
				if item_id != "gold":
					affordable = affordable and int(profile.data.inventory.stacks.get(item_id, 0)) >= int(preview.costs[item_id])
			if not affordable:
				continue
			var upgraded := forge.upgrade(str(instance_id))
			check(bool(upgraded.get("ok", false)), "owned weapon upgrade transaction succeeds")
			if bool(upgraded.get("ok", false)):
				var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
				events.append("%s:+%d" % [str(equipment.template_id), int(equipment.level)])
				progressed = true
	return events

func run_campaign_battle(profile: PlayerProfile, campaign: CampaignService, stage_id: String, seed: int) -> Dictionary:
	var inventory := InventoryService.new(profile)
	var slots := supply_slots(inventory)
	var supplies_saved := inventory.configure_supplies(slots)
	check(bool(supplies_saved.get("ok", false)), "%s preparation saves available supplies" % stage_id)
	if not bool(supplies_saved.get("ok", false)):
		return {"ok":false, "reason":"supply_config"}
	var started := campaign.begin_run(stage_id)
	check(bool(started.get("ok", false)), "%s run starts from unlocked campaign state" % stage_id)
	if not bool(started.get("ok", false)):
		return {"ok":false, "reason":"run_start"}
	var weapon_id := str(profile.data.loadout.weapon_instance_id)
	var charm_id := str(profile.data.loadout.charm_instance_id)
	var weapon: Dictionary = profile.data.inventory.equipment[weapon_id]
	var charm: Dictionary = profile.data.inventory.equipment[charm_id]
	var session := BattleSession.new({"mode":"campaign", "seed":seed, "stage_id":stage_id, "stage":started.stage, "stage_config":started.stage_config, "weapon":str(weapon.template_id), "charm":str(charm.template_id), "level":int(weapon.level), "supplies":started.supplies, "supply_commit":started.supply_commit})
	var finished: Array[Dictionary] = []
	session.finished.connect(func(result: Dictionary): finished.append(result.duplicate(true)))
	var ticks := 0
	while session.phase != BattleSession.Phase.COMPLETE and ticks < 30000:
		if session.phase == BattleSession.Phase.AIM and session.turn == 0:
			session.advance_ai()
		session.tick()
		ticks += 1
	check(session.phase == BattleSession.Phase.COMPLETE and finished.size() == 1, "%s battle completes through natural BattleSession flow" % stage_id)
	if session.phase != BattleSession.Phase.COMPLETE or finished.is_empty():
		campaign.abandon_run(str(started.run_id))
		return {"ok":false, "reason":"unfinished", "ticks":ticks}
	var battle: Dictionary = finished[0]
	var outcome := "win" if int(battle.winner) == 0 else "loss"
	var settlement := campaign.settle_run(str(started.run_id), outcome, battle)
	check(bool(settlement.get("ok", false)), "%s %s settlement saves naturally produced result" % [stage_id, outcome])
	return {"ok":bool(settlement.get("ok", false)), "battle":battle, "outcome":outcome, "settlement":settlement, "ticks":ticks, "slots":slots}

func cleanup() -> void:
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)

func write_log(status: String, profile: PlayerProfile) -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/validation/round2")
	var file := FileAccess.open("res://docs/validation/round2/progression-tests.txt", FileAccess.WRITE)
	file.store_string("Command:\ngodot --headless --path . --script tests/test_round2_progression.gd\n\n")
	file.store_string("new_profile_gold=%d\nnew_profile_equipment=%d\n" % [180, 4])
	file.store_string("stage,attempt,seed,outcome,winner,player_actions,medkits_used,supply_uses,gold,stacks,equipment,first_clears,rockcore_instances,ticks\n")
	file.store_string("\n".join(rows) + "\n")
	file.store_string("status=%s\nmatches=%d\nfailures=%d\nfinal_gold=%d\nfinal_stacks=%s\nfinal_equipment=%s\n" % [status, match_count, failures, int(profile.data.gold), stack_summary(profile), equipment_summary(profile)])
	file.close()

func run() -> void:
	folder = "user://round2-progression-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	var inventory := InventoryService.new(profile)
	var campaign := CampaignService.new(profile)
	check(int(profile.data.gold) == 180 and profile.data.inventory.equipment.size() == 4, "isolated new profile starts with 180 gold and four initial instances")
	check(inventory.stack_count("copper_ore") == 0 and inventory.stack_count("armor_breaker") == 0 and not profile.data.campaign.first_clears.has("mine_furnace"), "isolated new profile has no injected Round 2 progression")

	var progression_complete := true
	for stage_index in range(STAGES.size()):
		var stage_id: String = STAGES[stage_index]
		var cleared := false
		for attempt in range(1, MAX_ATTEMPTS_PER_STAGE + 1):
			if match_count >= MAX_MATCHES:
				break
			var seed := 7100 + match_count
			var before_rocks := 0
			for instance_id in profile.data.inventory.equipment:
				if str(profile.data.inventory.equipment[instance_id].get("template_id", "")) == "rockcore": before_rocks += 1
			var result := run_campaign_battle(profile, campaign, stage_id, seed)
			match_count += 1
			if not bool(result.get("ok", false)):
				rows.append("%s,%d,%d,%s,,,,,%d,%s,%s,%s,%d,%d" % [stage_id, attempt, seed, str(result.get("reason", "save_error")), int(profile.data.gold), stack_summary(profile), equipment_summary(profile), str(profile.data.campaign.first_clears), before_rocks, int(result.get("ticks", 0))])
				progression_complete = false
				break
			var battle: Dictionary = result.battle
			var upgrades := upgrade_owned_weapons(profile)
			var rocks := 0
			for instance_id in profile.data.inventory.equipment:
				if str(profile.data.inventory.equipment[instance_id].get("template_id", "")) == "rockcore": rocks += 1
			rows.append("%s,%d,%d,%s,%d,%d,%d,%s,%d,%s,%s,%s,%d,%d" % [stage_id, attempt, seed, str(result.outcome), int(battle.winner), int(battle.player_actions), int(battle.medkits_used), str(battle.supply_uses), int(profile.data.gold), stack_summary(profile), equipment_summary(profile), str(profile.data.campaign.first_clears), rocks, int(result.ticks)])
			if not upgrades.is_empty():
				rows.append("# upgrades after %s attempt %d: %s" % [stage_id, attempt, ",".join(upgrades)])
			if str(result.outcome) == "win":
				cleared = true
				check(bool(profile.data.campaign.first_clears.get(stage_id, false)), "%s first clear persists before next stage" % stage_id)
				if stage_index < STAGES.size() - 1:
					check(campaign.can_enter(STAGES[stage_index + 1]).get("ok", false), "%s clear unlocks %s" % [stage_id, STAGES[stage_index + 1]])
				break
		if not cleared:
			progression_complete = false
			rows.append("# STOP: %s did not clear within %d attempts" % [stage_id, MAX_ATTEMPTS_PER_STAGE])
			break

	var reloaded := PlayerProfile.new(profile.path)
	check(int(reloaded.data.gold) == int(profile.data.gold), "final gold matches after reload")
	check(same_stacks(reloaded.data.inventory.stacks, profile.data.inventory.stacks), "final material and supply stacks match after reload")
	check(same_equipment(reloaded.data.inventory.equipment, profile.data.inventory.equipment), "final equipment and invested materials match after reload")
	check(reloaded.data.campaign == profile.data.campaign, "final campaign clears and settled runs match after reload")
	check(same_loadout(reloaded.data.loadout, profile.data.loadout), "final prepared loadout matches after reload")
	write_log("COMPLETE" if progression_complete else "INCOMPLETE_WITHIN_RETRY_CAP", profile)
	cleanup()
	print("ROUND2 PROGRESSION matches=%d status=%s failures=%d" % [match_count, "complete" if progression_complete else "incomplete", failures])
	quit(0 if failures == 0 else 1)
