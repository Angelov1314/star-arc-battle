class_name CampaignService
extends RefCounted

var profile: PlayerProfile
var inventory: InventoryService

func _init(player_profile: PlayerProfile) -> void:
	profile = player_profile
	inventory = InventoryService.new(profile)

func stage_status(stage_id: String, difficulty: String = "normal") -> Dictionary:
	if not CampaignData.has_stage(stage_id): return _failure("unknown_stage", "关卡不存在。")
	if difficulty not in ["normal", "elite"]: return _failure("unknown_difficulty", "难度不存在。")
	var stage := CampaignData.stage(stage_id, difficulty)
	var prerequisite := str(stage.unlocks_after)
	var normal_cleared := bool(profile.data.campaign.first_clears.get(stage_id, false))
	var unlocked := prerequisite.is_empty() or bool(profile.data.campaign.first_clears.get(prerequisite, false))
	var reason := "" if unlocked else "完成「%s」后解锁。" % CampaignData.stage(prerequisite).name
	if difficulty == "elite":
		unlocked = normal_cleared and bool(profile.data.campaign.first_clears.get("sky_lord", false))
		reason = "完成天空领主与本关普通难度后解锁。" if not unlocked else ""
	var key := _progress_key(stage_id, difficulty)
	stage.failure_gold = int(floor(float(stage.rewards.win.gold) * 0.2))
	var reward_preview := CampaignData.reward_definition(stage_id, difficulty, bool(profile.data.growth_first_clears.get(_growth_key(stage_id, difficulty), false)))
	var preview_stage: Dictionary = stage.stage_config.duplicate(true)
	preview_stage.hazards = _hazard_snapshot(preview_stage, int(preview_stage.get("target_level", 1)))
	return {"ok":true,"stage":stage,"stage_preview":preview_stage,"enemy_snapshot":CampaignData.enemy_snapshot(stage_id, difficulty),"unlocked":unlocked,"first_cleared":bool(profile.data.campaign.first_clears.get(key, false)),"normal_first_cleared":normal_cleared,"reason":reason,"difficulty":difficulty,"public_affixes":stage.get("public_affixes", []),"best_player_actions":int(profile.data.campaign.best_player_actions.get(key, 0)),"wins":int(profile.data.campaign.wins.get(key, 0)),"power":int(profile.combat_snapshot().power),"recommended_power":int(stage.stage_config.get("recommended_power", 1000)),"growth_reward_preview":reward_preview}

func can_enter(stage_id: String, difficulty: String = "normal") -> Dictionary:
	var status := stage_status(stage_id, difficulty)
	if not status.ok or not status.unlocked: return _failure(status.get("code", "locked"), status.get("reason", "关卡尚未解锁。"))
	return status

