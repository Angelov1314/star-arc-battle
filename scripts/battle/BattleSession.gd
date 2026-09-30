class_name BattleSession
extends RefCounted

signal changed
signal feedback(kind: String, pos: Vector2, value: float)
signal finished(result: Dictionary)

enum Phase { AIM, FLIGHT, SETTLE, COMPLETE }
var phase := Phase.AIM
var fighters: Array = []
var heights := PackedFloat32Array()
var shots: Array = []
var turn := 0
var round_number := 1
var wind := 0.0
var angle := 48.0
var power := 65.0
var selected_mode := "normal"
var item := "none"
var rage := false
var charging := false
var charge_direction := 1.0
var time_left := 25.0
var settle_time := 0.0
var ai_delay := 0.0
var mode := "ai"
var paused := false
var notice := "选择角度，按住空格蓄力，松开发射"
var rng := RandomNumberGenerator.new()
var id := ""
var last_shot := [{"angle": 0.0, "power": 0.0}, {"angle": 0.0, "power": 0.0}]
var stats := [{"hits": 0, "damage": 0.0, "shots": 0}, {"hits": 0, "damage": 0.0, "shots": 0}]
var ai_work: Array = []
var ai_best := {"score": INF, "angle": 45.0, "power": 75.0}
var ai_started := false
var elapsed := 0.0
var stage_id := ""
var stage: Dictionary = {}
var stage_config: Dictionary = {}
var mechanism := ""
var pending_hazard: Dictionary = {}
var enemy_end_count := 0
var boss_state := ""
var boss_locked_facing := 0
var supplies: Dictionary = {}
var supply_commit: Callable
var supply_used_this_action := false
var campaign_battle := false
var furnace_heat := 0
var armor_breaker_armed := false
var armor_breaker_pending := false
var armor_breaker_hits := 0
var armor_breaker_target := -1
var armor_breaker_pending_owner := -1
var player_actions := 0
var medkits_used := 0
var supply_uses: Dictionary = {}
var furnace_strike_turn := false
var player_action_counted := false
var storm_strike_turn := false
var wind_forecast: Array[float] = []
var elite_modifiers: Array[String] = []
var direct_hit_bonus := 0.0
var storm_phase_two := false
var altar_side := 0
var power_campaign := false
var stage_snapshot: Dictionary = {}

