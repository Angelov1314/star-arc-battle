extends Control

var profile: PlayerProfile
var profile_path := "user://profile.json"
var inventory: InventoryService
var campaign: CampaignService
var forge: ForgeService
var audio: GameAudio
var screen: Control
var battle: BattleView
var modal: Control
var current_page := "town"
var selected_weapon := "ember"
var selected_charm := "feather"
var battle_mode := "ai"
var last_result := {}
var town_badges: Array[Control] = []
var elapsed := 0.0
var toast_label: Label
var tutorial_hint_label: Label
var toast_timer := 0.0
var selected_stage_id := "forest_treebridge"
var selected_chapter := 1
var selected_difficulty := "normal"
var active_campaign_run: Dictionary = {}
var inventory_category := "all"
var inventory_sort := "quality"
var inventory_source := "all"
var inventory_search := ""
var inventory_page := 0
var selected_instance_id := "legacy-weapon-ember"
var selected_item_id := "ember"
var batch_selected: Array[String] = []
var craft_quantities := {"small_medkit":1,"stamina_tonic":1,"armor_breaker":1}
var craft_busy := false
var workshop_instance_id := ""
var workshop_tab := "upgrade"
var dismantle_busy := false
var workshop_list_page := 0
var result_audio_ledger: Dictionary = {}

func _ready() -> void:
	get_tree().auto_accept_quit = false
	theme = Styles.theme()
	if profile == null: profile = PlayerProfile.new(profile_path)
	inventory = InventoryService.new(profile)
	campaign = CampaignService.new(profile)
	forge = ForgeService.new(profile)
	if not profile.data.active_run.is_empty():
		var abandoned := campaign.abandon_run(str(profile.data.active_run.run_id))
		if not abandoned.ok: profile.notice = "上一局已中断，暂时无法保存放弃状态：" + str(abandoned.message)
	audio = GameAudio.new()
	add_child(audio)
	Styles.click_sound = audio.play.bind("click")
	Styles.hover_sound = audio.play.bind("hover")
	audio.volumes(profile.data.music,profile.data.sfx)
	audio.set_context("town")
	show_town()
	if not profile.notice.is_empty(): toast(profile.notice)

func _process(dt: float) -> void:
	elapsed += dt
	if toast_timer>0:
		toast_timer -= dt
		if toast_timer<=0 and is_instance_valid(toast_label): toast_label.queue_free()
	for i in range(town_badges.size()):
		if is_instance_valid(town_badges[i]):
			town_badges[i].position.y = float(town_badges[i].get_meta("base_y"))+sin(elapsed*1.7+i)*2.0

func clear_screen(page: String) -> void:
	current_page = page
	if audio:
		audio.set_context("battle" if page == "battle" else "town")
		if page != "battle": audio.volumes(profile.data.music, profile.data.sfx)
	if is_instance_valid(tutorial_hint_label): tutorial_hint_label.queue_free()
	tutorial_hint_label = null
	town_badges.clear()
	battle = null
	modal = null
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)

func backplate(title: String, subtitle: String) -> void:
	Styles.image(screen,"res://assets/art/town.png",Rect2(0,0,1280,720),Color("647b75"))
	Styles.panel(screen,Rect2(0,0,1280,720),Color("0c3037b0"),Color.TRANSPARENT,0)
	Styles.button(screen,"←  风铃港",Rect2(30,28,135,43),show_town)
	Styles.banner(screen,title,Rect2(196,20,600,58),30)
	Styles.label(screen,subtitle,Rect2(198,78,800,30),15,Styles.MUTED)
	currency(screen)

func currency(parent: Node) -> void:
	Styles.panel(parent,Rect2(928,26,320,48),Color("153d40ed"),Color("9c9970"),24)
	Styles.label(parent,"金币  %04d"%profile.data.gold,Rect2(950,36,160,25),18,Styles.GOLD)
	var growth := growth_progress()
	Styles.label(parent,"Lv. %02d" % int(growth.get("level", 1)),Rect2(1150,36,90,25),18)

func growth_progress() -> Dictionary:
	return profile.growth_progress() if profile.has_method("growth_progress") else {"level":1,"exp":0,"current":0,"required":120,"max_level":60}

func campaign_snapshot(overrides: Dictionary = {}) -> Dictionary:
	if profile.has_method("preview_combat_snapshot"):
		return profile.preview_combat_snapshot(overrides)
	return profile.combat_snapshot() if profile.has_method("combat_snapshot") else {"weapon":profile.data.weapon,"charm":profile.data.charm,"level":profile.data.levels[profile.data.weapon],"max_hp":1000,"direct_hit_bonus":0,"power":1000}

func find_equipment_instance(template_id: String, category: String) -> String:
	for instance_id in profile.data.inventory.equipment:
		if str(profile.data.inventory.equipment[instance_id].get("template_id", "")) == template_id and str(ItemData.definition(template_id).get("category", "")) == category: return str(instance_id)
	return str(profile.data.loadout.weapon_instance_id if category == "weapon" else profile.data.loadout.charm_instance_id)

func number_text(value: Variant) -> String:
	var amount := int(round(float(value)))
	if abs(amount) < 10000: return str(amount)
	var compact := float(amount) / 10000.0
	return ("%.1f万" % compact).replace(".0万", "万")

func snapshot_detail(snapshot: Dictionary) -> String:
	return "攻击 %s · 生命 %s · 减伤 %.0f%% · 战力 %s" % [number_text(snapshot.get("base_attack", 0)), number_text(snapshot.get("max_hp", 0)), float(snapshot.get("damage_reduction", 0.0)) * 100.0, number_text(snapshot.get("power", 0))]

func power_delta(before: Dictionary, after: Dictionary) -> String:
	var direct_before := float(before.get("base_attack", 0)) + float(before.get("direct_hit_bonus", 0))
	var direct_after := float(after.get("base_attack", 0)) + float(after.get("direct_hit_bonus", 0))
	return "标准直击 %+d · 生命 %+d · 减伤 %+.0f%% · 战力 %+d" % [int(round(direct_after - direct_before)), int(round(float(after.get("max_hp", 0)) - float(before.get("max_hp", 0)))), int(round((float(after.get("damage_reduction", 0.0)) - float(before.get("damage_reduction", 0.0))) * 100.0)), int(round(float(after.get("power", 0)) - float(before.get("power", 0))))]

func play_result_audio_once(result_id: String, winner: int, saved_reward: bool, leveled_up: bool = false) -> void:
	if result_id.is_empty() or result_audio_ledger.has(result_id): return
	result_audio_ledger[result_id] = true
	if saved_reward: audio.play("reward")
	if winner == 0: audio.play("win")
	elif winner == 1: audio.play("lose")
	else: audio.play("turn")
	if leveled_up: audio.play("level_up")

func show_town() -> void:
	clear_screen("town")
	Styles.image(screen,"res://assets/art/town.png",Rect2(0,0,1280,720))
	Styles.panel(screen,Rect2(24,23,365,119),Color("153d40e8"),Color("9aab80"),20)
	Styles.label(screen,"S T A R   A R C",Rect2(48,35,310,24),13,Styles.GOLD)
	Styles.label(screen,"星轨弹斗",Rect2(45,59,310,56), 42)
	Styles.label(screen,"风铃港  /  一场新的冒险",Rect2(49,114,300,20),13,Styles.MUTED)
	currency(screen)
	Styles.button(screen,"设置",Rect2(1118,91,130,38),show_settings)
	Styles.button(screen,"玩法指南",Rect2(974,91,130,38),show_help)
	building(Rect2(172,268,284,226),Vector2(222,485),"角色小屋","配装与属性",show_character)
	building(Rect2(471,175,330,226),Vector2(538,395),"竞技场","林间栈桥 · 1v1",show_lobby,true)
	building(Rect2(836,285,279,242),Vector2(898,515),"背包工坊","补给、掉落与强化",show_inventory)
	Styles.button(screen,"远征板",Rect2(760,91,130,38),show_expedition)
	Styles.panel(screen,Rect2(24,613,1232,83),Color("143b3df2"),Color("829777"),18)
	Styles.label(screen,"今日 · 风轻云暖",Rect2(46,627,285,29),20)
	var growth := growth_progress()
	var current_snapshot := campaign_snapshot()
	var growth_text := "已满级" if int(growth.get("level", 1)) >= int(growth.get("max_level", 60)) else "成长经验 %d / %d" % [int(growth.get("current", 0)),int(growth.get("required", 0))]
	Styles.label(screen,"Lv.%d  %s  ·  战力 %s" % [int(growth.get("level", 1)),growth_text,number_text(current_snapshot.get("power", 0))],Rect2(46,662,580,21),14,Styles.GOLD)
	var town_power := Styles.label(screen,"%s +%d  /  %s" % [GameData.WEAPONS[profile.data.weapon].name,profile.data.levels[profile.data.weapon],GameData.CHARMS[profile.data.charm].name],Rect2(594,641,320,25),15,Styles.GOLD)
	town_power.tooltip_text = snapshot_detail(current_snapshot) + "\n战力不含瞄准、范围、体力和临时增益。"
	Styles.button(screen,"踏入林间遗迹   →",Rect2(966,629,268,51),show_expedition,true)


func building(hit: Rect2, badge_pos: Vector2, title: String, subtitle: String, callback: Callable, primary: bool = false) -> void:
	var hotspot := Styles.button(screen,"",hit,callback)
	hotspot.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	hotspot.add_theme_stylebox_override("hover",Styles.box(Color(1.0,0.85,0.5,0.06),Color(1,0.9,0.6,0.55),28,2))
	hotspot.add_theme_stylebox_override("pressed",Styles.box(Color(1,1,1,0.12),Styles.GOLD,28))
	hotspot.tooltip_text = title+" · "+subtitle
	var group := Control.new()
	group.position = badge_pos
	group.set_meta("base_y",badge_pos.y)
	screen.add_child(group)
	town_badges.append(group)
	var button := Styles.banner_button(group,title,Rect2(0,0,195,46),callback)
	button.add_theme_font_size_override("font_size",21)
	button.tooltip_text = title + " · " + subtitle
	var caption := Styles.label(group,subtitle,Rect2(-28,49,252,23),13,Styles.CREAM)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_shadow_color",Color("153d40"))
	caption.add_theme_constant_override("shadow_offset_y",2)

func show_lobby() -> void:
	clear_screen("lobby")
	backplate("竞技场","选择一种挑战，带着你的配装进入林间栈桥。")
	Styles.panel(screen,Rect2(36,137,760,534))
	Styles.image(screen,"res://assets/art/forest.png",Rect2(48,149,736,342))
	Styles.panel(screen,Rect2(48,391,736,100),Color("143b3dd9"),Color.TRANSPARENT,0)
	Styles.label(screen,"林间栈桥",Rect2(71,400,550,45),32)
	Styles.label(screen,"FOREST CROSSING   ·   可破坏地形 / 动态风力",Rect2(73,451,650,24),13,Styles.GOLD)
	Styles.label(screen,"每回合 25 秒 · 最多 30 回合 · 爆炸会伤及自己",Rect2(68,513,670,28),16)
	Styles.label(screen,"训练模式提供完整预测线。普通对战需要你根据上一发修正。",Rect2(68,553,690,26),14,Styles.MUTED)
	Styles.label(screen,"你的配装：%s +%d  ·  %s"%[GameData.WEAPONS[profile.data.weapon].name,profile.data.levels[profile.data.weapon],GameData.CHARMS[profile.data.charm].name],Rect2(68,603,690,28),16,Styles.GOLD)
	Styles.panel(screen,Rect2(818,137,426,534))
	Styles.label(screen,"准备出发",Rect2(846,163,370,44),28)
	var modes := [["ai","单人挑战","与绯羽射手对战 · 获得金币与经验"],["training","靶场训练","完整弹道提示 · 对手不攻击"],["local","同机双人","轮流操作 · 与身边的朋友切磋"]]
	for i in range(modes.size()):
		var value: String = modes[i][0]
		var b := Styles.button(screen,modes[i][1],Rect2(846,224+i*101,370,49),func(): battle_mode=value; show_lobby(),battle_mode==value)
		b.add_theme_font_size_override("font_size",20)
		Styles.label(screen,modes[i][2],Rect2(848,279+i*101,370,25),13,Styles.MUTED)
	Styles.button(screen,"进入竞技场   →",Rect2(846,566,370,66),start_battle,true)

