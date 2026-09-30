extends SceneTree

class RecorderAudio extends GameAudio:
	var calls: Array[String] = []
	func _ready() -> void: pass
	func play(key: String) -> void: calls.append(key)
	func volumes(music_value: float, sfx_value: float) -> void:
		music_volume = music_value; sfx_volume = sfx_value
	func set_context(_next_context: String) -> void: pass
	func set_paused(value: bool) -> void: paused = value
	func clear() -> void: calls.clear()

var failures := 0
var main: Control
var recorder: RecorderAudio
var folder := ""

func check(value: bool, label: String) -> void:
	if value: print("PASS: " + label)
	else: failures += 1; printerr("FAIL: " + label)

func count(key: String) -> int:
	return recorder.calls.count(key)

func find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var found := find_button(child, text)
		if found != null: return found
	return null

func press(button: Button) -> void:
	check(button != null and not button.disabled, "button is actionable: " + (button.text if button else "missing"))
	if button == null or button.disabled: return
	button.pressed.emit()
	await process_frame

func replace_audio() -> void:
	var old: GameAudio = main.audio
	main.remove_child(old)
	old.queue_free()
	recorder = RecorderAudio.new()
	main.audio = recorder
	main.add_child(recorder)
	Styles.click_sound = recorder.play.bind("click")
	Styles.hover_sound = recorder.play.bind("hover")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	folder = "user://audio-interactions-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var profile := PlayerProfile.new(folder + "/profile.json")
	profile.ensure_round_one()
	profile.data.gold = 5000
	profile.data.inventory.stacks.enhancement_dust = 80
	profile.data.inventory.stacks.woodchip = 80
	profile.data.inventory.stacks.echo_gem = 1
	profile.data.campaign.first_clears.sky_lord = true
	profile.save()
	main = load("res://scenes/Main.tscn").instantiate()
	main.profile = profile
	root.add_child(main)
	await process_frame
	replace_audio()

	# Upgrade success is recorded only after the confirmation transaction completes.
	main.show_workshop(); await process_frame
	recorder.clear()
	main.confirm_upgrade("legacy-weapon-ember"); await process_frame
	check(count("upgrade") == 0, "upgrade is silent before confirmation")
	await press(find_button(main.modal, "确认强化"))
	check(count("upgrade") == 1 and count("error") == 0, "successful upgrade emits upgrade exactly once")

	# A material failure emits error and never the previous success key.
	main.profile.data.gold = 0
	main.profile.data.inventory.stacks.enhancement_dust = 0
	main.profile.data.inventory.stacks.woodchip = 0
	main.profile.save()
	recorder.clear()
	main.confirm_upgrade("legacy-weapon-ember"); await process_frame
	await press(find_button(main.modal, "确认强化"))
	check(count("error") == 1 and count("upgrade") == 0, "insufficient upgrade materials emit error without upgrade")
	if main.modal != null: main.close_modal(false)

	# Craft and socket are also post-commit sounds.
	main.profile.data.gold = 5000
	main.profile.data.inventory.stacks.enhancement_dust = 20
	main.profile.data.inventory.stacks.woodchip = 20
	main.profile.save()
	main.show_crafting(); await process_frame
	recorder.clear()
	main.confirm_craft("small_medkit", 1); await process_frame
	check(count("craft") == 0, "craft is silent before confirmation")
	await press(find_button(main.modal, "确认制作"))
	check(count("craft") == 1, "successful craft emits craft")
	main.show_workshop(); await process_frame
	recorder.clear()
	main.confirm_socket("legacy-weapon-ember", "echo_gem"); await process_frame
	await press(find_button(main.modal, "确认镶嵌"))
	check(count("socket") == 1 and count("error") == 0, "successful socket emits socket after commit")

	# A duplicate weapon is eligible for the destructive two-step fixture.
	var spare: Dictionary = main.profile.data.inventory.equipment["legacy-weapon-volt"].duplicate(true)
	spare.locked = false; spare.gem_item_id = null; spare.level = 0
	main.profile.data.inventory.equipment["audio-spare-volt"] = spare
	main.profile.save()
	var selection: Array[String] = ["audio-spare-volt"]
	main.batch_selected = selection
	main.show_workshop(); await process_frame
	# The workshop starts on upgrade; select dismantle using its existing tab control.
	main.workshop_tab = "dismantle"; main.show_workshop(); await process_frame
	recorder.clear()
	main.confirm_dismantle(); await process_frame
	await press(find_button(main.modal, "确认永久分解"))
	check(count("dismantle") == 1 and count("error") == 0, "successful dismantle emits dismantle after second confirmation")

	# Explicit close is cancellation, while a successful settings close is not.
	main.make_modal("取消检查"); recorder.clear(); main.close_modal()
	check(count("cancel") == 1, "explicit modal close emits cancel")
	main.show_settings(); await process_frame; recorder.clear()
	await press(find_button(main.modal, "保存设置"))
	check(count("cancel") == 0 and count("select") == 1, "successful settings close does not emit cancel")
	main.start_battle(); await process_frame
	recorder.clear()
	main.battle.session.time_left = 5.0
	main.battle.refresh_live(); main.battle.refresh_live(); main.battle.refresh_live()
	check(count("warning") == 1, "low-time warning is deduplicated within its displayed second")
	main.battle.session.paused = true
	main.battle.session.time_left = 4.0
	main.battle.refresh_live()
	check(count("warning") == 1, "paused countdown does not add a low-time warning")
	main.battle.set_paused(true)
	main.battle.leave_battle()
	await process_frame
	await process_frame
	check(not recorder.paused and is_equal_approx(recorder.music_volume, main.profile.data.music) and is_equal_approx(recorder.sfx_volume, main.profile.data.sfx), "pause-menu return restores audio before town transition")

	# Failed campaign storage plays error; restoring the same active run permits retry.
	var started: Dictionary = main.campaign.begin_run("forest_treebridge", "normal")
	check(bool(started.ok), "campaign run fixture starts")
	main.active_campaign_run = started
	var result := {"id":"audio-result", "winner":0, "mode":"campaign", "rounds":1, "seconds":1, "stats":{}, "player_actions":1, "medkits_used":0, "supply_uses":{}}
	var valid_path: String = main.profile.path
	main.profile.path = "/dev/null/audio-profile.json"
	recorder.clear(); main.show_campaign_result(result); await process_frame
	check(count("error") == 1 and count("win") == 0, "failed settlement has no celebration")
	main.profile.path = valid_path
	recorder.clear(); main.show_campaign_result(result); await process_frame
	check(count("reward") == 1 and count("win") == 1, "settlement retry celebrates after save")
	recorder.clear(); main.show_campaign_result(result); await process_frame
	check(count("win") == 0 and count("reward") == 0, "reopening the settled run does not replay result audio")

	print("AUDIO INTERACTION FAILURES: %d" % failures)
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