func _init(config: Dictionary = {}) -> void:
	mode = config.get("mode", "ai")
	stage_id = str(config.get("stage_id", ""))
	stage = config.get("stage", {})
	stage_config = config.get("stage_config", stage.get("stage_config", {}))
	var snapshot: Dictionary = config.get("combat_snapshot", {})
	stage_snapshot = config.get("stage_snapshot", {})
	# A stage id alone was also used by the 0.4 test/local fixtures.  Permanent
	# combat rules are gated by the frozen v1 snapshot so those modes keep their
	# established fixed-armour numbers.
	campaign_battle = not stage_id.is_empty()
	power_campaign = campaign_battle and int(snapshot.get("progression_version", 0)) == 1 and snapshot.has("base_attack") and snapshot.has("damage_reduction")
	supplies = config.get("supplies", {}).duplicate(true)
	supply_commit = config.get("supply_commit", Callable())
	mechanism = str(stage_config.get("mechanism", stage.get("mechanism", "")))
	if mechanism.is_empty() and str(stage_config.get("hazard", "")) == "spores": mechanism = "spore"
	if mechanism.is_empty() and str(stage_config.get("boss_state", "")) == "guarded_tired": mechanism = "moss_guardian"
	rng.seed = int(config.get("seed", Time.get_ticks_usec()))
	var raw_modifiers: Variant = config.get("modifiers", stage_config.get("modifiers", stage.get("modifiers", [])))
	if raw_modifiers is Array:
		for modifier in raw_modifiers:
			elite_modifiers.append(str(modifier))
	id = str(Time.get_unix_time_from_system()) + "-" + str(rng.randi())
	var terrain_kind: String = str(stage_config.get("terrain", stage_config.get("map", "")))
	terrain_kind = {"forest_treebridge":"tree_bridge", "forest_spore_corridor":"spore_corridor", "forest_moss_guardian":"moss_guardian"}.get(terrain_kind, terrain_kind)
	if terrain_kind.is_empty(): terrain_kind = {"forest_treebridge":"tree_bridge", "forest_spore_corridor":"spore_corridor", "forest_moss_guardian":"moss_guardian"}.get(stage_id, "")
	heights = Ballistics.terrain_variant(terrain_kind) if not terrain_kind.is_empty() else Ballistics.terrain()
	var weapon: String = str(snapshot.get("weapon", config.get("weapon", "ember")))
	var charm: String = str(snapshot.get("charm", config.get("charm", "feather")))
	var level: int = int(snapshot.get("level", config.get("level", 0)))
	var player_max_hp: float = float(snapshot.get("max_hp", config.get("max_hp", 1000.0)))
	direct_hit_bonus = float(snapshot.get("direct_hit_bonus", config.get("direct_hit_bonus", 0.0)))
	var raw_enemy: Variant = config.get("enemy_snapshot", stage_snapshot.get("enemy_snapshot", stage_config.get("enemy", {})))
	var enemy: Dictionary = raw_enemy if raw_enemy is Dictionary else {}
	var enemy_hp: float = float(enemy.get("max_hp", stage_config.get("enemy_hp", {"forest_treebridge":700.0, "forest_spore_corridor":850.0, "forest_moss_guardian":1200.0}.get(stage_id, 1000.0))))
	var enemy_name: String = str(enemy.get("name", "苔甲守卫" if stage_id == "forest_moss_guardian" else "孢子巡林者" if stage_id == "forest_spore_corridor" else "树桥巡林射手" if stage_id == "forest_treebridge" else ("绯羽射手" if mode == "ai" else ("练习伙伴" if mode == "training" else "红队旅人"))))
	fighters = [make_fighter("风铃旅人", float(stage_config.get("player_x", 230.0)), weapon, charm, level, 1, player_max_hp), make_fighter(enemy_name, float(enemy.get("x", stage_config.get("enemy_x", 1040.0))), str(enemy.get("weapon", "volt")), str(enemy.get("charm", "moss")), int(enemy.get("growth_level", enemy.get("level", 1 if stage_id == "forest_moss_guardian" else level))), -1, enemy_hp)]
	if power_campaign:
		_apply_power_snapshot(fighters[0], snapshot)
		_apply_power_snapshot(fighters[1], enemy)
	if elite_modifiers.has("armored"):
		if power_campaign:
			# v1 enemy snapshots freeze final DR, including the elite affix.
			pass
		else:
			fighters[1].armor = float(fighters[1].armor) + 8.0
	# Campaign opponents deliberately use broader aim error than the player-facing
	# preview/shot system. Existing arena, training, and local matches retain 1°.
	fighters[1].ai_spread = float(enemy.get("ai_spread", {"forest_treebridge":7.0, "forest_spore_corridor":5.0, "forest_moss_guardian":10.0}.get(stage_id, 1.0)))
	if mechanism.is_empty() and stage_id == "forest_spore_corridor": mechanism = "spore"
	if mechanism.is_empty() and stage_id == "forest_moss_guardian": mechanism = "moss_guardian"
	if mechanism.is_empty() and stage_id == "mine_furnace": mechanism = "furnace"
	if mechanism == "moss_guardian": boss_state = "defense"
	if mechanism == "storm_lord": boss_state = "wind_shield"
	# Forecasts are generated once per action and then consumed in order.  This
	# keeps the HUD, trace and live projectile on the same final (elite-adjusted)
	# wind value; pause never rolls or advances it.
	wind_forecast = [_roll_wind(), _roll_wind()]
	start_turn()

func _roll_wind() -> float:
	var result := rng.randf_range(-3.0, 3.0)
	if stage_id == "forest_treebridge": result = rng.randf_range(-1.4, 1.4)
	if elite_modifiers.has("strong_wind"): result *= 1.3
	return snappedf(result, 0.1)

func forecast_wind() -> float:
	return float(wind_forecast[0]) if not wind_forecast.is_empty() else wind

