extends SceneTree

var rows: Array[String] = ["kind,stage,seed,player_weapon,enemy_weapon,player_charm,enemy_charm,player_x,enemy_x,enemy_spread,player_hits/player_shots,enemy_hits/enemy_shots,player_actions,winner,ticks"]
var failures := 0

func _initialize() -> void: call_deferred("run")

func run_match(kind: String, stage_id: String, seed: int, weapon: String, charm: String, swap: bool) -> void:
	var stage := CampaignData.stage(stage_id)
	var cfg: Dictionary = stage.stage_config.duplicate(true)
	var enemy: Dictionary = cfg.get("enemy", {}).duplicate(true)
	if kind == "comparison":
		enemy.weapon = "rockcore"
		enemy.charm = "moss"
		enemy.x = 230.0 if swap else 1040.0
		cfg.player_x = 1040.0 if swap else 230.0
	cfg.enemy = enemy
	var s := BattleSession.new({"mode":"ai","seed":seed,"stage_id":stage_id,"stage":stage,"stage_config":cfg,"weapon":weapon,"charm":charm,"level":3})
	var results: Array = []
	s.finished.connect(func(result): results.append(result))
	var ticks := 0
	while s.phase != BattleSession.Phase.COMPLETE and ticks < 30000:
		if s.phase == BattleSession.Phase.AIM and s.turn == 0: s.advance_ai()
		s.tick()
		ticks += 1
	if s.phase != BattleSession.Phase.COMPLETE:
		failures += 1
		rows.append("%s,%s,%d,%s,%s,%s,%s,%d,%d,%.1f,%d/%d,%d/%d,%d,UNFINISHED,%d" % [kind,stage_id,seed,weapon,str(enemy.get("weapon","volt")),charm,str(enemy.get("charm","moss")),cfg.get("player_x",230),enemy.get("x",1040),s.fighters[1].ai_spread,s.stats[0].hits,s.stats[0].shots,s.stats[1].hits,s.stats[1].shots,s.player_actions,ticks])
		return
	rows.append("%s,%s,%d,%s,%s,%s,%s,%d,%d,%.1f,%d/%d,%d/%d,%d,%d,%d" % [kind,stage_id,seed,weapon,str(enemy.get("weapon","volt")),charm,str(enemy.get("charm","moss")),cfg.get("player_x",230),enemy.get("x",1040),s.fighters[1].ai_spread,s.stats[0].hits,s.stats[0].shots,s.stats[1].hits,s.stats[1].shots,s.player_actions,int(results[0].winner),ticks])

func run() -> void:
	for i in range(3): run_match("feasibility", ["mine_entrance","mine_fracture","mine_furnace"][i], 2300+i, "ember", "feather", false)
	var index := 0
	for weapon in ["ember","volt","rockcore"]:
		for charm in ["feather","moss"]:
			for swap in [false,true]:
				run_match("comparison", "mine_fracture", 2500+index, weapon, charm, swap)
				index += 1
	DirAccess.make_dir_recursive_absolute("res://docs/validation/round2")
	var file := FileAccess.open("res://docs/validation/round2/balance.txt", FileAccess.WRITE)
	file.store_string("\n".join(rows) + "\nfailures=%d\n" % failures)
	file.close()
	print("ROUND2 BALANCE matches=%d failures=%d" % [rows.size()-1, failures])
	quit(0 if failures == 0 else 1)
