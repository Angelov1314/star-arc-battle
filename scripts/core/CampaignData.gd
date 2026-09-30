class_name CampaignData
extends RefCounted

const TARGET_LEVELS := {"forest_treebridge":1,"forest_spore_corridor":2,"forest_moss_guardian":4,"mine_entrance":6,"mine_fracture":8,"mine_furnace":10,"sky_corridor":13,"sky_altar":16,"sky_lord":20}
const ELITE_TARGET_LEVELS := {"forest_treebridge":23,"forest_spore_corridor":27,"forest_moss_guardian":31,"mine_entrance":35,"mine_fracture":39,"mine_furnace":43,"sky_corridor":48,"sky_altar":53,"sky_lord":58}
const FIRST_CLEAR_LEVELS := {"forest_treebridge":2,"forest_spore_corridor":4,"forest_moss_guardian":6,"mine_entrance":8,"mine_fracture":10,"mine_furnace":13,"sky_corridor":16,"sky_altar":20,"sky_lord":23}
# v1 campaign-only balance overrides.  The initial standard sampler put all
# three bosses at 90–100% win rate and Mine Fracture at 100%; raw stage data is
# intentionally left unchanged for legacy/non-campaign paths.
const MODERN_ENEMY_OVERRIDES := {"forest_moss_guardian":{"ai_spread":7.0,"max_hp":1380.0,"attack_multiplier":1.25},"mine_fracture":{"max_hp":1325.0},"mine_furnace":{"ai_spread":7.0,"max_hp":1725.0,"attack_multiplier":1.5},"sky_lord":{"ai_spread":7.0}}

const STAGES := {
	"forest_treebridge": {
		"id":"forest_treebridge", "chapter":1, "index":1, "name":"树桥试炼", "kind":"normal", "unlocks_after":"",
		"failure_gold":9, "rewards":{"win":{"gold":45,"stacks":{"enhancement_dust":2,"woodchip":1,"small_medkit":1}},"first_clear":{"gold":120,"stacks":{}}},
		"stage_config":{"map":"forest_treebridge","enemy":"ranger","wind":"gentle"},
	},
	"forest_spore_corridor": {
		"id":"forest_spore_corridor", "chapter":1, "index":2, "name":"孢子回廊", "kind":"normal", "unlocks_after":"forest_treebridge",
		"failure_gold":9, "rewards":{"win":{"gold":45,"stacks":{"enhancement_dust":2,"woodchip":1,"stamina_tonic":1}},"first_clear":{"gold":120,"stacks":{}}},
		"stage_config":{"map":"forest_spore_corridor","enemy":"ranger","hazard":"spores"},
	},
	"forest_moss_guardian": {
		"id":"forest_moss_guardian", "chapter":1, "index":3, "name":"苔甲守卫", "kind":"boss", "unlocks_after":"forest_spore_corridor",
		"failure_gold":18, "rewards":{"win":{"gold":90,"stacks":{"enhancement_dust":4,"woodchip":2,"small_medkit":1,"stamina_tonic":1}},"first_clear":{"gold":120,"stacks":{}}},
		"stage_config":{"map":"forest_moss_guardian","enemy":"moss_guardian","boss_state":"guarded_tired"},
	},
	"mine_entrance": {"id":"mine_entrance","chapter":2,"index":1,"name":"矿井入口","kind":"normal","unlocks_after":"forest_moss_guardian","failure_gold":13,"rewards":{"win":{"gold":65,"stacks":{"enhancement_dust":3,"copper_ore":2,"small_medkit":1}},"first_clear":{"gold":180,"stacks":{}}},"stage_config":{"map":"mine_entrance","terrain":"mine_entrance","enemy":{"name":"矿井巡卫","max_hp":1050,"level":2,"ai_spread":7},"mechanism":"high_ground"}},
	"mine_fracture": {"id":"mine_fracture","chapter":2,"index":2,"name":"裂岩矿道","kind":"normal","unlocks_after":"mine_entrance","failure_gold":13,"rewards":{"win":{"gold":65,"stacks":{"enhancement_dust":3,"copper_ore":2,"stamina_tonic":1}},"first_clear":{"gold":180,"stacks":{}}},"stage_config":{"map":"mine_fracture","terrain":"mine_fracture","enemy":{"name":"裂岩守卫","max_hp":1150,"level":3,"ai_spread":8},"mechanism":"thin_ground"}},
	"mine_furnace": {"id":"mine_furnace","chapter":2,"index":3,"name":"熔炉核心","kind":"boss","unlocks_after":"mine_fracture","failure_gold":26,"rewards":{"win":{"gold":130,"stacks":{"enhancement_dust":6,"copper_ore":4,"armor_breaker":1}},"first_clear":{"gold":180,"stacks":{"rockcore":1}}},"stage_config":{"map":"mine_furnace","terrain":"mine_furnace","enemy":{"name":"熔炉核心","max_hp":1500,"level":3,"ai_spread":10},"mechanism":"furnace"}},
}

