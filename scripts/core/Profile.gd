class_name PlayerProfile
extends RefCounted

const CURRENT_VERSION := 5
var path: String
var data: Dictionary
var notice := ""
var migration_blocked := false
var migration_source_path := ""

func _init(save_path: String = "user://profile.json") -> void:
	path = save_path
	data = defaults()
	load_profile()

static func defaults() -> Dictionary:
	var equipment := {
		"legacy-weapon-ember":{"template_id":"ember","level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0},
		"legacy-weapon-volt":{"template_id":"volt","level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0},
		"legacy-charm-feather":{"template_id":"feather","level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0},
		"legacy-charm-moss":{"template_id":"moss","level":0,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":0},
	}
	return {"version":CURRENT_VERSION,"growth_exp":0,"progression_version":ProgressionData.PROGRESSION_VERSION,"growth_first_clears":{},"gold":180,"xp":0,"wins":0,"matches":0,"weapon":"ember","charm":"feather","levels":{"ember":0,"volt":0},"ledger":[],"music":0.35,"sfx":0.65,"tutorial_seen":{},"inventory":{"stacks":{},"equipment":equipment,"new_items":[],"acquired_at":{},"starter_supplies_claimed":false},"loadout":{"weapon_instance_id":"legacy-weapon-ember","charm_instance_id":"legacy-charm-feather","supplies":[]},"campaign":{"first_clears":{},"objectives":{},"boss_repeat_wins":{},"settled_runs":{},"wins":{},"best_player_actions":{},"sky_repeat_weapon_index":{},"elite_gem_counter":{}},"active_run":{}}

func valid(value: Variant) -> bool:
	if not value is Dictionary or int(value.get("version", 0)) not in [1, 2, 3, 4, CURRENT_VERSION]: return false
	for key in ["gold", "xp", "wins", "matches"]:
		if not (value.get(key) is float or value.get(key) is int) or float(value[key]) < 0.0 or float(value[key]) > 100000000.0: return false
	if not GameData.WEAPONS.has(value.get("weapon")) or not GameData.CHARMS.has(value.get("charm")): return false
	if not value.get("levels") is Dictionary or not value.get("ledger") is Array: return false
	for key in ["ember", "volt"]:
		if not (value.levels.get(key) is float or value.levels.get(key) is int) or float(value.levels[key]) < 0 or float(value.levels[key]) > 8: return false
	for id in value.ledger:
		if not id is String: return false
	for key in ["music", "sfx"]:
		if not (value.get(key, 0.5) is float or value.get(key) is int): return false
	if int(value.version) >= 3 and not _valid_round_one(value): return false
	if int(value.version) >= 5 and (not _whole_nonnegative(value.get("growth_exp", -1)) or int(value.get("growth_exp", 0)) > ProgressionData.MAX_EXP or int(value.get("progression_version", 0)) != ProgressionData.PROGRESSION_VERSION or not value.get("growth_first_clears") is Dictionary): return false
	return true

func _valid_round_one(value: Dictionary) -> bool:
	if int(value.version) >= 4:
		if not value.get("tutorial_seen") is Dictionary: return false
		for hint_id in value.tutorial_seen:
			if str(hint_id) not in ["first_campaign", "first_material", "first_upgrade"] or not value.tutorial_seen[hint_id] is bool: return false
	var inventory: Variant = value.get("inventory")
	var loadout: Variant = value.get("loadout")
	var campaign: Variant = value.get("campaign")
	if not inventory is Dictionary or not loadout is Dictionary or not campaign is Dictionary or not value.get("active_run") is Dictionary: return false
	if not inventory.get("stacks") is Dictionary or not inventory.get("equipment") is Dictionary or not inventory.get("new_items") is Array or not inventory.get("acquired_at") is Dictionary or not inventory.get("starter_supplies_claimed") is bool: return false
	for item_id in inventory.stacks:
		if not ItemData.has(str(item_id)) or not _whole_nonnegative(inventory.stacks[item_id]): return false
	for instance_id in inventory.equipment:
		var equipment: Variant = inventory.equipment[instance_id]
		if not equipment is Dictionary or not ItemData.has(str(equipment.get("template_id",""))) or ItemData.definition(str(equipment.get("template_id",""))).get("category", "") not in ["weapon", "charm"] or not _whole_nonnegative(equipment.get("level")) or int(equipment.level) > 8 or not equipment.get("locked") is bool or not equipment.get("invested_materials") is Dictionary: return false
		var gem_id = equipment.get("gem_item_id", null)
		if gem_id != null and (ItemData.definition(str(equipment.get("template_id", ""))).get("category", "") != "weapon" or str(gem_id) not in ["echo_gem", "pierce_gem"]): return false
		for material_id in equipment.invested_materials:
			if ItemData.definition(str(material_id)).get("category", "") != "material" or not _whole_nonnegative(equipment.invested_materials[material_id]): return false
	if not inventory.equipment.has(str(loadout.get("weapon_instance_id",""))) or not inventory.equipment.has(str(loadout.get("charm_instance_id",""))) or not loadout.get("supplies") is Array or loadout.supplies.size() > 2: return false
	if ItemData.definition(str(inventory.equipment[str(loadout.weapon_instance_id)].template_id)).category != "weapon" or ItemData.definition(str(inventory.equipment[str(loadout.charm_instance_id)].template_id)).category != "charm": return false
	var supply_ids := {}
	for slot in loadout.supplies:
		if not slot is Dictionary or not ItemData.is_supply(str(slot.get("item_id",""))) or not _whole_nonnegative(slot.get("quantity",0)) or int(slot.quantity) < 1 or int(slot.quantity) > 2 or supply_ids.has(str(slot.item_id)): return false
		supply_ids[str(slot.item_id)] = true
	for key in ["first_clears","objectives","boss_repeat_wins","settled_runs"]:
		if not campaign.get(key) is Dictionary: return false
	if int(value.version) >= 4:
		for key in ["wins","best_player_actions","sky_repeat_weapon_index","elite_gem_counter"]:
			if not campaign.get(key) is Dictionary: return false
	var active: Dictionary = value.active_run
	if not active.is_empty():
		if not active.get("run_id") is String or not active.get("stage_id") is String or not CampaignData.has_stage(str(active.stage_id)) or str(active.get("status","")) != "running" or not active.get("supplies") is Dictionary or not active.get("consumed") is Dictionary: return false
		if int(value.version) >= 4 and str(active.get("difficulty", "")) not in ["normal", "elite"]: return false
		for item_id in active.supplies:
			if not ItemData.is_supply(str(item_id)) or not _whole_nonnegative(active.supplies[item_id]) or int(active.supplies[item_id]) < 1 or int(active.supplies[item_id]) > 2: return false
		for item_id in active.consumed:
			if not active.supplies.has(item_id) or not _whole_nonnegative(active.consumed[item_id]) or int(active.consumed[item_id]) > int(active.supplies[item_id]): return false
		if int(value.version) >= 5:
			for key in ["progression_version", "growth_level", "growth_exp_at_start"]:
				if not _whole_nonnegative(active.get(key, -1)): return false
			if int(active.progression_version) != ProgressionData.PROGRESSION_VERSION or int(active.growth_level) < 1 or int(active.growth_level) > ProgressionData.MAX_LEVEL or int(active.growth_exp_at_start) > ProgressionData.MAX_EXP: return false
			for key in ["combat_snapshot", "enemy_snapshot", "stage_snapshot", "reward_snapshot"]:
				if not active.get(key) is Dictionary: return false
			for snapshot in [active.combat_snapshot, active.enemy_snapshot]:
				for numeric_key in ["base_attack", "direct_hit_bonus", "max_hp", "damage_reduction", "power"]:
					if not (snapshot.get(numeric_key) is int or snapshot.get(numeric_key) is float) or not is_finite(float(snapshot[numeric_key])): return false
				if float(snapshot.base_attack) < 0.0 or float(snapshot.direct_hit_bonus) < 0.0 or float(snapshot.max_hp) <= 0.0 or float(snapshot.damage_reduction) < 0.0 or float(snapshot.damage_reduction) >= 1.0 or int(snapshot.get("progression_version", 0)) != ProgressionData.PROGRESSION_VERSION: return false
	return true

func _whole_nonnegative(value: Variant) -> bool:
	return (value is int or value is float) and float(value) >= 0.0 and is_equal_approx(float(value), floor(float(value)))

func read_file(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path): return null
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(file_path)) == OK else null

func load_profile() -> void:
	var value: Variant = read_file(path)
	if not valid(value):
		value = read_file(path + ".bak")
		if valid(value):
			notice = "已从备份恢复你的旅程。"
			migration_source_path = path + ".bak"
		elif FileAccess.file_exists(path):
			notice = "存档无法读取，已保留原文件并开启新旅程。"
			DirAccess.copy_absolute(path, path + ".damaged-" + str(Time.get_unix_time_from_system()).replace(".", "-"))
			return
		else: return
	if migration_source_path.is_empty(): migration_source_path = path
	data.merge(value, true)
	data.music = clampf(float(data.music), 0.0, 1.0)
	data.sfx = clampf(float(data.sfx), 0.0, 1.0)
	if int(data.version) < 3: _migrate_to_round_one()
	elif int(data.version) < 4: _migrate_to_round_three()
	if int(data.version) < CURRENT_VERSION: _migrate_to_permanent_power()

func ensure_round_one() -> bool:
	if int(data.version) < 3 or not data.has("inventory"): _migrate_to_round_one()
	elif int(data.version) < 4: _migrate_to_round_three()
	if int(data.version) < CURRENT_VERSION: _migrate_to_permanent_power()
	if migration_blocked: return false
	if not bool(data.inventory.get("starter_supplies_claimed", false)):
		var result := transaction(func() -> bool:
			data.inventory.stacks.small_medkit = int(data.inventory.stacks.get("small_medkit", 0)) + 2
			data.inventory.stacks.stamina_tonic = int(data.inventory.stacks.get("stamina_tonic", 0)) + 2
			data.inventory.starter_supplies_claimed = true
			return true
		, "starter_supplies", "已领取远征入门补给。")
		return bool(result.ok)
	return true

func _migrate_to_round_one() -> void:
	var old_weapon := str(data.get("weapon", "ember"))
	var old_charm := str(data.get("charm", "feather"))
	var old_levels: Dictionary = data.get("levels", {})
	var now := int(Time.get_unix_time_from_system())
	var equipment := {}
	for template_id in ["ember", "volt"]: equipment["legacy-weapon-" + template_id] = _equipment(template_id, int(old_levels.get(template_id, 0)), now)
	for template_id in ["feather", "moss"]: equipment["legacy-charm-" + template_id] = _equipment(template_id, 0, now)
	data.inventory = {"stacks":{},"equipment":equipment,"new_items":[],"acquired_at":{},"starter_supplies_claimed":false}
	data.loadout = {"weapon_instance_id":"legacy-weapon-" + old_weapon,"charm_instance_id":"legacy-charm-" + old_charm,"supplies":[]}
	data.campaign = {"first_clears":{},"objectives":{},"boss_repeat_wins":{},"settled_runs":{},"wins":{},"best_player_actions":{},"sky_repeat_weapon_index":{},"elite_gem_counter":{}}
	data.active_run = {}
	data.version = 4
	_sync_legacy_mirrors()

func _migrate_to_round_three() -> void:
	# v3 already owns instance inventory. Preserve it exactly and only add data that
	# did not exist before; old upgrades retain their recorded (or zero) investment.
	for instance_id in data.inventory.equipment:
		var equipment: Dictionary = data.inventory.equipment[instance_id]
		if not equipment.has("gem_item_id"): equipment.gem_item_id = null
		if not equipment.has("invested_materials") or not equipment.invested_materials is Dictionary: equipment.invested_materials = {}
		data.inventory.equipment[instance_id] = equipment
	for key in ["wins","best_player_actions","sky_repeat_weapon_index","elite_gem_counter"]:
		if not data.campaign.get(key) is Dictionary: data.campaign[key] = {}
	if not data.get("tutorial_seen") is Dictionary: data.tutorial_seen = {}
	if not data.active_run.is_empty():
		data.active_run.difficulty = str(data.active_run.get("difficulty", "normal"))
		if data.active_run.difficulty not in ["normal", "elite"]: data.active_run.difficulty = "normal"
		if not data.active_run.get("combat_snapshot") is Dictionary: data.active_run.combat_snapshot = combat_snapshot()
	data.version = 4
	_sync_legacy_mirrors()

func _migrate_to_permanent_power() -> void:
	# Preserve an untouched v4 source exactly once before changing its schema.
	if FileAccess.file_exists(migration_source_path) and not FileAccess.file_exists(path + ".v4.bak"):
		if DirAccess.copy_absolute(migration_source_path, path + ".v4.bak") != OK:
			notice = "无法创建 v4 存档备份；成长迁移未执行。"
			migration_blocked = true
			return
	var highest := 1
	for stage_id in CampaignData.TARGET_LEVELS:
		if bool(data.campaign.first_clears.get(stage_id, false)):
			highest = max(highest, int(CampaignData.FIRST_CLEAR_LEVELS[stage_id]))
		if bool(data.campaign.first_clears.get(stage_id + ":elite", false)) and bool(data.campaign.first_clears.get(stage_id, false)) and bool(data.campaign.first_clears.get("sky_lord", false)):
			highest = max(highest, int(CampaignData.ELITE_TARGET_LEVELS[stage_id]))
	data.growth_exp = ProgressionData.exp_for_level(highest)
	data.progression_version = ProgressionData.PROGRESSION_VERSION
	data.growth_first_clears = {}
	for stage_id in CampaignData.TARGET_LEVELS:
		if bool(data.campaign.first_clears.get(stage_id, false)): data.growth_first_clears["v1:%s:normal" % stage_id] = true
		if bool(data.campaign.first_clears.get(stage_id + ":elite", false)): data.growth_first_clears["v1:%s:elite" % stage_id] = true
	if not data.active_run.is_empty():
		data.active_run = {}
		notice = "检测到旧版本未完成远征，已安全放弃；已使用补给不会返还。"
	data.version = CURRENT_VERSION
	_sync_legacy_mirrors()

func _equipment(template_id: String, level: int, acquired_at: int) -> Dictionary:
	return {"template_id":template_id,"level":level,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":acquired_at}

func _sync_legacy_mirrors() -> void:
	if not data.has("loadout") or not data.has("inventory"): return
	var weapon: Dictionary = data.inventory.equipment.get(str(data.loadout.get("weapon_instance_id", "")), {})
	var charm: Dictionary = data.inventory.equipment.get(str(data.loadout.get("charm_instance_id", "")), {})
	if not weapon.is_empty(): data.weapon = str(weapon.template_id)
	if not charm.is_empty(): data.charm = str(charm.template_id)
	data.levels = {"ember":0,"volt":0,"rockcore":0}
	if not weapon.is_empty() and str(weapon.template_id) in data.levels: data.levels[weapon.template_id] = int(weapon.level)

func growth_level() -> int:
	return ProgressionData.level_for_exp(int(data.get("growth_exp", 0)))

func growth_progress() -> Dictionary:
	var level := growth_level()
	var current := int(data.get("growth_exp", 0))
	var required := ProgressionData.exp_for_level(level + 1) if level < ProgressionData.MAX_LEVEL else ProgressionData.MAX_EXP
	return {"level":level,"exp":current,"current":current - ProgressionData.exp_for_level(level),"required":required - ProgressionData.exp_for_level(level),"max_level":ProgressionData.MAX_LEVEL}

func preview_combat_snapshot(overrides: Dictionary = {}) -> Dictionary:
	var weapon_id := str(data.loadout.get("weapon_instance_id", ""))
	var charm_id := str(data.loadout.get("charm_instance_id", ""))
	if overrides.has("weapon_instance_id"): weapon_id = str(overrides.weapon_instance_id)
	if overrides.has("charm_instance_id"): charm_id = str(overrides.charm_instance_id)
	var weapon: Dictionary = data.inventory.equipment.get(weapon_id, {})
	var charm: Dictionary = data.inventory.equipment.get(charm_id, {})
	var gem_id = overrides.get("gem_item_id", weapon.get("gem_item_id", null))
	var enhancement := int(overrides.get("level", weapon.get("level", 0)))
	var snapshot := ProgressionData.player_snapshot(str(weapon.get("template_id", data.get("weapon", "ember"))), str(charm.get("template_id", data.get("charm", "feather"))), enhancement, gem_id, growth_level())
	snapshot.weapon_instance_id = weapon_id
	snapshot.charm_instance_id = charm_id
	return snapshot

func combat_snapshot(mode: String = "campaign") -> Dictionary:
	if mode == "campaign": return preview_combat_snapshot()
	var snapshot := preview_combat_snapshot()
	snapshot.max_hp = 1000.0 + (60.0 if snapshot.gem_item_id == "echo_gem" else 0.0)
	snapshot.base_attack = GameData.attack(str(snapshot.weapon), int(snapshot.level))
	snapshot.direct_hit_bonus = 8.0 if snapshot.gem_item_id == "pierce_gem" else 0.0
	snapshot.damage_reduction = 0.0
	snapshot.power = ProgressionData.power(float(snapshot.base_attack), float(snapshot.direct_hit_bonus), float(snapshot.max_hp), 0.0)
	return snapshot

func tutorial_seen(hint_id: String) -> bool:
	return bool(data.get("tutorial_seen", {}).get(hint_id, false))

func acknowledge_hint(hint_id: String) -> Dictionary:
	if hint_id not in ["first_campaign", "first_material", "first_upgrade"]: return {"ok":false,"code":"invalid_hint","message":"提示不存在。"}
	if tutorial_seen(hint_id): return {"ok":true,"code":"already_seen","message":""}
	return transaction(func() -> bool:
		if not data.get("tutorial_seen") is Dictionary: data.tutorial_seen = {}
		data.tutorial_seen[hint_id] = true
		return true
	, "hint_acknowledged", "")

func mark_tutorial_seen(hint_id: String) -> Dictionary:
	return acknowledge_hint(hint_id)

func save() -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		notice = "存档写入失败，请检查可用空间。"
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	if file.get_error() != OK:
		file.close()
		notice = "存档写入失败，请检查可用空间。"
		return false
	file.close()
	if not valid(read_file(path + ".tmp")):
		notice = "存档临时文件校验失败，本次更改未保存。"
		return false
	if valid(read_file(path)) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		notice = "无法备份存档，本次更改未保存。"
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		notice = "无法替换存档，本次更改未保存。"
		return false
	return true

func transaction(change: Callable, success_code: String = "saved", success_message: String = "已保存。", extra: Dictionary = {}) -> Dictionary:
	var old := data.duplicate(true)
	if not change.call():
		data = old
		return {"ok":false,"code":"invalid_state","message":"当前状态无法执行此操作。"}
	_sync_legacy_mirrors()
	if not save():
		data = old
		return {"ok":false,"code":"save_failed","message":notice}
	var result := {"ok":true,"code":success_code,"message":success_message}
	result.merge(extra, true)
	return result

func equip(weapon: String, charm: String) -> bool:
	if not GameData.WEAPONS.has(weapon) or not GameData.CHARMS.has(charm): return false
	ensure_round_one()
	var result := transaction(func() -> bool:
		var weapon_id := _find_equipment_instance(weapon, "weapon")
		var charm_id := _find_equipment_instance(charm, "charm")
		if weapon_id.is_empty() or charm_id.is_empty(): return false
		data.loadout.weapon_instance_id = weapon_id
		data.loadout.charm_instance_id = charm_id
		return true
	)
	return bool(result.ok)

func _find_equipment_instance(template_id: String, category: String) -> String:
	var current_id := str(data.loadout.get("weapon_instance_id", "") if category == "weapon" else data.loadout.get("charm_instance_id", ""))
	var current: Dictionary = data.inventory.equipment.get(current_id, {})
	if str(current.get("template_id", "")) == template_id: return current_id
	for instance_id in data.inventory.equipment:
		var equipment: Dictionary = data.inventory.equipment[instance_id]
		if str(equipment.template_id) == template_id and ItemData.definition(template_id).get("category", "") == category: return str(instance_id)
	return ""

func upgrade_cost(weapon: String) -> int:
	return 60 * (int(data.levels.get(weapon, 0)) + 1)

func upgrade(weapon: String) -> bool:
	if not GameData.WEAPONS.has(weapon): return false
	ensure_round_one()
	var instance_id := _find_equipment_instance(weapon, "weapon")
	return not instance_id.is_empty() and bool(ForgeService.new(self).upgrade(instance_id).ok)

func reward(id: String, winner: int, mode: String) -> Dictionary:
	if mode != "ai" or id in data.ledger: return {"gold":0,"xp":0,"saved":true}
	var gold := 90 if winner == 0 else (55 if winner == -1 else 40)
	var xp := 60 if winner == 0 else 30
	var result := transaction(func() -> bool:
		data.gold = int(data.gold) + gold
		data.xp = int(data.xp) + xp
		data.matches = int(data.matches) + 1
		data.wins = int(data.wins) + (1 if winner == 0 else 0)
		data.ledger.append(id)
		if data.ledger.size() > 100: data.ledger.pop_front()
		return true
	)
	return {"gold":gold,"xp":xp,"saved":bool(result.ok)}
