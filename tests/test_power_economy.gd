extends SceneTree

var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func run() -> void:
	var folder := "user://power-economy-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	var campaign := CampaignService.new(profile)
	var ids := ["forest_treebridge","forest_spore_corridor","forest_moss_guardian","mine_entrance","mine_fracture","mine_furnace","sky_corridor","sky_altar","sky_lord"]
	for id in ids:
		var started := campaign.begin_run(id)
		check(started.ok, "%s opens through normal first-clear chain" % id)
		if started.ok: check(campaign.settle_run(str(started.run_id), "win").ok, "%s first-clear settlement commits" % id)
	check(int(profile.data.growth_exp) == 7260 and profile.growth_level() == 23, "nine normal first clears total exactly 7260 experience at level 23")
	var fail_start := campaign.begin_run("forest_treebridge")
	var failure := campaign.settle_run(str(fail_start.run_id), "loss")
	check(failure.ok and int(failure.rewards.growth.raw_exp) == 0 and int(profile.data.growth_exp) == 7260, "loss gives zero permanent experience")
	var quit_start := campaign.begin_run("forest_treebridge")
	var quit := campaign.settle_run(str(quit_start.run_id), "quit")
	check(quit.ok and int(quit.rewards.growth.raw_exp) == 0 and int(profile.data.growth_exp) == 7260, "quit gives zero permanent experience")
	var repeated := campaign.begin_run("forest_treebridge")
	var award := campaign.settle_run(str(repeated.run_id), "win")
	var duplicate := campaign.settle_run(str(repeated.run_id), "win")
	check(award.ok and duplicate.code == "already_settled" and int(profile.data.growth_exp) == 7300, "repeat run earns base experience once and duplicate settlement cannot mint it")
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("POWER ECONOMY FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
