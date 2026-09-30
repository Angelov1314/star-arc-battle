class_name BattleView
extends Node2D

signal battle_finished(result: Dictionary)
signal leave_requested
signal restart_requested
var session: BattleSession
var sound: GameAudio
var ui: Control
var labels := {}
var hp_bars: Array[ProgressBar] = []
var buttons := {}
var angle_slider: HSlider
var power_slider: HSlider
var pause_layer: Control
var background: Texture2D
var heroes: Texture2D
var moss_guardian: Texture2D
var furnace_guardian: Texture2D
var storm_lord: Texture2D
var soil: Texture2D
var effects: Array = []
var clock := 0.0
var shake := 0.0
var prediction := PackedVector2Array()
var preview_timer := 0.0
var last_preview_key := ""
var moving := false
var recoil := [0.0, 0.0]
var hit_flash := [0.0, 0.0]
var font: Font
var config := {}
var last_step_sound := -1.0
var last_adjust_sound := -1.0
var low_time_warning_turn := -1
var low_time_warning_second := -1

func _ready() -> void:
	var requested_stage := str(config.get("stage_id", ""))
	if requested_stage.begins_with("sky_") and ResourceLoader.exists("res://assets/art/sky-background.png"):
		background = load("res://assets/art/sky-background.png")
	elif requested_stage.begins_with("mine_") and ResourceLoader.exists("res://assets/art/mine-background.png"):
		background = load("res://assets/art/mine-background.png")
	else:
		background = load("res://assets/art/forest.png")
	soil = load("res://assets/art/soil.png")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	heroes = load("res://assets/art/heroes.png")
	moss_guardian = load("res://assets/art/moss-guardian.png")
	furnace_guardian = load("res://assets/art/furnace-guardian.png") if ResourceLoader.exists("res://assets/art/furnace-guardian.png") else null
	storm_lord = load("res://assets/art/storm-lord.png") if ResourceLoader.exists("res://assets/art/storm-lord.png") else null
	font = Styles.theme().default_font
	session = BattleSession.new(config)
	session.changed.connect(refresh)
	session.feedback.connect(on_feedback)
	session.finished.connect(func(result: Dictionary): battle_finished.emit(result))
	create_ui()
	refresh()
	if sound:
		sound.set_context("battle")
		sound.play("turn")

func _physics_process(_dt: float) -> void:
	if session.human_turn():
		var direction := Input.get_axis("ui_left", "ui_right")
		if Input.is_physical_key_pressed(KEY_A): direction = -1.0
		if Input.is_physical_key_pressed(KEY_D): direction = 1.0
		moving = direction != 0.0 and not session.charging
		if direction != 0.0:
			var old_position: Vector2 = session.fighters[session.turn].pos
			session.move(direction, Ballistics.DT)
			if old_position != session.fighters[session.turn].pos and clock - last_step_sound >= 0.14:
				last_step_sound = clock
				play_sound("step")
		if Input.is_physical_key_pressed(KEY_Q): adjust_angle(-40.0*Ballistics.DT)
		if Input.is_physical_key_pressed(KEY_E): adjust_angle(40.0*Ballistics.DT)
		if not session.charging:
			if Input.is_physical_key_pressed(KEY_W): adjust_power(36.0*Ballistics.DT)
			if Input.is_physical_key_pressed(KEY_S): adjust_power(-36.0*Ballistics.DT)
	else:
		moving = false
	session.tick()

func _process(dt: float) -> void:
	if not session.paused:
		clock += dt
		shake = maxf(0.0, shake-dt*25.0)
		for i in range(2):
			recoil[i] = maxf(0.0,recoil[i]-dt*6.0)
			hit_flash[i] = maxf(0.0,hit_flash[i]-dt*3.0)
		for effect in effects:
			effect.age += dt
		effects = effects.filter(func(effect): return effect.age < effect.life)
	preview_timer -= dt
	if preview_timer <= 0.0:
		preview_timer = 0.08
		var key := "%s/%s/%s/%s/%s/%s" % [session.angle,session.power,session.selected_mode,session.item,session.turn,session.fighters[session.turn].pos]
		if session.human_turn() and key != last_preview_key:
			prediction = session.trace().points
			last_preview_key = key
		refresh_live()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	if event.keycode == KEY_ESCAPE and event.pressed:
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if not session.human_turn():
		return
	if event.keycode == KEY_SPACE:
		if event.pressed: session.start_charge()
		else: try_release_charge()
		get_viewport().set_input_as_handled()
	elif event.pressed:
		match event.keycode:
			KEY_ENTER: try_fire()
			KEY_Z: choose_mode("light")
			KEY_X: choose_mode("normal")
			KEY_C: choose_mode("heavy")
			KEY_1: choose_item("none")
			KEY_2: choose_item("amp")
			KEY_3: choose_item("rapid")
			KEY_4: choose_item("tracker")
			KEY_H: try_heal()
			KEY_R: toggle_rage()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null and session.phase != BattleSession.Phase.COMPLETE:
		set_paused(true)

