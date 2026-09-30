extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_stage_fields_and_terrain()
	test_spore_timing_and_pause()
	test_guarded_direct_hits()
	test_supply_transaction()
	test_three_stage_autoplay()
	test_boss_seed_comparison()
	print("CAMPAIGN BATTLE CHECKS: %d | FAILURES: %d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func stage_config(stage_id: String) -> Dictionary:
	return CampaignData.stage(stage_id).stage_config

func battle(stage_id: String, extras: Dictionary = {}) -> BattleSession:
	var config := {"mode":"local", "seed":171, "stage_id":stage_id, "stage":CampaignData.stage(stage_id), "stage_config":stage_config(stage_id)}
	for key in extras: config[key] = extras[key]
	return BattleSession.new(config)

func test_stage_fields_and_terrain() -> void:
	var bridge := battle("forest_treebridge")
	var spores := battle("forest_spore_corridor")
	var guardian := battle("forest_moss_guardian")
	check(bridge.fighters[1].max_hp == 700.0 and spores.fighters[1].max_hp == 850.0 and guardian.fighters[1].max_hp == 1200.0, "chapter one enemies use distinct configured health")
	check(not is_equal_approx(Ballistics.height_at(bridge.heights, 640), Ballistics.height_at(spores.heights, 640)), "tree bridge and spore corridor have distinct height fields")
	check(not is_equal_approx(Ballistics.height_at(spores.heights, 795), Ballistics.height_at(guardian.heights, 795)), "spore corridor and guardian arena have distinct height fields")
	for i in range(20):
		bridge.start_turn()
		check(absf(bridge.wind) <= 1.401, "tree bridge wind stays gentle")

func test_spore_timing_and_pause() -> void:
	var s := battle("forest_spore_corridor")
	s.apply_enemy_end_events()
	check(s.pending_hazard.is_empty(), "spores do not announce after first enemy end")
	s.apply_enemy_end_events()
	check(not s.pending_hazard.is_empty(), "spores announce after second enemy end")
	var x := float(s.pending_hazard.x)
	s.fighters[0].pos.x = x
	s.fighters[1].pos.x = x
	var player_hp: float = s.fighters[0].hp
	var enemy_hp: float = s.fighters[1].hp
	s.paused = true
	s.tick(4.0)
	check(s.fighters[0].hp == player_hp and not s.pending_hazard.is_empty(), "pause does not advance pending spores")
	s.paused = false
	s.turn = 1
	s.start_turn()
	check(s.fighters[0].hp == player_hp - 60.0 and s.fighters[1].hp == enemy_hp - 60.0, "next enemy start resolves marked spore area for all fighters")

func test_guarded_direct_hits() -> void:
	var s := battle("forest_moss_guardian")
	s.boss_state = "defense"
	s.boss_locked_facing = -1
	var shot := {"owner":0, "damage":1000.0, "radius":68.0}
	var direct := {"target":1, "pos":s.fighters[1].pos + Vector2(-8, 0)}
	s.explode(shot, direct)
	check(is_equal_approx(s.fighters[1].hp, 704.0), "defense halves a frontal direct hit after armour")
	s.fighters[1].hp = 10.0
	s.explode(shot, direct)
	check(s.fighters[1].hp == 0.0, "low-health frontal defense hit can still defeat guardian")
	var splash := battle("forest_moss_guardian")
	splash.boss_state = "defense"
	splash.boss_locked_facing = -1
	splash.explode(shot, {"target":-1, "pos":splash.fighters[1].pos})
	check(is_equal_approx(splash.fighters[1].hp, 208.0), "ground splash does not receive frontal direct-hit reduction")
	var tired := battle("forest_moss_guardian")
	tired.boss_state = "fatigue"
	tired.boss_locked_facing = -1
	tired.explode(shot, direct)
	check(is_equal_approx(tired.fighters[1].hp, 208.0), "fatigue restores full direct-hit damage")

func test_supply_transaction() -> void:
	var failed := battle("forest_treebridge", {"supplies":{"small_medkit":1}, "supply_commit":func(_item_id): return {"ok":false, "message":"disk failed"}})
	failed.fighters[0].hp = 500.0
	check(not failed.heal() and failed.fighters[0].hp == 500.0 and failed.supplies.small_medkit == 1, "failed supply save grants no healing and consumes nothing")
	var remaining := [2]
	var committed := battle("forest_treebridge", {"supplies":{"small_medkit":2, "stamina_tonic":1}, "supply_commit":func(_item_id):
		remaining[0] -= 1
		return {"ok":true, "remaining":remaining[0]}})
	committed.fighters[0].hp = 500.0
	check(committed.heal() and committed.fighters[0].hp == 750.0 and committed.supplies.small_medkit == 1, "saved medkit applies once")
	check(not committed.use_supply("stamina_tonic"), "one campaign supply is limited to each player action")
	committed.supply_used_this_action = false
	committed.fighters[0].hp = 400.0
	check(committed.heal() and committed.supplies.small_medkit == 0, "two carried medkits display their per-run remaining count")
	committed.supply_used_this_action = false
	check(not committed.heal() and committed.supplies.small_medkit == 0, "third use cannot draw from warehouse beyond carried supplies")

func test_three_stage_autoplay() -> void:
	for stage_id in ["forest_treebridge", "forest_spore_corridor", "forest_moss_guardian"]:
		var s := battle(stage_id)
		var loops := 0
		while s.phase != BattleSession.Phase.COMPLETE and loops < 30000:
			if s.phase == BattleSession.Phase.AIM: s.advance_ai()
			s.tick()
			loops += 1
		check(s.phase == BattleSession.Phase.COMPLETE and loops < 30000, "%s full automatic battle terminates without forced result" % stage_id)
		var winner: int = 0 if s.fighters[1].hp <= 0.0 else 1 if s.fighters[0].hp <= 0.0 else -1
		print("AUTOPLAY %s: winner=%d turn_counter=%d ticks=%d seconds=%.1f" % [stage_id, winner, s.round_number, loops, s.elapsed])

func test_boss_seed_comparison() -> void:
	for level in [0, 1]:
		var wins := 0
		var turns: Array[int] = []
		for seed in [101, 202, 303, 404, 505]:
			var s := battle("forest_moss_guardian", {"seed":seed, "level":level})
			var loops := 0
			while s.phase != BattleSession.Phase.COMPLETE and loops < 30000:
				if s.phase == BattleSession.Phase.AIM: s.advance_ai()
				s.tick()
				loops += 1
			check(s.phase == BattleSession.Phase.COMPLETE and loops < 30000, "boss seed %d at +%d terminates normally" % [seed, level])
			if s.fighters[1].hp <= 0.0: wins += 1
			turns.append(s.round_number)
		print("BOSS SEEDS +%d: player_wins=%d/5 turn_counters=%s" % [level, wins, turns])