func show_expedition() -> void:
	clear_screen("expedition")
	var chapter_names := ["林间遗迹", "炽铜矿坑", "天空遗址"]
	backplate("远征板 · " + chapter_names[selected_chapter - 1],"普通关推进章节；精英关公开词缀、独立记录与额外材料。")
	Styles.panel(screen,Rect2(36,137,274,532),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"第 %d 章" % selected_chapter,Rect2(64,164,200,34),24,Color("3a2c1c"))
	Styles.label(screen,chapter_names[selected_chapter - 1],Rect2(64,201,210,31),20,Color("3a2c1c"))
	Styles.label(screen,"完成上一节点后开放下一站",Rect2(64,239,210,38),14,Color("544027"))
	Styles.button(screen,"第一章 · 林间遗迹",Rect2(52,270,202,34),func(): selected_chapter=1; selected_stage_id="forest_treebridge"; show_expedition(),selected_chapter==1)
	Styles.button(screen,"第二章 · 炽铜矿坑",Rect2(52,310,202,34),func(): selected_chapter=2; selected_stage_id="mine_entrance"; show_expedition(),selected_chapter==2)
	Styles.button(screen,"第三章 · 天空遗址",Rect2(52,350,202,34),func(): selected_chapter=3; selected_stage_id="sky_corridor"; show_expedition(),selected_chapter==3)
	Styles.label(screen,"难度",Rect2(64,406,110,26),17,Color("3a2c1c"))
	Styles.button(screen,"普通",Rect2(52,437,96,34),func(): selected_difficulty="normal"; show_expedition(),selected_difficulty=="normal")
	var elite_toggle := Styles.button(screen,"精英",Rect2(156,437,96,34),func(): selected_difficulty="elite"; show_expedition(),selected_difficulty=="elite")
	elite_toggle.tooltip_text = "普通领主首通后开放；精英记录与首次奖励独立。"
	var stage_ids := ["forest_treebridge","forest_spore_corridor","forest_moss_guardian"] if selected_chapter == 1 else (["mine_entrance","mine_fracture","mine_furnace"] if selected_chapter == 2 else ["sky_corridor","sky_altar","sky_lord"])
	for i in range(stage_ids.size()):
		var stage_id: String = stage_ids[i]
		var status := campaign.stage_status(stage_id, selected_difficulty)
		var unlocked := bool(status.unlocked)
		var title := str(status.stage.name) if unlocked else "🔒 " + str(status.stage.name)
		var node := Styles.button(screen,title,Rect2(58,490+i*54,230,42),func(): selected_stage_id=stage_id; show_expedition(),selected_stage_id==stage_id and unlocked)
		node.disabled = not unlocked
		Styles.label(screen,"已首通" if bool(status.first_cleared) else (str(status.reason) if not unlocked else "可挑战"),Rect2(68,532+i*54,205,18),12,Color("544027"))
	var selected := campaign.stage_status(selected_stage_id, selected_difficulty)
	if not selected.unlocked:
		for stage_id in stage_ids:
			if campaign.stage_status(stage_id, selected_difficulty).unlocked:
				selected_stage_id = stage_id
				selected = campaign.stage_status(stage_id, selected_difficulty)
				break
	Styles.panel(screen,Rect2(332,137,528,532),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,str(selected.stage.name),Rect2(366,165,450,46),31,Color("3a2c1c"))
	var completion_text := "已首通" if selected.first_cleared else ("尚未通关" if selected_difficulty == "elite" else "首次奖励待领取")
	Styles.label(screen,"%s  ·  %s" % ["BOSS" if selected.stage.kind == "boss" else "普通关", completion_text],Rect2(369,217,410,23),14,Color("544027"))
	var player_power := int(selected.get("power", campaign_snapshot().get("power", 0)))
	var recommended_power := int(selected.get("recommended_power", selected.get("stage_config", {}).get("recommended_power", 0)))
	var power_ratio := float(selected.get("power_ratio", float(player_power) / float(maxi(1, recommended_power))))
	var power_hint := str(selected.get("power_hint", "越级挑战" if power_ratio < 0.8 else ("接近推荐" if power_ratio <= 1.25 else "战力占优")))
	var power_label := Styles.label(screen,"我的战力 %s  ·  推荐 %s  ·  %s" % [number_text(player_power), number_text(recommended_power), power_hint],Rect2(369,239,445,21),14,Color("54703e") if power_ratio >= 0.8 else Color("a8392f"))
	power_label.tooltip_text = "战力不含瞄准、范围、体力和临时增益；推荐值仅作引导，不保证胜利。\n我的完整战力：%d\n推荐完整战力：%d\n比例：%.2f 倍" % [player_power, recommended_power, power_ratio]
	var chapter_image := "res://assets/art/forest.png" if selected_chapter == 1 else ("res://assets/art/mine-background.png" if selected_chapter == 2 else "res://assets/art/sky-background.png")
	Styles.image(screen,chapter_image,Rect2(358,259,476,184),Color("819d79"))
	# The three nodes form the visible chapter route; lock state is still enforced by CampaignService.
	for i in range(stage_ids.size()):
		var route_id: String = stage_ids[i]
		var route_status := campaign.stage_status(route_id, selected_difficulty)
		var route := Styles.button(screen,"%d" % (i+1),Rect2(410+i*145,326,52,52),func(): selected_stage_id=route_id; show_expedition(),true)
		route.disabled = not bool(route_status.unlocked)
		route.tooltip_text = str(route_status.stage.name) if route_status.unlocked else str(route_status.reason)
		if i < stage_ids.size()-1: Styles.panel(screen,Rect2(462+i*145,349,93,6),Color("bd9b5b"),Color.TRANSPARENT,0)
	var config: Dictionary = selected.stage.stage_config
	var stage_preview: Dictionary = selected.get("stage_preview", {})
	var hazards: Dictionary = stage_preview.get("hazards", {})
	var mechanic := str(config.get("mechanism", "风流、符文与可破坏地表会改变你的落点。"))
	if mechanic == "high_ground": mechanic = "高地出生位会放大角度与力度的取舍。"
	if mechanic == "thin_ground": mechanic = "薄层地表更容易被爆炸改变。"
	if selected_stage_id == "sky_corridor": mechanic = "逆风长廊：HUD 预告当前与下一行动的风；进入下一行动时使用已展示数值。"
	elif selected_stage_id == "sky_altar": mechanic = "风暴祭坛：左右符文交替预警；机关伤害 %s。" % number_text(hazards.get("altar", 0))
	elif selected_stage_id == "sky_lord": mechanic = "风盾减伤 · 半血狂暴 · 预警轰击 %s" % number_text(hazards.get("storm", 0))
	var mechanic_label := Styles.label(screen,mechanic,Rect2(369,458,440,34),16,Color("3a2c1c"))
	if selected_stage_id == "sky_lord": mechanic_label.tooltip_text = "风盾与二阶段独立影响伤害；预警轰击 %d 为本关冻结数值，玩家升级不会让机关变强。" % int(hazards.get("storm", 0))
	var win: Dictionary = selected.stage.rewards.win
	var growth_preview: Dictionary = selected.get("growth", selected.get("growth_preview", selected.get("growth_reward_preview", {})))
	var exp_text := ""
	if not growth_preview.is_empty(): exp_text = " · 成长经验 +%d" % int(growth_preview.get("applied_exp", growth_preview.get("raw_exp", 0)))
	var reward_line := "%s通关：%s" % ["精英" if selected_difficulty=="elite" else "普通", reward_summary(win)]
	if not exp_text.is_empty(): reward_line += "\n" + exp_text.trim_prefix(" · ")
	var reward_label := Styles.label(screen,reward_line,Rect2(369,500,445,42),14,Color("3a2c1c"))
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.tooltip_text = "%s\n成长经验 +%d" % ["通关奖励：" + reward_summary(win), int(growth_preview.get("applied_exp", growth_preview.get("raw_exp", 0)))]
	reward_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var first_reward: Dictionary = selected.stage.rewards.first_clear
	var no_elite_first_reward: bool = first_reward.is_empty() or (int(first_reward.get("gold", 0)) == 0 and first_reward.get("stacks", {}).is_empty())
	var first_text := "精英首次：独立首通纪录与奖励" if selected_difficulty == "elite" and no_elite_first_reward else "首次通关：" + reward_summary(first_reward)
	var first_label := Styles.label(screen,first_text,Rect2(369,542,445,22),14,Color("3a2c1c"))
	first_label.tooltip_text = first_text
	first_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var affixes: Array = selected.get("public_affixes", config.get("affixes", []))
	var affix_names := {"strong_wind":"强风：最终风力 ×1.3", "thin_soil":"薄土：破坏半径 ×1.15", "armored":"护甲：常驻减伤 +4%"}
	var affix_lines: Array[String] = []
	for affix in affixes: affix_lines.append(str(affix_names.get(str(affix), str(affix))))
	if selected_difficulty == "elite": Styles.label(screen,"精英词缀：" + (" · ".join(affix_lines) if not affix_lines.is_empty() else "本关无额外词缀"),Rect2(369,566,445,24),14,Color("a8392f"))
	var best_actions := int(selected.get("best_player_actions", 0))
	var record := ("最佳行动 %d · 胜利 %d 次" % [best_actions, int(selected.get("wins", 0))]) if best_actions > 0 else "暂无纪录"
	var normal_done := 0
	for route_id in stage_ids:
		if bool(campaign.stage_status(route_id, selected_difficulty).get("first_cleared", false)): normal_done += 1
	Styles.label(screen,"%s完成 %d / %d · %s" % ["精英" if selected_difficulty == "elite" else "普通", normal_done, stage_ids.size(), record],Rect2(369,610,445,22),14,Color("544027"))
	if selected_difficulty == "normal" and selected_stage_id.begins_with("forest_"):
		var no_medkit := bool(profile.data.campaign.objectives.get(selected_stage_id+":no_medkit",false))
		var six_actions := bool(profile.data.campaign.objectives.get(selected_stage_id+":six_actions",false))
		var objective := Styles.label(screen,"目标：无急救包 / 8 次行动（各奖励 金币 60、粉尘 2）",Rect2(369,566,445,38),14,Color("54703e") if no_medkit and six_actions else Color("544027"))
		objective.tooltip_text = "不使用急救包：%s\n8 次行动内：%s\n每项奖励：60 金币、粉尘 2" % ["已达成" if no_medkit else "未达成", "已达成" if six_actions else "未达成"]
		objective.mouse_filter = Control.MOUSE_FILTER_STOP
	elif selected_difficulty == "normal":
		Styles.label(screen,"失败：%d 金币；主动退出没有奖励。" % int(selected.stage.failure_gold),Rect2(369,580,445,24),14,Color("544027"))
	Styles.panel(screen,Rect2(882,137,362,532),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"备战补给",Rect2(911,164,280,35),25,Color("3a2c1c"))
	var slots := inventory.supply_snapshot()
	for i in range(2):
		var slot: Dictionary = slots[i] if i < slots.size() else {}
		var item_id := str(slot.get("item_id", ""))
		var label := "空槽" if item_id.is_empty() else "%s ×%d（持有 %d）" % [ItemData.definition(item_id).name,int(slot.quantity),inventory.stack_count(item_id)]
		Styles.panel(screen,Rect2(910,219+i*75,304,61),Color("21484a"),Color("66866c"),10)
		Styles.label(screen,label,Rect2(926,231+i*75,270,25),16,Styles.GOLD if not item_id.is_empty() else Styles.MUTED)
		Styles.button(screen,"编辑",Rect2(1129,252+i*75,70,22),show_inventory)
	var elite_boss_wins := 0
	for boss_id in ["forest_moss_guardian", "mine_furnace", "sky_lord"]: elite_boss_wins += int(profile.data.campaign.wins.get(boss_id + ":elite", 0))
	var next_gem := "回响晶" if elite_boss_wins % 2 == 0 else "贯穿晶"
	var sky_wins := int(profile.data.campaign.boss_repeat_wins.get("sky_lord", 0))
	var weapon_order := ["爆炎炮", "雷光弩", "岩芯炮"]
	var weapon_index := int(profile.data.campaign.sky_repeat_weapon_index.get("sky_lord", 0)) % 3
	var normal_repeat := "天空领主重复胜利：%d / 3；下一次三胜奖励 %s。" % [sky_wins % 3, weapon_order[weapon_index]]
	var repeat_hint := "精英领主胜利必得宝石；下一颗：%s。" % next_gem if selected_difficulty == "elite" and str(selected.stage.get("kind", "")) == "boss" else (normal_repeat if selected_difficulty == "normal" and selected_stage_id == "sky_lord" else "补给开始时不扣除；使用成功保存后才生效。")
	Styles.label(screen,repeat_hint,Rect2(911,385,295,45),14,Color("544027"))
	var enter := Styles.button(screen,"进入%s副本   →" % ("精英" if selected_difficulty=="elite" else "普通"),Rect2(910,561,304,59),func(): start_campaign(selected_stage_id, selected_difficulty),true)
	enter.disabled = not bool(selected.unlocked)
	if not bool(selected.unlocked): Styles.label(screen,str(selected.reason),Rect2(911,520,290,30),14,Color("a8392f"))