func begin_run(stage_id: String, difficulty: String = "normal") -> Dictionary:
	var entry := can_enter(stage_id, difficulty)
	if not entry.ok: return entry
	if not profile.data.active_run.is_empty(): return _failure("active_run_exists", "上一局尚未结算，请先重试保存或放弃该局。")
	var run_id := "run-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	var supplies := {}
	for slot in inventory.supply_snapshot():
		var item_id := str(slot.item_id)
		var selected := int(slot.quantity)
		var owned := inventory.stack_count(item_id)
		if owned < selected: return _failure("insufficient_supplies", "%s 还差 %d 份。" % [ItemData.definition(item_id).name, selected - owned])
		supplies[item_id] = selected
	var combat_snapshot := profile.combat_snapshot()
	var stage_snapshot: Dictionary = entry.stage.stage_config.duplicate(true)
	var target_level := int(stage_snapshot.get("target_level", 1))
	stage_snapshot.hazards = _hazard_snapshot(stage_snapshot, target_level)
	var enemy_snapshot := _enemy_snapshot(stage_snapshot, difficulty, target_level)
	var reward_snapshot := {"progression_version":ProgressionData.PROGRESSION_VERSION,"stage_rewards":entry.stage.rewards.duplicate(true),"failure_gold":int(entry.stage.failure_gold),"growth":CampaignData.reward_definition(stage_id, difficulty, bool(profile.data.growth_first_clears.get(_growth_key(stage_id, difficulty), false))),"first_clear_eligible":not bool(profile.data.campaign.first_clears.get(_progress_key(stage_id, difficulty), false)),"growth_first_clear_eligible":not bool(profile.data.growth_first_clears.get(_growth_key(stage_id, difficulty), false)),"difficulty":difficulty,"kind":str(entry.stage.kind),"stage_id":stage_id,"objective_rules":{"enabled":difficulty == "normal" and stage_id.begins_with("forest_"),"no_medkit":{"gold":60,"stacks":{"enhancement_dust":2}},"six_actions":{"gold":60,"stacks":{"enhancement_dust":2}}}}
	if difficulty == "normal" and stage_id == "sky_lord" and not bool(reward_snapshot.first_clear_eligible):
		var upcoming_repeat := int(profile.data.campaign.boss_repeat_wins.get("sky_lord", 0)) + 1
		if upcoming_repeat % 3 == 0: reward_snapshot.repeat_weapon_id = ["ember", "volt", "rockcore"][int(profile.data.campaign.sky_repeat_weapon_index.get("sky_lord", 0)) % 3]
	if difficulty == "elite" and str(entry.stage.kind) == "boss":
		var total_elite := 1
		for boss_id in ["forest_moss_guardian", "mine_furnace", "sky_lord"]: total_elite += int(profile.data.campaign.wins.get(boss_id + ":elite", 0))
		reward_snapshot.elite_gem_id = ["echo_gem", "pierce_gem"][(total_elite - 1) % 2]
	var started := profile.transaction(func() -> bool:
		profile.data.active_run = {"run_id":run_id,"stage_id":stage_id,"difficulty":difficulty,"supplies":supplies,"consumed":{},"status":"running","progression_version":ProgressionData.PROGRESSION_VERSION,"growth_level":int(combat_snapshot.growth_level),"growth_exp_at_start":int(profile.data.growth_exp),"combat_snapshot":combat_snapshot,"enemy_snapshot":enemy_snapshot,"stage_snapshot":stage_snapshot,"reward_snapshot":reward_snapshot}
		return true
	, "run_started", "已进入副本。")
	if not started.ok: return started
	return {"ok":true,"code":"run_started","message":"已进入副本。","run_id":run_id,"stage_id":stage_id,"difficulty":difficulty,"stage":entry.stage,"stage_config":stage_snapshot.duplicate(true),"supplies":supplies.duplicate(true),"combat_snapshot":combat_snapshot.duplicate(true),"enemy_snapshot":enemy_snapshot.duplicate(true),"stage_snapshot":stage_snapshot.duplicate(true),"reward_snapshot":reward_snapshot.duplicate(true),"supply_commit":Callable(inventory, "consume_supply").bind(run_id)}

func abandon_run(run_id: String) -> Dictionary:
	return profile.transaction(func() -> bool:
		if profile.data.active_run.is_empty() or str(profile.data.active_run.run_id) != run_id: return false
		profile.data.active_run = {}
		return true
	, "run_abandoned", "已放弃副本；已使用补给不会返还。")