func make_fighter(name: String, x: float, weapon: String, charm: String, level: int, facing: int, max_hp: float = 1000.0) -> Dictionary:
	return {"name": name, "pos": Vector2(x, Ballistics.height_at(heights, x) - Ballistics.RADIUS), "hp": max_hp, "max_hp": max_hp, "stamina": 100.0 + float(GameData.CHARMS[charm].stamina), "max_stamina": 100.0 + float(GameData.CHARMS[charm].stamina), "armor": float(GameData.CHARMS[charm].armor), "damage_reduction": 0.0, "base_attack": GameData.attack(weapon, level), "direct_hit_bonus": 0.0, "power": 0, "rage": 0.0, "weapon": weapon, "level": level, "facing": facing, "charges": {"amp": 3, "rapid": 3, "tracker": 2, "heal": 2}, "fall_speed": 0.0, "ai_spread":1.0}

func _apply_power_snapshot(fighter: Dictionary, snapshot: Dictionary) -> void:
	fighter.max_hp = float(snapshot.get("max_hp", fighter.max_hp))
	fighter.hp = fighter.max_hp
	fighter.base_attack = float(snapshot.get("base_attack", fighter.base_attack))
	fighter.direct_hit_bonus = float(snapshot.get("direct_hit_bonus", 0.0))
	fighter.damage_reduction = clampf(float(snapshot.get("damage_reduction", 0.0)), 0.0, 0.99)
	fighter.power = int(snapshot.get("power", 0))
	fighter.level = int(snapshot.get("growth_level", snapshot.get("level", fighter.level)))
	# The old eight-point armour is represented by damage_reduction in v1; it
	# must never be applied again as a flat subtraction.
	fighter.armor = 0.0

func human_turn() -> bool:
	return phase == Phase.AIM and not paused and (turn == 0 or mode == "local")

func start_turn() -> void:
	phase = Phase.AIM
	if wind_forecast.is_empty(): wind_forecast.append(_roll_wind())
	wind = wind_forecast.pop_front()
	wind_forecast.append(_roll_wind())
	time_left = 25.0
	charging = false
	selected_mode = "normal"
	item = "none"
	rage = false
	supply_used_this_action = false
	player_action_counted = false
	if turn == 1:
		furnace_strike_turn = false
		storm_strike_turn = false
		apply_enemy_start_events()
		if phase == Phase.COMPLETE: return
	fighters[turn].stamina = fighters[turn].max_stamina
	fighters[turn].facing = 1 if fighters[turn].pos.x < fighters[1-turn].pos.x else -1
	if mechanism == "moss_guardian" and turn == 0:
		boss_locked_facing = -1 if fighters[0].pos.x < fighters[1].pos.x else 1
		fighters[1].facing = boss_locked_facing
	power = float(last_shot[turn].power) if float(last_shot[turn].power) > 0.0 else 65.0
	angle = float(last_shot[turn].angle) if float(last_shot[turn].angle) > 0.0 else 48.0
	ai_delay = 0.85
	ai_started = false
	ai_work.clear()
	notice = "%s 的回合" % fighters[turn].name
	feedback.emit("turn", fighters[turn].pos, 0.0)
	changed.emit()

