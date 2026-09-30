extends SceneTree
var failures:=0
const PAINTED_STYLE_BOX := preload("res://scripts/ui/PaintedStyleBox.gd")
func check(ok: bool, label: String)->void:
	if ok: print("PASS: "+label)
	else: failures+=1; printerr("FAIL: "+label)
func _initialize()->void: call_deferred("run")
func run()->void:
	var folder="user://painted-ui-test-"+str(Time.get_ticks_usec()); DirAccess.make_dir_recursive_absolute(folder)
	var p:=PlayerProfile.new(folder+"/profile.json"); p.ensure_round_one(); p.save()
	var main=load("res://scenes/Main.tscn").instantiate(); main.profile=p; root.add_child(main); await process_frame
	var ui_theme := Styles.theme()
	var button_style := ui_theme.get_stylebox("normal", "Button")
	var atlas := load(Styles.UI_ATLAS) as Texture2D
	check(atlas != null and atlas.get_width() >= 512 and button_style.get_script() == PAINTED_STYLE_BOX and button_style.get("texture") != null, "bitmap atlas loads and global button skin is present")
	for target in [["hover", "Button"], ["pressed", "Button"], ["disabled", "Button"], ["normal", "LineEdit"], ["focus", "LineEdit"], ["normal", "OptionButton"], ["panel", "PopupMenu"], ["panel", "TooltipPanel"]]:
		var style := ui_theme.get_stylebox(str(target[0]), str(target[1]))
		check(style.get_script() == PAINTED_STYLE_BOX and style.get("texture") != null, "%s %s has painted skin" % [str(target[1]), str(target[0])])
	for page in ["show_town","show_lobby","show_expedition","show_inventory","show_character","show_workshop","show_crafting","show_settings","show_help"]:
		main.call(page); await process_frame; check(main.screen!=null and main.screen.get_child_count()>0,page+" builds screen")
	main.queue_free(); await process_frame
	for n in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder+"/"+n)
	DirAccess.remove_absolute(folder); print("PAINTED UI FAILURES: %d"%failures); quit(0 if failures==0 else 1)
