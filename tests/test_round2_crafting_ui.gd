extends SceneTree
var failures:=0
func check(v:bool,s:String)->void:
	if v: print("PASS: "+s)
	else: failures+=1;printerr("FAIL: "+s)
func find(node:Node, kind:String, text:String="") -> Node:
	for child in node.get_children():
		if (kind=="spin" and child is SpinBox) or (kind=="button" and child is Button and child.text==text): return child
		var hit:=find(child,kind,text)
		if hit:return hit
	return null
func find_spins(node:Node, result:Array) -> void:
	for child in node.get_children():
		if child is SpinBox: result.append(child)
		find_spins(child,result)
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:="user://round2-craft-ui-"+str(Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var main:Control=load("res://scenes/Main.tscn").instantiate();main.profile=PlayerProfile.new(folder+"/profile.json");main.profile.ensure_round_one();main.profile.data.inventory.stacks.copper_ore=12;main.profile.data.inventory.stacks.enhancement_dust=12;main.profile.save();root.add_child(main);main.show_crafting();await process_frame
	var spins:Array=[]
	find_spins(main.screen,spins)
	check(spins.size()>=3,"supply recipe quantity controls remain visible alongside later recipes")
	spins[2].value=3;await process_frame
	var craft:=find(main.screen,"button","制作 3 份") as Button
	check(craft!=null,"armor breaker quantity control updates its craft button")
	craft.pressed.emit();await process_frame
	var confirm:=find(main.modal,"button","确认制作") as Button
	check(confirm!=null and main.inventory.stack_count("armor_breaker")==0 and main.inventory.stack_count("copper_ore")==12,"confirm does not pre-deduct")
	confirm.pressed.emit();confirm.pressed.emit();await process_frame
	check(main.inventory.stack_count("armor_breaker")==3 and main.inventory.stack_count("copper_ore")==6 and main.inventory.stack_count("enhancement_dust")==6,"duplicate confirm only crafts once with enough materials for a second craft")
	var second_craft:=find(main.screen,"button","制作 3 份") as Button
	check(second_craft!=null and not second_craft.disabled,"a completed craft enables a new independent confirmation")
	second_craft.pressed.emit();await process_frame
	var second_confirm:=find(main.modal,"button","确认制作") as Button
	second_confirm.pressed.emit();await process_frame
	check(main.inventory.stack_count("armor_breaker")==6 and main.inventory.stack_count("copper_ore")==0 and main.inventory.stack_count("enhancement_dust")==0,"second confirmation spends the remaining materials once")
	var restored:=PlayerProfile.new(folder+"/profile.json");check(int(restored.data.inventory.stacks.get("armor_breaker",0))==6 and int(restored.data.inventory.stacks.get("copper_ore",0))==0 and int(restored.data.inventory.stacks.get("enhancement_dust",0))==0,"crafted inventory reloads with both confirmed costs")
	check(not main.inventory.craft("armor_breaker",100).ok,"quantity boundary rejects")
	main.profile.data.gold=1000;main.profile.data.inventory.stacks.enhancement_dust=10;main.profile.data.inventory.stacks.woodchip=10;main.profile.save()
	main.show_workshop();await process_frame
	main.confirm_upgrade("legacy-weapon-ember");await process_frame
	var upgrade:=find(main.modal,"button","确认强化") as Button
	check(upgrade!=null,"upgrade confirmation is visible")
	upgrade.pressed.emit();upgrade.pressed.emit();await process_frame
	check(int(main.profile.data.inventory.equipment["legacy-weapon-ember"].level)==1,"duplicate upgrade confirmation only raises one level: "+str(main.profile.data.inventory.equipment["legacy-weapon-ember"].level))
	var upgraded:=PlayerProfile.new(folder+"/profile.json")
	check(int(upgraded.data.inventory.equipment["legacy-weapon-ember"].level)==1 and int(upgraded.data.gold)==940,"single upgrade cost persists: level "+str(upgraded.data.inventory.equipment["legacy-weapon-ember"].level)+" gold "+str(upgraded.data.gold))
	print("CRAFT UI FAILURES: %d"%failures);quit(0 if failures==0 else 1)