func reward_summary(reward: Dictionary) -> String:
	var pieces := ["金币 %d" % int(reward.get("gold",0))]
	for item_id in reward.get("stacks", {}): pieces.append(ItemData.definition(str(item_id)).name+" "+str(reward.stacks[item_id]))
	return " · ".join(pieces)

func service_message(result: Dictionary, fallback: String) -> String:
	var reason := str(result.get("reason", ""))
	if not reason.is_empty(): return reason
	var message := str(result.get("message", ""))
	return message if not message.is_empty() else fallback

func start_campaign(stage_id: String, difficulty: String = "normal") -> void:
	restore_audio_preferences()
	var started := campaign.begin_run(stage_id, difficulty)
	if not started.ok:
		toast(str(started.message))
		return
	active_campaign_run = started
	clear_screen("battle")
	battle = BattleView.new()
	var snapshot: Dictionary = started.get("combat_snapshot", campaign_snapshot())
	battle.config = {"mode":"campaign","weapon":snapshot.weapon,"charm":snapshot.charm,"level":snapshot.level,"combat_snapshot":snapshot,"enemy_snapshot":started.get("enemy_snapshot", {}),"stage_snapshot":started.get("stage_snapshot", started.get("stage_config", {})),"reward_snapshot":started.get("reward_snapshot", {}),"stage_id":started.stage_id,"difficulty":difficulty,"stage":started.stage,"stage_config":started.stage_config,"run_id":started.run_id,"supplies":started.supplies,"supply_commit":started.supply_commit}
	battle.sound = audio
	battle.battle_finished.connect(func(result: Dictionary): call_deferred("show_campaign_result",result))
	battle.leave_requested.connect(func(): restore_audio_preferences(); call_deferred("leave_campaign"))
	battle.restart_requested.connect(func(): restore_audio_preferences(); call_deferred("restart_campaign"))
	screen.add_child(battle)
	show_first_tutorial("first_campaign", "远征提示：观察当前风力，调整角度与力度；补给会在成功使用后才扣除。")

func show_first_tutorial(key: String, text: String) -> void:
	if not profile.has_method("tutorial_seen") or not profile.has_method("mark_tutorial_seen"): return
	if bool(profile.tutorial_seen(key)): return
	var marked := profile.mark_tutorial_seen(key)
	if not bool(marked.get("ok", false)): return
	if is_instance_valid(tutorial_hint_label): tutorial_hint_label.queue_free()
	var hint_y := 194.0 if current_page == "battle" else 236.0 if current_page == "campaign_result" else 104.0
	var hint: Label = Styles.label(self, text, Rect2(250,hint_y,780,34), 15, Styles.GOLD)
	tutorial_hint_label = hint
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_stylebox_override("normal", Styles.painted_box("banner", 8))
	hint.z_index = 102
	get_tree().create_timer(4.5).timeout.connect(func(): if is_instance_valid(hint): hint.queue_free())

func leave_campaign() -> void:
	restore_audio_preferences()
	if not active_campaign_run.is_empty(): campaign.abandon_run(str(active_campaign_run.run_id))
	active_campaign_run = {}
	show_town()

func restart_campaign() -> void:
	restore_audio_preferences()
	var stage_id := str(active_campaign_run.get("stage_id", selected_stage_id))
	var difficulty := str(active_campaign_run.get("difficulty", selected_difficulty))
	if not active_campaign_run.is_empty(): campaign.abandon_run(str(active_campaign_run.run_id))
	active_campaign_run = {}
	start_campaign(stage_id, difficulty)

func show_inventory() -> void:
	clear_screen("inventory")
	backplate("背包", "武器、饰品、材料与副本补给都收纳在这里。")
	Styles.panel(screen,Rect2(28,133,221,548),Color("153c3eee"),Color("6d896d"),16)
	Styles.label(screen,"分类",Rect2(52,158,150,29),22,Styles.GOLD)
	var categories := [["all","全部"],["weapon","武器"],["charm","饰品"],["material","材料"],["supply","补给"]]
	for i in range(categories.size()):
		var key: String = categories[i][0]
		Styles.button(screen,categories[i][1],Rect2(48,205+i*47,174,38),func(): inventory_category=key; inventory_page=0; show_inventory(),inventory_category==key)
	Styles.label(screen,"排序",Rect2(52,460,150,28),19,Styles.GOLD)
	Styles.button(screen,"品质优先",Rect2(48,496,174,36),func(): inventory_sort="quality"; show_inventory(),inventory_sort=="quality")
	Styles.button(screen,"最近获得",Rect2(48,540,174,36),func(): inventory_sort="recent"; show_inventory(),inventory_sort=="recent")
	Styles.label(screen,"来源筛选",Rect2(52,582,150,22),16,Styles.GOLD)
	Styles.button(screen,"全部",Rect2(48,606,54,30),func(): inventory_source="all"; show_inventory(),inventory_source=="all")
	Styles.button(screen,"林间",Rect2(108,606,54,30),func(): inventory_source="forest"; show_inventory(),inventory_source=="forest")
	Styles.button(screen,"矿坑",Rect2(168,606,54,30),func(): inventory_source="mine"; show_inventory(),inventory_source=="mine")
	Styles.button(screen,"制作",Rect2(48,642,54,30),func(): inventory_source="crafting"; show_inventory(),inventory_source=="crafting")
	Styles.button(screen,"入门",Rect2(108,642,54,30),func(): inventory_source="starter"; show_inventory(),inventory_source=="starter")
	Styles.button(screen,"工坊",Rect2(168,642,54,30),show_workshop,true)
	Styles.panel(screen,Rect2(270,133,592,548),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"物品仓库",Rect2(296,156,250,32),24,Color("3a2c1c"))
	var search_box := LineEdit.new()
	search_box.placeholder_text = "搜索名称"
	search_box.text = inventory_search
	search_box.position = Vector2(602,155)
	search_box.size = Vector2(226,35)
	search_box.text_changed.connect(func(value):
		if inventory_search != value: audio.play("select")
		inventory_search=value; inventory_page=0; show_inventory())
	screen.add_child(search_box)
	if not inventory_search.is_empty(): search_box.call_deferred("grab_focus")
	var items := inventory.inventory_items(inventory_category, inventory_search, inventory_sort, inventory_source)
	var start := inventory_page * 24
	for i in range(24):
		var x := 294 + (i % 6) * 91
		var y := 211 + (i / 6) * 92
		var card := Styles.slot_button(screen,Rect2(x,y,76,76),func(): select_inventory_item(items[start+i]) if start+i < items.size() else null)
		card.tooltip_text = "空格" if start+i >= items.size() else str(items[start+i].name)
		if start+i < items.size():
			var item: Dictionary = items[start+i]
			card.add_theme_stylebox_override("normal",Styles.painted_box("slot",10,Color(1.12,1.08,0.94) if str(item.id) == selected_item_id else Color.WHITE))
			atlas_icon(item.id,Rect2(x+7,y+5,62,47))
			var stack_label := Styles.label(screen,"×%d" % int(item.quantity) if item.has("quantity") else "+%d" % int(item.level),Rect2(x+7,y+53,54,18),13,Styles.CREAM)
			stack_label.add_theme_color_override("font_shadow_color", Color("102b2d"))
			stack_label.add_theme_constant_override("shadow_offset_x", 1)
			stack_label.add_theme_constant_override("shadow_offset_y", 1)
			if item.has("instance_id"):
				var instance_id := str(item.instance_id)
				var equipped := instance_id in [str(profile.data.loadout.weapon_instance_id),str(profile.data.loadout.charm_instance_id)]
				var tag_x := x + 4
				if equipped:
					Styles.panel(screen,Rect2(tag_x,y+4,14,14),Color("4a321e"),Color("76502d"),3)
					var equipped_tag := Styles.label(screen,"装",Rect2(tag_x,y+3,14,14),10,Styles.CREAM)
					equipped_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					equipped_tag.mouse_filter = Control.MOUSE_FILTER_STOP
					equipped_tag.tooltip_text = "已装备"
					tag_x += 17
				if bool(item.locked):
					Styles.panel(screen,Rect2(tag_x,y+4,14,14),Color("4a321e"),Color("76502d"),3)
					var locked_tag := Styles.label(screen,"锁",Rect2(tag_x,y+3,14,14),10,Styles.CREAM)
					locked_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					locked_tag.mouse_filter = Control.MOUSE_FILTER_STOP
					locked_tag.tooltip_text = "已锁定"
				elif not equipped and bool(item.is_new): Styles.label(screen,"新",Rect2(x+5,y+3,18,18),12,Color("a8392f"))
				var checkbox := CheckBox.new()
				checkbox.button_pressed = instance_id in batch_selected
				checkbox.position = Vector2(x+57,y+55)
				checkbox.size = Vector2(16,16)
				checkbox.custom_minimum_size = Vector2(16,16)
				checkbox.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
				checkbox.add_theme_stylebox_override("hover",Styles.box(Color("fff3cd"),Styles.GOLD,4,1))
				checkbox.add_theme_stylebox_override("pressed",Styles.box(Color("f1bc69"),Styles.INK,4,1))
				checkbox.tooltip_text = "批量选择"
				checkbox.pressed.connect(func(): toggle_batch(instance_id))
				screen.add_child(checkbox)
		else:
			card.disabled = true
			card.add_theme_stylebox_override("disabled",Styles.painted_box("slot",10,Color(0.48,0.52,0.48)))
	Styles.label(screen,"%d 件物品 · 第 %d / %d 页" % [items.size(),inventory_page+1,maxi(1,int(ceil(float(items.size())/24.0)))],Rect2(300,591,250,25),14,Color("544027"))
	Styles.label(screen,"已选择 %d 件装备" % batch_selected.size(),Rect2(300,620,180,22),14,Color("544027"))
	var lock_button := Styles.button(screen,"批量锁定",Rect2(480,615,102,36),func(): batch_lock(true),true)
	lock_button.disabled = batch_selected.is_empty()
	var unlock_button := Styles.button(screen,"批量解锁",Rect2(590,615,102,36),func(): batch_lock(false),true)
	unlock_button.disabled = batch_selected.is_empty()
	var clear_button := Styles.button(screen,"清选择",Rect2(700,615,92,36),func(): batch_selected.clear(); show_inventory(),true)
	clear_button.disabled = batch_selected.is_empty()
	var previous := Styles.button(screen,"上一页",Rect2(619,586,92,34),func(): inventory_page=maxi(0,inventory_page-1); show_inventory(),true)
	previous.disabled = inventory_page <= 0
	var next := Styles.button(screen,"下一页",Rect2(724,586,92,34),func(): inventory_page+=1; show_inventory(),true)
	next.disabled = start + 24 >= items.size()
	Styles.panel(screen,Rect2(883,133,361,548),Color("153c3eee"),Color("bd9b5b"),16)
	render_inventory_detail()