func tick(dt: float = Ballistics.DT) -> void:
	if paused or phase == Phase.COMPLETE:
		return
	elapsed += dt
	if phase == Phase.AIM:
		time_left -= dt
		if charging:
			power += charge_direction * 70.0 * dt
			if power >= 100.0:
				power = 100.0
				charge_direction = -1.0
			elif power <= 0.0:
				power = 0.0
				charge_direction = 1.0
		if time_left <= 0.0:
			if charging: feedback.emit("charge_cancel", origin(), 0.0)
			charging = false
			phase = Phase.SETTLE
			settle_time = 0.6
			notice = "回合时间到"
			changed.emit()
		elif turn == 1 and mode != "local":
			ai_delay -= dt
			if ai_delay <= 0.0:
				if mode == "training" or furnace_strike_turn or storm_strike_turn:
					phase = Phase.SETTLE
					settle_time = 0.4
				else:
					advance_ai()
	elif phase == Phase.FLIGHT:
		var remaining: Array = []
		for shot in shots:
			shot.age += dt
			var next := Ballistics.step(shot.pos, shot.vel, wind, fighters[1-shot.owner].pos if shot.tracker else null)
			var hit := Ballistics.collision(shot.pos, next.pos, heights, fighters, shot.owner, shot.age)
			shot.pos = next.pos
			shot.vel = next.vel
			shot.trail.append(shot.pos)
			if shot.trail.size() > 32:
				shot.trail.pop_front()
			if hit.is_empty():
				remaining.append(shot)
			elif hit.kind != "out":
				explode(shot, hit)
		shots = remaining
		settle_fighters(dt)
		if shots.is_empty():
			# A vial is consumed by the player's next fired batch.  If every
			# projectile leaves the field without hitting an opponent there is no
			# target to debuff, so discard the batch-local pending trigger here.
			# Do not clear armor_breaker_hits: that is an already-applied debuff.
			if armor_breaker_pending:
				armor_breaker_pending = false
				armor_breaker_pending_owner = -1
			phase = Phase.SETTLE
			settle_time = 0.85
			changed.emit()
	elif phase == Phase.SETTLE:
		settle_time -= dt
		var landed := settle_fighters(dt)
		if settle_time <= 0.0 and landed:
			if turn == 0 and not player_action_counted:
				player_actions += 1
				player_action_counted = true
			if fighters[0].hp <= 0.0 or fighters[1].hp <= 0.0:
				var winner := -1 if fighters[0].hp <= 0.0 and fighters[1].hp <= 0.0 else (0 if fighters[1].hp <= 0.0 else 1)
				finish(winner)
			elif round_number >= 30:
				var player_ratio: float = fighters[0].hp / fighters[0].max_hp
				var enemy_ratio: float = fighters[1].hp / fighters[1].max_hp
				finish(-1 if is_equal_approx(player_ratio, enemy_ratio) else (0 if player_ratio > enemy_ratio else 1))
			else:
				if turn == 1: apply_enemy_end_events()
				turn = 1-turn
				round_number += 1
				start_turn()

func settle_fighters(dt: float) -> bool:
	var landed := true
	for fighter in fighters:
		var target := Ballistics.height_at(heights, fighter.pos.x) - Ballistics.RADIUS
		if fighter.pos.y < target - 0.05:
			fighter.fall_speed += 650.0 * dt
			fighter.pos.y = minf(target, fighter.pos.y + fighter.fall_speed * dt)
			landed = false
		else:
			fighter.pos.y = target
			fighter.fall_speed = 0.0
	return landed

func move(direction: float, dt: float) -> void:
	if not human_turn() or charging:
		return
	var actor: Dictionary = fighters[turn]
	var old_x: float = actor.pos.x
	var new_x := clampf(old_x + direction * 115.0 * dt, 65.0, 1215.0)
	if absf(new_x - fighters[1-turn].pos.x) < 58.0:
		return
	var cost := absf(new_x-old_x) * 0.22
	if cost <= float(actor.stamina):
		actor.pos = Vector2(new_x, Ballistics.height_at(heights, new_x)-Ballistics.RADIUS)
		actor.stamina -= cost
		actor.facing = int(signf(direction))
		changed.emit()

func origin() -> Vector2:
	return fighters[turn].pos + Vector2(fighters[turn].facing * 32.0, -14.0)

func trace() -> Dictionary:
	return Ballistics.trace(origin(), Ballistics.velocity(angle, power, fighters[turn].facing, fighters[turn].weapon, selected_mode), wind, heights, fighters, turn, item == "tracker")

func select_mode(value: String) -> void:
	if human_turn() and GameData.MODES.has(value):
		selected_mode = value
		changed.emit()

func select_item(value: String) -> void:
	if human_turn() and GameData.ITEMS.has(value):
		item = value
		changed.emit()

