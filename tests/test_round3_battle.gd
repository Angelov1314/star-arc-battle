extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func make(stage_id: String, extras: Dictionary = {}) -> BattleSession:
	var stage := CampaignData.stage(stage_id, str(extras.get("difficulty", "normal")))
	var config := {"mode":"local", "seed": 4242, "stage_id":stage_id, "stage":stage, "stage_config":stage.stage_config}
	for key in extras: config[key] = extras[key]
	return BattleSession.new(config)

func settle_action(session: BattleSession) -> void:
	for _i in range(5000):
		session.tick()
		if session.phase == BattleSession.Phase.AIM or session.phase == BattleSession.Phase.COMPLETE:
			return
	check(false, "action settles")

func expire_player_into_enemy(session: BattleSession) -> void:
	session.time_left = 0.0
	session.tick(0.01)
	session.tick(0.7)

func test_stage_and_forecast() -> void:
	var corridor := make("sky_corridor")
	var altar := make("sky_altar")
	var lord := make("sky_lord")
	check(corridor.fighters[1].max_hp == 1200.0 and altar.fighters[1].max_hp == 1350.0 and lord.fighters[1].max_hp == 1800.0, "Sky Ruins enemy HP uses approved configuration")
	check(corridor.fighters[1].level == 4 and altar.fighters[1].level == 4 and lord.fighters[1].level == 5, "Sky Ruins enemy levels use approved configuration")
	check(not is_equal_approx(Ballistics.height_at(corridor.heights, 640), Ballistics.height_at(altar.heights, 640)) and not is_equal_approx(Ballistics.height_at(altar.heights, 640), Ballistics.height_at(lord.heights, 640)), "three sky stages have independent height fields")
	var visible_next := corridor.forecast_wind()
	corridor.paused = true
	corridor.tick(30.0)
	check(corridor.wind_forecast.size() == 2 and corridor.forecast_wind() == visible_next, "pause does not consume or reroll forecast wind")
	corridor.paused = false
	corridor.turn = 1
	corridor.start_turn()
	check(corridor.wind == visible_next, "next action uses exactly the wind that was forecast")
	var elite := make("sky_corridor", {"difficulty":"elite"})
	check(elite.elite_modifiers.has("strong_wind") and elite.elite_modifiers.has("thin_soil"), "elite modifiers reach BattleSession")

func test_altar_warning() -> void:
	var safe := make("sky_altar")
	safe.apply_enemy_end_events()
	var first_x := float(safe.pending_hazard.x)
	check(str(safe.pending_hazard.kind) == "altar" and float(safe.pending_hazard.damage) == 80.0, "altar marks an 80-damage rune after enemy end")
	var hp := float(safe.fighters[0].hp)
	safe.move(1.0 if first_x < 640.0 else -1.0, 2.0)
	expire_player_into_enemy(safe)
	check(safe.fighters[0].hp == hp, "altar grants a full player action to leave rune")
	var hit := make("sky_altar")
	hit.apply_enemy_end_events()
	var hit_hp := float(hit.fighters[0].hp)
	expire_player_into_enemy(hit)
	check(hit.fighters[0].hp == hit_hp - 80.0, "altar resolves exactly 80 damage when player stays")
	hit.apply_enemy_end_events()
	check(float(hit.pending_hazard.x) != first_x, "altar alternates left and right rune zones")