func settle_run(run_id: String, outcome: String, battle_stats: Dictionary = {}) -> Dictionary:
	if outcome not in ["win", "loss", "quit"]: return _failure("invalid_outcome", "无效的副本结果。")
	if profile.data.campaign.settled_runs.has(run_id): return {"ok":true,"code":"already_settled","message":"本局奖励已保存。","rewards":{}}
	var run: Dictionary = profile.data.active_run
	if run.is_empty() or str(run.get("run_id", "")) != run_id: return _failure("unknown_run", "本局已离开，无法结算。")
	var stage_id := str(run.stage_id)
	var difficulty := str(run.get("difficulty", "normal"))
	if not run.get("reward_snapshot") is Dictionary: return _failure("invalid_run", "副本奖励快照损坏。")
	# Supply consumption is persisted as part of the run.  Battle statistics are
	# presentation data and can arrive stale while a result screen is retrying.
	var rewards := _rewards_from_snapshot(run.reward_snapshot, outcome, battle_stats, run.consumed)
	var exp_before := int(profile.data.growth_exp)
	var level_before := profile.growth_level()
	var power_before := int(run.combat_snapshot.get("power", profile.combat_snapshot().power))
	rewards.growth = {"raw_exp":0,"applied_exp":0,"discarded_exp":0,"exp_before":exp_before,"exp_after":exp_before,"level_before":level_before,"level_after":level_before,"power_before":power_before,"power_after":int(profile.combat_snapshot().power)}
	return profile.transaction(func() -> bool:
		if profile.data.campaign.settled_runs.has(run_id): return true
		if outcome == "win":
			var progress_key := _progress_key(stage_id, difficulty)
			profile.data.campaign.first_clears[progress_key] = true
			profile.data.campaign.wins[progress_key] = int(profile.data.campaign.wins.get(progress_key, 0)) + 1
			var actions := int(battle_stats.get("player_actions", 0))
			if actions > 0 and (int(profile.data.campaign.best_player_actions.get(progress_key, 0)) == 0 or actions < int(profile.data.campaign.best_player_actions.get(progress_key, 0))): profile.data.campaign.best_player_actions[progress_key] = actions
			for objective_key in rewards.get("objectives", []): profile.data.campaign.objectives[objective_key] = true
			if difficulty == "normal" and str(run.reward_snapshot.kind) == "boss" and not bool(rewards.first_clear):
				profile.data.campaign.boss_repeat_wins[stage_id] = int(profile.data.campaign.boss_repeat_wins.get(stage_id, 0)) + 1
				if stage_id == "sky_lord": _add_sky_repeat_weapon(rewards, str(run.reward_snapshot.get("repeat_weapon_id", "")))
			if difficulty == "elite" and str(run.reward_snapshot.kind) == "boss": _add_elite_boss_gem(rewards, str(run.reward_snapshot.get("elite_gem_id", "")))
			var raw_exp := int(rewards.get("growth_exp_raw", 0))
			var before_exp := int(profile.data.growth_exp)
			var accepted_exp := mini(raw_exp, ProgressionData.MAX_EXP - before_exp)
			profile.data.growth_exp = before_exp + accepted_exp
			rewards.growth_exp_raw = raw_exp
			rewards.growth_exp_applied = accepted_exp
			rewards.growth_exp_overflow = raw_exp - accepted_exp
			if bool(rewards.get("growth_first_clear", false)): profile.data.growth_first_clears[_growth_key(stage_id, difficulty)] = true
			rewards.growth = {"raw_exp":raw_exp,"applied_exp":accepted_exp,"discarded_exp":raw_exp - accepted_exp,"exp_before":before_exp,"exp_after":int(profile.data.growth_exp),"level_before":level_before,"level_after":profile.growth_level(),"power_before":power_before,"power_after":int(profile.combat_snapshot().power)}
			_add_rewards(rewards)
		elif outcome == "loss": profile.data.gold = int(profile.data.gold) + int(rewards.gold)
		profile.data.campaign.settled_runs[run_id] = true
		profile.data.active_run = {}
		return true
	, "run_settled", "奖励已保存。", {"rewards":rewards})