func heal() -> bool:
	var actor: Dictionary = fighters[turn]
	if campaign_battle:
		return use_supply("small_medkit")
	if phase != Phase.AIM or paused or actor.hp >= actor.max_hp or actor.stamina < 30.0 or int(actor.charges.heal) <= 0:
		return false
	var recovered: float = float(actor.max_hp) * 0.25 if power_campaign else 250.0
	actor.hp = minf(actor.max_hp, actor.hp + recovered)
	actor.stamina -= 30.0
	actor.charges.heal -= 1
	feedback.emit("heal", actor.pos, recovered)
	changed.emit()
	return true

func use_supply(item_id: String) -> bool:
	if not campaign_battle or phase != Phase.AIM or paused or turn != 0 or supply_used_this_action:
		return false
	var actor: Dictionary = fighters[0]
	var effect: float = (actor.max_hp * 0.25 if power_campaign else 250.0) if item_id == "small_medkit" else 25.0 if item_id == "stamina_tonic" else 0.0
	if item_id == "armor_breaker": effect = 1.0
	var current: float = float(actor.hp) if item_id == "small_medkit" else float(actor.stamina)
	var maximum: float = float(actor.max_hp) if item_id == "small_medkit" else float(actor.max_stamina)
	if item_id == "armor_breaker" and armor_breaker_armed: return false
	if effect <= 0.0 or (item_id != "armor_breaker" and current >= maximum) or int(supplies.get(item_id, 0)) <= 0 or not supply_commit.is_valid():
		return false
	var outcome = supply_commit.call(item_id)
	if not outcome is Dictionary or not bool(outcome.get("ok", false)):
		notice = str(outcome.get("message", "补给保存失败，效果未生效")) if outcome is Dictionary else "补给保存失败，效果未生效"
		changed.emit()
		return false
	supplies[item_id] = int(outcome.get("remaining", int(supplies[item_id]) - 1))
	supply_uses[item_id] = int(supply_uses.get(item_id, 0)) + 1
	if item_id == "armor_breaker":
		armor_breaker_armed = true
		notice = "破甲药剂已装填：下一次命中施加两次破甲"
	elif item_id == "small_medkit":
		actor.hp = minf(actor.max_hp, actor.hp + effect)
		medkits_used += 1
		feedback.emit("heal", actor.pos, effect)
	else:
		actor.stamina = minf(actor.max_stamina, actor.stamina + effect)
		feedback.emit("stamina", actor.pos, effect)
	supply_used_this_action = true
	notice = "补给已保存并生效"
	changed.emit()
	return true

func start_charge() -> void:
	if not human_turn():
		return
	charging = true
	charge_direction = 1.0
	power = 0.0
	feedback.emit("charge", origin(), 0.0)

func release_charge() -> void:
	if charging and human_turn():
		charging = false
		fire()

func fire() -> bool:
	if phase != Phase.AIM or paused:
		return false
	var actor: Dictionary = fighters[turn]
	var cost: float = GameData.MODES[selected_mode].cost + GameData.ITEMS[item].cost
	if actor.stamina < cost or (item != "none" and int(actor.charges[item]) <= 0) or (rage and actor.rage < 100.0):
		notice = "资源不足，请调整弹种或道具"
		changed.emit()
		return false
	charging = false
	actor.stamina -= cost
	if item != "none":
		actor.charges[item] -= 1
	if rage:
		actor.rage = 0.0
	last_shot[turn] = {"angle": angle, "power": power}
	# The vial belongs to the campaign player. Enemy turns and player timeouts
	# cannot steal its next-shot payload; it persists until the player fires.
	armor_breaker_pending = armor_breaker_armed if turn == 0 else false
	armor_breaker_pending_owner = 0 if armor_breaker_armed and turn == 0 else -1
	if turn == 0: armor_breaker_armed = false
	stats[turn].shots += int(GameData.ITEMS[item].count)
	for i in range(int(GameData.ITEMS[item].count)):
		var spread := (-1.8 if i == 0 else 1.8) if item == "rapid" else 0.0
		var multiplier := float(GameData.MODES[selected_mode].damage) * float(GameData.ITEMS[item].damage) * (1.8 if rage else 1.0)
		var direct_bonus := float(actor.direct_hit_bonus) * multiplier if power_campaign else direct_hit_bonus * multiplier if turn == 0 else 0.0
		var base_damage := float(actor.base_attack) * multiplier if power_campaign else GameData.damage(actor.weapon, actor.level, selected_mode, item, rage, 0.0)
		shots.append({"pos": origin(), "vel": Ballistics.velocity(angle+spread, power, actor.facing, actor.weapon, selected_mode), "owner": turn, "tracker": item == "tracker", "age": 0.0, "trail": [], "damage": base_damage, "direct_bonus": direct_bonus, "radius": float(GameData.WEAPONS[actor.weapon].radius)})
	phase = Phase.FLIGHT
	notice = "观察落点，下一回合修正角度与力度"
	feedback.emit("fire", origin(), 1.0 if selected_mode == "heavy" or rage else 0.0)
	changed.emit()
	return true

