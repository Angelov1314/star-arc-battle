class_name GameData
extends RefCounted

const WEAPONS = {
	"ember": {"name": "爆炎炮", "subtitle": "EMBER • 范围压制", "damage": 192.0, "radius": 68.0, "speed": 1.0, "color": Color("efac57"), "description": "更宽的爆炸范围，让接近目标的落点也能造成可观伤害。"},
	"volt": {"name": "雷光弩", "subtitle": "VOLT • 精准打击", "damage": 214.0, "radius": 46.0, "speed": 1.08, "color": Color("77d9db"), "description": "更快的飞行速度与更高的直击伤害，适合精准射手。"},
	"rockcore": {"name": "岩芯炮", "subtitle": "ROCKCORE • 震荡范围", "damage": 176.0, "radius": 86.0, "speed": 0.94, "color": Color("c98a54"), "description": "直击较弱，但拥有更大的爆炸范围。"},
}
const MODES = {
	"light": {"name": "轻弹", "damage": 0.82, "speed": 0.95, "cost": 0.0},
	"normal": {"name": "标准", "damage": 1.0, "speed": 1.0, "cost": 0.0},
	"heavy": {"name": "重击", "damage": 1.35, "speed": 1.05, "cost": 25.0},
}
const ITEMS = {
	"none": {"name": "普通", "damage": 1.0, "cost": 0.0, "count": 1},
	"amp": {"name": "增幅", "damage": 1.5, "cost": 30.0, "count": 1},
	"rapid": {"name": "双发", "damage": 0.65, "cost": 30.0, "count": 2},
	"tracker": {"name": "追踪", "damage": 0.7, "cost": 25.0, "count": 1},
}
const CHARMS = {"feather": {"name": "风羽徽章", "description": "体力 +15", "stamina": 15.0, "armor": 0.0}, "moss": {"name": "森石护符", "description": "减伤 +8", "stamina": 0.0, "armor": 8.0}}

static func attack(weapon: String, level: int) -> float:
	return float(WEAPONS[weapon].damage) + level * 8.0

static func damage(weapon: String, level: int, mode: String, item: String, rage: bool, armor: float, falloff: float = 1.0, direct_hit_bonus: float = 0.0) -> float:
	var multiplier: float = MODES[mode].damage * ITEMS[item].damage * (1.8 if rage else 1.0)
	return maxf(1.0, (attack(weapon, level) + direct_hit_bonus) * multiplier * falloff - armor)

static func launch_speed(weapon: String, mode: String, power: float) -> float:
	return power * 10.4 * float(WEAPONS[weapon].speed) * float(MODES[mode].speed)
