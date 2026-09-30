extends SceneTree
var failures := 0
func check(v: bool, label: String) -> void:
	if v: print("PASS: "+label)
	else: failures+=1; printerr("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := "user://round2-supplies-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder+"/profile.json"
	var p := PlayerProfile.new(path)
	var inv := InventoryService.new(p)
	p.data.inventory.stacks.armor_breaker=2
	p.save()
	check(inv.configure_supplies([{"item_id":"small_medkit","quantity":1},{"item_id":"stamina_tonic","quantity":1}]).ok,"old two supplies save")
	check(inv.configure_supplies([{"item_id":"stamina_tonic","quantity":1},{"item_id":"armor_breaker","quantity":2}]).ok,"replace medkit with armor breaker")
	check(not inv.configure_supplies([{"item_id":"small_medkit","quantity":1},{"item_id":"stamina_tonic","quantity":1},{"item_id":"armor_breaker","quantity":1}]).ok,"third supply conflict rejects")
	var restored := PlayerProfile.new(path)
	var restored_inv := InventoryService.new(restored)
	check(restored_inv.supply_snapshot().size()==2 and restored_inv.stack_count("armor_breaker")==2,"supply config restarts without inventory deduction")
	print("ROUND2 SUPPLIES FAILURES: %d"%failures)
	quit(0 if failures==0 else 1)