func atlas_icon(item_id: String, rect: Rect2) -> void:
	var order := ["ember","volt","feather","moss","woodchip","enhancement_dust","small_medkit","stamina_tonic"]
	var index := order.find(item_id)
	var mine_order := ["copper_ore","armor_breaker","rockcore"]
	var mine_index := mine_order.find(item_id)
	var sky_order := ["relic_shard","echo_gem","pierce_gem"]
	var sky_index := sky_order.find(item_id)
	if index < 0 and mine_index < 0 and sky_index < 0: return
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/art/inventory-atlas.png") if index >= 0 else (load("res://assets/art/mine-items-atlas.png") if mine_index >= 0 else load("res://assets/art/sky-items-atlas.png"))
	atlas.region = Rect2(float(index % 4) * 443.5,float(index / 4) * 443.5,443.5,443.5) if index >= 0 else (Rect2(float(mine_index)*724.0,0,724,724) if mine_index >= 0 else Rect2(float(sky_index) * 724.0,0,724,724))
	var icon := TextureRect.new()
	icon.texture = atlas
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = rect.position
	icon.size = rect.size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(icon)

func select_inventory_item(item: Dictionary) -> void:
	audio.play("select")
	selected_item_id = str(item.id)
	if item.has("instance_id"): selected_instance_id = str(item.instance_id)
	inventory.mark_seen(selected_item_id, str(item.get("instance_id", "")))
	show_inventory()

func toggle_batch(instance_id: String) -> void:
	audio.play("select")
	if instance_id in batch_selected: batch_selected.erase(instance_id)
	else: batch_selected.append(instance_id)
	show_inventory()

func batch_lock(locked: bool) -> void:
	var result := inventory.set_locked(batch_selected, locked)
	if result.ok: audio.play("lock" if locked else "unlock")
	else: audio.play("error")
	toast(str(result.message))
	if result.ok: batch_selected.clear()
	show_inventory()

func render_inventory_detail() -> void:
	Styles.label(screen,"详情与备战",Rect2(909,157,285,31),23,Styles.GOLD)
	var equipment: Dictionary = profile.data.inventory.equipment.get(selected_instance_id, {})
	if not equipment.is_empty() and selected_item_id == str(equipment.template_id):
		var definition := ItemData.definition(str(equipment.template_id))
		atlas_icon(str(equipment.template_id),Rect2(910,204,84,70))
		Styles.label(screen,str(definition.name) + "  +%d" % int(equipment.level),Rect2(1004,211,210,29),19)
		var equipped := selected_instance_id == str(profile.data.loadout.weapon_instance_id) or selected_instance_id == str(profile.data.loadout.charm_instance_id)
		Styles.label(screen,"已装备" if equipped else "未装备",Rect2(1004,244,190,22),14,Styles.GOLD if equipped else Styles.MUTED)
		if definition.category == "weapon":
			var equip_preview := campaign_snapshot({"weapon_instance_id":selected_instance_id})
			var equip_delta := Styles.label(screen,"远征  攻击 %s · 生命 %s\n减伤 %.0f%% · 战力 %s" % [number_text(equip_preview.get("base_attack", 0)), number_text(equip_preview.get("max_hp", 0)), float(equip_preview.get("damage_reduction", 0.0)) * 100.0, number_text(equip_preview.get("power", 0))],Rect2(910,286,286,38),13,Styles.CREAM)
			equip_delta.tooltip_text = snapshot_detail(equip_preview) + "\n保存配装前不会改动存档。"
			equip_delta.mouse_filter = Control.MOUSE_FILTER_STOP
			Styles.button(screen,"装备此武器",Rect2(910,332,286,38),func(): equip_instance(selected_instance_id,"weapon"),not equipped)
		else:
			var charm_id := str(equipment.template_id)
			var charm_detail := "远征减伤 4%" if charm_id == "moss" else str(GameData.CHARMS[charm_id].description)
			var charm_label := Styles.label(screen,charm_detail,Rect2(910,292,290,25),16,Styles.CREAM)
			if charm_id == "moss":
				charm_label.tooltip_text = "远征：减伤 4%。\n竞技 / 训练：护甲 +8（沿用旧对战数值）。"
				charm_label.mouse_filter = Control.MOUSE_FILTER_STOP
			Styles.button(screen,"装备此饰品",Rect2(910,327,286,43),func(): equip_instance(selected_instance_id,"charm"),not equipped)
	else:
		var definition := ItemData.definition(selected_item_id)
		if definition.is_empty():
			Styles.label(screen,"选择物品以查看详情。",Rect2(910,216,280,48),16,Styles.MUTED)
		else:
			atlas_icon(selected_item_id,Rect2(910,204,84,70))
			Styles.label(screen,str(definition.name),Rect2(1004,211,210,29),19)
			Styles.label(screen,"持有 ×%d" % inventory.stack_count(selected_item_id),Rect2(1004,244,190,22),14,Styles.GOLD)
			var use_text := item_detail_text(selected_item_id)
			Styles.label(screen,use_text,Rect2(910,292,286,48),15,Styles.CREAM)
			Styles.label(screen,"来源：" + str(definition.source),Rect2(910,341,286,38),14,Styles.MUTED)
		Styles.button(screen,"查看来源",Rect2(910,374,132,34),go_material_source)
	Styles.label(screen,"出战补给 · 每类 1–2 份",Rect2(910,422,285,24),17,Styles.GOLD)
	var slots := inventory.supply_snapshot()
	var names := ["小型急救包","体力饮剂","破甲药剂"]
	var ids := ["small_medkit","stamina_tonic","armor_breaker"]
	for i in range(3):
		var quantity := 0
		for slot in slots:
			if str(slot.item_id) == ids[i]: quantity = int(slot.quantity)
		Styles.label(screen,"%s：%s" % [names[i],"未携带" if quantity == 0 else "×%d（持有 %d）" % [quantity,inventory.stack_count(ids[i])]],Rect2(910,456+i*48,190,22),14,Styles.CREAM)
		Styles.button(screen,"−",Rect2(1108,449+i*48,42,36),func(): set_supply(ids[i],quantity-1))
		Styles.button(screen,"+",Rect2(1158,449+i*48,42,36),func(): set_supply(ids[i],quantity+1))
	Styles.label(screen,"最多携带两种；补给在战斗中成功使用后才扣库存。",Rect2(910,603,284,36),14,Styles.MUTED)
	Styles.button(screen,"前往远征",Rect2(910,642,286,38),show_expedition,true)

func item_detail_text(item_id: String) -> String:
	match item_id:
		"small_medkit": return "恢复本次远征最大生命的 25%；满生命时不会消耗。"
		"stamina_tonic": return "恢复最多 25 体力；每次行动只能使用一次。"
		"armor_breaker": return "下一次命中后，目标接下来的两次受击护甲减半。"
		"rockcore": return "范围更大的重型炮，完成熔炉核心首次胜利后获得。"
		"relic_shard": return "天空遗址的晶屑，可在工坊制作宝石。"
		"echo_gem": return "镶嵌后按当前成长倍率提高最大生命。"
		"pierce_gem": return "镶嵌后按当前成长倍率提高直击基础伤害。"
		"copper_ore": return "来自炽铜矿坑，用于破甲药剂和 +6 以上强化。"
		"enhancement_dust": return "来自关卡奖励，用于制作补给和武器强化。"
		_: return "用于武器强化，消耗随目标等级增加。"

func set_supply(item_id: String, quantity: int) -> void:
	var slots := inventory.supply_snapshot()
	var updated: Array = []
	for slot in slots:
		if str(slot.item_id) != item_id: updated.append(slot)
	if quantity > 0: updated.append({"item_id":item_id,"quantity":clampi(quantity,1,2)})
	var result := inventory.configure_supplies(updated)
	if result.ok: audio.play("select")
	else: audio.play("error")
	toast("最多只能携带两种补给，请先移除一种。" if result.code == "too_many_slots" else str(result.message))
	show_inventory()

func equip_instance(instance_id: String, category: String) -> void:
	var result := inventory.equip_instance(instance_id)
	if result.ok: audio.play("equip")
	else: audio.play("error")
	toast(str(result.message))
	show_inventory()

func start_battle() -> void:
	restore_audio_preferences()
	clear_screen("battle")
	battle = BattleView.new()
	# Arena, training and local play retain the 0.4.0 combat scale.
	var snapshot := profile.combat_snapshot(battle_mode) if profile.has_method("combat_snapshot") else campaign_snapshot()
	battle.config = {"mode":battle_mode,"weapon":snapshot.weapon,"charm":snapshot.charm,"level":snapshot.level,"combat_snapshot":snapshot}
	battle.sound = audio
	battle.battle_finished.connect(func(result: Dictionary): call_deferred("show_result",result))
	battle.leave_requested.connect(func(): restore_audio_preferences(); call_deferred("show_town"))
	battle.restart_requested.connect(func(): restore_audio_preferences(); call_deferred("start_battle"))
	screen.add_child(battle)

func restore_audio_preferences() -> void:
	if audio:
		audio.set_paused(false)
		audio.volumes(profile.data.music, profile.data.sfx)

func show_character() -> void:
	selected_weapon = profile.data.weapon
	selected_charm = profile.data.charm
	render_character()