func create_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Styles.theme()
	add_child(ui)
	Styles.panel(ui,Rect2(20,18,365,86))
	Styles.panel(ui,Rect2(895,18,365,86))
	Styles.panel(ui,Rect2(458,18,364,86),Color("123637ee"),Color("6e8b71"))
	for i in range(2):
		var x := 36.0 if i == 0 else 911.0
		var enemy_boss_portrait: Texture2D = moss_guardian if session.mechanism == "moss_guardian" else furnace_guardian if session.mechanism == "furnace" else storm_lord if session.mechanism == "storm_lord" else null
		if i == 1 and enemy_boss_portrait != null:
			var boss_portrait := TextureRect.new()
			boss_portrait.texture = enemy_boss_portrait
			boss_portrait.position = Vector2(x, 22)
			boss_portrait.size = Vector2(68, 72)
			boss_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			boss_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			boss_portrait.clip_contents = true
			boss_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ui.add_child(boss_portrait)
			boss_portrait.set_deferred("size", Vector2(68, 72))
		else:
			Styles.portrait(ui,i*2+(1 if session.fighters[i].weapon=="volt" else 0),Rect2(x,22,68,72))
		labels["name%d"%i] = Styles.label(ui,session.fighters[i].name,Rect2(x+74,29,200,25),19)
		var bar := ProgressBar.new()
		bar.position = Vector2(x+74,64)
		bar.size = Vector2(218,10)
		bar.max_value = session.fighters[i].max_hp
		bar.show_percentage = false
		var fill := Styles.box(Color("77d4c1") if i==0 else Color("ec977e"),Color.TRANSPARENT,4,0)
		fill.content_margin_top = 0
		fill.content_margin_bottom = 0
		bar.add_theme_stylebox_override("fill",fill)
		ui.add_child(bar)
		bar.set_deferred("size",Vector2(218,10))
		hp_bars.append(bar)
		labels["hp%d"%i] = Styles.label(ui,"",Rect2(x+74,78,220,18),12,Styles.MUTED)
	labels.turn = Styles.label(ui,"",Rect2(474,28,170,22),14,Styles.GOLD)
	labels.wind = Styles.label(ui,"",Rect2(474,56,192,32),23)
	labels.timer = Styles.label(ui,"25",Rect2(709,30,91,56),36,Styles.GOLD)
	Styles.button(ui,"II",Rect2(840,25,42,38),toggle_pause)
	labels.notice = Styles.label(ui,"",Rect2(270,118,740,34),18)
	labels.notice.add_theme_stylebox_override("normal", Styles.painted_box("banner", 8))
	labels.notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.notice.add_theme_color_override("font_shadow_color",Color("12322e"))
	labels.notice.add_theme_constant_override("shadow_outline_size",4)
	labels.mechanic = Styles.label(ui,"",Rect2(360,151,560,26),15,Styles.GOLD)
	labels.mechanic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.mechanic.add_theme_stylebox_override("normal", Styles.painted_box("secondary", 8))
	labels.mechanic.add_theme_color_override("font_shadow_color", Color("06191d"))
	labels.mechanic.add_theme_constant_override("shadow_outline_size", 2)
	Styles.panel(ui,Rect2(16,568,1248,138),Color("102e34f5"),Color("657c66"),18)
	labels.resources = Styles.label(ui,"",Rect2(36,582,250,25),14,Styles.TEAL)
	labels.last = Styles.label(ui,"",Rect2(36,613,250,22),13,Styles.MUTED)
	Styles.label(ui,"A / D 移动   ·   Q / E 角度",Rect2(36,645,260,22),13,Styles.MUTED)
	Styles.label(ui,"空格蓄力 / 松开发射",Rect2(36,671,260,20),13,Styles.GOLD)
	labels.angle = Styles.label(ui,"",Rect2(302,581,230,25),17)
	labels.power = Styles.label(ui,"",Rect2(302,637,230,25),17,Styles.GOLD)
	angle_slider = make_slider(Rect2(304,609,230,18),10,85,on_angle_slider)
	power_slider = make_slider(Rect2(304,666,230,18),0,100,on_power_slider)
	var index := 0
	for key in GameData.MODES:
		var k: String = key
		buttons[k] = Styles.button(ui,GameData.MODES[k].name,Rect2(557+index*80,581,72,35),func(): choose_mode(k))
		index += 1
	index = 0
	for key in GameData.ITEMS:
		var k: String = key
		buttons[k] = Styles.button(ui,GameData.ITEMS[k].name,Rect2(557+index*80,628,72,35),func(): choose_item(k))
		buttons[k].tooltip_text = "%s · 体力 %d · 伤害 ×%.2f" % [GameData.ITEMS[k].name,GameData.ITEMS[k].cost,GameData.ITEMS[k].damage]
		index += 1
	labels.cost = Styles.label(ui,"",Rect2(557,672,330,21),12,Styles.MUTED)
	buttons.heal = Styles.button(ui,"治疗",Rect2(886,581,94,37),try_heal)
	buttons.drink = Styles.button(ui,"饮剂",Rect2(886,628,94,34),func(): try_supply("stamina_tonic"))
	buttons.rage = Styles.button(ui,"怒气",Rect2(886,667,94,32),toggle_rage)
	buttons.armor_breaker = Styles.button(ui,"破甲",Rect2(1000,665,110,30),func(): try_supply("armor_breaker"))
	buttons.fire = Styles.button(ui,"发 射  →",Rect2(1000,587,242, 70),func():
		if session.human_turn(): try_fire(),true)
	buttons.fire.add_theme_font_size_override("font_size",25)
	# The hint belongs inside the fire control's lower third, leaving the
	# independent armor-breaker action unobscured on the row below.
	labels.fire_hint = Styles.label(ui,"也可按 Enter 立即发射",Rect2(1000,632,242,20),12,Styles.MUTED)
	labels.fire_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.fire_hint.visible = false
	# Sliders and action buttons must not swallow the Space release event.
	for child in ui.get_children():
		if child is BaseButton or child is Slider:
			child.focus_mode = Control.FOCUS_NONE


