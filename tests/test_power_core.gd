extends SceneTree

var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func run() -> void:
	check(ProgressionData.exp_for_level(1) == 0 and ProgressionData.exp_for_level(60) == 41300 and ProgressionData.level_for_exp(41300) == 60, "authoritative experience thresholds reach 41300 at level 60")
	var low := ProgressionData.player_snapshot("ember", "feather", 0, null, 1)
	var high := ProgressionData.player_snapshot("volt", "moss", 8, "echo_gem", 60)
	check(int(low.power) == 1000 and int(high.power) == 1000000, "reference loadouts hit exact 1000 and one-million endpoints")
	var maximum := 0
	for weapon in ["ember", "volt", "rockcore"]:
		for enhancement in range(9):
			for charm in ["feather", "moss"]:
				for gem in [null, "echo_gem", "pierce_gem"]:
					maximum = max(maximum, int(ProgressionData.player_snapshot(weapon, charm, enhancement, gem, 60).power))
	check(maximum == 1000000, "all legal level-60 equipment states stay within the one-million cap")
	var folder := "user://power-core-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	var service := CampaignService.new(profile)
	var forge := ForgeService.new(profile)
	var offhand_preview := forge.preview_upgrade("legacy-weapon-volt")
	check(offhand_preview.ok and str(offhand_preview.before_snapshot.weapon) == "volt" and str(offhand_preview.after_snapshot.weapon) == "volt", "forge preview evaluates the selected unequipped weapon rather than current loadout")
	var first := service.begin_run("forest_treebridge")
	check(first.ok and first.has("enemy_snapshot") and first.has("stage_snapshot") and first.has("reward_snapshot") and int(first.combat_snapshot.power) == 1000, "new run freezes player enemy stage and reward snapshots")
	var frozen: Dictionary = first.reward_snapshot.duplicate(true)
	var settled := service.settle_run(str(first.run_id), "win")
	check(settled.ok and int(settled.rewards.gold) == int(frozen.stage_rewards.win.gold) + int(frozen.stage_rewards.first_clear.gold) and int(settled.rewards.growth_exp_applied) == 120 and int(profile.data.growth_exp) == 120, "settlement uses frozen reward definition and applies first-clear experience")
	profile.data.growth_exp = 41290
	profile.save()
	var next := service.begin_run("forest_treebridge")
	var cap := service.settle_run(str(next.run_id), "win")
	check(cap.ok and int(profile.data.growth_exp) == 41300 and int(cap.rewards.growth_exp_applied) == 10 and int(cap.rewards.growth_exp_overflow) > 0, "experience clamps within the final cross-level settlement")
	var legacy := profile.data.duplicate(true)
	legacy.version = 4; legacy.erase("growth_exp"); legacy.erase("progression_version"); legacy.erase("growth_first_clears")
	legacy.campaign.first_clears = {"forest_treebridge":true,"sky_lord":true,"sky_lord:elite":true}
	var legacy_path := folder + "/legacy-v4.json"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE); file.store_string(JSON.stringify(legacy)); file.close()
	var migrated := PlayerProfile.new(legacy_path)
	check(migrated.data.version == 5 and migrated.growth_level() == 58 and FileAccess.file_exists(legacy_path + ".v4.bak") and bool(migrated.data.growth_first_clears.get("v1:sky_lord:elite", false)), "v4 migration saves one backup and derives legal elite milestone")
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("POWER CORE FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