func test_storm_lord_and_direct_gem() -> void:
	var lord := make("sky_lord", {"combat_snapshot":{"weapon":"ember", "charm":"feather", "level":0, "max_hp":1060.0, "direct_hit_bonus":8.0}})
	check(lord.fighters[0].max_hp == 1060.0 and lord.fighters[1].max_hp == 1800.0, "combat snapshot applies player health only")
	var direct := {"owner":0, "damage":100.0, "direct_bonus":8.0, "radius":68.0}
	var direct_hit := {"target":1, "pos":lord.fighters[1].pos}
	lord.explode(direct, direct_hit)
	check(is_equal_approx(lord.fighters[1].hp, 1735.0), "wind shield reduces direct base plus gem bonus by 35%")
	var splash := make("sky_lord", {"direct_hit_bonus":8.0})
	splash.boss_state = "exposed"
	splash.explode(direct, {"target":-1, "pos":splash.fighters[1].pos})
	check(is_equal_approx(splash.fighters[1].hp, 1708.0), "pierce gem does not add to splash damage")
	lord.fighters[1].hp = 901.0
	lord.explode({"owner":0,"damage":1000.0,"direct_bonus":0.0,"radius":68.0}, direct_hit)
	check(lord.storm_phase_two and lord.boss_state == "phase_two" and lord.pending_hazard.is_empty(), "half-health phase change warns without immediate hazard")
	var phase_two := make("sky_lord")
	phase_two.storm_phase_two = true
	phase_two.boss_state = "phase_two"
	phase_two.apply_enemy_end_events()
	check(str(phase_two.pending_hazard.kind) == "storm" and float(phase_two.pending_hazard.damage) == 100.0, "phase two marks 100-damage storm every enemy end")
	var hp := float(phase_two.fighters[0].hp)
	expire_player_into_enemy(phase_two)
	check(phase_two.fighters[0].hp == hp - 100.0 and phase_two.storm_strike_turn, "storm resolves at next enemy start and replaces projectile")

func live_projectile_damage(snapshot: Dictionary, direct: bool) -> Dictionary:
	var session := make("sky_corridor", {"combat_snapshot":snapshot})
	session.fighters[0].pos = Vector2(240.0, Ballistics.height_at(session.heights, 240.0) - Ballistics.RADIUS)
	session.angle = 0.0 if direct else 43.0
	session.power = 20.0 if direct else 54.0
	if direct:
		session.fighters[1].pos = Vector2(330.0, Ballistics.height_at(session.heights, 330.0) - Ballistics.RADIUS)
	else:
		var preview := session.trace()
		# Stay outside body-collision range but inside the explosion radius.  This
		# preserves a real ground collision while allowing splash to reach the boss.
		var splash_x := clampf(preview.hit.pos.x + 46.0, 80.0, 1200.0)
		session.fighters[1].pos = Vector2(splash_x, Ballistics.height_at(session.heights, splash_x) - Ballistics.RADIUS)
	var damages: Array[float] = []
	var target_pos: Vector2 = session.fighters[1].pos
	var on_feedback := func(kind: String, pos: Vector2, value: float):
		if kind == "damage" and pos.distance_to(target_pos) < 2.0: damages.append(value)
	session.feedback.connect(on_feedback)
	var fired := session.fire()
	for _i in range(3000):
		session.tick()
		if session.phase != BattleSession.Phase.FLIGHT: break
	session.feedback.disconnect(on_feedback)
	return {"fired":fired, "damage":float(damages[0]) if not damages.is_empty() else -1.0}

func test_live_projectile_gem_contract() -> void:
	var base := {"weapon":"ember", "charm":"feather", "level":0, "max_hp":1000.0, "direct_hit_bonus":0.0}
	var gem := base.duplicate(true)
	gem.direct_hit_bonus = 8.0
	var direct_base := live_projectile_damage(base, true)
	var direct_gem := live_projectile_damage(gem, true)
	var splash_base := live_projectile_damage(base, false)
	var splash_gem := live_projectile_damage(gem, false)
	print("ROUND3_LIVE_GEM direct_base=%.2f direct_gem=%.2f splash_base=%.2f splash_gem=%.2f" % [direct_base.damage, direct_gem.damage, splash_base.damage, splash_gem.damage])
	check(bool(direct_base.fired) and bool(direct_gem.fired) and is_equal_approx(float(direct_gem.damage) - float(direct_base.damage), 8.0), "live projectile body hit receives +8 pierce bonus")
	check(bool(splash_base.fired) and bool(splash_gem.fired) and splash_base.damage > 0.0 and is_equal_approx(float(splash_gem.damage), float(splash_base.damage)), "live ground splash receives no pierce bonus")