func make_slider(rect: Rect2, minimum: float, maximum: float, callback: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.position = rect.position
	slider.size = rect.size
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1.0
	slider.value_changed.connect(callback)
	ui.add_child(slider)
	return slider

func play_sound(key: String) -> void:
	if sound: sound.play(key)

func adjust_angle(delta: float) -> void:
	var before := session.angle
	session.angle = clampf(session.angle + delta, 10.0, 85.0)
	if not is_equal_approx(before, session.angle) and clock - last_adjust_sound >= 0.08:
		last_adjust_sound = clock
		play_sound("slider")

func adjust_power(delta: float) -> void:
	var before := session.power
	session.power = clampf(session.power + delta, 0.0, 100.0)
	if not is_equal_approx(before, session.power) and clock - last_adjust_sound >= 0.08:
		last_adjust_sound = clock
		play_sound("slider")

func on_angle_slider(value: float) -> void:
	if session.human_turn() and not is_equal_approx(session.angle, value):
		session.angle = value
		play_sound("slider")

func on_power_slider(value: float) -> void:
	if session.human_turn() and not is_equal_approx(session.power, value):
		session.power = value
		play_sound("slider")

func choose_mode(value: String) -> void:
	var previous := session.selected_mode
	session.select_mode(value)
	if session.selected_mode != previous: play_sound("select")

func choose_item(value: String) -> void:
	var previous := session.item
	session.select_item(value)
	if session.item != previous: play_sound("select")

func try_fire() -> void:
	if not session.fire(): play_sound("error")

func try_heal() -> void:
	if not session.heal(): play_sound("error")

func try_supply(item_id: String) -> void:
	if not session.use_supply(item_id): play_sound("error")

func try_release_charge() -> void:
	if session.charging and session.human_turn(): session.release_charge()

func refresh_live() -> void:
	if labels.is_empty(): return
	var remaining := maxi(0, int(ceil(session.time_left)))
	labels.timer.text = "%02d" % remaining if session.phase==BattleSession.Phase.AIM else "···"
	labels.timer.modulate = Color("ff997d") if session.time_left<6 else Color.WHITE
	if session.human_turn() and session.phase == BattleSession.Phase.AIM and remaining > 0 and remaining <= 5:
		if low_time_warning_turn != session.turn or low_time_warning_second != remaining:
			low_time_warning_turn = session.turn
			low_time_warning_second = remaining
			play_sound("warning")
	labels.angle.text = "角度   %02d°" % session.angle
	labels.power.text = "力度   %02d / 100" % session.power
	angle_slider.set_value_no_signal(session.angle)
	power_slider.set_value_no_signal(session.power)
	labels.notice.text = session.notice
	labels.mechanic.text = mechanism_text()

func mechanism_text() -> String:
	var armor_text := ""
	if session.armor_breaker_armed:
		armor_text = " · 破甲已装填：下一发命中触发"
	elif session.armor_breaker_pending:
		armor_text = " · 破甲待命：本批命中触发"
	elif session.armor_breaker_hits > 0:
		armor_text = " · 敌方破甲剩余有效受击 %d" % session.armor_breaker_hits
	if session.mechanism == "spore":
		if not session.pending_hazard.is_empty(): return ("孢子预告：下次敌方行动开始结算 %s 伤害" % compact_power(int(session.pending_hazard.get("damage", hazard_damage("spore", 60))))) + armor_text
		return "孢子回廊：每两次敌方行动结束预告一次危险区" + armor_text
	if session.mechanism == "moss_guardian":
		return "苔甲守卫 · %s · 朝向已锁定 %s%s" % ["防御：正面直击 50%" if session.boss_state == "defense" else "疲惫：正常受伤", "←" if session.boss_locked_facing < 0 else "→", armor_text]
	if session.mechanism == "furnace":
		return "熔炉热量 %d / 100%s%s" % [session.furnace_heat, " · 轰击预警：下次敌方行动开始" if not session.pending_hazard.is_empty() else "", armor_text]
	if session.mechanism == "sky_corridor": return "逆风长廊：当前 / 下一行动风力已预报%s" % armor_text
	if session.mechanism == "sky_altar": return "风暴祭坛：左右符文交替预警 · 命中 %s%s" % [compact_power(int(session.pending_hazard.get("damage", hazard_damage("altar", 80)))), armor_text]
	if session.mechanism == "storm_lord":
		var shield := "风盾减伤 35%" if session.boss_state == "wind_shield" else "暴露：正常受伤" if not session.storm_phase_two else "第二阶段：每次敌方结束预警区域"
		return "风暴领主 · %s%s" % [shield, armor_text]
	if session.stage_id == "forest_treebridge": return "树桥试炼：温和风力 · 宽阔桥面" + armor_text
	return armor_text.trim_prefix(" · ")

func hazard_damage(kind: String, fallback: int) -> int:
	var hazards: Dictionary = session.stage_snapshot.get("hazards", {})
	return int(round(float(hazards.get(kind, fallback))))

func refresh() -> void:
	if ui == null: return
	last_preview_key = ""
	var actor: Dictionary = session.fighters[session.turn]
	var enabled := session.human_turn()
	for i in range(2):
		hp_bars[i].value = session.fighters[i].hp
		hp_bars[i].max_value = session.fighters[i].max_hp
		var fighter: Dictionary = session.fighters[i]
		var power_text := " · 战力 %s" % compact_power(int(fighter.get("power", 0))) if session.power_campaign else ""
		labels["hp%d"%i].text = "%d / %d   ·   %s%s" % [fighter.hp,fighter.max_hp,GameData.WEAPONS[fighter.weapon].name,power_text]
		labels["name%d"%i].modulate = Styles.GOLD if session.turn==i else Color.WHITE
	labels.turn.text = "第 %02d / 30 回合  ·  %s" % [session.round_number,"你的回合" if session.turn==0 else "对方回合"]
	var next_wind := session.forecast_wind()
	labels.wind.text = "%s %.1f  →  %s %.1f" % ["→" if session.wind >= 0 else "←", absf(session.wind), "→" if next_wind >= 0 else "←", absf(next_wind)] if session.mechanism == "sky_corridor" else "%s  风力 %.1f" % ["→" if session.wind >= 0 else "←",absf(session.wind)]
	labels.resources.text = "体力 %d / %d    怒气 %d%%" % [actor.stamina,actor.max_stamina,actor.rage]
	var last: Dictionary = session.last_shot[session.turn]
	labels.last.text = "上次射击   %d° / %d 力度" % [last.angle,last.power] if last.power>0 else "首发：观察风向与地形"
	for key in buttons:
		buttons[key].disabled = not enabled
	for key in GameData.MODES:
		buttons[key].modulate = Styles.GOLD if key==session.selected_mode else Color.WHITE
	for key in GameData.ITEMS:
		buttons[key].modulate = Styles.GOLD if key==session.item else Color.WHITE
		if key != "none":
			buttons[key].text = "%s %d" % [GameData.ITEMS[key].name,actor.charges[key]]
			buttons[key].disabled = not enabled or int(actor.charges[key])==0
	if session.campaign_battle:
		buttons.heal.text = "急救 %d" % int(session.supplies.get("small_medkit", 0))
		var heal_amount := int(round(actor.max_hp * 0.25))
		buttons.heal.tooltip_text = "恢复最大生命的 25%%（本局最多 %d）；仅本次行动一次，保存成功后生效" % heal_amount if session.power_campaign else "恢复最多 250 生命；仅本次行动一次，保存成功后生效"
		buttons.heal.disabled = not enabled or actor.hp>=actor.max_hp or session.supply_used_this_action or int(session.supplies.get("small_medkit", 0))<=0
		buttons.drink.visible = true
		buttons.drink.text = "饮剂 %d" % int(session.supplies.get("stamina_tonic", 0))
		buttons.drink.tooltip_text = "恢复最多 25 体力；仅本次行动一次，保存成功后生效"
		buttons.drink.disabled = not enabled or actor.stamina>=actor.max_stamina or session.supply_used_this_action or int(session.supplies.get("stamina_tonic", 0))<=0
		buttons.armor_breaker.visible = true
		buttons.armor_breaker.text = "破甲%s %d" % ["已装填" if session.armor_breaker_armed else "", int(session.supplies.get("armor_breaker", 0))]
		buttons.armor_breaker.tooltip_text = "命中后使目标常驻减伤减半，持续后续两次受击。" if session.power_campaign else "命中后使目标固定护甲减半，持续后续两次受击。"
		buttons.armor_breaker.disabled = not enabled or session.supply_used_this_action or session.armor_breaker_armed or int(session.supplies.get("armor_breaker", 0)) <= 0
	else:
		buttons.heal.text = "治疗 %d" % actor.charges.heal
		buttons.heal.tooltip_text = "恢复 250 生命 · 消耗 30 体力 · 满生命时不可用"
		buttons.heal.disabled = not enabled or actor.hp>=actor.max_hp or actor.stamina<30 or int(actor.charges.heal)==0
		buttons.drink.visible = false
		buttons.armor_breaker.visible = false
	buttons.rage.text = "爆发已就绪" if actor.rage>=100 else "怒气 %d%%"%actor.rage
	buttons.rage.disabled = not enabled or actor.rage<100
	buttons.rage.tooltip_text = "怒气满 100 可激活 · 下一发伤害 ×1.8"
	buttons.rage.modulate = Styles.GOLD if session.rage else Color.WHITE
	var cost: float = GameData.MODES[session.selected_mode].cost+GameData.ITEMS[session.item].cost
	labels.cost.text = "消耗 %d 体力   ·   %s" % [cost,"训练：完整弹道" if session.mode=="training" else "追踪弹后半程制导" if session.item=="tracker" else "W / S 微调力度"]
	buttons.fire.disabled = not enabled or actor.stamina<cost or (session.item!="none" and int(actor.charges[session.item])==0)
	buttons.fire.text = "发 射  →" if enabled else "等待对方" if session.phase==BattleSession.Phase.AIM else "弹道结算中"
	angle_slider.editable = enabled and not session.charging
	power_slider.editable = enabled and not session.charging
	refresh_live()

func compact_power(value: int) -> String:
	if value >= 10000:
		return ("%.1f万" % (float(value) / 10000.0)).replace(".0万", "万")
	return str(maxi(0, value))

func toggle_rage() -> void:
	if session.human_turn() and session.fighters[session.turn].rage>=100:
		session.rage = not session.rage
		play_sound("power")
		refresh()

func toggle_pause() -> void:
	set_paused(not session.paused)

func set_paused(value: bool) -> void:
	if session.phase==BattleSession.Phase.COMPLETE: return
	var was_charging := session.charging
	if value and was_charging: play_sound("charge_cancel")
	if value: play_sound("pause")
	session.paused = value
	session.charging = false
	if sound: sound.set_paused(value)
	if not value: play_sound("resume")
	if is_instance_valid(pause_layer):
		pause_layer.queue_free()
		pause_layer = null
	if value:
		pause_layer = Control.new()
		pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
		ui.add_child(pause_layer)
		Styles.panel(pause_layer,Rect2(0,0,1280,720),Color("09242ad9"),Color.TRANSPARENT,0)
		Styles.panel(pause_layer,Rect2(420,144,440,455))
		Styles.label(pause_layer,"休息一下",Rect2(462,177,350,50),32)
		Styles.label(pause_layer,"战斗和倒计时已暂停",Rect2(462,256,350,28),16,Styles.MUTED)
		Styles.button(pause_layer,"继续对战",Rect2(462,304,356,48),func(): set_paused(false),true)
		Styles.button(pause_layer,"重新挑战",Rect2(462,365,356,48),restart_battle)
		Styles.button(pause_layer,"返回风铃港",Rect2(462,426,356,48),leave_battle)
		Styles.label(pause_layer,"中途退出不结算奖励",Rect2(462,561,356,26),13,Styles.MUTED)
		if sound:
			Styles.label(pause_layer,"音效",Rect2(462,496,80,25),14,Styles.MUTED)
			var slider := HSlider.new()
			slider.position=Vector2(539,501)
			slider.size=Vector2(279,19)
			slider.max_value=1.0
			slider.step=0.01
			slider.value=sound.sfx_volume
			slider.value_changed.connect(func(v): sound.volumes(sound.music_volume, v); play_sound("slider"))
			pause_layer.add_child(slider)
	refresh()

func leave_battle() -> void:
	if session.paused: set_paused(false)
	leave_requested.emit()

func restart_battle() -> void:
	if session.paused: set_paused(false)
	restart_requested.emit()

func on_feedback(kind: String, pos: Vector2, value: float) -> void:
	var audio_key: String = str({"turn":"turn", "fire":"fire", "explosion":"explosion", "damage":"damage", "heal":"heal", "stamina":"heal", "hazard":"hazard", "guard":"power", "armor_break":"power", "phase":"power", "charge":"charge", "charge_cancel":"charge_cancel", "warning":"warning"}.get(kind, ""))
	if not audio_key.is_empty(): play_sound(audio_key)
	if kind == "fire" and value > 0.0: play_sound("power")
	if kind == "fire": recoil[session.turn] = 1.0
	if kind == "damage":
		shake = 4.0
		for i in range(2):
			if session.fighters[i].pos.distance_to(pos)<10: hit_flash[i] = 1.0
	if kind == "explosion": shake = maxf(shake,3.0)
	if kind in ["damage","heal","explosion","fire","hazard","guard","stamina"]:
		effects.append({"kind":kind,"pos":pos,"value":value,"age":0.0,"life":1.2 if kind in ["damage","heal"] else 0.55})

func _draw() -> void:
	if session == null or background == null: return
	draw_texture_rect(background,Rect2(0,0,1280,720),false)
	# Atmospheric motes stay decorative and do not affect collision.
	for i in range(24):
		var x := fmod(i*97.0+clock*(4.0+i%3),1280.0)
		var y := 155.0+fmod(i*37.0+sin(clock*0.5+i)*12.0,330.0)
		draw_circle(Vector2(x,y),1.5,Color(1.0,0.91,0.58,0.22+0.13*sin(clock+i)))
	draw_set_transform(Vector2(sin(clock*93.0)*shake,cos(clock*81.0)*shake))
	draw_terrain()
	draw_mechanism_overlay()
	if session.human_turn():
		var limit := prediction.size() if session.mode=="training" else mini(prediction.size(),22)
		for i in range(1,limit):
			if prediction[i].y > 110.0 and i%2==0:
				draw_circle(prediction[i],3.4,Color(0.07,0.2,0.15,0.65))
				draw_circle(prediction[i],2.0,Color(1,0.91,0.59,0.9*(1.0-float(i)/maxf(limit,1))))
		if session.mode=="training" and prediction.size()>1:
			draw_arc(prediction[-1],12,0,TAU,32,Styles.GOLD,2.0,true)
	for i in range(2): draw_fighter(i)
	for shot in session.shots:
		for j in range(1,shot.trail.size()):
			draw_line(shot.trail[j-1],shot.trail[j],Color(1,0.75,0.3,float(j)/32.0),3.0,true)
		draw_circle(shot.pos,10.0,Color(1,0.7,0.2,0.18))
		draw_circle(shot.pos,4.5,Color("ffe9a6"))
		if shot.pos.y<110:
			draw_string(font,Vector2(clampf(shot.pos.x,100,1170),122),"↑",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Styles.GOLD)
	for effect in effects: draw_effect(effect)
	draw_set_transform(Vector2.ZERO)

func draw_terrain() -> void:
	var mine := session.stage_id.begins_with("mine_")
	var sky := session.stage_id.begins_with("sky_")
	var fill := Color("6d4938") if mine else Color("77776e") if sky else Color("aaa383")
	var edge := Color("71402b") if mine else Color("4c5965") if sky else Color("284c34")
	var grass := Color("c78342") if mine else Color("9a9c91") if sky else Color("8ba74b")
	var polygon := PackedVector2Array([Vector2(0,720)])
	for i in range(session.heights.size()): polygon.append(Vector2(i*Ballistics.STEP,session.heights[i]))
	polygon.append(Vector2(1280,720))
	var uv := PackedVector2Array()
	for point in polygon: uv.append(point/420.0)
	draw_polygon(polygon,PackedColorArray([fill]),uv,soil)
	for i in range(session.heights.size()-1):
		var a := Vector2(i*Ballistics.STEP,session.heights[i])
		var b := Vector2((i+1)*Ballistics.STEP,session.heights[i+1])
		draw_line(a,b,edge,12.0,true)
		draw_line(a-Vector2(0,2),b-Vector2(0,2),grass,5.0,true)
		if i%4==0:
			if mine:
				draw_colored_polygon(PackedVector2Array([a+Vector2(-7,-3),a+Vector2(-1,-11),a+Vector2(6,-4),a+Vector2(2,1)]),Color("b86d35"))
				draw_circle(a+Vector2(9,-12),1.8,Color("f4a54f"))
			elif sky:
				draw_line(a + Vector2(-4,-7),a + Vector2(4,-7),Color("c5c6bd"),2.0,true)
			else:
				draw_line(a,a+Vector2(-4,-9),Color("91ac50"),2.0,true)
				draw_line(a,a+Vector2(4,-7),Color("a8bc5c"),2.0,true)

func draw_mechanism_overlay() -> void:
	if not session.pending_hazard.is_empty():
		var hazard := session.pending_hazard
		var centre := Vector2(float(hazard.x), Ballistics.height_at(session.heights, float(hazard.x)) - 7.0)
		var radius := float(hazard.radius)
		var hazard_kind := str(hazard.get("kind", ""))
		var warning := Color("f19b58") if hazard_kind == "furnace" else Color("72d7e6") if hazard_kind == "storm" else Color("e8a8e9")
		draw_circle(centre, radius, Color(warning, 0.16))
		draw_arc(centre, radius, 0, TAU, 40, warning, 2.0, true)
		for i in range(8):
			var puff := centre + Vector2.from_angle(clock * 1.5 + i * TAU / 8.0) * (radius * 0.58)
			if hazard_kind == "furnace":
				draw_circle(puff, 3.0 + sin(clock * 3.0 + i), Color("f6a54a"))
			else:
				draw_circle(puff, 7.0 + sin(clock * 3.0 + i) * 2.0, Color(0.83,0.53,0.88,0.5))

func draw_fighter(index: int) -> void:
	var fighter: Dictionary = session.fighters[index]
	var feet: Vector2 = fighter.pos+Vector2(0,Ballistics.RADIUS)
	draw_set_transform(feet)
	draw_set_transform(feet,0.0,Vector2(1,0.28))
	draw_circle(Vector2.ZERO,32.0,Color(0.03,0.08,0.05,0.45))
	var bounce := absf(sin(clock*12.0))*3.5 if moving and index==session.turn else sin(clock*2.4+index)*1.2
	var lean := -float(recoil[index])*0.15*float(fighter.facing)
	if fighter.hp<=0: lean += 0.5*float(fighter.facing)
	var cell := heroes.get_size()/2.0
	var column := 1 if fighter.weapon=="volt" else 0
	draw_set_transform(feet+Vector2(-float(recoil[index])*8.0*fighter.facing,-bounce),lean,Vector2(fighter.facing,1))
	var tint := Color(1.4,0.7,0.6) if hit_flash[index]>0 else Color.WHITE
	if index == 1 and session.mechanism == "moss_guardian": tint = Color("b7d57f") if session.boss_state == "defense" else Color("d9bd72")
	if index == 1 and session.mechanism == "storm_lord": tint = Color("a5d8e4") if session.boss_state == "wind_shield" else Color.WHITE
	if index == 1 and session.mechanism == "moss_guardian" and moss_guardian != null:
		draw_texture_rect(moss_guardian, Rect2(-90,-173,180,180), false, tint)
	elif index == 1 and session.mechanism == "furnace" and furnace_guardian != null:
		draw_texture_rect(furnace_guardian, Rect2(-90,-173,180,180), false, tint)
	elif index == 1 and session.mechanism == "storm_lord" and storm_lord != null:
		draw_texture_rect(storm_lord, Rect2(-90,-173,180,180), false, tint)
	else:
		draw_texture_rect_region(heroes,Rect2(-64,-124,128,128),Rect2(Vector2(column,index)*cell,cell),tint)
	draw_set_transform(Vector2.ZERO)
	if session.turn==index and session.phase==BattleSession.Phase.AIM:
		var p := feet+Vector2(0,-139+sin(clock*4.0)*3.0)
		draw_colored_polygon(PackedVector2Array([p+Vector2(-6,-7),p+Vector2(6,-7),p+Vector2(0,2)]),Styles.GOLD)
		draw_arc(fighter.pos,42,-deg_to_rad(session.angle)-0.2,-deg_to_rad(session.angle)+0.2,12,Styles.GOLD,2.0,true)
	var bar := Rect2(feet+Vector2(-34,-132),Vector2(68,5))
	draw_style_box(Styles.box(Color("163b39"),Color.TRANSPARENT,2),bar)
	draw_style_box(Styles.box(Styles.TEAL if index==0 else Color("ed9b78"),Color.TRANSPARENT,2),Rect2(bar.position,Vector2(68.0*fighter.hp/fighter.max_hp,5)))
	if index == 1 and session.mechanism == "moss_guardian":
		var status := "防御" if session.boss_state == "defense" else "疲惫"
		draw_string_outline(font, fighter.pos + Vector2(-34,-151), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color("102d29"))
		draw_string(font, fighter.pos + Vector2(-34,-151), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Styles.GOLD if session.boss_state == "fatigue" else Color("b9e477"))
	if index == 1 and session.mechanism == "storm_lord":
		var storm_status := "二阶段" if session.storm_phase_two else "风盾" if session.boss_state == "wind_shield" else "暴露"
		draw_string_outline(font, fighter.pos + Vector2(-34,-151), storm_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 3, Color("102d29"))
		draw_string(font, fighter.pos + Vector2(-34,-151), storm_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Styles.GOLD if session.storm_phase_two else Color("86dce7"))

func draw_effect(effect: Dictionary) -> void:
	var t: float = effect.age/effect.life
	var alpha := 1.0-t
	if effect.kind in ["damage","heal"]:
		var text := ("+" if effect.kind=="heal" else "−")+str(int(round(effect.value)))
		draw_string_outline(font,effect.pos+Vector2(-27,-75-t*36),text,HORIZONTAL_ALIGNMENT_LEFT,-1,26,4,Color(0.05,0.16,0.14,alpha))
		draw_string(font,effect.pos+Vector2(-27,-75-t*36),text,HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color(0.5,1,0.75,alpha) if effect.kind=="heal" else Color(1,0.91,0.61,alpha))
	else:
		var radius: float = effect.value if effect.kind=="explosion" else 22.0
		draw_circle(effect.pos,radius*t,Color(1,0.73,0.24,alpha*0.25))
		draw_arc(effect.pos,maxf(1.0,radius*t),0,TAU,36,Color(1,0.91,0.59,alpha),3.0,true)
		for i in range(10):
			var direction := Vector2.from_angle(i*TAU/10.0)
			draw_circle(effect.pos+direction*radius*t,3.0*alpha,Color(1,0.8,0.34,alpha))
