extends SceneTree

var failures := 0
var folder := ""
func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)
func write(path: String, value: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE); f.store_string(JSON.stringify(value)); f.close()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	folder = "user://power-audit-" + str(Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(folder)
	# Disk migrations exercise real loader, backup, and legacy preservation.
	for version in [1,2,3,4]:
		var path := folder + "/v%d.json" % version
		var data := PlayerProfile.defaults(); data.version = version; data.gold = 777; data.xp = 66; data.levels.ember = 8
		data.inventory.equipment["legacy-weapon-ember"].level = 8; data.inventory.equipment["legacy-weapon-ember"].gem_item_id = "echo_gem"; data.inventory.equipment["legacy-weapon-ember"].invested_materials = {"enhancement_dust":12}
		if version < 3: data.erase("inventory"); data.erase("loadout"); data.erase("campaign"); data.active_run = {}
		write(path, data)
		var migrated := PlayerProfile.new(path); migrated.ensure_round_one()
		check(migrated.data.version == 5 and int(migrated.data.gold) == 777 and int(migrated.data.xp) == 66 and int(migrated.data.inventory.equipment["legacy-weapon-ember"].level) == 8, "v%d disk migration preserves gold/xp/+8" % version)
		if version >= 3: check(str(migrated.data.inventory.equipment["legacy-weapon-ember"].gem_item_id) == "echo_gem" and int(migrated.data.inventory.equipment["legacy-weapon-ember"].invested_materials.enhancement_dust) == 12, "v%d preserves gem and investment ledger" % version)
		if version == 4:
			var backup := FileAccess.get_file_as_string(path + ".v4.bak"); var once := PlayerProfile.new(path); once.ensure_round_one()
			check(backup == FileAccess.get_file_as_string(path + ".v4.bak") and once.growth_level() == migrated.growth_level(), "v4 migration is one-time and backup remains untouched")
	# A directory at the mandated migration-backup path must block rather than
	# overwrite the old save.  This is a real v4 JSON file and filesystem target.
	var blocked_path := folder + "/backup-blocked.json"; var legacy := PlayerProfile.defaults(); legacy.version = 4; legacy.gold = 432; write(blocked_path, legacy)
	DirAccess.make_dir_absolute(blocked_path + ".v4.bak")
	var blocked := PlayerProfile.new(blocked_path); var original: Dictionary = blocked.read_file(blocked_path)
	check(blocked.migration_blocked and int(original.get("version", 0)) == 4 and int(original.get("gold", 0)) == 432, "v4 backup-directory failure blocks migration without overwriting primary")
	# A valid v4 interrupted run is deliberately abandoned during v5 migration;
	# its already-consumed supply remains consumed and cannot create growth XP.
	var active_path := folder + "/legacy-active.json"; var active_legacy := PlayerProfile.defaults(); active_legacy.version = 4
	active_legacy.inventory.stacks.small_medkit = 1
	active_legacy.active_run = {"run_id":"legacy-active","stage_id":"forest_treebridge","difficulty":"normal","supplies":{"small_medkit":2},"consumed":{"small_medkit":1},"status":"running","combat_snapshot":{}}
	write(active_path, active_legacy)
	var active_migrated := PlayerProfile.new(active_path)
	check(active_migrated.data.active_run.is_empty() and int(active_migrated.data.inventory.stacks.small_medkit) == 1 and int(active_migrated.data.growth_exp) == 0 and active_migrated.notice.contains("旧版本未完成远征"), "v4 active run is abandoned without refund or growth")
	# Corrupt primary recovers a valid backup.
	var good := PlayerProfile.new(folder + "/recovery.json"); good.ensure_round_one(); good.data.gold = 555; good.save(); DirAccess.copy_absolute(good.path, good.path + ".bak")
	var bad := FileAccess.open(good.path, FileAccess.WRITE); bad.store_string("not-json"); bad.close()
	var recovered := PlayerProfile.new(good.path); check(int(recovered.data.gold) == 555 and recovered.notice.contains("备份"), "corrupt primary restores valid backup")
	# Endpoint enumeration uses the production formula and every legal loadout.
	var endpoint := 0; var finite := true; var monotonic := true
	for weapon in ["ember","volt","rockcore"]:
		for charm in ["feather","moss"]:
			for gem in [null,"echo_gem","pierce_gem"]:
				var previous := -1
				for enhancement in range(9):
					previous = -1
					for level in range(1,61):
						var s := ProgressionData.player_snapshot(weapon,charm,enhancement,gem,level); finite = finite and is_finite(float(s.power)) and float(s.power) >= 0; monotonic = monotonic and int(s.power) > previous; previous = int(s.power)
						if weapon == "volt" and charm == "moss" and gem == "echo_gem" and enhancement == 8 and level == 60: endpoint = int(s.power)
	check(finite and monotonic and endpoint == 1000000, "all legal level curves are finite/strict and endpoint is exactly 1000000")
	# Frozen run and idempotent settlement through CampaignService.
	var profile := PlayerProfile.new(folder + "/run.json"); profile.ensure_round_one(); profile.data.campaign.first_clears = {"forest_treebridge":true,"forest_spore_corridor":true}; profile.save()
	var service := CampaignService.new(profile); var started := service.begin_run("forest_spore_corridor")
	started.combat_snapshot.power = -99
	check(int(profile.data.active_run.combat_snapshot.power) > 0, "begin_run return snapshot is deeply detached from active run")
	var loss := service.settle_run(str(started.run_id), "loss", {}); var again := service.settle_run(str(started.run_id), "loss", {})
	check(int(loss.rewards.get("growth_exp_raw", 0)) == 0 and int(profile.data.growth_exp) == 0 and again.ok, "loss grants zero growth and duplicate run is idempotent")
	# A real save failure during a winning settlement must restore memory and leave
	# the frozen active run available for one successful retry.
	var retry_profile := PlayerProfile.new(folder + "/retry.json"); retry_profile.ensure_round_one(); retry_profile.save()
	var retry_service := CampaignService.new(retry_profile); var retry_run := retry_service.begin_run("forest_treebridge")
	DirAccess.make_dir_absolute(retry_profile.path + ".tmp")
	var failed_save := retry_service.settle_run(str(retry_run.run_id), "win", {"player_actions":1,"medkits_used":0})
	var disk_after_failure := PlayerProfile.new(retry_profile.path)
	check(not failed_save.ok and not retry_profile.data.active_run.is_empty() and not disk_after_failure.data.active_run.is_empty() and int(retry_profile.data.growth_exp) == 0, "tmp-directory settlement failure rolls back memory/disk and retains active run")
	DirAccess.remove_absolute(retry_profile.path + ".tmp")
	var retry_ok := retry_service.settle_run(str(retry_run.run_id), "win", {"player_actions":1,"medkits_used":0}); var exp_once := int(retry_profile.data.growth_exp)
	var retry_again := retry_service.settle_run(str(retry_run.run_id), "win", {"player_actions":1,"medkits_used":0})
	check(retry_ok.ok and exp_once > 0 and retry_profile.data.active_run.is_empty() and retry_again.ok and int(retry_profile.data.growth_exp) == exp_once, "repaired tmp retries once and never duplicates XP")
	# Mutating begin_run's returned frozen definitions must not affect the stored
	# run; settlement uses only the stored reward snapshot and survives reload.
	var frozen_profile := PlayerProfile.new(folder + "/frozen.json"); frozen_profile.ensure_round_one(); frozen_profile.save()
	var frozen_service := CampaignService.new(frozen_profile); var frozen := frozen_service.begin_run("forest_treebridge")
	var stored_raw := int(frozen_profile.data.active_run.reward_snapshot.growth.first_clear_exp)
	frozen.reward_snapshot.growth.base_exp = 999999; frozen.reward_snapshot.growth.first_clear_exp = 999999; frozen.stage_snapshot.hazards.spore = -1
	var frozen_settle := frozen_service.settle_run(str(frozen.run_id), "win", {"player_actions":1,"medkits_used":0})
	var frozen_reload := PlayerProfile.new(frozen_profile.path)
	check(frozen_settle.ok and int(frozen_settle.rewards.growth.raw_exp) == stored_raw and int(frozen_reload.data.growth_exp) == stored_raw and frozen_reload.data.active_run.is_empty(), "returned reward/stage snapshots cannot alter frozen settlement after reload")
	print("POWER INTEGRITY AUDIT FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