func test_elite_modifiers() -> void:
	var armored := make("sky_lord", {"difficulty":"elite"})
	check(armored.fighters[1].armor == 16.0, "armored adds fixed +8 enemy armour once")
	var normal := make("sky_altar")
	var thin := make("sky_altar", {"difficulty":"elite"})
	var point := Vector2(640, Ballistics.height_at(normal.heights, 640))
	normal.explode({"owner":0,"damage":1.0,"radius":60.0}, {"target":-1,"pos":point})
	thin.explode({"owner":0,"damage":1.0,"radius":60.0}, {"target":-1,"pos":point})
	check(Ballistics.height_at(thin.heights, 705) > Ballistics.height_at(normal.heights, 705), "thin soil expands destruction radius once")

func simulate(stage_id: String, difficulty: String, seed: int, snapshot: Dictionary) -> Dictionary:
	var s := make(stage_id, {"seed":seed, "difficulty":difficulty, "combat_snapshot":snapshot})
	var settled: Array[Dictionary] = []
	var on_finished := func(result: Dictionary): settled.append(result.duplicate(true))
	s.finished.connect(on_finished)
	var ticks := 0
	while s.phase != BattleSession.Phase.COMPLETE and ticks < 36000:
		if s.phase == BattleSession.Phase.AIM:
			s.advance_ai()
		s.tick()
		ticks += 1
	var result: Dictionary = settled[0] if not settled.is_empty() else {}
	s.finished.disconnect(on_finished)
	return {"done":s.phase == BattleSession.Phase.COMPLETE and not result.is_empty(), "ticks":ticks, "winner":int(result.get("winner", -99)), "rounds":int(result.get("rounds", 0)), "actions":int(result.get("player_actions", 0)), "shots":int(result.get("stats", [{}, {}])[0].get("shots", 0)), "hits":int(result.get("stats", [{}, {}])[0].get("hits", 0)), "max_hp":s.fighters[0].max_hp, "weapon":s.fighters[0].weapon, "charm":s.fighters[0].get("charm", "snapshot")}

func test_thirty_simulations() -> void:
	var completed := 0
	var ticks_total := 0
	var fixtures := []
	for stage_id in ["forest_treebridge", "forest_spore_corridor", "forest_moss_guardian", "mine_entrance", "mine_fracture", "mine_furnace", "sky_corridor", "sky_altar", "sky_lord"]:
		for difficulty in ["normal", "elite"]:
			fixtures.append({"stage":stage_id, "difficulty":difficulty})
	# Thirty sessions cover every normal/elite encounter plus two extra sky
	# samples at distinct player loadouts.  Results are emitted by finish(), not
	# reconstructed from residual HP after a ratio-cap result.
	for index in range(30):
		var fixture: Dictionary = fixtures[index % fixtures.size()]
		var loadout := {"weapon":["ember", "volt", "rockcore"][index % 3], "charm":"feather" if index % 2 == 0 else "moss", "level":index % 5, "max_hp":1000.0 + (60.0 if index % 4 == 0 else 0.0), "direct_hit_bonus":8.0 if index % 3 == 1 else 0.0}
		var result := simulate(str(fixture.stage), str(fixture.difficulty), 100 + index, loadout)
		check(bool(result.done), "%s/%s seed %d terminates" % [fixture.stage, fixture.difficulty, 100 + index])
		if bool(result.done): completed += 1
		ticks_total += int(result.ticks)
		print("ROUND3_SIM stage=%s difficulty=%s seed=%d winner=%d rounds=%d actions=%d shots=%d hits=%d weapon=%s max_hp=%d" % [fixture.stage, fixture.difficulty, 100 + index, result.winner, result.rounds, result.actions, result.shots, result.hits, result.weapon, result.max_hp])
	print("ROUND3_SIMULATIONS completed=%d/30 total_ticks=%d" % [completed, ticks_total])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_stage_and_forecast()
	test_altar_warning()
	test_storm_lord_and_direct_gem()
	test_live_projectile_gem_contract()
	test_elite_modifiers()
	test_thirty_simulations()
	print("ROUND3 BATTLE CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
