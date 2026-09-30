class_name ForgeService
extends RefCounted

var profile: PlayerProfile

func _init(player_profile: PlayerProfile) -> void:
	profile = player_profile
	profile.ensure_round_one()

func preview_upgrade(instance_id: String) -> Dictionary:
	var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
	if equipment.is_empty() or ItemData.definition(str(equipment.get("template_id", ""))).category != "weapon": return _failure("invalid_equipment", "请选择一把武器。")
	var target := int(equipment.level) + 1
	if target > 8: return _failure("max_level", "该武器已达到 +8。")
	if target > 5 and not bool(profile.data.campaign.first_clears.get("mine_furnace", false)): return _failure("locked", "完成熔炉核心后开放 +6～+8。")
	var costs := {"gold":60 * target, "enhancement_dust":2 * target, "woodchip":target} if target <= 5 else ({"gold":420,"enhancement_dust":12,"copper_ore":6} if target == 6 else ({"gold":560,"enhancement_dust":16,"copper_ore":9} if target == 7 else {"gold":720,"enhancement_dust":20,"copper_ore":12}))
	var owned := {"gold":int(profile.data.gold)}
	for item_id in costs:
		if item_id != "gold": owned[item_id] = int(profile.data.inventory.stacks.get(item_id,0))
	return {"ok":true,"code":"preview","target_level":target,"costs":costs,"has":owned,"before_snapshot":profile.preview_combat_snapshot({"weapon_instance_id":instance_id}),"after_snapshot":profile.preview_combat_snapshot({"weapon_instance_id":instance_id,"level":target})}

func upgrade(instance_id: String) -> Dictionary:
	var preview := preview_upgrade(instance_id)
	if not preview.ok: return preview
	var costs: Dictionary = preview.costs
	if int(profile.data.gold) < int(costs.gold): return _failure("insufficient_materials", "金币或强化材料不足。")
	for item_id in costs:
		if item_id != "gold" and int(profile.data.inventory.stacks.get(item_id,0)) < int(costs[item_id]): return _failure("insufficient_materials", "金币或强化材料不足。")
	return profile.transaction(func() -> bool:
		var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
		if equipment.is_empty() or int(equipment.level) + 1 != int(preview.target_level): return false
		profile.data.gold = int(profile.data.gold) - int(costs.gold)
		for item_id in costs:
			if item_id == "gold": continue
			profile.data.inventory.stacks[item_id] = int(profile.data.inventory.stacks.get(item_id, 0)) - int(costs[item_id])
			equipment.invested_materials[item_id] = int(equipment.invested_materials.get(item_id, 0)) + int(costs[item_id])
		equipment.level = int(preview.target_level)
		profile.data.inventory.equipment[instance_id] = equipment
		return true
	, "upgraded", "强化成功。", {"level":int(preview.target_level)})

func preview_socket(instance_id: String, gem_id: String) -> Dictionary:
	var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
	if equipment.is_empty() or ItemData.definition(str(equipment.get("template_id", ""))).get("category", "") != "weapon": return _failure("invalid_equipment", "请选择一把武器。")
	if gem_id not in ["echo_gem", "pierce_gem"]: return _failure("invalid_gem", "请选择一颗宝石。")
	if not bool(profile.data.campaign.first_clears.get("sky_lord", false)): return _failure("locked", "完成天空领主后开放镶嵌。")
	var old_gem = equipment.get("gem_item_id", null)
	if str(old_gem) == gem_id: return _failure("same_gem", "已镶嵌同一种宝石。")
	var costs := {"gold":30} if old_gem != null else {"gold":0}
	if int(profile.data.inventory.stacks.get(gem_id, 0)) < 1: return _failure("missing_gem", "背包中没有这颗宝石。")
	if int(profile.data.gold) < int(costs.gold): return _failure("insufficient_gold", "金币不足，无法替换宝石。")
	return {"ok":true,"code":"preview","instance_id":instance_id,"gem_id":gem_id,"old_gem":old_gem,"costs":costs,"rewards":({str(old_gem):1} if old_gem != null else {}),"delta":_gem_delta(gem_id, old_gem),"before_snapshot":profile.preview_combat_snapshot({"weapon_instance_id":instance_id}),"after_snapshot":profile.preview_combat_snapshot({"weapon_instance_id":instance_id,"gem_item_id":gem_id}),"reason":""}

func socket_gem(instance_id: String, gem_id: String) -> Dictionary:
	var preview := preview_socket(instance_id, gem_id)
	if not preview.ok: return preview
	return profile.transaction(func() -> bool:
		var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
		if equipment.is_empty() or str(equipment.get("gem_item_id", "")) == gem_id or int(profile.data.inventory.stacks.get(gem_id, 0)) < 1 or int(profile.data.gold) < int(preview.costs.gold): return false
		profile.data.inventory.stacks[gem_id] = int(profile.data.inventory.stacks.get(gem_id, 0)) - 1
		if preview.old_gem != null: profile.data.inventory.stacks[str(preview.old_gem)] = int(profile.data.inventory.stacks.get(str(preview.old_gem), 0)) + 1
		profile.data.gold = int(profile.data.gold) - int(preview.costs.gold)
		equipment.gem_item_id = gem_id
		profile.data.inventory.equipment[instance_id] = equipment
		return true
	, "gem_socketed", "宝石已镶嵌。", {"preview":preview})