static func has_stage(stage_id: String) -> bool:
	return STAGES.has(stage_id) or SKY_STAGES.has(stage_id)

const SKY_STAGES := {
	"sky_corridor": {"id":"sky_corridor","chapter":3,"index":1,"name":"逆风长廊","kind":"normal","unlocks_after":"mine_furnace","failure_gold":17,"rewards":{"win":{"gold":85,"stacks":{"enhancement_dust":4,"relic_shard":1}},"first_clear":{"gold":240,"stacks":{}}},"stage_config":{"map":"sky_corridor","terrain":"sky_corridor","enemy":{"name":"逆风守卫","max_hp":1200,"level":4,"ai_spread":8},"mechanism":"sky_corridor"}},
	"sky_altar": {"id":"sky_altar","chapter":3,"index":2,"name":"风暴祭坛","kind":"normal","unlocks_after":"sky_corridor","failure_gold":17,"rewards":{"win":{"gold":85,"stacks":{"enhancement_dust":4,"relic_shard":1}},"first_clear":{"gold":240,"stacks":{}}},"stage_config":{"map":"sky_altar","terrain":"sky_altar","enemy":{"name":"符文精英","max_hp":1350,"level":4,"ai_spread":9},"mechanism":"sky_altar"}},
	"sky_lord": {"id":"sky_lord","chapter":3,"index":3,"name":"风暴领主","kind":"boss","unlocks_after":"sky_altar","failure_gold":34,"rewards":{"win":{"gold":170,"stacks":{"enhancement_dust":8,"relic_shard":2}},"first_clear":{"gold":240,"stacks":{"echo_gem":1,"pierce_gem":1}}},"stage_config":{"map":"sky_lord","terrain":"sky_lord","enemy":{"name":"风暴领主","max_hp":1800,"level":5,"ai_spread":10},"mechanism":"storm_lord"}},
}

const ELITE_AFFIXES := {
	"forest_treebridge":["strong_wind"], "forest_spore_corridor":["thin_soil"], "forest_moss_guardian":["armored"],
	"mine_entrance":["strong_wind","thin_soil"], "mine_fracture":["thin_soil","armored"], "mine_furnace":["strong_wind","armored"],
	"sky_corridor":["strong_wind","thin_soil"], "sky_altar":["thin_soil","armored"], "sky_lord":["strong_wind","armored"],
}

static func stage(stage_id: String, difficulty: String = "normal") -> Dictionary:
	var base: Dictionary = STAGES.get(stage_id, SKY_STAGES.get(stage_id, {})).duplicate(true)
	if base.is_empty(): return base
	var target := int(ELITE_TARGET_LEVELS.get(stage_id, 1) if difficulty == "elite" else TARGET_LEVELS.get(stage_id, 1))
	base.stage_config.target_level = target
	base.stage_config.recommended_power = roundi(1000.0 * ProgressionData.scale(target))
	base.stage_config.hazard_scale = ProgressionData.scale(target)
	if difficulty != "elite": return base
	base.difficulty = "elite"
	base.name = "精英 · " + str(base.name)
	base.stage_config.modifiers = ELITE_AFFIXES.get(stage_id, []).duplicate()
	base.public_affixes = base.stage_config.modifiers.duplicate()
	var elite_win := {"gold":int(floor(float(base.rewards.win.gold) * 1.5)),"stacks":{}}
	for item_id in base.rewards.win.stacks: elite_win.stacks[item_id] = int(floor(float(base.rewards.win.stacks[item_id]) * 1.5))
	base.rewards.win = elite_win
	base.rewards.first_clear = {"gold":0,"stacks":{}}
	return base

