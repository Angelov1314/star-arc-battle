extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if value: print("PASS: "+label)
	else: failures += 1; printerr("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := "user://round2-data-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder+"/profile.json")
	var inventory := InventoryService.new(profile)
	var campaign := CampaignService.new(profile)
	var forge := ForgeService.new(profile)
	check(not inventory.equip_instance("missing").ok,"cannot equip unowned rockcore")
	profile.data.inventory.stacks.copper_ore=198
	profile.data.inventory.stacks.enhancement_dust=198
	check(profile.save(),"fixture save")
	check(inventory.craft("armor_breaker",99).ok and inventory.stack_count("armor_breaker")==99,"craft max quantity atomically")
	check(not inventory.craft("armor_breaker",100).ok,"craft quantity cap")
	check(inventory.set_locked(["legacy-weapon-ember","legacy-weapon-volt"],true).ok and profile.data.inventory.equipment["legacy-weapon-ember"].locked,"batch lock")
	profile.data.campaign.first_clears.mine_furnace=true
	profile.data.inventory.stacks.enhancement_dust=12
	profile.data.inventory.stacks.copper_ore=6
	profile.data.gold=1000
	profile.data.inventory.equipment["legacy-weapon-ember"].level=5
	check(profile.save(),"high forge fixture")
	check(forge.upgrade("legacy-weapon-ember").ok and int(profile.data.inventory.equipment["legacy-weapon-ember"].level)==6,"furnace unlocks plus six")
	var reloaded_high := PlayerProfile.new(folder+"/profile.json")
	check(int(reloaded_high.data.inventory.equipment["legacy-weapon-ember"].level)==6,"plus six persists after reload")
	profile.data.inventory.equipment["legacy-weapon-ember"].level=8
	profile.save()
	check(not forge.upgrade("legacy-weapon-ember").ok,"plus eight cap")
	var reward_profile := PlayerProfile.new(folder+"/reward.json")
	var reward_campaign := CampaignService.new(reward_profile)
	for stage_id in ["forest_treebridge","forest_spore_corridor","forest_moss_guardian","mine_entrance","mine_fracture"]: reward_profile.data.campaign.first_clears[stage_id]=true
	reward_profile.save()
	var run := reward_campaign.begin_run("mine_furnace")
	check(run.ok,"furnace run starts")
	var result := reward_campaign.settle_run(str(run.get("run_id","")),"win",{})
	var rocks := 0
	for id in reward_profile.data.inventory.equipment:
		if reward_profile.data.inventory.equipment[id].template_id=="rockcore": rocks += 1
	check(result.ok and rocks==1,"furnace first clear grants one rockcore instance: "+str(result))
	check(reward_campaign.settle_run(run.run_id,"win",{}).code=="already_settled" and rocks==1,"rockcore reward idempotent")
	var rock_id := ""
	for id in reward_profile.data.inventory.equipment:
		if reward_profile.data.inventory.equipment[id].template_id=="rockcore": rock_id=str(id)
	check(reward_profile.equip("rockcore","moss"),"rewarded rockcore can equip with charm")
	var rock_reload := PlayerProfile.new(folder+"/reward.json")
	check(rock_reload.data.weapon=="rockcore" and rock_reload.data.charm=="moss","rockcore loadout persists")
	rock_reload.data.campaign.first_clears.mine_furnace=true
	rock_reload.data.inventory.equipment[rock_id].level=5
	rock_reload.data.inventory.stacks.enhancement_dust=12
	rock_reload.data.inventory.stacks.copper_ore=6
	rock_reload.data.gold=500
	rock_reload.save()
	var rock_preview := ForgeService.new(rock_reload).preview_upgrade(rock_id)
	check(rock_preview.ok and rock_preview.has.has("copper_ore") and int(rock_preview.has.copper_ore)==6,"plus six preview exposes copper inventory")
	print("ROUND2 DATA FAILURES: %d"%failures)
	quit(0 if failures==0 else 1)