func render_character() -> void:
	clear_screen("character")
	backplate("角色小屋","每件装备都改变你的射击方式。保存后，下一场对战立即生效。")
	Styles.panel(screen,Rect2(36,138,381,535))
	Styles.label(screen,"风铃旅人",Rect2(69,167,315,44),29)
	Styles.label(screen,"SKYBOUND EXPLORER",Rect2(72,214,310,22),12,Styles.GOLD)
	Styles.hero(screen,0 if selected_weapon=="ember" else 1,Rect2(46,240,365,349))
	Styles.label(screen,"装备预览",Rect2(71,598,310,25),16,Styles.GOLD)
	Styles.label(screen,"旅途记录   %d 胜 / %d 场"%[profile.data.wins,profile.data.matches],Rect2(71,632,320,24),14,Styles.MUTED)
	Styles.panel(screen,Rect2(438,138,806,535))
	Styles.label(screen,"武器",Rect2(467,160,220,34),22)
	var weapon_levels := {}
	for instance_id in profile.data.inventory.equipment:
		var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
		var template_id := str(equipment.template_id)
		if ItemData.definition(template_id).get("category","") == "weapon" and not weapon_levels.has(template_id): weapon_levels[template_id] = int(equipment.level)
	var weapon_keys: Array[String] = []
	for key in ["ember","volt","rockcore"]:
		if weapon_levels.has(key): weapon_keys.append(key)
	var card_gap := 12.0
	var card_width := (760.0 - card_gap * float(weapon_keys.size()-1)) / float(maxi(1,weapon_keys.size()))
	for i in range(weapon_keys.size()):
		var key: String = weapon_keys[i]
		var level := int(weapon_levels[key])
		var x := 468.0 + float(i) * (card_width + card_gap)
		Styles.panel(screen,Rect2(x,209,card_width,139),Color("204649"),Styles.GOLD if selected_weapon==key else Color("456966"),12)
		Styles.label(screen,GameData.WEAPONS[key].name+" +%d"%level,Rect2(x+14,224,card_width-28,31),19 if weapon_keys.size() > 2 else 23)
		var card_snapshot := campaign_snapshot({"weapon_instance_id":find_equipment_instance(key, "weapon")})
		var card_stats := Styles.label(screen,"攻击 %s · 战力 %s" % [number_text(card_snapshot.get("base_attack", 0)), number_text(card_snapshot.get("power", 0))],Rect2(x+14,265,card_width-28,23),13,Styles.MUTED)
		card_stats.tooltip_text = snapshot_detail(card_snapshot)
		Styles.button(screen,"已选择" if selected_weapon==key else "选择武器",Rect2(x+14,301,card_width-28,33),func(): selected_weapon=key; render_character(),selected_weapon==key)
	Styles.label(screen,"饰品",Rect2(467,369,220,31),22)
	for i in range(2):
		var key := "feather" if i==0 else "moss"
		var charm_text := "远征减伤 4%" if key == "moss" else str(GameData.CHARMS[key].description)
		var charm_button := Styles.button(screen,GameData.CHARMS[key].name+"   ·   "+charm_text,Rect2(468+i*371,412,350,49),func(): selected_charm=key; render_character(),selected_charm==key)
		if key == "moss": charm_button.tooltip_text = "远征：减伤 4%。\n竞技 / 训练：护甲 +8（沿用旧对战数值）。"
	var selected_weapon_id := str(profile.data.loadout.weapon_instance_id)
	var selected_charm_id := str(profile.data.loadout.charm_instance_id)
	for instance_id in profile.data.inventory.equipment:
		var candidate: Dictionary = profile.data.inventory.equipment[instance_id]
		if str(candidate.get("template_id", "")) == selected_weapon and ItemData.definition(selected_weapon).get("category", "") == "weapon": selected_weapon_id = str(instance_id)
		if str(candidate.get("template_id", "")) == selected_charm and ItemData.definition(selected_charm).get("category", "") == "charm": selected_charm_id = str(instance_id)
	var active_snapshot := campaign_snapshot()
	var preview_snapshot := campaign_snapshot({"weapon_instance_id":selected_weapon_id,"charm_instance_id":selected_charm_id})
	Styles.label(screen,"配装预览：" + snapshot_detail(active_snapshot),Rect2(468,494,720,30),18,Styles.GOLD)
	var preview_delta := Styles.label(screen,"选择后：" + snapshot_detail(preview_snapshot),Rect2(468,529,720,26),16,Styles.CREAM)
	preview_delta.tooltip_text = "本页的攻击、生命、减伤和战力均来自配装预览；保存前不会改动存档。\n" + power_delta(active_snapshot, preview_snapshot)
	Styles.label(screen,"远征战力不含瞄准、范围、体力和临时增益；竞技/训练保持旧数值。",Rect2(468,561,720,22),14,Styles.MUTED)
	Styles.button(screen,"保存配装",Rect2(955,599,260,48),func():
		if profile.equip(selected_weapon,selected_charm):
			audio.play("equip")
			toast("配装已保存，准备迎接下一场挑战。")
		else:
			audio.play("error")
			toast(profile.notice),true)
	Styles.label(screen,"完成熔炉核心后，岩芯炮会加入这里。",Rect2(468,610,430,25),13,Styles.MUTED)

func show_workshop() -> void:
	clear_screen("workshop")
	backplate("强化工坊","强化、制作、宝石镶嵌和分解都以真实实例与预览为准。")
	Styles.button(screen,"强化",Rect2(420,92,118,34),func(): workshop_tab="upgrade"; workshop_list_page=0; show_workshop(),workshop_tab=="upgrade")
	Styles.button(screen,"制作",Rect2(546,92,118,34),show_crafting,workshop_tab=="craft")
	Styles.button(screen,"镶嵌",Rect2(672,92,118,34),func(): workshop_tab="socket"; workshop_list_page=0; show_workshop(),workshop_tab=="socket")
	Styles.button(screen,"分解",Rect2(798,92,118,34),func(): workshop_tab="dismantle"; workshop_list_page=0; show_workshop(),workshop_tab=="dismantle")
	if workshop_tab == "socket":
		render_socket_workshop()
		return
	if workshop_tab == "dismantle":
		render_dismantle_workshop()
		return
	var selected_id := workshop_instance_id
	var selected_equipment: Dictionary = profile.data.inventory.equipment.get(selected_id,{})
	if selected_equipment.is_empty() or str(ItemData.definition(str(selected_equipment.get("template_id",""))).get("category","")) != "weapon":
		selected_id = str(profile.data.loadout.weapon_instance_id)
		selected_equipment = profile.data.inventory.equipment.get(selected_id,{})
		workshop_instance_id = selected_id
	var selected_key := str(selected_equipment.get("template_id","ember"))
	var preview := forge.preview_upgrade(selected_id)
	Styles.panel(screen,Rect2(36,139,250,534),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"武器列表",Rect2(62,166,180,31),23,Color("3a2c1c"))
	var weapon_ids: Array[String] = []
	for instance_id in profile.data.inventory.equipment:
		var template_id := str(profile.data.inventory.equipment[instance_id].template_id)
		if ItemData.definition(template_id).get("category","")=="weapon": weapon_ids.append(str(instance_id))
	weapon_ids.sort()
	var upgrade_start := workshop_list_page * 5
	for i in range(mini(5, weapon_ids.size() - upgrade_start)):
		var instance_id: String = weapon_ids[upgrade_start + i]
		var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
		var key: String = str(equipment.template_id)
		var label: String = str(GameData.WEAPONS[key].name) + "  +%d" % int(equipment.level)
		if instance_id == str(profile.data.loadout.weapon_instance_id): label += " · 已装备"
		Styles.button(screen,label,Rect2(60,222+i*64,202,48),func(): workshop_instance_id=instance_id; show_workshop(),instance_id==selected_id)
	var upgrade_previous := Styles.button(screen,"上一页",Rect2(60,571,94,32),func(): workshop_list_page=maxi(0,workshop_list_page-1); show_workshop())
	upgrade_previous.disabled = workshop_list_page == 0
	var upgrade_next := Styles.button(screen,"下一页",Rect2(166,571,94,32),func(): workshop_list_page+=1; show_workshop())
	upgrade_next.disabled = upgrade_start + 5 >= weapon_ids.size()
	Styles.label(screen,"材料可从林间遗迹和炽铜矿坑获得。",Rect2(62,535,200,26),12,Color("544027"))
	Styles.button(screen,"查看来源",Rect2(60,571,202,44),go_material_source)
	Styles.button(screen,"制作补给",Rect2(60,622,202,44),show_crafting,true)
	Styles.panel(screen,Rect2(308,139,404,534),Color("e4d2a5f2"),Color("bd9b5b"),16)
	atlas_icon(selected_key,Rect2(403,172,210,210))
	Styles.label(screen,GameData.WEAPONS[selected_key].name,Rect2(350,395,320,42),30,Color("3a2c1c"))
	var level := int(selected_equipment.get("level",0))
	Styles.label(screen,"+%d  →  +%d" % [level,mini(8,level+1)],Rect2(350,445,320,46),30,Color("3a2c1c"))
	var upgrade_before := campaign_snapshot({"weapon_instance_id":selected_id})
	var upgrade_after: Dictionary = preview.get("after_snapshot", campaign_snapshot({"weapon_instance_id":selected_id,"level":mini(8,level+1)}))
	var upgrade_before_label := Styles.label(screen,"强化前：攻击 %s · 生命 %s\n减伤 %.0f%% · 战力 %s" % [number_text(upgrade_before.get("base_attack", 0)), number_text(upgrade_before.get("max_hp", 0)), float(upgrade_before.get("damage_reduction", 0.0)) * 100.0, number_text(upgrade_before.get("power", 0))],Rect2(350,505,350,40),13,Color("3a2c1c"))
	upgrade_before_label.tooltip_text = "强化前完整数值：\n" + snapshot_detail(upgrade_before)
	upgrade_before_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var upgrade_delta_label := Styles.label(screen,"强化后：攻击 %s · 生命 %s\n减伤 %.0f%% · 战力 %s" % [number_text(upgrade_after.get("base_attack", 0)), number_text(upgrade_after.get("max_hp", 0)), float(upgrade_after.get("damage_reduction", 0.0)) * 100.0, number_text(upgrade_after.get("power", 0))],Rect2(350,550,350,40),14,Color("544027"))
	upgrade_delta_label.tooltip_text = "强化后完整数值：\n" + snapshot_detail(upgrade_after) + "\n\n变化：\n" + power_delta(upgrade_before, upgrade_after)
	upgrade_delta_label.mouse_filter = Control.MOUSE_FILTER_STOP
	Styles.panel(screen,Rect2(734,139,510,534),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"本次强化",Rect2(763,166,300,34),25,Color("3a2c1c"))
	if preview.ok:
		var cost: Dictionary = preview.costs
		var affordable := true
		var rows := [["金币",int(profile.data.gold),int(cost.gold),"forest_treebridge"]]
		for item_id in cost:
			if item_id != "gold": rows.append([ItemData.definition(str(item_id)).name,inventory.stack_count(str(item_id)),int(cost[item_id]),str(ItemData.definition(str(item_id)).get("source_stage_id","forest_treebridge"))])
		for i in range(rows.size()):
			var row: Array = rows[i]
			var missing := maxi(0,int(row[2])-int(row[1]))
			affordable = affordable and missing == 0
			var text := "%s  %d / %d" % [str(row[0]),int(row[1]),int(row[2])]
			if missing > 0: text += " · 还差 %d，前往 %s" % [missing,CampaignData.stage(str(row[3])).name]
			Styles.label(screen,text,Rect2(765,228+i*48,440,36),17,Color("a8392f") if missing > 0 else Color("3a2c1c"))
		Styles.label(screen,"成功率 100%",Rect2(765,381,350,30),19,Color("54703e"))
		var upgrade_button := Styles.button(screen,"强化 · %d 金币" % int(cost.gold),Rect2(765,532,440,55),func(): confirm_upgrade(selected_id),true)
		upgrade_button.disabled = not affordable
	else:
		Styles.label(screen,str(preview.message),Rect2(765,228,420,52),18,Color("544027"))
		if str(preview.code) == "locked": Styles.label(screen,"熔炉核心位于炽铜矿坑第三站。",Rect2(765,286,400,28),15,Color("a8392f"))