func explode(shot: Dictionary, hit: Dictionary) -> void:
	feedback.emit("explosion", hit.pos, shot.radius)
	for i in range(fighters.size()):
		var target: Dictionary = fighters[i]
		if target.hp <= 0.0:
			continue
		var distance := maxf(0.0, hit.pos.distance_to(target.pos) - Ballistics.RADIUS)
		if distance > float(shot.radius) and int(hit.target) != i:
			continue
		var factor := 1.0 if int(hit.target) == i else lerpf(1.0, 0.2, distance / float(shot.radius))
		var effective_armor: float = float(target.armor) * (0.5 if armor_breaker_hits > 0 and i == armor_breaker_target else 1.0)
		var direct_bonus: float = float(shot.get("direct_bonus", 0.0)) if int(hit.target) == i else 0.0
		var raw_damage: float = float(shot.damage) * factor + direct_bonus
		var reduction := float(target.get("damage_reduction", 0.0))
		if armor_breaker_hits > 0 and i == armor_breaker_target: reduction *= 0.5
		var damage := maxf(1.0, raw_damage * (1.0 - reduction)) if power_campaign else maxf(1.0, raw_damage - effective_armor)
		var phase_multiplier := 1.0
		# Only a projectile-body collision is a direct hit. Ground splash is
		# deliberately never reduced by the guardian's frontal armour.
		if i == 1 and mechanism == "moss_guardian" and boss_state == "defense" and int(hit.target) == 1:
			if signf(hit.pos.x - target.pos.x) == float(boss_locked_facing):
				phase_multiplier = 0.5
				feedback.emit("guard", target.pos, damage)
		if i == 1 and mechanism == "storm_lord" and boss_state == "wind_shield":
			phase_multiplier = 0.65
			feedback.emit("guard", target.pos, damage)
		if power_campaign:
			damage = maxf(1.0, raw_damage * (1.0 - reduction) * phase_multiplier)
		else:
			damage *= phase_multiplier
		damage = minf(float(target.hp), damage)
		if i != int(shot.owner) and armor_breaker_pending and int(shot.owner) == armor_breaker_pending_owner and damage > 0.0:
			armor_breaker_pending = false
			armor_breaker_pending_owner = -1
			armor_breaker_target = i
			armor_breaker_hits = 2
			feedback.emit("armor_break", target.pos, 2.0)
		elif i == armor_breaker_target and armor_breaker_hits > 0 and damage > 0.0:
			armor_breaker_hits -= 1
			if armor_breaker_hits == 0: armor_breaker_target = -1
		target.hp = maxf(0.0, target.hp - damage)
		var target_rage_gain := (damage / maxf(1.0, float(target.max_hp))) * 90.0 if power_campaign else damage * 0.09
		target.rage = minf(100.0, target.rage + target_rage_gain)
		if i != int(shot.owner):
			var owner_rage_gain := (damage / maxf(1.0, float(target.max_hp))) * 75.0 if power_campaign else damage * 0.075
			fighters[shot.owner].rage = minf(100.0, fighters[shot.owner].rage + owner_rage_gain)
			stats[shot.owner].hits += 1
			stats[shot.owner].damage += damage
		feedback.emit("damage", target.pos, damage)
	if mechanism == "storm_lord" and not storm_phase_two and fighters[1].hp > 0.0 and fighters[1].hp <= fighters[1].max_hp * 0.5:
		storm_phase_two = true
		boss_state = "phase_two"
		notice = "风暴领主进入第二阶段：下一次区域攻击仍会先预警"
		feedback.emit("phase", fighters[1].pos, 2.0)
	var carve_radius: float = float(shot.radius) * (1.15 if elite_modifiers.has("thin_soil") else 1.0)
	heights = Ballistics.carve(heights, hit.pos, carve_radius, 48.0 if mechanism == "thin_ground" else 30.0)
	changed.emit()