func preview_unsocket(instance_id: String) -> Dictionary:
	var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
	if equipment.is_empty() or ItemData.definition(str(equipment.get("template_id", ""))).get("category", "") != "weapon": return _failure("invalid_equipment", "请选择一把武器。")
	var gem_id = equipment.get("gem_item_id", null)
	if gem_id == null: return _failure("empty_socket", "该武器没有镶嵌宝石。")
	if not bool(profile.data.campaign.first_clears.get("sky_lord", false)): return _failure("locked", "完成天空领主后开放拆卸。")
	if int(profile.data.gold) < 30: return _failure("insufficient_gold", "金币不足，无法拆卸宝石。")
	return {"ok":true,"code":"preview","instance_id":instance_id,"gem_id":str(gem_id),"costs":{"gold":30},"rewards":{str(gem_id):1},"delta":_gem_delta("", gem_id),"before_snapshot":profile.preview_combat_snapshot({"weapon_instance_id":instance_id}),"after_snapshot":profile.preview_combat_snapshot({"weapon_instance_id":instance_id,"gem_item_id":null}),"reason":""}

func unsocket_gem(instance_id: String) -> Dictionary:
	var preview := preview_unsocket(instance_id)
	if not preview.ok: return preview
	return profile.transaction(func() -> bool:
		var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
		if equipment.is_empty() or equipment.get("gem_item_id", null) == null or int(profile.data.gold) < 30: return false
		profile.data.gold = int(profile.data.gold) - 30
		profile.data.inventory.stacks[str(equipment.gem_item_id)] = int(profile.data.inventory.stacks.get(str(equipment.gem_item_id), 0)) + 1
		equipment.gem_item_id = null
		profile.data.inventory.equipment[instance_id] = equipment
		return true
	, "gem_unsocketed", "宝石已拆卸并返还。", {"preview":preview})

func preview_dismantle(instance_ids: Array) -> Dictionary:
	if instance_ids.is_empty(): return _failure("empty_selection", "请先选择装备。")
	if not bool(profile.data.campaign.first_clears.get("sky_lord", false)): return _failure("locked", "完成天空领主后开放分解。")
	var unique := {}
	var returns := {"enhancement_dust":0}
	for raw_id in instance_ids:
		var instance_id := str(raw_id)
		if unique.has(instance_id): return _failure("duplicate_selection", "同一装备不能重复选择。")
		unique[instance_id] = true
		var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
		var reason := _dismantle_reason(instance_id, equipment)
		if not reason.is_empty(): return _failure("cannot_dismantle", reason)
		returns.enhancement_dust = int(returns.enhancement_dust) + 1
		for material_id in equipment.invested_materials:
			returns[material_id] = int(returns.get(material_id, 0)) + int(floor(float(equipment.invested_materials[material_id]) * 0.3))
	var redundancy_reason := _redundancy_reason(unique.keys())
	if not redundancy_reason.is_empty(): return _failure("cannot_dismantle", redundancy_reason)
	return {"ok":true,"code":"preview","instance_ids":unique.keys(),"costs":{},"rewards":returns,"delta":{"equipment":-unique.size()},"reason":""}

func dismantle(instance_ids: Array) -> Dictionary:
	var preview := preview_dismantle(instance_ids)
	if not preview.ok: return preview
	return profile.transaction(func() -> bool:
		if not _redundancy_reason(instance_ids).is_empty(): return false
		for raw_id in instance_ids:
			var equipment: Dictionary = profile.data.inventory.equipment.get(str(raw_id), {})
			if not _dismantle_reason(str(raw_id), equipment).is_empty(): return false
		for item_id in preview.rewards: profile.data.inventory.stacks[item_id] = int(profile.data.inventory.stacks.get(item_id, 0)) + int(preview.rewards[item_id])
		for raw_id in instance_ids: profile.data.inventory.equipment.erase(str(raw_id))
		return true
	, "dismantled", "装备已分解。", {"preview":preview})

func _gem_delta(new_gem: String, old_gem: Variant) -> Dictionary:
	var before := ItemData.definition(str(old_gem)) if old_gem != null else {}
	var after := ItemData.definition(new_gem)
	return {"max_hp":int(after.get("max_hp", 0)) - int(before.get("max_hp", 0)), "direct_hit_bonus":int(after.get("direct_hit_bonus", 0)) - int(before.get("direct_hit_bonus", 0))}

func _dismantle_reason(instance_id: String, equipment: Dictionary) -> String:
	if equipment.is_empty(): return "装备不存在。"
	if instance_id in [str(profile.data.loadout.get("weapon_instance_id", "")), str(profile.data.loadout.get("charm_instance_id", ""))]: return "当前装备不能分解。"
	if bool(equipment.get("locked", false)): return "已锁定装备不能分解。"
	if equipment.get("gem_item_id", null) != null: return "镶嵌宝石的装备不能分解。"
	return ""

func _redundancy_reason(instance_ids: Array) -> String:
	var selected_by_template := {}
	for raw_id in instance_ids:
		var equipment: Dictionary = profile.data.inventory.equipment.get(str(raw_id), {})
		if equipment.is_empty(): return "装备不存在。"
		var template_id := str(equipment.get("template_id", ""))
		selected_by_template[template_id] = int(selected_by_template.get(template_id, 0)) + 1
	for template_id in selected_by_template:
		var owned := 0
		for instance_id in profile.data.inventory.equipment:
			if str(profile.data.inventory.equipment[instance_id].get("template_id", "")) == str(template_id): owned += 1
		if owned - int(selected_by_template[template_id]) < 1: return "暂无同类多余装备。"
	return ""

func _failure(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":code,"message":message}