func render_socket_workshop() -> void:
	Styles.panel(screen,Rect2(70,145,1140,510),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"武器宝石槽",Rect2(102,170,320,38),29,Color("3a2c1c"))
	Styles.label(screen,"空槽免费；拆卸或替换花费 30 金币，原宝石会返还。",Rect2(102,214,680,26),16,Color("544027"))
	var weapon_ids: Array[String] = []
	for instance_id in profile.data.inventory.equipment:
		var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
		if str(ItemData.definition(str(equipment.get("template_id", ""))).get("category", "")) == "weapon": weapon_ids.append(str(instance_id))
	weapon_ids.sort()
	if workshop_instance_id.is_empty() or not workshop_instance_id in weapon_ids: workshop_instance_id = str(profile.data.loadout.weapon_instance_id)
	var socket_start := workshop_list_page * 5
	for i in range(mini(5, weapon_ids.size() - socket_start)):
		var instance_id := weapon_ids[socket_start + i]
		var weapon: Dictionary = profile.data.inventory.equipment[instance_id]
		var raw_gem: Variant = weapon.get("gem_item_id", null)
		var gem_id := "" if raw_gem == null else str(raw_gem)
		var text := "%s +%d  ·  %s" % [ItemData.definition(str(weapon.template_id)).name, int(weapon.level), "空槽" if gem_id.is_empty() else ItemData.definition(gem_id).name]
		Styles.button(screen,text,Rect2(102,260+i*54,470,42),func(): workshop_instance_id=instance_id; show_workshop(),instance_id==workshop_instance_id)
	var socket_previous := Styles.button(screen,"上一页",Rect2(102,540,100,32),func(): workshop_list_page=maxi(0,workshop_list_page-1); show_workshop())
	socket_previous.disabled = workshop_list_page == 0
	var socket_next := Styles.button(screen,"下一页",Rect2(214,540,100,32),func(): workshop_list_page+=1; show_workshop())
	socket_next.disabled = socket_start + 5 >= weapon_ids.size()
	var selected: Dictionary = profile.data.inventory.equipment.get(workshop_instance_id, {})
	if selected.is_empty():
		Styles.label(screen,"暂无可镶嵌的武器。",Rect2(640,280,420,40),20,Color("544027"))
		return
	var raw_current_gem: Variant = selected.get("gem_item_id", null)
	var current_gem := "" if raw_current_gem == null else str(raw_current_gem)
	Styles.panel(screen,Rect2(610,250,560,330),Color("21484a"),Color("66866c"),14)
	atlas_icon(str(selected.get("template_id", "ember")), Rect2(628,260,72,72))
	Styles.label(screen,"当前槽位：" + ("空槽" if current_gem.is_empty() else ItemData.definition(current_gem).name),Rect2(715,276,390,32),22,Styles.GOLD)
	Styles.label(screen,"这把装备：" + snapshot_detail(campaign_snapshot({"weapon_instance_id":workshop_instance_id})),Rect2(642,320,480,25),14,Styles.CREAM)
	for i in range(2):
		var gem_id := "echo_gem" if i == 0 else "pierce_gem"
		var preview := forge.preview_socket(workshop_instance_id, gem_id)
		var y := 370 + i * 72
		Styles.label(screen,"%s ×%d" % [ItemData.definition(gem_id).name, inventory.stack_count(gem_id)],Rect2(642,y,210,28),18,Styles.CREAM)
		atlas_icon(gem_id, Rect2(850,y-8,42,42))
		var socket_before := campaign_snapshot({"weapon_instance_id":workshop_instance_id})
		var socket_after: Dictionary = preview.get("after_snapshot", campaign_snapshot({"weapon_instance_id":workshop_instance_id,"gem_item_id":gem_id}))
		var socket_delta_text := "直击 %+d · 生命 %+d\n减伤 %+.0f%% · 战力 %+d" % [int(round(float(socket_after.get("base_attack", 0)) + float(socket_after.get("direct_hit_bonus", 0)) - float(socket_before.get("base_attack", 0)) - float(socket_before.get("direct_hit_bonus", 0)))), int(round(float(socket_after.get("max_hp", 0)) - float(socket_before.get("max_hp", 0)))), int(round((float(socket_after.get("damage_reduction", 0.0)) - float(socket_before.get("damage_reduction", 0.0))) * 100.0)), int(round(float(socket_after.get("power", 0)) - float(socket_before.get("power", 0))))]
		var socket_delta_label := Styles.label(screen,socket_delta_text,Rect2(642,y+27,250,34),12,Styles.MUTED)
		socket_delta_label.tooltip_text = "镶嵌变化：\n" + power_delta(socket_before, socket_after) + "\n\n镶嵌后完整数值：\n" + snapshot_detail(socket_after)
		socket_delta_label.mouse_filter = Control.MOUSE_FILTER_STOP
		var action := Styles.button(screen,"镶嵌 " + ItemData.definition(gem_id).name if current_gem != gem_id else "已镶嵌",Rect2(902,y-4,200,38),func(): confirm_socket(workshop_instance_id, gem_id),true)
		action.disabled = not bool(preview.get("ok", false)) or current_gem == gem_id
		if not bool(preview.get("ok", false)): action.tooltip_text = service_message(preview, "暂不可用")
	if not current_gem.is_empty():
		var unsocket := forge.preview_unsocket(workshop_instance_id)
		var remove := Styles.button(screen,"拆卸并返还宝石",Rect2(642,520,460,42),func(): confirm_unsocket(workshop_instance_id),true)
		remove.disabled = not bool(unsocket.get("ok", false))

func confirm_socket(instance_id: String, gem_id: String) -> void:
	var preview := forge.preview_socket(instance_id, gem_id)
	if not bool(preview.get("ok", false)): audio.play("error"); toast(service_message(preview, "无法镶嵌。")); return
	var layer := make_modal("确认镶嵌 · " + ItemData.definition(gem_id).name)
	var raw_old_gem: Variant = preview.get("old_gem", null)
	var old_gem := "" if raw_old_gem == null else str(raw_old_gem)
	var cost := int(preview.get("costs", {}).get("gold", 0))
	var remaining := int(profile.data.gold) - cost
	var reclaim: String = "返还 " + str(ItemData.definition(old_gem).get("name", old_gem)) if not old_gem.is_empty() else "无返还（空槽）"
	Styles.label(layer,"花费 %d 金币；确认后剩余 %d 金币。" % [cost, remaining],Rect2(370,265,500,32),18,Styles.CREAM)
	Styles.label(layer,"%s。" % reclaim,Rect2(370,310,500,32),18,Styles.GOLD)
	var socket_before := campaign_snapshot({"weapon_instance_id":instance_id})
	var socket_after: Dictionary = preview.get("after_snapshot", campaign_snapshot({"weapon_instance_id":instance_id,"gem_item_id":gem_id}))
	var change := Styles.label(layer,"远征变化：" + power_delta(socket_before, socket_after),Rect2(370,352,500,48),15,Styles.GOLD)
	change.tooltip_text = "标准直击包含直击宝石；范围伤害不包含直击宝石。"
	Styles.button(layer,"确认镶嵌",Rect2(370,470,500,56),func():
		if bool(layer.get_meta("submitted", false)): return
		layer.set_meta("submitted", true)
		var result := forge.socket_gem(instance_id, gem_id)
		if bool(result.get("ok", false)): audio.play("socket")
		else: audio.play("error")
		toast(str(result.get("message", "镶嵌完成。")))
		show_workshop(),true)

func confirm_unsocket(instance_id: String) -> void:
	var preview := forge.preview_unsocket(instance_id)
	if not bool(preview.get("ok", false)): audio.play("error"); toast(service_message(preview, "无法拆卸。")); return
	var layer := make_modal("确认拆卸宝石")
	Styles.label(layer,"花费 30 金币，宝石将返回背包。",Rect2(370,285,500,38),19,Styles.CREAM)
	var unsocket_before := campaign_snapshot({"weapon_instance_id":instance_id})
	var unsocket_after: Dictionary = preview.get("after_snapshot", campaign_snapshot({"weapon_instance_id":instance_id,"gem_item_id":null}))
	Styles.label(layer,"战力预览：" + power_delta(unsocket_before, unsocket_after),Rect2(370,340,500,28),15,Styles.GOLD)
	Styles.button(layer,"确认拆卸",Rect2(370,470,500,56),func():
		if bool(layer.get_meta("submitted", false)): return
		layer.set_meta("submitted", true)
		var result := forge.unsocket_gem(instance_id)
		if bool(result.get("ok", false)): audio.play("socket")
		else: audio.play("error")
		toast(str(result.get("message", "宝石已返还。")))
		show_workshop(),true)

func render_dismantle_workshop() -> void:
	Styles.panel(screen,Rect2(70,145,1140,510),Color("e4d2a5f2"),Color("bd9b5b"),16)
	Styles.label(screen,"批量分解",Rect2(102,170,300,38),29,Color("3a2c1c"))
	Styles.label(screen,"已装备、锁定、已镶嵌与最后一把武器不能选择；先逐件核验，再进行第二次确认。",Rect2(102,214,1000,26),15,Color("544027"))
	var ids: Array[String] = []
	for instance_id in profile.data.inventory.equipment: ids.append(str(instance_id))
	ids.sort()
	var eligible_count := 0
	for instance_id in ids:
		if bool(forge.preview_dismantle([instance_id]).get("ok", false)): eligible_count += 1
	var dismantle_start := workshop_list_page * 5
	for i in range(mini(5, ids.size() - dismantle_start)):
		var instance_id := ids[dismantle_start + i]
		var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
		var definition := ItemData.definition(str(equipment.template_id))
		var row := Styles.button(screen,"%s +%d%s" % [definition.name, int(equipment.level), "  [已选]" if instance_id in batch_selected else ""],Rect2(102,260+i*48,490,38),func(): toggle_dismantle(instance_id),instance_id in batch_selected)
		var item_preview := forge.preview_dismantle([instance_id])
		row.disabled = not bool(item_preview.get("ok", false)) and not instance_id in batch_selected
		row.tooltip_text = service_message(item_preview, "可分解")
	var dismantle_previous := Styles.button(screen,"上一页",Rect2(102,540,100,32),func(): workshop_list_page=maxi(0,workshop_list_page-1); show_workshop())
	dismantle_previous.disabled = workshop_list_page == 0
	var dismantle_next := Styles.button(screen,"下一页",Rect2(214,540,100,32),func(): workshop_list_page+=1; show_workshop())
	dismantle_next.disabled = dismantle_start + 5 >= ids.size()
	var preview := forge.preview_dismantle(batch_selected)
	Styles.panel(screen,Rect2(630,260,500,246),Color("21484a"),Color("66866c"),14)
	Styles.label(screen,"暂无可分解的多余装备" if eligible_count == 0 else "本批选择 %d 件" % batch_selected.size(),Rect2(660,286,420,32),22,Styles.GOLD)
	var yields: Dictionary = preview.get("rewards", preview.get("refunds", {}))
	var yield_lines: Array[String] = []
	for item_id in yields: yield_lines.append(ItemData.definition(str(item_id)).name + " +" + str(yields[item_id]))
	Styles.label(screen,"逐件合计：" + (" · ".join(yield_lines) if not yield_lines.is_empty() else "尚未选择"),Rect2(660,338,420,52),16,Styles.CREAM)
	Styles.label(screen,service_message(preview, "选择装备后显示真实返还。"),Rect2(660,405,420,38),14,Styles.MUTED)
	var button := Styles.button(screen,"预览并进入二次确认",Rect2(660,458,420,40),confirm_dismantle,true)
	button.disabled = batch_selected.is_empty() or not bool(preview.get("ok", false)) or dismantle_busy