func finish(winner: int) -> void:
	if phase == Phase.COMPLETE:
		return
	phase = Phase.COMPLETE
	charging = false
	shots.clear()
	armor_breaker_armed = false
	armor_breaker_pending = false
	armor_breaker_pending_owner = -1
	armor_breaker_hits = 0
	armor_breaker_target = -1
	finished.emit({"id": id, "winner": winner, "mode": mode, "rounds": round_number, "stats": stats.duplicate(true), "seconds": elapsed, "stage_id": stage_id, "player_actions":player_actions, "medkits_used":medkits_used, "supply_uses":supply_uses.duplicate(true)})

func apply_enemy_end_events() -> void:
	enemy_end_count += 1
	if mechanism == "spore" and enemy_end_count % 2 == 0:
		var centre := clampf(fighters[0].pos.x + rng.randf_range(-80.0, 80.0), 120.0, 1160.0)
		pending_hazard = {"kind":"spore", "x":centre, "radius":float(stage_config.get("spore_radius", 92.0)), "damage":_hazard_damage("spore", 60.0)}
		notice = "孢子区已标记：下次敌方行动开始结算，先移动躲避"
		feedback.emit("warning", Vector2(centre, Ballistics.height_at(heights, centre) - 26.0), 0.0)
	if mechanism == "moss_guardian":
		boss_state = "fatigue" if boss_state == "defense" else "defense"
		notice = "苔甲守卫：%s" % ("疲惫，正面直击不减伤" if boss_state == "fatigue" else "防御，锁定正面直击减伤")
	if mechanism == "furnace":
		furnace_heat += 50
		if furnace_heat >= 100:
			pending_hazard = {"kind":"furnace", "x":fighters[0].pos.x, "radius":110.0, "damage":_hazard_damage("furnace", 90.0)}
			notice = "熔炉轰击预警：下次敌方行动开始结算，先移动躲避"
			feedback.emit("warning", Vector2(fighters[0].pos.x, Ballistics.height_at(heights, fighters[0].pos.x) - 26.0), 0.0)
	if mechanism == "sky_altar":
		# The first mark overlaps the default player perch, so it is visible and
		# meaningful immediately; each side remains a bounded, escapable region.
		var altar_x := 300.0 if altar_side == 0 else 900.0
		altar_side = 1 - altar_side
		pending_hazard = {"kind":"altar", "x":altar_x, "radius":118.0, "damage":_hazard_damage("altar", 80.0)}
		notice = "符文区域已标记：下次敌方行动开始结算，完整行动内可移动躲避"
		feedback.emit("warning", Vector2(altar_x, Ballistics.height_at(heights, altar_x) - 26.0), 0.0)
	if mechanism == "storm_lord":
		if not storm_phase_two:
			boss_state = "exposed" if boss_state == "wind_shield" else "wind_shield"
		var cadence := 1 if storm_phase_two else 2
		if enemy_end_count % cadence == 0:
			# Lock the player position at telegraph time.  The caster never receives
			# its own area damage and the warning always permits a full response turn.
			var storm_x := clampf(fighters[0].pos.x, 150.0, 1130.0)
			pending_hazard = {"kind":"storm", "x":storm_x, "radius":130.0, "damage":_hazard_damage("storm", 100.0), "player_only":true}
			notice = "风暴区域预警：下次敌方行动开始结算，先移动躲避"
			feedback.emit("warning", Vector2(storm_x, Ballistics.height_at(heights, storm_x) - 26.0), 0.0)
	changed.emit()

