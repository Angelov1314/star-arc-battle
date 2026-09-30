class_name ProgressionData
extends RefCounted

const PROGRESSION_VERSION := 1
const MAX_LEVEL := 60
const MAX_EXP := 41300
const MAX_POWER := 1000000
const REFERENCE_FACTOR := sqrt((278.0 / 192.0) * 1.06 / 0.96)

static func exp_for_level(level: int) -> int:
	var l := clampi(level, 1, MAX_LEVEL)
	return 100 * (l - 1) + 10 * l * (l - 1)

static func level_for_exp(exp: int) -> int:
	var capped := clampi(exp, 0, MAX_EXP)
	for level in range(MAX_LEVEL, 0, -1):
		if capped >= exp_for_level(level): return level
	return 1

static func scale(level: int) -> float:
	var l := clampi(level, 1, MAX_LEVEL)
	return pow(1000.0 / REFERENCE_FACTOR, float(l - 1) / 59.0)

static func power(base_attack: float, direct_hit_bonus: float, max_hp: float, damage_reduction: float) -> int:
	var effective_hp := maxf(1.0, max_hp / maxf(0.0001, 1.0 - clampf(damage_reduction, 0.0, 0.99)))
	return roundi(1000.0 * sqrt(maxf(0.0, (base_attack + direct_hit_bonus) / 192.0 * effective_hp / 1000.0)))

static func player_snapshot(weapon: String, charm: String, enhancement: int, gem_id: Variant, growth_level: int) -> Dictionary:
	var weapon_id := weapon if GameData.WEAPONS.has(weapon) else "ember"
	var charm_id := charm if GameData.CHARMS.has(charm) else "feather"
	var upgrade := clampi(enhancement, 0, 8)
	var level := clampi(growth_level, 1, MAX_LEVEL)
	var multiplier := scale(level)
	var echo: bool = gem_id == "echo_gem"
	var pierce: bool = gem_id == "pierce_gem"
	var base_attack := (float(GameData.WEAPONS[weapon_id].damage) + 8.0 * upgrade) * multiplier
	var direct_hit_bonus := 16.0 * multiplier if pierce else 0.0
	var max_hp := (1060.0 if echo else 1000.0) * multiplier
	var reduction := 0.04 if charm_id == "moss" else 0.0
	return {"weapon":weapon_id,"charm":charm_id,"level":upgrade,"growth_level":level,"base_attack":base_attack,"direct_hit_bonus":direct_hit_bonus,"max_hp":max_hp,"damage_reduction":reduction,"power":power(base_attack, direct_hit_bonus, max_hp, reduction),"progression_version":PROGRESSION_VERSION,"gem_item_id":gem_id}