func toggle_dismantle(instance_id: String) -> void:
	audio.play("select")
	if instance_id in batch_selected: batch_selected.erase(instance_id)
	else: batch_selected.append(instance_id)
	show_workshop()

func confirm_dismantle() -> void:
	if dismantle_busy: return
	var preview := forge.preview_dismantle(batch_selected)
	if not bool(preview.get("ok", false)): audio.play("error"); toast(service_message(preview, "无法分解。")); return
	var layer := make_modal("第二次确认 · 分解 %d 件" % batch_selected.size())
	var item_names: Array[String] = []
	for instance_id in batch_selected:
		var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
		if not equipment.is_empty(): item_names.append(ItemData.definition(str(equipment.get("template_id", ""))).get("name", "未知装备") + " +%d" % int(equipment.get("level", 0)))
	var rewards: Dictionary = preview.get("rewards", preview.get("refunds", {}))
	var reward_text: Array[String] = []
	for item_id in rewards: reward_text.append(ItemData.definition(str(item_id)).get("name", str(item_id)) + " +" + str(rewards[item_id]))
	Styles.label(layer,"移除：" + " · ".join(item_names),Rect2(370,255,500,56),17,Color("f0a986"))
	Styles.label(layer,"返还：" + (" · ".join(reward_text) if not reward_text.is_empty() else "无") + "；金币不返还。",Rect2(370,330,500,42),17,Styles.CREAM)
	Styles.button(layer,"确认永久分解",Rect2(370,470,500,56),func():
		if bool(layer.get_meta("submitted", false)) or dismantle_busy: return
		layer.set_meta("submitted", true); dismantle_busy = true
		var result := forge.dismantle(batch_selected.duplicate())
		dismantle_busy = false
		if bool(result.get("ok", false)):
			audio.play("dismantle")
			batch_selected.clear()
		else: audio.play("error")
		toast(str(result.get("message", "分解完成。")))
		show_workshop(),true)


func show_crafting() -> void:
	clear_screen("crafting")
	backplate("工坊制作","选择补给或宝石配方；宝石在普通天空领主首通后开放。")
	Styles.panel(screen,Rect2(70,144,1140,500),Color("e4d2a5f2"),Color("bd9b5b"),16)
	var recipes := ["small_medkit","stamina_tonic","armor_breaker","echo_gem","pierce_gem"]
	for i in range(recipes.size()):
		var item_id: String = recipes[i]
		var quantity := int(craft_quantities.get(item_id,1))
		var preview := inventory.craft_preview(item_id, quantity)
		var x := 100 + (i % 3) * 350
		var y := 170 + (i / 3) * 232
		Styles.panel(screen,Rect2(x,y,320,212),Color("f6e6bd"),Color("9a7a47"),12)
		atlas_icon(item_id,Rect2(x+20,y+18,68,68))
		Styles.label(screen,ItemData.definition(item_id).name,Rect2(x+100,y+24,190,30),20,Color("3a2c1c"))
		var cost_lines := []
		for material in preview.get("costs", {}): cost_lines.append(("金币" if str(material) == "gold" else ItemData.definition(material).get("name", str(material))) + " ×" + str(preview.costs[material]))
		var first_cost_line := " · ".join(cost_lines.slice(0, mini(2, cost_lines.size())))
		var second_cost_line := " · ".join(cost_lines.slice(2))
		Styles.label(screen,"总消耗：" + first_cost_line + ("\n" + second_cost_line if not second_cost_line.is_empty() else ""),Rect2(x+20,y+88,280,40),13,Color("544027"))
		Styles.label(screen,"产出 %d 份 · 持有 %d" % [quantity,inventory.stack_count(item_id)],Rect2(x+20,y+132,270,22),15,Color("3a2c1c"))
		var spinner := SpinBox.new()
		spinner.min_value=1; spinner.max_value=99; spinner.step=1; spinner.value=quantity
		spinner.position=Vector2(x+20,y+158); spinner.size=Vector2(90,32)
		spinner.value_changed.connect(func(value): audio.play("slider"); craft_quantities[item_id]=int(value); show_crafting())
		screen.add_child(spinner)
		var enough := bool(preview.get("ok", false))
		for material in preview.get("costs", {}): enough = enough and (int(profile.data.gold) >= int(preview.costs[material]) if material == "gold" else inventory.stack_count(material) >= int(preview.costs[material]))
		if not enough: Styles.label(screen,str(preview.get("message", "材料不足 · 前往遗迹获取")),Rect2(x+20,y+184,280,16),11,Color("a8392f"))
		var craft_button := Styles.button(screen,"制作 %d 份" % quantity,Rect2(x+190,y+158,108,32),func(): confirm_craft(item_id,quantity),true)
		craft_button.disabled = not enough or craft_busy

func confirm_craft(item_id: String, quantity: int) -> void:
	if craft_busy: return
	var preview := inventory.craft_preview(item_id,quantity)
	if not preview.ok: audio.play("error"); toast(str(preview.message)); return
	var layer := make_modal("确认制作 · " + ItemData.definition(item_id).name)
	Styles.label(layer,"产出 %d 份" % quantity,Rect2(370,260,500,32),24,Styles.GOLD)
	var cost_lines := []
	for material_id in preview.costs: cost_lines.append(("金币" if str(material_id) == "gold" else ItemData.definition(str(material_id)).get("name", str(material_id))) + " ×" + str(preview.costs[material_id]))
	Styles.label(layer,"本次消耗：" + " · ".join(cost_lines),Rect2(370,315,500,28),16,Styles.MUTED)
	Styles.label(layer,"确认后获得补给。",Rect2(370,350,500,28),16,Styles.MUTED)
	Styles.button(layer,"确认制作",Rect2(370,470,500,56),func():
		if bool(layer.get_meta("submitted",false)) or craft_busy: return
		layer.set_meta("submitted",true)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		craft_busy=true
		var result := inventory.craft(item_id,quantity)
		if result.ok: audio.play("craft")
		else: audio.play("error")
		toast(str(result.message))
		craft_busy=false
		show_crafting()
	,true)

func make_modal(title: String) -> Control:
	if is_instance_valid(modal): modal.queue_free()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(modal)
	Styles.panel(modal,Rect2(0,0,1280,720),Color("071e27d9"),Color.TRANSPARENT,0)
	Styles.panel(modal,Rect2(330,132,620,476))
	Styles.label(modal,title,Rect2(370,164,520, 50),30)
	Styles.button(modal,"×",Rect2(879,155, 40,40),close_modal)
	return modal


func close_modal(cancel: bool = true) -> void:
	if cancel: audio.play("cancel")
	if is_instance_valid(modal): modal.queue_free()
	modal = null

func confirm_upgrade(instance_id: String) -> void:
	var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id,{})
	if equipment.is_empty():
		audio.play("error")
		toast("这把武器已不在仓库中。")
		return
	var weapon := str(equipment.template_id)
	var layer := make_modal("确认强化 · "+GameData.WEAPONS[weapon].name)
	var preview := forge.preview_upgrade(instance_id)
	if not preview.ok:
		audio.play("error")
		toast(str(preview.message))
		close_modal(false)
		return
	var level: int = int(equipment.level)
	var costs: Dictionary = preview.costs
	Styles.label(layer,"+%d   →   +%d"%[level,level+1],Rect2(370,249,500,61),42,Styles.GOLD)
	var upgrade_before := campaign_snapshot({"weapon_instance_id":instance_id})
	var upgrade_after: Dictionary = preview.get("after_snapshot", campaign_snapshot({"weapon_instance_id":instance_id,"level":level+1}))
	Styles.label(layer,"战力预览：" + power_delta(upgrade_before, upgrade_after),Rect2(370,333,500,38),18)
	var material_id := "copper_ore" if costs.has("copper_ore") else "woodchip"
	Styles.label(layer,"消耗 %d 金币 · 粉尘 %d · %s %d" % [int(costs.gold),int(costs.enhancement_dust),"铜矿" if material_id=="copper_ore" else "木屑",int(costs[material_id])],Rect2(370,399,500,30),17,Styles.MUTED)
	Styles.label(layer,"持有：金币 %d · 粉尘 %d · 材料 %d" % [int(profile.data.gold),inventory.stack_count("enhancement_dust"),inventory.stack_count(material_id)],Rect2(370,435,500,26),15,Styles.GOLD)
	Styles.button(layer,"确认强化",Rect2(370,492,500, 60),func():
		if bool(layer.get_meta("submitted",false)): return
		layer.set_meta("submitted",true)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var result := forge.upgrade(instance_id)
		if result.ok:
			audio.play("upgrade")
			show_workshop()
			toast("强化成功；远征攻击与战力已按当前成长重新计算。")
			show_first_tutorial("first_upgrade", "强化提示：强化消耗会记录在这件武器上；分解只返还部分材料。")
		else:
			audio.play("error")
			toast(str(result.message))
			layer.mouse_filter = Control.MOUSE_FILTER_STOP
			layer.set_meta("submitted",false)
	,true)

func go_material_source() -> void:
	var definition := ItemData.definition(selected_item_id)
	selected_stage_id = str(definition.get("source_stage_id","forest_treebridge"))
	selected_chapter = int(CampaignData.stage(selected_stage_id).get("chapter",1))
	show_expedition()