func _hazard_damage(kind: String, fallback: float) -> float:
	if not power_campaign: return fallback
	var hazards: Dictionary = stage_snapshot.get("hazards", stage_config.get("hazards", {}))
	if hazards.has(kind): return float(hazards[kind])
	var explicit: Variant = stage_snapshot.get("%s_damage" % kind, stage_config.get("%s_damage" % kind, null))
	if explicit != null: return float(explicit)
	return fallback * float(stage_snapshot.get("hazard_scale", stage_config.get("hazard_scale", 1.0)))

func apply_enemy_start_events() -> void:
	if pending_hazard.is_empty(): return
	var hazard := pending_hazard
	pending_hazard = {}
	if str(hazard.get("kind", "")) == "furnace":
		furnace_heat = 0
		furnace_strike_turn = true
	if str(hazard.get("kind", "")) == "storm":
		storm_strike_turn = true
	var any_dead := false
	for i in range(fighters.size()):
		if bool(hazard.get("player_only", false)) and i != 0:
			continue
		var target: Dictionary = fighters[i]
		if absf(float(target.pos.x) - float(hazard.x)) <= float(hazard.radius):
			var damage := minf(float(target.hp), float(hazard.damage))
			target.hp = maxf(0.0, float(target.hp) - damage)
			feedback.emit("hazard", Vector2(float(hazard.x), Ballistics.height_at(heights, float(hazard.x)) - 26.0), damage)
			any_dead = any_dead or target.hp <= 0.0
	if any_dead:
		var winner := -1 if fighters[0].hp <= 0.0 and fighters[1].hp <= 0.0 else 0 if fighters[1].hp <= 0.0 else 1
		finish(winner)
		return
	changed.emit()

func prepare_ai() -> void:
	ai_started = true
	var hp_ratio := float(fighters[turn].hp) / maxf(1.0, float(fighters[turn].max_hp))
	var should_heal := hp_ratio < 0.58 if power_campaign else float(fighters[turn].hp) < 580.0
	if should_heal:
		heal()
	selected_mode = "heavy" if fighters[turn].stamina >= 55.0 and ((hp_ratio < 0.65) if power_campaign else fighters[turn].hp < 650.0) else "normal"
	item = "amp" if int(fighters[turn].charges.amp) > 0 and fighters[turn].stamina >= 55.0 and ((hp_ratio < 0.45) if power_campaign else fighters[turn].hp < 450.0) else "none"
	rage = fighters[turn].rage >= 100.0
	fighters[turn].facing = 1 if fighters[turn].pos.x < fighters[1-turn].pos.x else -1
	ai_best = {"score": INF, "angle": 45.0, "power": 75.0}
	for candidate_angle in range(25, 81, 5):
		for candidate_power in range(42, 101, 4):
			ai_work.append(Vector2(candidate_angle, candidate_power))
	notice = "绯羽正在判断风向与落点…"

func advance_ai() -> void:
	if not ai_started:
		prepare_ai()
	# Limit work each physics frame so the UI remains responsive.
	for i in range(mini(5, ai_work.size())):
		var candidate: Vector2 = ai_work.pop_back()
		var result := Ballistics.trace(origin(), Ballistics.velocity(candidate.x, candidate.y, fighters[turn].facing, fighters[turn].weapon, selected_mode), wind, heights, fighters, turn)
		var score: float = result.hit.pos.distance_to(fighters[1-turn].pos)
		if int(result.hit.target) == 1-turn:
			score -= 35.0
		if result.hit.pos.distance_to(fighters[turn].pos) < 100.0:
			score += 500.0
		if score < float(ai_best.score):
			ai_best = {"score": score, "angle": candidate.x, "power": candidate.y}
	if ai_work.is_empty():
		var spread: float = float(fighters[turn].get("ai_spread", 1.0))
		angle = clampf(float(ai_best.angle) + rng.randf_range(-spread, spread), 10.0, 85.0)
		power = clampf(float(ai_best.power) + rng.randf_range(-spread * 1.2, spread * 1.2), 0.0, 100.0)
		fire()
