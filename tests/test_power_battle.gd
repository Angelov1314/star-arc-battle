extends SceneTree

var checks := 0
var failures := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: " + label)
	else:
		failures += 1
		printerr("FAIL: " + label)

func enemy_snapshot(stage_id: String, difficulty: String) -> Dictionary:
	return CampaignData.enemy_snapshot(stage_id, difficulty)

func make(level: int, stage_id: String = "forest_spore_corridor", difficulty: String = "normal", gem: Variant = null, charm: String = "feather") -> BattleSession:
	var stage := CampaignData.stage(stage_id, difficulty)
	var player := ProgressionData.player_snapshot("ember", charm, 0, gem, level)
	return BattleSession.new({"mode":"campaign","seed":101,"stage_id":stage_id,"stage":stage,"stage_config":stage.stage_config,"stage_snapshot":stage.stage_config,"combat_snapshot":player,"enemy_snapshot":enemy_snapshot(stage_id, difficulty),"supplies":{"small_medkit":1},"supply_commit":func(_item): return {"ok":true,"remaining":0}})

func test_live_power_rules() -> void:
	for level in [1, 10, 20, 30, 40, 50, 60]:
		var session := make(level)
		var player: Dictionary = ProgressionData.player_snapshot("ember", "feather", 0, null, level)
		check(is_equal_approx(float(session.fighters[0].max_hp), float(player.max_hp)) and is_equal_approx(float(session.fighters[0].base_attack), float(player.base_attack)), "Lv%d session consumes frozen scaled HP and attack" % level)
		var before := float(session.fighters[1].hp)
		session.explode({"owner":0,"damage":float(player.base_attack),"direct_bonus":0.0,"radius":68.0}, {"target":1,"pos":session.fighters[1].pos})
		check(is_equal_approx(before - float(session.fighters[1].hp), minf(before, float(player.base_attack) * 0.96)), "Lv%d direct projectile applies enemy 4%% DR once" % level)
		var heal_session := make(level)
		heal_session.fighters[0].hp = float(heal_session.fighters[0].max_hp) * 0.5
		check(heal_session.heal() and is_equal_approx(float(heal_session.fighters[0].hp), float(heal_session.fighters[0].max_hp) * 0.75), "Lv%d medical pack restores 25%% max HP" % level)
		var rage_session := make(level)
		rage_session.fighters[1].hp = float(rage_session.fighters[1].max_hp)
		var enemy_hp := float(rage_session.fighters[1].max_hp)
		rage_session.explode({"owner":0,"damage":enemy_hp * 0.5,"direct_bonus":0.0,"radius":68.0}, {"target":1,"pos":rage_session.fighters[1].pos})
		check(is_equal_approx(float(rage_session.fighters[1].rage), 43.2) and is_equal_approx(float(rage_session.fighters[0].rage), 36.0), "Lv%d rage uses actual damage / receiver max HP" % level)

func test_gem_and_fixed_hazard() -> void:
	var pierce := make(20, "sky_altar", "normal", "pierce_gem")
	var direct_before := float(pierce.fighters[1].hp)
	pierce.explode({"owner":0,"damage":float(pierce.fighters[0].base_attack),"direct_bonus":float(pierce.fighters[0].direct_hit_bonus),"radius":68.0}, {"target":1,"pos":pierce.fighters[1].pos})
	var direct_damage := direct_before - float(pierce.fighters[1].hp)
	var splash := make(20, "sky_altar", "normal", "pierce_gem")
	var splash_before := float(splash.fighters[1].hp)
	splash.explode({"owner":0,"damage":float(splash.fighters[0].base_attack),"direct_bonus":float(splash.fighters[0].direct_hit_bonus),"radius":68.0}, {"target":-1,"pos":splash.fighters[1].pos})
	check(direct_damage > splash_before - float(splash.fighters[1].hp), "scaled pierce gem affects direct hit but never splash")
	var low := make(1, "sky_altar")
	var high := make(60, "sky_altar")
	low.apply_enemy_end_events(); high.apply_enemy_end_events()
	check(is_equal_approx(float(low.pending_hazard.damage), float(high.pending_hazard.damage)) and is_equal_approx(float(low.pending_hazard.damage), 80.0 * ProgressionData.scale(16)), "hazard uses fixed stage target scale rather than player level")

func live_direct(level: int, gem: Variant) -> float:
	var s := make(level, "forest_treebridge", "normal", gem)
	s.fighters[0].pos = Vector2(240, Ballistics.height_at(s.heights, 240) - Ballistics.RADIUS)
	s.fighters[1].pos = Vector2(330, Ballistics.height_at(s.heights, 330) - Ballistics.RADIUS)
	s.fighters[1].max_hp = 1000000000000.0; s.fighters[1].hp = s.fighters[1].max_hp
	s.angle = 0.0; s.power = 20.0
	var before := float(s.fighters[1].hp)
	check(s.fire(), "Lv%d real projectile fires" % level)
	for _tick in range(3000):
		s.tick()
		if s.phase != BattleSession.Phase.FLIGHT: break
	return before - float(s.fighters[1].hp)

func test_live_projectiles() -> void:
	for level in [1,20,60]:
		var plain := live_direct(level, null)
		var pierce := live_direct(level, "pierce_gem")
		check(pierce > plain and plain > 0.0, "Lv%d fire-to-tick body hit receives scaled g16" % level)
	var breaker := make(1, "forest_treebridge", "normal", null, "feather")
	breaker.fighters[1].damage_reduction = 0.04
	breaker.armor_breaker_target = 1; breaker.armor_breaker_hits = 2
	var hp := float(breaker.fighters[1].hp)
	breaker.explode({"owner":0,"damage":100.0,"direct_bonus":0.0,"radius":68.0},{"target":1,"pos":breaker.fighters[1].pos})
	breaker.explode({"owner":0,"damage":100.0,"direct_bonus":0.0,"radius":68.0},{"target":1,"pos":breaker.fighters[1].pos})
	check(is_equal_approx(hp - float(breaker.fighters[1].hp), 196.0) and breaker.armor_breaker_hits == 0, "armor breaker halves DR for exactly two hits")

func test_old_mode_unchanged() -> void:
	var legacy := BattleSession.new({"mode":"local","weapon":"ember","charm":"moss"})
	legacy.explode({"owner":0,"damage":100.0,"direct_bonus":0.0,"radius":68.0}, {"target":1,"pos":legacy.fighters[1].pos})
	check(not legacy.power_campaign and is_equal_approx(float(legacy.fighters[1].hp), 908.0), "0.4 local match retains fixed eight armour")

func _initialize() -> void: call_deferred("run")
func run() -> void:
	test_live_power_rules()
	test_gem_and_fixed_hazard()
	test_live_projectiles()
	test_old_mode_unchanged()
	print("POWER BATTLE CHECKS: %d | FAILURES: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)