func _rewards(stage_id: String, outcome: String, battle_stats: Dictionary = {}, consumed_supplies: Dictionary = {}, difficulty: String = "normal") -> Dictionary:
	var stage := CampaignData.stage(stage_id, difficulty)
	if outcome == "quit": return {"gold":0,"stacks":{},"first_clear":false}
	if outcome == "loss": return {"gold":int(floor(float(stage.rewards.win.gold) * 0.2)),"stacks":{},"first_clear":false,"groups":[{"kind":"loss","label":"失败奖励","gold":int(floor(float(stage.rewards.win.gold) * 0.2)),"stacks":{}}]}
	var win: Dictionary = stage.rewards.win.duplicate(true)
	win.groups = [{"kind":difficulty,"label":"精英通关" if difficulty == "elite" else "普通通关","gold":int(win.gold),"stacks":win.stacks.duplicate(true)}]
	var first := not bool(profile.data.campaign.first_clears.get(_progress_key(stage_id, difficulty), false))
	if first:
		win.gold = int(win.gold) + int(stage.rewards.first_clear.gold)
		for item_id in stage.rewards.first_clear.stacks:
			win.stacks[item_id] = int(win.stacks.get(item_id, 0)) + int(stage.rewards.first_clear.stacks[item_id])
		if int(stage.rewards.first_clear.gold) > 0 or not stage.rewards.first_clear.stacks.is_empty(): win.groups.append({"kind":"first_clear","label":"首次通关","gold":int(stage.rewards.first_clear.gold),"stacks":stage.rewards.first_clear.stacks.duplicate(true)})
	win.first_clear = first
	win.objectives = []
	if difficulty == "normal" and stage_id.begins_with("forest_"):
		var objectives: Dictionary = profile.data.campaign.objectives
		for objective_id in ["no_medkit", "six_actions"]:
			var qualified := int(consumed_supplies.get("small_medkit", 0)) == 0 and int(battle_stats.get("medkits_used", 1)) == 0 if objective_id == "no_medkit" else int(battle_stats.get("player_actions", 999)) <= 8
			var key: String = stage_id + ":" + objective_id
			if qualified and not bool(objectives.get(key,false)):
				win.gold = int(win.gold) + 60
				win.stacks.enhancement_dust = int(win.stacks.get("enhancement_dust",0)) + 2
				win.objectives.append(key)
				win.groups.append({"kind":"objective","label":"挑战目标","objective_id":objective_id,"gold":60,"stacks":{"enhancement_dust":2}})
	return win

func _progress_key(stage_id: String, difficulty: String) -> String:
	return stage_id if difficulty == "normal" else stage_id + ":elite"

func _growth_key(stage_id: String, difficulty: String) -> String:
	return "v%d:%s:%s" % [ProgressionData.PROGRESSION_VERSION, stage_id, difficulty]

func _enemy_snapshot(stage_snapshot: Dictionary, difficulty: String, target_level: int) -> Dictionary:
	return CampaignData.enemy_snapshot(str(stage_snapshot.get("map", "")), difficulty)

func _hazard_snapshot(stage_snapshot: Dictionary, target_level: int) -> Dictionary:
	var multiplier := ProgressionData.scale(target_level)
	# All possible fixed hazard channels are frozen so battle never re-reads a live stage definition.
	return {"spore":60.0 * multiplier,"furnace":90.0 * multiplier,"altar":80.0 * multiplier,"storm":100.0 * multiplier,"scale":multiplier,"mechanism":str(stage_snapshot.get("mechanism", ""))}

