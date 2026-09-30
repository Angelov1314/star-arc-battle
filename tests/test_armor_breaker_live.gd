extends SceneTree
var failures := 0

func check(value: bool, label: String) -> void:
	if value:
		print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func campaign_session(supplies: Dictionary = {}, session_mode: String = "local") -> BattleSession:
	var stage := CampaignData.stage("mine_entrance")
	return BattleSession.new({
		"mode":session_mode, "seed":443, "stage_id":"mine_entrance", "stage":stage,
		"stage_config":stage.stage_config, "supplies":supplies,
		"supply_commit":func(_item_id): return {"ok":true, "remaining":0},
	})

func place_live_rapid_target(session: BattleSession) -> void:
	# At this range both real rapid projectiles collide with the enemy body;
	# its splash cannot reach the shooter.  This makes each captured damage
	# event unambiguously an enemy hit rather than self damage.
	session.fighters[0].pos = Vector2(500.0, Ballistics.height_at(session.heights, 500.0) - Ballistics.RADIUS)
	session.fighters[1].pos = Vector2(590.0, Ballistics.height_at(session.heights, 590.0) - Ballistics.RADIUS)
	session.fighters[1].armor = 40.0
	session.angle = 20.0
	session.power = 20.0
	session.item = "rapid"

func fire_and_collect_enemy_damage(session: BattleSession) -> Array[float]:
	var enemy_damage: Array[float] = []
	var enemy_position: Vector2 = session.fighters[1].pos
	session.feedback.connect(func(kind: String, position: Vector2, value: float):
		if kind == "damage" and is_equal_approx(position.x, enemy_position.x):
			enemy_damage.append(value)
	)
	check(session.fire(), "real rapid fire starts")
	for i in range(2400):
		session.tick()
		if session.phase != BattleSession.Phase.FLIGHT:
			break
	check(session.phase != BattleSession.Phase.FLIGHT, "rapid batch completes through tick")
	print("ENEMY RAPID DAMAGE ", enemy_damage)
	return enemy_damage

func wait_for_player_turn_after_enemy_fire(session: BattleSession) -> void:
	for i in range(12000):
		session.tick()
		if session.turn == 0 and session.phase == BattleSession.Phase.AIM:
			return
	check(false, "enemy completes a real fired turn")

func run() -> void:
	var baseline := campaign_session()
	place_live_rapid_target(baseline)
	var normal_damage := fire_and_collect_enemy_damage(baseline)
	check(normal_damage.size() == 2, "baseline rapid produces exactly two enemy damage events")

	var boosted := campaign_session({"armor_breaker":1})
	place_live_rapid_target(boosted)
	check(boosted.use_supply("armor_breaker"), "armor breaker save succeeds before firing")
	var breaker_damage := fire_and_collect_enemy_damage(boosted)
	check(breaker_damage.size() == 2, "armed rapid produces exactly two enemy damage events")
	if normal_damage.size() == 2 and breaker_damage.size() == 2:
		check(is_equal_approx(breaker_damage[0], normal_damage[0]), "first hit keeps 40 armour")
		check(is_equal_approx(breaker_damage[1], normal_damage[1] + 20.0), "second hit receives exactly half of 40 armour")
	check(boosted.armor_breaker_hits == 1 and boosted.armor_breaker_target == 1, "rapid consumes one of two post-hit armour-break charges")
	var remaining_before_hazard := boosted.armor_breaker_hits
	boosted.pending_hazard = {"kind":"furnace", "x":boosted.fighters[1].pos.x, "radius":110.0, "damage":90.0}
	boosted.apply_enemy_start_events()
	check(boosted.armor_breaker_hits == remaining_before_hazard and boosted.armor_breaker_target == 1, "environment damage does not consume armor-break hit count")

	var ownership := campaign_session({"armor_breaker":1}, "ai")
	check(ownership.use_supply("armor_breaker"), "player drinks armor breaker")
	ownership.time_left = 0.0
	ownership.tick(0.01)
	ownership.tick(0.7)
	check(ownership.turn == 1 and ownership.phase == BattleSession.Phase.AIM and ownership.armor_breaker_armed, "player timeout preserves unloaded vial into enemy turn")
	wait_for_player_turn_after_enemy_fire(ownership)
	check(ownership.armor_breaker_armed and not ownership.armor_breaker_pending and ownership.armor_breaker_hits == 0, "enemy fire cannot steal or apply player vial")
	place_live_rapid_target(ownership)
	ownership.item = "none"
	check(ownership.fire() and ownership.armor_breaker_pending and ownership.armor_breaker_pending_owner == 0 and not ownership.armor_breaker_armed, "next player fire owns the preserved vial")

	var miss := campaign_session({"armor_breaker":1})
	check(miss.use_supply("armor_breaker"), "miss fixture drinks armor breaker")
	miss.angle = 80.0
	miss.power = 100.0
	check(miss.fire(), "armed miss is a real fire")
	for i in range(2400):
		miss.tick()
		if miss.phase != BattleSession.Phase.FLIGHT:
			break
	check(miss.phase != BattleSession.Phase.FLIGHT and not miss.armor_breaker_pending and miss.armor_breaker_pending_owner == -1, "out-of-range batch clears pending armor breaker")
	print("ARMOR BREAKER LIVE FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
