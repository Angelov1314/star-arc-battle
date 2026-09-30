extends SceneTree

var failures := 0
var folder := ""

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition: print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func unlock_to_sky(profile: PlayerProfile) -> void:
	for id in ["forest_treebridge", "forest_spore_corridor", "forest_moss_guardian", "mine_entrance", "mine_fracture", "mine_furnace", "sky_corridor", "sky_altar"]:
		profile.data.campaign.first_clears[id] = true

func same_stacks(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size(): return false
	for key in left:
		if not right.has(key) or int(left[key]) != int(right[key]): return false
	return true

func settle(campaign: CampaignService, id: String, difficulty: String = "normal", actions: int = 9) -> Dictionary:
	var started := campaign.begin_run(id, difficulty)
	if not started.ok: return started
	return campaign.settle_run(str(started.run_id), "win", {"player_actions":actions})

func cleanup() -> void:
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)

func run() -> void:
	folder = "user://round3-integrity-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	var inventory := InventoryService.new(profile)
	var campaign := CampaignService.new(profile)
	check(profile.data.version == PlayerProfile.CURRENT_VERSION and ItemData.DEFINITIONS.size() == 14, "current profile schema and all fourteen item definitions exist")
	check(CampaignData.STAGES.size() + CampaignData.SKY_STAGES.size() == 9 and CampaignData.stage("sky_lord").stage_config.enemy.max_hp == 1800, "nine normal stages include documented sky enemy values")
	check(not campaign.can_enter("sky_corridor").ok, "third chapter remains locked before normal furnace clear")
	unlock_to_sky(profile)
	check(profile.save(), "sky unlock fixture saves")
	var lord := settle(campaign, "sky_lord")
	check(lord.ok and int(profile.data.inventory.stacks.get("echo_gem", 0)) == 1 and int(profile.data.inventory.stacks.get("pierce_gem", 0)) == 1, "sky lord first clear atomically grants both gems")
	check(campaign.stage_status("forest_treebridge", "elite").unlocked and not campaign.stage_status("sky_lord", "elite").first_cleared, "elite unlock separates normal and elite first clears")
	check(inventory.configure_supplies([{"item_id":"small_medkit","quantity":1}]).ok, "abnormal exit fixture configures supply")
	var interrupted := campaign.begin_run("sky_lord")
	check(interrupted.ok and interrupted.supply_commit.call("small_medkit").ok, "active run persists supply use before interruption")
	var resumed := PlayerProfile.new(profile.path)
	var resumed_campaign := CampaignService.new(resumed)
	check(str(resumed.data.active_run.get("difficulty", "")) == "normal" and int(resumed.data.inventory.stacks.get("small_medkit", 0)) == int(profile.data.inventory.stacks.get("small_medkit", 0)), "restart preserves active run difficulty and already consumed supply")
	check(resumed_campaign.abandon_run(str(resumed.data.active_run.run_id)).ok and PlayerProfile.new(resumed.path).data.active_run.is_empty(), "abnormal exit can be abandoned without refunding supply")
	profile = PlayerProfile.new(profile.path)
	inventory = InventoryService.new(profile)
	campaign = CampaignService.new(profile)
	var quit_profile := PlayerProfile.new(folder + "/quit-snapshot.json")
	unlock_to_sky(quit_profile); quit_profile.data.campaign.first_clears.sky_lord = true; quit_profile.data.inventory.stacks.small_medkit = 1
	check(quit_profile.save(), "quit difficulty snapshot fixture saves")
	var quit_campaign := CampaignService.new(quit_profile)
	check(InventoryService.new(quit_profile).configure_supplies([{"item_id":"small_medkit","quantity":1}]).ok, "quit fixture prepares one supply")
	var normal_snapshot := quit_campaign.begin_run("sky_lord", "normal")
	check(normal_snapshot.ok and normal_snapshot.supply_commit.call("small_medkit").ok, "normal run commits actual supply before quit")
	# UI may change its selected difficulty after launch, but settlement reads active_run.
	var quit_settlement := quit_campaign.settle_run(str(normal_snapshot.run_id), "quit", {"difficulty":"elite"})
	var quit_reload := PlayerProfile.new(quit_profile.path)
	check(quit_settlement.ok and int(quit_settlement.rewards.gold) == 0 and quit_reload.data.active_run.is_empty() and int(quit_reload.data.inventory.stacks.get("small_medkit", 0)) == 2, "quit retains consumed supply and battle stats cannot alter snapshotted normal difficulty")
	var loss_profile := PlayerProfile.new(folder + "/difficulty-loss.json")
	unlock_to_sky(loss_profile); loss_profile.data.campaign.first_clears.sky_lord = true
	check(loss_profile.save(), "difficulty loss fixture saves")
	var loss_campaign := CampaignService.new(loss_profile)
	var normal_loss := loss_campaign.begin_run("sky_corridor", "normal")
	var normal_loss_reward := loss_campaign.settle_run(str(normal_loss.run_id), "loss", {})
	var elite_loss := loss_campaign.begin_run("sky_corridor", "elite")
	var elite_loss_reward := loss_campaign.settle_run(str(elite_loss.run_id), "loss", {})
	var elite_boss_loss := loss_campaign.begin_run("sky_lord", "elite")
	var elite_boss_loss_reward := loss_campaign.settle_run(str(elite_boss_loss.run_id), "loss", {})
	check(normal_loss_reward.ok and int(normal_loss_reward.rewards.gold) == 17 and int(loss_campaign.stage_status("sky_corridor", "normal").stage.failure_gold) == 17 and int(elite_loss_reward.rewards.gold) == 25 and int(loss_campaign.stage_status("sky_corridor", "elite").stage.failure_gold) == 25 and int(elite_boss_loss_reward.rewards.gold) == 51 and int(loss_campaign.stage_status("sky_lord", "elite").stage.failure_gold) == 51, "normal and elite failures pay displayed floor twenty-percent current-difficulty rewards")

	var forge := ForgeService.new(profile)
	var weapon_id := str(profile.data.loadout.weapon_instance_id)
	var empty_socket := forge.preview_socket(weapon_id, "echo_gem")
	check(empty_socket.ok and int(empty_socket.costs.gold) == 0 and int(empty_socket.delta.max_hp) == 60, "empty socket preview is free and exposes health delta")
	check(forge.socket_gem(weapon_id, "echo_gem").ok and is_equal_approx(float(profile.combat_snapshot().max_hp), 1060.0 * ProgressionData.scale(profile.growth_level())), "socket persists gem and growth-scaled combat maximum health")
	check(forge.preview_socket(weapon_id, "echo_gem").code == "same_gem", "same gem replacement is disabled")
	var unsocket_gold := int(profile.data.gold)
	check(forge.unsocket_gem(weapon_id).ok and int(profile.data.gold) == unsocket_gold - 30 and int(profile.data.inventory.stacks.echo_gem) == 1, "unsocket charges once and returns original gem")
	# Every gem transaction remains atomic when its final disk write fails.
	var failing := PlayerProfile.new(folder + "/gem-failure.json")
	unlock_to_sky(failing); failing.data.campaign.first_clears.sky_lord = true; failing.data.inventory.stacks.echo_gem = 2; failing.data.inventory.stacks.pierce_gem = 1; failing.data.inventory.stacks.relic_shard = 12; failing.data.inventory.stacks.enhancement_dust = 8; failing.data.gold = 400
	check(failing.save(), "gem failure fixture saves")
	var failing_forge := ForgeService.new(failing)
	var failing_weapon := str(failing.data.loadout.weapon_instance_id)
	failing.path = folder + "/missing/socket.json"
	check(not failing_forge.socket_gem(failing_weapon, "echo_gem").ok and int(failing.data.inventory.stacks.echo_gem) == 2 and failing.data.inventory.equipment[failing_weapon].gem_item_id == null, "socket save failure retains gem and empty socket in memory")
	failing.path = folder + "/gem-failure.json"
	check(failing_forge.socket_gem(failing_weapon, "echo_gem").ok, "socket retry saves")
	var before_swap := failing.data.duplicate(true)
	failing.path = folder + "/missing/swap.json"
	check(not failing_forge.socket_gem(failing_weapon, "pierce_gem").ok and str(failing.data.inventory.equipment[failing_weapon].gem_item_id) == "echo_gem" and same_stacks(failing.data.inventory.stacks, before_swap.inventory.stacks), "replacement save failure retains original gem and all stacks")
	failing.path = folder + "/gem-failure.json"
	check(failing_forge.socket_gem(failing_weapon, "pierce_gem").ok, "replacement retry saves")
	var before_unsocket := failing.data.duplicate(true)
	failing.path = folder + "/missing/unsocket.json"
	check(not failing_forge.unsocket_gem(failing_weapon).ok and str(failing.data.inventory.equipment[failing_weapon].gem_item_id) == "pierce_gem" and same_stacks(failing.data.inventory.stacks, before_unsocket.inventory.stacks), "unsocket save failure retains socket and stack")
	failing.path = folder + "/gem-failure.json"
	var before_craft := failing.data.duplicate(true)
	failing.path = folder + "/missing/craft.json"
	check(not InventoryService.new(failing).craft("echo_gem", 1).ok and same_stacks(failing.data.inventory.stacks, before_craft.inventory.stacks) and int(failing.data.gold) == int(before_craft.gold), "gem craft save failure rolls memory back")
	failing.path = folder + "/gem-failure.json"
	var failing_reload := PlayerProfile.new(failing.path)
	check(str(failing_reload.data.inventory.equipment[failing_weapon].gem_item_id) == "pierce_gem" and int(failing_reload.data.inventory.stacks.echo_gem) == 2, "gem transaction failures leave disk at last committed replacement")
	profile.data.inventory.stacks.relic_shard = 12
	profile.data.inventory.stacks.enhancement_dust = 8
	profile.data.gold = 180
	check(profile.save(), "gem crafting fixture saves")
	check(inventory.craft("pierce_gem", 1).ok and int(profile.data.gold) == 0 and int(profile.data.inventory.stacks.pierce_gem) == 2, "gem crafting debits gold and materials atomically")

	# Add a disposable ungemmed weapon with known actual investment; equipped, locked,
	# gemmed, and final weapons must remain ineligible.
	profile.data.inventory.equipment.extra = {"template_id":"volt","level":3,"locked":false,"gem_item_id":null,"invested_materials":{"woodchip":11,"enhancement_dust":5},"is_new":false,"acquired_at":0}
	check(profile.save(), "dismantle fixture saves")
	var dismantle_preview := forge.preview_dismantle(["extra"])
	check(dismantle_preview.ok and int(dismantle_preview.rewards.enhancement_dust) == 2 and int(dismantle_preview.rewards.woodchip) == 3, "dismantle returns dust plus floor thirty percent actual materials")
	check(forge.dismantle(["extra"]).ok and not profile.data.inventory.equipment.has("extra"), "dismantle saves a whole selection once")
	check(not forge.preview_dismantle([weapon_id]).ok, "current weapon cannot be dismantled")
	profile.data.inventory.equipment.locked_extra = {"template_id":"volt","level":0,"locked":true,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0}
	profile.data.inventory.equipment.gem_extra = {"template_id":"volt","level":0,"locked":false,"gem_item_id":"echo_gem","invested_materials":{},"is_new":false,"acquired_at":0}
	check(profile.save(), "dismantle protection fixture saves")
	var before_mixed: Dictionary = profile.data.inventory.equipment.duplicate(true)
	check(not forge.dismantle(["locked_extra", "gem_extra"]).ok and profile.data.inventory.equipment == before_mixed, "mixed invalid dismantle batch aborts every item")
	check(not forge.preview_dismantle(["locked_extra"]).ok and not forge.preview_dismantle(["gem_extra"]).ok, "locked and gemmed equipment protections are enforced")
	var only_weapon := PlayerProfile.new(folder + "/last-weapon.json")
	unlock_to_sky(only_weapon); only_weapon.data.loadout.charm_instance_id = "legacy-charm-feather"; only_weapon.data.inventory.equipment.erase("legacy-weapon-volt")
	check(only_weapon.save() and not ForgeService.new(only_weapon).preview_dismantle(["legacy-weapon-ember"]).ok, "last weapon protection is enforced")
	var no_duplicates := PlayerProfile.new(folder + "/no-duplicates.json")
	unlock_to_sky(no_duplicates)
	check(no_duplicates.save() and not ForgeService.new(no_duplicates).preview_dismantle(["legacy-weapon-volt"]).ok, "unlocked new profile has no eligible duplicate equipment")
	var batch_profile := PlayerProfile.new(folder + "/batch-refund.json")
	unlock_to_sky(batch_profile)
	batch_profile.data.campaign.first_clears.sky_lord = true
	batch_profile.data.loadout.weapon_instance_id = "legacy-weapon-volt"
	batch_profile.data.inventory.equipment.ember_extra_a = {"template_id":"ember","level":0,"locked":false,"gem_item_id":null,"invested_materials":{"woodchip":2},"is_new":false,"acquired_at":0}
	batch_profile.data.inventory.equipment.ember_extra_b = {"template_id":"ember","level":0,"locked":false,"gem_item_id":null,"invested_materials":{"woodchip":2},"is_new":false,"acquired_at":0}
	check(batch_profile.save(), "two-item dismantle fixture saves")
	var batch_forge := ForgeService.new(batch_profile)
	var batch_preview := batch_forge.preview_dismantle(["ember_extra_a", "ember_extra_b"])
	check(batch_preview.ok and int(batch_preview.rewards.enhancement_dust) == 2 and int(batch_preview.rewards.get("woodchip", 0)) == 0, "batch dismantle returns base dust per item and floors each investment before summing")
	check(batch_forge.dismantle(["ember_extra_a", "ember_extra_b"]).ok, "two eligible duplicates dismantle atomically")
	var batch_reload := PlayerProfile.new(batch_profile.path)
	check(int(batch_reload.data.inventory.stacks.get("enhancement_dust", 0)) == 2 and int(batch_reload.data.inventory.stacks.get("woodchip", 0)) == 0 and not batch_reload.data.inventory.equipment.has("ember_extra_a"), "two-item dismantle material recovery persists after restart")
	var hints := PlayerProfile.new(folder + "/hints.json")
	check(not hints.tutorial_seen("first_campaign") and hints.acknowledge_hint("first_campaign").ok and hints.tutorial_seen("first_campaign"), "one-time campaign hint marks after successful save")
	var reopened_hints := PlayerProfile.new(hints.path)
	check(reopened_hints.tutorial_seen("first_campaign") and reopened_hints.acknowledge_hint("first_campaign").code == "already_seen", "hint remains seen across restart without duplicate transaction")
	hints.path = folder + "/missing/hint.json"
	check(not hints.acknowledge_hint("first_material").ok and not hints.tutorial_seen("first_material"), "hint write failure does not mark memory")
	hints.path = folder + "/hints.json"
	check(not PlayerProfile.new(hints.path).tutorial_seen("first_material") and not hints.acknowledge_hint("invalid").ok, "hint write failure leaves disk unchanged and invalid hint rejects")

	var disk_before := profile.data.duplicate(true)
	profile.data.inventory.equipment.extra2 = {"template_id":"volt","level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0}
	check(profile.save(), "disk rollback fixture saves")
	var disk_count := int(profile.data.inventory.equipment.size())
	profile.path = folder + "/missing/disk.json"
	check(not forge.dismantle(["extra2"]).ok and int(profile.data.inventory.equipment.size()) == disk_count, "dismantle disk failure restores in-memory selection")
	profile.path = folder + "/profile.json"
	check(PlayerProfile.new(profile.path).data.inventory.equipment.has("extra2"), "dismantle disk failure leaves restarted profile unchanged")

	# Three normal repeat boss wins grant the fixed rotating weapon only on the third.
	profile = PlayerProfile.new(profile.path)
	campaign = CampaignService.new(profile)
	for ignored in range(3): check(settle(campaign, "sky_lord").ok, "normal sky lord repeat settles")
	var ember_count := 0
	for instance_id in profile.data.inventory.equipment:
		if str(profile.data.inventory.equipment[instance_id].template_id) == "ember": ember_count += 1
	check(int(profile.data.campaign.boss_repeat_wins.get("sky_lord", 0)) == 3 and ember_count == 2, "third normal repeat grants the first rotating +0 ember instance")
	check(InventoryService.new(profile).equip_instance("legacy-weapon-volt").ok, "repeat-drop fixture equips another weapon")
	var repeat_ember := ""
	for instance_id in profile.data.inventory.equipment:
		if str(profile.data.inventory.equipment[instance_id].template_id) == "ember" and str(instance_id) != str(profile.data.loadout.weapon_instance_id): repeat_ember = str(instance_id)
	check(not repeat_ember.is_empty() and ForgeService.new(profile).preview_dismantle([repeat_ember]).ok, "third normal repeat creates one eligible same-template duplicate")
	var elite := settle(campaign, "sky_lord", "elite")
	check(elite.ok and int(elite.rewards.gold) == 255 and int(profile.data.inventory.stacks.get("echo_gem", 0)) == 2, "elite boss pays 1.5x base and first alternating gem without normal reward duplication")
	for ignored in range(6): check(settle(campaign, "sky_lord").ok, "later normal sky lord repeat settles")
	var volt_count := 0
	var rockcore_count := 0
	for instance_id in profile.data.inventory.equipment:
		var template_id := str(profile.data.inventory.equipment[instance_id].template_id)
		if template_id == "volt": volt_count += 1
		if template_id == "rockcore": rockcore_count += 1
	check(int(profile.data.campaign.boss_repeat_wins.sky_lord) == 9 and volt_count == 5 and rockcore_count == 1, "repeat wins 6 and 9 persist the volt then rockcore rotation after restart")
	var failed_elite := campaign.begin_run("sky_lord", "elite")
	profile.path = folder + "/missing/elite.json"
	check(not campaign.settle_run(str(failed_elite.run_id), "win", {}).ok and int(profile.data.campaign.elite_gem_counter.get("boss", 0)) == 1, "elite reward write failure rolls back shared gem counter")
	profile.path = folder + "/profile.json"
	check(campaign.settle_run(str(failed_elite.run_id), "win", {}).ok, "elite reward save retry succeeds once")
	check(settle(campaign, "sky_lord", "elite").ok, "third elite boss settles")
	var elite_pierce := int(profile.data.inventory.stacks.get("pierce_gem", 0))
	var elite_echo := int(profile.data.inventory.stacks.get("echo_gem", 0))
	var elite_counter := int(profile.data.campaign.elite_gem_counter.boss)
	print("elite gems echo=%d pierce=%d counter=%d" % [elite_echo, elite_pierce, elite_counter])
	check(elite_pierce == 3 and elite_echo == 3 and elite_counter == 3, "elite gem rotation persists echo-pierce-echo across failure and restart")
	var shared := PlayerProfile.new(folder + "/shared-elite.json")
	unlock_to_sky(shared); shared.data.campaign.first_clears.sky_lord = true
	check(shared.save(), "shared elite counter fixture saves")
	var shared_campaign := CampaignService.new(shared)
	check(settle(shared_campaign, "forest_moss_guardian", "elite").ok and settle(shared_campaign, "mine_furnace", "elite").ok and settle(shared_campaign, "sky_lord", "elite").ok, "three chapter elite bosses settle through one shared sequence")
	check(int(shared.data.inventory.stacks.get("echo_gem", 0)) == 2 and int(shared.data.inventory.stacks.get("pierce_gem", 0)) == 1 and int(shared.data.campaign.elite_gem_counter.boss) == 3, "elite boss gems alternate across all three boss IDs")

	for legacy_version in [1, 2]:
		var legacy := {"version":legacy_version,"gold":777,"xp":66,"wins":2,"matches":3,"weapon":"volt","charm":"moss","levels":{"ember":8,"volt":3},"ledger":[],"music":0.17,"sfx":0.83}
		write_json(folder + "/legacy-v%d.json" % legacy_version, legacy)
		var legacy_reload := PlayerProfile.new(folder + "/legacy-v%d.json" % legacy_version)
		check(legacy_reload.data.version == PlayerProfile.CURRENT_VERSION and int(legacy_reload.data.gold) == 777 and int(legacy_reload.data.xp) == 66 and is_equal_approx(float(legacy_reload.data.music), 0.17) and int(legacy_reload.data.inventory.equipment["legacy-weapon-ember"].level) == 8, "v%d disk migration preserves gold xp settings and +8" % legacy_version)

	# Native v3 schema migrates without inventing historical material investment.
	var v3 := PlayerProfile.defaults()
	v3.version = 3
	v3.campaign.erase("wins"); v3.campaign.erase("best_player_actions"); v3.campaign.erase("sky_repeat_weapon_index"); v3.campaign.erase("elite_gem_counter")
	v3.inventory.equipment["legacy-weapon-ember"].invested_materials = {}
	v3.inventory.equipment["legacy-weapon-ember"].level = 8
	v3.inventory.equipment["legacy-weapon-ember"].locked = true
	v3.inventory.equipment["legacy-weapon-rockcore"] = {"template_id":"rockcore","level":8,"locked":true,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0}
	write_json(folder + "/v3.json", v3)
	var migrated := PlayerProfile.new(folder + "/v3.json")
	check(migrated.data.version == PlayerProfile.CURRENT_VERSION and migrated.data.campaign.wins is Dictionary and int(migrated.data.gold) == 180 and is_equal_approx(float(migrated.data.music), 0.35) and int(migrated.data.inventory.equipment["legacy-weapon-ember"].level) == 8 and bool(migrated.data.inventory.equipment["legacy-weapon-ember"].locked) and migrated.data.inventory.equipment.has("legacy-weapon-rockcore") and migrated.data.inventory.equipment["legacy-weapon-ember"].invested_materials.is_empty(), "v3 disk migration preserves resources settings +8 rockcore locks and zero historical investment")
	cleanup()
	print("ROUND3 INTEGRITY FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