func show_campaign_result(result: Dictionary) -> void:
	last_result = result
	var outcome := "win" if int(result.winner) == 0 else "loss"
	var saved := campaign.settle_run(str(active_campaign_run.run_id), outcome, result)
	var stage_id := str(active_campaign_run.get("stage_id",selected_stage_id))
	var stage := CampaignData.stage(stage_id)
	var mine_stage := int(stage.get("chapter",1)) == 2
	clear_screen("campaign_result")
	var result_background := "res://assets/art/sky-background.png" if int(stage.get("chapter",1)) == 3 else ("res://assets/art/mine-background.png" if mine_stage else "res://assets/art/forest.png")
	Styles.image(screen,result_background,Rect2(0,0,1280,720),Color("82978a"))
	Styles.panel(screen,Rect2(0,0,1280,720),Color("0d303499"),Color.TRANSPARENT,0)
	Styles.panel(screen,Rect2(174,94,932,533),Color("153b3df2"),Color("c39b55"),24)
	var won := outcome == "win"
	var result_chapter := "天空遗址" if int(stage.get("chapter",1)) == 3 else ("炽铜矿坑" if mine_stage else "林间遗迹")
	Styles.label(screen,result_chapter + " · " + str(stage.get("name","结算")),Rect2(222,128,650,26),14,Styles.GOLD)
	Styles.label(screen,"胜利！" if won else "本次挑战失败",Rect2(218,166,650,61),40)
	var rewards: Dictionary = saved.get("rewards", {})
	if saved.ok:
		var growth: Dictionary = saved.get("growth", rewards.get("growth", {}))
		var reward_lines: Array = []
		for group in rewards.get("groups", []):
			var stacks: Dictionary = group.get("stacks", {})
			var items := []
			for item_id in stacks: items.append(ItemData.definition(item_id).name + " +" + str(stacks[item_id]))
			var group_label := str(group.label)
			if str(group.get("kind","")) == "objective":
				group_label = "挑战·不用急救包" if str(group.get("objective_id","")) == "no_medkit" else "挑战·8次行动内"
			if str(group.get("kind", "")) in ["elite_gem", "repeat_weapon"]:
				group_label = "✦ " + group_label
			reward_lines.append(group_label + "：金币 +%d" % int(group.gold) + (" · " + " · ".join(items) if not items.is_empty() else ""))
		if reward_lines.is_empty() and not won:
			reward_lines.append("失败补给：金币 +%d" % int(rewards.get("gold", 0)))
		Styles.label(screen,"\n".join(reward_lines),Rect2(244,276,700,100),18,Styles.GOLD)
		if not growth.is_empty():
			var applied_exp := int(growth.get("applied_exp", 0))
			var raw_exp := int(growth.get("raw_exp", applied_exp))
			var discarded_exp := int(growth.get("discarded_exp", 0))
			var level_before := int(growth.get("level_before", growth_progress().get("level", 1)))
			var level_after := int(growth.get("level_after", level_before))
			var growth_line := "成长经验 +%d  ·  Lv.%d → Lv.%d" % [applied_exp, level_before, level_after]
			if discarded_exp > 0: growth_line += "  · 已达满级，剩余 %d 经验不再累计" % discarded_exp
			elif raw_exp > applied_exp: growth_line += "  · %d 经验未计入" % (raw_exp - applied_exp)
			var growth_label := Styles.label(screen,growth_line,Rect2(244,385,700,30),17,Styles.GOLD)
			growth_label.tooltip_text = "经验与等级已在本局奖励事务中保存。\n战力：%d → %d" % [int(growth.get("power_before", 0)), int(growth.get("power_after", 0))]
		elif not won:
			Styles.label(screen,"成长经验 +0  · 失败、平局与退出不会获得成长经验。",Rect2(244,385,700,30),17,Styles.MUTED)
		var rare_row := 0
		for group in rewards.get("groups", []):
			if str(group.get("kind", "")) in ["elite_gem", "repeat_weapon"]:
				for item_id in group.get("stacks", {}):
					atlas_icon(str(item_id), Rect2(960,286 + rare_row * 42,34,34))
					rare_row += 1
		Styles.label(screen,"以上各项奖励已保存到仓库。" if won else "失败奖励已保存。",Rect2(244,426,650,28),16,Styles.CREAM)
		var has_material := false
		for item_id in rewards.get("stacks", {}):
			if str(ItemData.definition(str(item_id)).get("category", "")) == "material": has_material = true
		if has_material: show_first_tutorial("first_material", "材料提示：材料可用于强化、补给与宝石制作；背包会显示来源。")
		Styles.button(screen,"返回风铃港",Rect2(244,510,286,53),func(): active_campaign_run={}; show_town())
		Styles.button(screen,"回到远征",Rect2(548,510,286,53),func(): active_campaign_run={}; show_expedition(),true)
	else:
		Styles.label(screen,"奖励等待保存",Rect2(244,294,500,42),26,Color("f0a986"))
		Styles.label(screen,str(saved.message) + " 使用同一局编号重试不会重复发奖。",Rect2(244,352,670,52),16,Styles.CREAM)
		Styles.button(screen,"重试保存",Rect2(244,510,286,53),func(): show_campaign_result(result),true)
		Styles.button(screen,"放弃奖励并返城",Rect2(548,510,286,53),func(): leave_campaign())
	if saved.ok:
		var growth: Dictionary = saved.get("growth", rewards.get("growth", {}))
		play_result_audio_once(str(active_campaign_run.get("run_id", result.get("id", ""))), int(result.winner), true, int(growth.get("level_after", 0)) > int(growth.get("level_before", 0)))
	else:
		audio.play("error")


func show_result(result: Dictionary) -> void:
	last_result = result
	clear_screen("result")
	var reward := profile.reward(result.id,result.winner,result.mode)
	Styles.image(screen,"res://assets/art/forest.png",Rect2(0,0,1280,720),Color("82978a"))
	Styles.panel(screen,Rect2(0,0,1280,720),Color("0d303499"),Color.TRANSPARENT,0)
	Styles.panel(screen,Rect2(156,81,968,558),Color("153b3df2"),Color("8f9f73"),24)
	var title := "势均力敌" if result.winner==-1 else ("漂亮的一击！" if result.winner==0 else "下次，再近一点")
	if result.mode=="local": title = "平局" if result.winner==-1 else ("蓝队获胜" if result.winner==0 else "红队获胜")
	Styles.label(screen,"MATCH COMPLETE",Rect2(208,114,760,26),13,Styles.GOLD)
	Styles.label(screen,title,Rect2(205,151,760,69), 42)
	Styles.hero(screen,0 if result.winner!=1 else 3,Rect2(191,244,294,305))
	Styles.label(screen,"第 %d 回合结束 · %d 分 %02d 秒"%[result.rounds,int(result.seconds)/60,int(result.seconds)%60],Rect2(520,245,540,30),17,Styles.MUTED)
	var stats: Dictionary = result.stats[1 if result.mode=="local" and result.winner==1 else 0]
	Styles.label(screen,"%d"%stats.hits,Rect2(520,299,150,62), 42,Styles.GOLD)
	Styles.label(screen,"%d"%stats.damage,Rect2(759,299,250,62), 42,Styles.GOLD)
	Styles.label(screen,"命中次数",Rect2(520,365,180,26),14,Styles.MUTED)
	Styles.label(screen,"累计伤害",Rect2(759,365,230,26),14,Styles.MUTED)
	Styles.panel(screen,Rect2(520,414,546,83),Color("234b48"),Color("6f8768"),12)
	Styles.label(screen,"金币 +%d      经验 +%d"%[reward.gold,reward.xp],Rect2(545,434,496,36),24,Styles.GOLD)
	Styles.label(screen,"奖励已保存" if reward.saved and result.mode=="ai" else "训练 / 同机对局不发放成长奖励" if result.mode!="ai" else "保存失败，点击重试后再离开",Rect2(520,507,547,25),13,Styles.MUTED)
	Styles.button(screen,"返回风铃港",Rect2(520,558,257,49),show_town)
	Styles.button(screen,"再来一局   →",Rect2(797,558,269,49),start_battle,true)
	if not reward.saved:
		Styles.button(screen,"重试保存奖励",Rect2(797,502,269,37),func(): show_result(result))
	if result.mode != "ai" or reward.saved:
		play_result_audio_once(str(result.id), int(result.winner), reward.saved and result.mode == "ai")
	else:
		audio.play("error")

func show_settings() -> void:
	var layer := make_modal("声音设置")
	var settings := {"music":profile.data.music,"sfx":profile.data.sfx}
	for i in range(2):
		var key := "music" if i==0 else "sfx"
		Styles.label(layer,"音乐" if i==0 else "音效",Rect2(372,250+i*97,450,29),20)
		var slider := HSlider.new()
		slider.position = Vector2(373,293+i*97)
		slider.size = Vector2(495,24)
		slider.min_value=0
		slider.max_value=1
		slider.step=0.01
		slider.value=settings[key]
		slider.value_changed.connect(func(value): settings[key]=value; audio.volumes(settings.music,settings.sfx); audio.play("slider"))
		layer.add_child(slider)
	Styles.button(layer,"保存设置",Rect2(370,495,500,57),func():
		var old := profile.data.duplicate(true)
		profile.data.music=settings.music
		profile.data.sfx=settings.sfx
		if profile.save():
			audio.play("select")
			close_modal(false)
			toast("声音设置已保存。")
		else:
			audio.play("error")
			profile.data=old
			audio.volumes(old.music,old.sfx)
			toast(profile.notice),true)

func show_help() -> void:
	var layer := make_modal("第一发，从这里开始")
	var lines := ["01   A / D 移动，消耗体力；Q / E 调整角度。","02   按住空格蓄力，松开发射；W / S 微调力度。","03   也可拖动滑条，点击发射或按 Enter。","04   Z / X / C 选弹种；1–4 选道具；H 治疗。","05   怒气满 100 后按 R 开启爆发。","06   地形会被炸开，近距离爆炸也会伤及自己。"]
	for i in range(lines.size()): Styles.label(layer,lines[i],Rect2(365,237+i*42,550,30),15,Styles.CREAM)
	Styles.button(layer,"进入训练靶场",Rect2(370,472,240,48),func(): battle_mode="training"; start_battle(),true)
	Styles.button(layer,"重看：风流预告",Rect2(630,472,240,48),func(): show_tip("逆风长廊 · 风流预告","逆风长廊 HUD 会先显示当前与下一行动的风；下一行动使用已经展示的数值。"))
	Styles.button(layer,"重看：符文区域",Rect2(370,530,240,40),func(): show_tip("符文区域","敌方行动结束后标记区域；你拥有完整的一次行动离开它。"))
	Styles.button(layer,"重看：宝石与分解",Rect2(630,530,240,40),func(): show_tip("宝石与分解","空槽镶嵌免费；替换或拆卸返还宝石。分解会在第二次确认后执行。"))
	Styles.button(layer,"重看：首次远征",Rect2(370,570,155,28),func(): show_tip("首次远征","观察当前风力，选择角度与力度后发射；补给成功使用后才扣除。"))
	Styles.button(layer,"重看：首次材料",Rect2(540,570,155,28),func(): show_tip("首次材料","材料用于强化、制作补给和宝石。"))
	Styles.button(layer,"重看：首次强化",Rect2(710,570,155,28),func(): show_tip("首次强化","强化投入会记录在武器上，分解只返还部分材料。"))

func show_tip(title: String, text: String) -> void:
	var layer := make_modal(title)
	Styles.label(layer,text,Rect2(370,275,500,80),20,Styles.CREAM)
	Styles.button(layer,"知道了",Rect2(370,470,500,56),close_modal,true)

func toast(message: String) -> void:
	if is_instance_valid(toast_label): toast_label.queue_free()
	toast_label = Styles.label(self,message,Rect2(290,15,700,42),16,Styles.GOLD)
	toast_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_stylebox_override("normal",Styles.painted_box("secondary",8))
	toast_label.z_index=100
	toast_timer=3.5

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and current_page!="battle":
		if is_instance_valid(modal): close_modal()
		elif current_page=="campaign_result": toast("请点击“重试保存”或“放弃奖励并返城”。")
		elif current_page!="town": show_town()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

func quit_game() -> void:
	if not active_campaign_run.is_empty(): campaign.abandon_run(str(active_campaign_run.run_id))
	audio.shutdown()
	await get_tree().create_timer(0.12).timeout
	get_tree().quit()

func _exit_tree() -> void:
	Styles.click_sound = Callable()
	Styles.hover_sound = Callable()
