class_name ItemData
extends RefCounted

const DEFINITIONS := {
	"ember": {"id":"ember", "category":"weapon", "name":"爆炎炮", "quality":"稀有", "quality_rank":2, "source":"新旅程初始配装", "source_ids":["starter"], "source_stage_id":"forest_treebridge"},
	"volt": {"id":"volt", "category":"weapon", "name":"雷光弩", "quality":"稀有", "quality_rank":2, "source":"新旅程初始配装", "source_ids":["starter"], "source_stage_id":"forest_treebridge"},
	"feather": {"id":"feather", "category":"charm", "name":"风羽徽章", "quality":"普通", "quality_rank":1, "source":"新旅程初始配装", "source_ids":["starter"], "source_stage_id":"forest_treebridge"},
	"moss": {"id":"moss", "category":"charm", "name":"森石护符", "quality":"普通", "quality_rank":1, "source":"新旅程初始配装", "source_ids":["starter"], "source_stage_id":"forest_treebridge"},
	"woodchip": {"id":"woodchip", "category":"material", "name":"森纹木屑", "quality":"普通", "quality_rank":1, "source":"第一章关卡奖励", "source_ids":["forest"], "source_stage_id":"forest_treebridge"},
	"enhancement_dust": {"id":"enhancement_dust", "category":"material", "name":"强化粉尘", "quality":"普通", "quality_rank":1, "source":"林间遗迹与炽铜矿坑关卡奖励", "source_ids":["forest","mine"], "source_stage_id":"forest_treebridge"},
	"small_medkit": {"id":"small_medkit", "category":"supply", "name":"小型急救包", "quality":"普通", "quality_rank":1, "source":"入门补给、林间与矿坑奖励、制作", "source_ids":["starter","forest","mine","crafting"], "source_stage_id":"forest_treebridge"},
	"stamina_tonic": {"id":"stamina_tonic", "category":"supply", "name":"体力饮剂", "quality":"普通", "quality_rank":1, "source":"入门补给、林间与矿坑奖励、制作", "source_ids":["starter","forest","mine","crafting"], "source_stage_id":"forest_spore_corridor"},
	"copper_ore": {"id":"copper_ore", "category":"material", "name":"铜矿石", "quality":"普通", "quality_rank":1, "source":"炽铜矿坑关卡奖励", "source_ids":["mine"], "source_stage_id":"mine_entrance"},
	"armor_breaker": {"id":"armor_breaker", "category":"supply", "name":"破甲药剂", "quality":"稀有", "quality_rank":2, "source":"熔炉核心奖励与制作", "source_ids":["mine","crafting"], "source_stage_id":"mine_furnace"},
	"rockcore": {"id":"rockcore", "category":"weapon", "name":"岩芯炮", "quality":"史诗", "quality_rank":3, "source":"熔炉核心首次胜利", "source_ids":["mine"], "source_stage_id":"mine_furnace"},
	"relic_shard": {"id":"relic_shard", "category":"material", "name":"遗迹晶屑", "quality":"稀有", "quality_rank":2, "source":"天空遗址关卡奖励", "source_ids":["sky"], "source_stage_id":"sky_corridor"},
	"echo_gem": {"id":"echo_gem", "category":"gem", "name":"回响晶", "quality":"史诗", "quality_rank":3, "source":"天空遗址领主、精英领主与制作", "source_ids":["sky","elite","crafting"], "source_stage_id":"sky_lord", "max_hp":60},
	"pierce_gem": {"id":"pierce_gem", "category":"gem", "name":"贯穿晶", "quality":"史诗", "quality_rank":3, "source":"天空遗址领主、精英领主与制作", "source_ids":["sky","elite","crafting"], "source_stage_id":"sky_lord", "direct_hit_bonus":8},
}

static func has(item_id: String) -> bool:
	return DEFINITIONS.has(item_id)

static func definition(item_id: String) -> Dictionary:
	return DEFINITIONS.get(item_id, {}).duplicate(true)

static func is_supply(item_id: String) -> bool:
	return DEFINITIONS.get(item_id, {}).get("category", "") == "supply"
