extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: "+message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_damage()
	test_ballistics()
	test_rules()
	test_profile()
	test_matches()
	print("CHECKS: %d | FAILURES: %d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_damage() -> void:
	for weapon in GameData.WEAPONS:
		for mode in GameData.MODES:
			for item in GameData.ITEMS:
				var expected: float = GameData.attack(weapon,0)*GameData.MODES[mode].damage*GameData.ITEMS[item].damage
				check(is_equal_approx(GameData.damage(weapon,0,mode,item,false,0.0),expected),"composed damage "+weapon+mode+item)
	check(GameData.damage("ember",0,"heavy","amp",true,0)>GameData.damage("ember",0,"normal","amp",true,0),"heavy remains effective with item and rage")

func test_ballistics() -> void:
	for weapon in GameData.WEAPONS:
		for mode in GameData.MODES:
			for wind in [-3.0,0.0,3.0]:
				var s := BattleSession.new({"mode":"local","seed":44,"weapon":weapon})
				s.wind=wind
				s.selected_mode=mode
				s.angle=46.0
				s.power=82.0
				var predicted := s.trace()
				var impacts: Array[Vector2] = []
				s.feedback.connect(func(kind,pos,_value):
					if kind=="explosion": impacts.append(pos))
				s.fire()
				for frame in range(1400):
					s.tick()
					if s.phase!=BattleSession.Phase.FLIGHT: break
				if predicted.hit.kind!="out":
					check(not impacts.is_empty(),"predicted collision exists")
					if not impacts.is_empty(): check(impacts[0].distance_to(predicted.hit.pos)<2.0,"preview agrees with live projectile")
				check(s.phase!=BattleSession.Phase.FLIGHT,"projectile terminates")
	var heights := Ballistics.terrain()
	var targets: Array = [{"hp":100.0,"pos":Vector2(500,300)},{"hp":100.0,"pos":Vector2(700,300)}]
	var hit := Ballistics.collision(Vector2(400,300),Vector2(800,300),heights,targets,0,0.1)
	check(hit.get("target",-1)==1,"swept collision catches high speed crossing")
	var crater := Ballistics.carve(heights,Vector2(500,500),68)
	check(Ballistics.height_at(crater,500)>Ballistics.height_at(heights,500),"crater changes collision height")
	check(heights==Ballistics.terrain(),"carve does not mutate source terrain")

func test_rules() -> void:
	var s := BattleSession.new({"mode":"local","seed":1})
	var initial: float = s.fighters[0].stamina
	check(not s.heal(),"full health heal rejected")
	check(s.fighters[0].stamina==initial and s.fighters[0].charges.heal==2,"rejected heal consumes nothing")
	s.selected_mode="heavy"
	s.item="amp"
	s.fighters[0].stamina=54
	check(not s.fire(),"combined stamina gate")
	s.fighters[0].stamina=55
	check(s.fire(),"legal shot accepted")
	check(s.fighters[0].stamina==0 and s.fighters[0].charges.amp==2,"consume resources once")
	check(not s.fire(),"second fire blocked during flight")
	var before: Vector2 = s.shots[0].pos
	s.paused=true
	s.tick()
	check(s.shots[0].pos==before,"pause freezes projectile")
	var timeout := BattleSession.new({"mode":"local","seed":2})
	timeout.charging=true
	timeout.time_left=0.001
	timeout.tick()
	check(not timeout.charging and timeout.phase==BattleSession.Phase.SETTLE,"timeout clears charging")
	var zero := BattleSession.new({"mode":"local","seed":3})
	zero.power=0
	zero.fire()
	for i in range(1600):
		zero.tick()
		if zero.turn==1: break
	check(zero.turn==1,"zero power resolves without hanging")
	var mutual := BattleSession.new({"mode":"local","seed":4})
	mutual.fighters[0].hp=0
	mutual.fighters[1].hp=0
	mutual.phase=BattleSession.Phase.SETTLE
	mutual.settle_time=0
	var results: Array=[]
	mutual.finished.connect(func(result): results.append(result))
	mutual.tick()
	mutual.tick()
	check(results.size()==1 and results[0].winner==-1,"simultaneous defeat settles draw once")
	var rapid := BattleSession.new({"mode":"local","seed":8})
	rapid.item="rapid"
	rapid.fire()
	check(rapid.shots.size()==2 and rapid.fighters[0].charges.rapid==2,"double shot consumes one item")

func test_profile() -> void:
	var folder := "user://verification-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder+"/profile.json"
	var p := PlayerProfile.new(path)
	check(p.save(),"new profile saved")
	check(p.equip("volt","moss"),"equip persists")
	p.data.inventory.stacks.enhancement_dust = 2
	p.data.inventory.stacks.woodchip = 1
	check(p.save(),"upgrade material fixture persists")
	check(p.upgrade("volt"),"upgrade succeeds")
	var q := PlayerProfile.new(path)
	check(q.data.weapon=="volt" and q.data.charm=="moss" and q.data.levels.volt==1,"restart restores loadout and upgrade")
	var first := q.reward("match-1",0,"ai")
	var gold: int=q.data.gold
	check(first.gold==90 and first.saved,"win reward saved")
	check(q.reward("match-1",0,"ai").gold==0 and q.data.gold==gold,"duplicate reward rejected")
	check(q.reward("practice",0,"training").gold==0,"training has no reward")
	var corrupt := FileAccess.open(path,FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	var restored := PlayerProfile.new(path)
	check(restored.notice.contains("备份") and restored.data.weapon=="volt","backup recovery")
	var old := PlayerProfile.defaults()
	old.version=1
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	var migrated := PlayerProfile.new(path)
	check(migrated.data.version==PlayerProfile.CURRENT_VERSION and migrated.data.has("inventory"),"version 1 migrates")
	old.levels="malformed"
	check(not migrated.valid(old),"malformed nested data rejected")
	var unavailable := PlayerProfile.new(folder+"/missing/profile.json")
	var before: int=unavailable.data.gold
	check(not unavailable.upgrade("ember") and unavailable.data.gold==before and unavailable.data.levels.ember==0,"failed persistence rolls back purchase")
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder+"/"+name)
	DirAccess.remove_absolute(folder)

func test_matches() -> void:
	var started := Time.get_ticks_msec()
	for game in range(10):
		var s := BattleSession.new({"mode":"local","seed":1200+game,"weapon":"ember" if game%2==0 else "volt"})
		var endings: Array=[]
		s.finished.connect(func(result): endings.append(result))
		var loops := 0
		while s.phase!=BattleSession.Phase.COMPLETE and loops<30000:
			if s.phase==BattleSession.Phase.AIM:
				s.advance_ai()
			s.tick()
			loops+=1
		check(s.phase==BattleSession.Phase.COMPLETE and endings.size()==1,"automated match %d terminates once"%game)
		check(s.round_number<=30,"round cap")
		print("MATCH %02d: winner=%d turns=%d hits=%d/%d simulated=%.1fs"%[game,endings[0].winner if not endings.is_empty() else -9,s.round_number,s.stats[0].hits,s.stats[1].hits,s.elapsed])
	print("10 match simulation wall time: %.2fs"%((Time.get_ticks_msec()-started)/1000.0))