func _rewards_from_snapshot(snapshot: Dictionary, outcome: String, battle_stats: Dictionary, consumed_supplies: Dictionary) -> Dictionary:
	if outcome == "quit": return {"gold":0,"stacks":{},"first_clear":false,"growth_exp_raw":0,"growth_first_clear":false}
	if outcome == "loss": return {"gold":int(snapshot.get("failure_gold", 0)),"stacks":{},"first_clear":false,"growth_exp_raw":0,"growth_first_clear":false,"groups":[{"kind":"loss","label":"失败奖励","gold":int(snapshot.get("failure_gold", 0)),"stacks":{}}]}
	var stage_rewards: Dictionary = snapshot.stage_rewards
	var win: Dictionary = stage_rewards.win.duplicate(true)
	win.groups = [{"kind":str(snapshot.difficulty),"label":"精英通关" if str(snapshot.difficulty) == "elite" else "普通通关","gold":int(win.gold),"stacks":win.stacks.duplicate(true)}]
	var first := bool(snapshot.get("first_clear_eligible", false))
	if first:
		win.gold = int(win.gold) + int(stage_rewards.first_clear.gold)
		for item_id in stage_rewards.first_clear.stacks: win.stacks[item_id] = int(win.stacks.get(item_id, 0)) + int(stage_rewards.first_clear.stacks[item_id])
		if int(stage_rewards.first_clear.gold) > 0 or not stage_rewards.first_clear.stacks.is_empty(): win.groups.append({"kind":"first_clear","label":"首次通关","gold":int(stage_rewards.first_clear.gold),"stacks":stage_rewards.first_clear.stacks.duplicate(true)})
	win.first_clear = first
	win.objectives = []
	var rules: Dictionary = snapshot.get("objective_rules", {})
	if bool(rules.get("enabled", false)):
		for objective_id in ["no_medkit", "six_actions"]:
			var qualified := int(consumed_supplies.get("small_medkit", 0)) == 0 and int(battle_stats.get("medkits_used", 1)) == 0 if objective_id == "no_medkit" else int(battle_stats.get("player_actions", 999)) <= 8
			var key: String = str(snapshot.stage_id) + ":" + objective_id
			if qualified and not bool(profile.data.campaign.objectives.get(key, false)):
				var award: Dictionary = rules[objective_id]
				win.gold = int(win.gold) + int(award.gold)
				for item_id in award.stacks: win.stacks[item_id] = int(win.stacks.get(item_id, 0)) + int(award.stacks[item_id])
				win.objectives.append(key)
				win.groups.append({"kind":"objective","label":"挑战目标","objective_id":objective_id,"gold":int(award.gold),"stacks":award.stacks.duplicate(true)})
	var growth: Dictionary = snapshot.growth
	win.growth_exp_raw = int(growth.first_clear_exp) if bool(snapshot.get("growth_first_clear_eligible", false)) else int(growth.base_exp)
	win.growth_first_clear = bool(snapshot.get("growth_first_clear_eligible", false))
	return win

func _add_sky_repeat_weapon(rewards: Dictionary, frozen_item_id: String = "") -> void:
	var wins := int(profile.data.campaign.boss_repeat_wins.get("sky_lord", 0))
	if frozen_item_id.is_empty(): return
	var counter: Dictionary = profile.data["campaign"].get("sky_repeat_weapon_index", {})
	counter["sky_lord"] = int(counter.get("sky_lord", 0)) + 1
	profile.data["campaign"]["sky_repeat_weapon_index"] = counter
	rewards.stacks[frozen_item_id] = int(rewards.stacks.get(frozen_item_id, 0)) + 1
	rewards.groups.append({"kind":"repeat_weapon","label":"三胜循环奖励","gold":0,"stacks":{frozen_item_id:1}})

func _add_elite_boss_gem(rewards: Dictionary, frozen_gem: String = "") -> void:
	if frozen_gem.is_empty(): return
	var counter: Dictionary = profile.data["campaign"].get("elite_gem_counter", {})
	var total_elite_boss_wins := 0
	for boss_id in ["forest_moss_guardian", "mine_furnace", "sky_lord"]:
		total_elite_boss_wins += int(profile.data.campaign.wins.get(boss_id + ":elite", 0))
	counter["boss"] = total_elite_boss_wins
	profile.data["campaign"]["elite_gem_counter"] = counter
	rewards.stacks[frozen_gem] = int(rewards.stacks.get(frozen_gem, 0)) + 1
	rewards.groups.append({"kind":"elite_gem","label":"精英领主宝石","gold":0,"stacks":{frozen_gem:1}})

func _add_rewards(rewards: Dictionary) -> void:
	profile.data.gold = int(profile.data.gold) + int(rewards.gold)
	for item_id in rewards.stacks:
		if ItemData.definition(item_id).get("category", "") == "weapon":
			var instance_id := "reward-%s-%d" % [item_id, Time.get_ticks_usec()]
			profile.data.inventory.equipment[instance_id] = {"template_id":item_id,"level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":true,"acquired_at":int(Time.get_unix_time_from_system())}
			continue
		profile.data.inventory.stacks[item_id] = int(profile.data.inventory.stacks.get(item_id, 0)) + int(rewards.stacks[item_id])
		profile.data.inventory.acquired_at[item_id] = int(Time.get_unix_time_from_system())
		if not item_id in profile.data.inventory.new_items: profile.data.inventory.new_items.append(item_id)

func _failure(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":code,"message":message}
