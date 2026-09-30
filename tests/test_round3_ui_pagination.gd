extends SceneTree

var failures := 0
func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var folder := "user://round3-page-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	profile.ensure_round_one()
	profile.data.campaign.first_clears.sky_lord = true
	for index in range(60):
		profile.data.inventory.equipment["page-%02d" % index] = {"template_id":"volt" if index % 2 else "ember","level":index % 9,"locked":false,"gem_item_id":null,"invested_materials":{},"is_new":false,"acquired_at":index}
	profile.save()
	var main: Variant = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile; root.add_child(main); await process_frame
	main.workshop_tab = "upgrade"; main.workshop_list_page = 11; main.show_workshop(); await process_frame
	check(main.workshop_list_page == 11, "upgrade list keeps a valid final page for 60 reward weapons")
	main.workshop_tab = "socket"; main.workshop_list_page = 11; main.show_workshop(); await process_frame
	check(main.workshop_list_page == 11, "socket list keeps a valid final page for 60 reward weapons")
	main.workshop_tab = "dismantle"; main.workshop_list_page = 11; main.show_workshop(); await process_frame
	check(main.workshop_list_page == 11, "dismantle list keeps a valid final page for 60 instances")
	main.call("toggle_dismantle", "page-58"); main.call("toggle_dismantle", "page-59"); main.confirm_dismantle(); await process_frame
	check(main.modal != null, "large-batch selection reaches the second confirmation")
	main.queue_free(); await process_frame
	for name in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder + "/" + name)
	DirAccess.remove_absolute(folder)
	print("ROUND3 PAGINATION FAILURES: %d" % failures)
	quit(0 if failures == 0 else 1)