static func reward_definition(stage_id: String, difficulty: String, was_first_clear: bool) -> Dictionary:
	var target := int(ELITE_TARGET_LEVELS.get(stage_id, 1) if difficulty == "elite" else TARGET_LEVELS.get(stage_id, 1))
	var q := floori(float(100 + 20 * target) / 3.0)
	if str(stage(stage_id, difficulty).get("kind", "normal")) == "boss": q = floori(float(q) * 1.25)
	var first_total := q
	if difficulty == "normal" and not was_first_clear:
		var settlement_level := int(FIRST_CLEAR_LEVELS.get(stage_id, 1))
		first_total = max(q, ProgressionData.exp_for_level(settlement_level) - ProgressionData.exp_for_level(target))
	if difficulty == "elite" and not was_first_clear: first_total += q
	return {"progression_version":ProgressionData.PROGRESSION_VERSION,"target_level":target,"base_exp":q,"first_clear_exp":first_total if not was_first_clear else 0,"is_first_clear":not was_first_clear}

static func enemy_snapshot(stage_id: String, difficulty: String = "normal") -> Dictionary:
	var definition := stage(stage_id, difficulty)
	if definition.is_empty(): return {}
	var config: Dictionary = definition.stage_config
	var target := int(config.get("target_level", 1))
	var multiplier := ProgressionData.scale(target)
	var legacy := normalized_enemy(stage_id, config.get("enemy", {}))
	for key in MODERN_ENEMY_OVERRIDES.get(stage_id, {}): legacy[key] = MODERN_ENEMY_OVERRIDES[stage_id][key]
	var armored: bool = difficulty == "elite" and "armored" in config.get("modifiers", [])
	var reduction := 0.04 + (0.04 if armored else 0.0)
	var max_hp := float(legacy.get("max_hp", 1000)) * multiplier
	var weapon := str(legacy.get("weapon", "volt"))
	var enhancement := int(legacy.get("level", 0))
	var base_attack := GameData.attack(weapon, enhancement) * multiplier * float(legacy.get("attack_multiplier", 1.0))
	return {"name":str(legacy.get("name", "敌人")),"weapon":weapon,"charm":str(legacy.get("charm", "moss")),"level":enhancement,"max_hp":max_hp,"base_attack":base_attack,"direct_hit_bonus":0.0,"damage_reduction":reduction,"ai_spread":float(legacy.get("ai_spread", 7.0)),"growth_level":target,"power":ProgressionData.power(base_attack, 0.0, max_hp, reduction),"progression_version":ProgressionData.PROGRESSION_VERSION}

static func normalized_enemy(stage_id: String, raw: Variant) -> Dictionary:
	if raw is Dictionary: return raw.duplicate(true)
	var defaults := {"forest_treebridge":{"name":"树桥巡林射手","max_hp":700.0,"level":0,"ai_spread":7.0,"weapon":"volt","charm":"moss"},"forest_spore_corridor":{"name":"孢子巡林者","max_hp":850.0,"level":0,"ai_spread":5.0,"weapon":"volt","charm":"moss"},"forest_moss_guardian":{"name":"苔甲守卫","max_hp":1200.0,"level":1,"ai_spread":10.0,"weapon":"volt","charm":"moss"}}
	return defaults.get(stage_id, {"name":"敌人","max_hp":1000.0,"ai_spread":7.0,"weapon":"volt","charm":"moss"}).duplicate(true)
