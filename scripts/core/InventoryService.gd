class_name InventoryService
extends RefCounted

var profile: PlayerProfile
const RECIPES := {"small_medkit":{"woodchip":2,"enhancement_dust":1},"stamina_tonic":{"woodchip":1,"enhancement_dust":2},"armor_breaker":{"copper_ore":2,"enhancement_dust":2},"echo_gem":{"relic_shard":12,"enhancement_dust":8,"gold":180},"pierce_gem":{"relic_shard":12,"enhancement_dust":8,"gold":180}}

func _init(player_profile: PlayerProfile) -> void:
	profile = player_profile
	profile.ensure_round_one()

func stack_count(item_id: String) -> int:
	return int(profile.data.inventory.stacks.get(item_id, 0))

func inventory_items(category: String = "all", search: String = "", sort_by: String = "quality", source_filter: String = "all") -> Array:
	var items: Array = []
	var needle := search.strip_edges().to_lower()
	for item_id in profile.data.inventory.stacks:
		var definition := ItemData.definition(item_id)
		if definition.is_empty() or (category != "all" and definition.category != category) or (source_filter != "all" and not source_filter in definition.get("source_ids", [])): continue
		if not needle.is_empty() and not str(definition.name).to_lower().contains(needle): continue
		definition.quantity = int(profile.data.inventory.stacks[item_id])
		definition.is_new = item_id in profile.data.inventory.new_items
		definition.acquired_at = int(profile.data.inventory.acquired_at.get(item_id, 0))
		items.append(definition)
	for instance_id in profile.data.inventory.equipment:
		var equipment: Dictionary = profile.data.inventory.equipment[instance_id]
		var definition := ItemData.definition(str(equipment.template_id))
		if definition.is_empty() or (category != "all" and definition.category != category) or (source_filter != "all" and not source_filter in definition.get("source_ids", [])): continue
		if not needle.is_empty() and not str(definition.name).to_lower().contains(needle): continue
		definition.instance_id = instance_id
		definition.level = int(equipment.level)
		definition.locked = bool(equipment.locked)
		definition.gem_item_id = equipment.get("gem_item_id", null)
		definition.is_new = bool(equipment.is_new)
		definition.acquired_at = int(equipment.acquired_at)
		items.append(definition)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if sort_by == "recent": return int(a.acquired_at) > int(b.acquired_at)
		return int(a.quality_rank) > int(b.quality_rank) if int(a.quality_rank) != int(b.quality_rank) else int(a.acquired_at) > int(b.acquired_at)
	)
	return items

func configure_supplies(slots: Array) -> Dictionary:
	if slots.size() > 2: return _failure("too_many_slots", "最多携带两种补给。")
	var seen := {}
	var normalized: Array = []
	for slot in slots:
		if not slot is Dictionary: return _failure("invalid_slot", "补给配置无效。")
		var item_id := str(slot.get("item_id", ""))
		var quantity := int(slot.get("quantity", 0))
		if not ItemData.is_supply(item_id) or quantity < 1 or quantity > 2: return _failure("invalid_supply", "每种补给携带数量为 1 至 2。")
		if seen.has(item_id): return _failure("duplicate_supply", "同类补给不能占用两个槽位。")
		seen[item_id] = true
		normalized.append({"item_id":item_id,"quantity":quantity})
	return profile.transaction(func() -> bool:
		profile.data.loadout.supplies = normalized
		return true
	, "supplies_saved", "补给配置已保存。")

func supply_snapshot() -> Array:
	return profile.data.loadout.supplies.duplicate(true)

func mark_seen(item_id: String, instance_id: String = "") -> Dictionary:
	return profile.transaction(func() -> bool:
		if not instance_id.is_empty():
			var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
			if equipment.is_empty(): return false
			equipment.is_new = false
			profile.data.inventory.equipment[instance_id] = equipment
		elif ItemData.has(item_id):
			profile.data.inventory.new_items.erase(item_id)
		else: return false
		return true
	, "seen", "")

func equip_instance(instance_id: String) -> Dictionary:
	return profile.transaction(func() -> bool:
		var equipment: Dictionary = profile.data.inventory.equipment.get(instance_id, {})
		if equipment.is_empty(): return false
		var category := str(ItemData.definition(str(equipment.template_id)).get("category", ""))
		if category == "weapon": profile.data.loadout.weapon_instance_id = instance_id
		elif category == "charm": profile.data.loadout.charm_instance_id = instance_id
		else: return false
		return true
	, "equipped", "配装已保存。")

func craft_preview(item_id: String, quantity: int) -> Dictionary:
	if not RECIPES.has(item_id) or quantity < 1 or quantity > 99: return _failure("invalid_recipe", "制作数量需为 1 至 99。")
	if item_id in ["echo_gem", "pierce_gem"] and not bool(profile.data.campaign.first_clears.get("sky_lord", false)): return _failure("locked", "完成天空领主后开放宝石制作。")
	var costs := {}
	for material in RECIPES[item_id]: costs[material] = int(RECIPES[item_id][material]) * quantity
	return {"ok":true,"item_id":item_id,"quantity":quantity,"costs":costs}

func craft(item_id: String, quantity: int) -> Dictionary:
	var preview := craft_preview(item_id, quantity)
	if not preview.ok: return preview
	var costs: Dictionary = preview.costs
	for material in costs:
		if material == "gold":
			if int(profile.data.gold) < int(costs[material]): return _failure("insufficient_materials", "金币或材料不足，制作未执行。")
		elif stack_count(material) < int(costs[material]): return _failure("insufficient_materials", "材料不足，制作未执行。")
	return profile.transaction(func() -> bool:
		for material in costs:
			if material == "gold": profile.data.gold = int(profile.data.gold) - int(costs[material])
			else: profile.data.inventory.stacks[material] = int(profile.data.inventory.stacks.get(material,0)) - int(costs[material])
		profile.data.inventory.stacks[item_id] = int(profile.data.inventory.stacks.get(item_id,0)) + quantity
		profile.data.inventory.acquired_at[item_id] = int(Time.get_unix_time_from_system())
		if not item_id in profile.data.inventory.new_items: profile.data.inventory.new_items.append(item_id)
		return true
	, "crafted", "制作完成。", {"item_id":item_id,"quantity":quantity})

func set_locked(instance_ids: Array, locked: bool) -> Dictionary:
	if instance_ids.is_empty(): return _failure("empty_selection", "请先选择装备。")
	return profile.transaction(func() -> bool:
		for instance_id in instance_ids:
			var equipment: Dictionary = profile.data.inventory.equipment.get(str(instance_id), {})
			if equipment.is_empty(): return false
			equipment.locked = locked
			profile.data.inventory.equipment[str(instance_id)] = equipment
		return true
	, "lock_updated", "装备锁定状态已更新。")

func consume_supply(item_id: String, run_id: String) -> Dictionary:
	if not ItemData.is_supply(item_id): return _failure("not_supply", "这不是副本补给。")
	var result := profile.transaction(func() -> bool:
		var run: Dictionary = profile.data.active_run
		if run.is_empty() or str(run.run_id) != run_id: return false
		var allowed := int(run.supplies.get(item_id, 0))
		var consumed := int(run.consumed.get(item_id, 0))
		if consumed >= allowed or int(profile.data.inventory.stacks.get(item_id, 0)) < 1: return false
		profile.data.inventory.stacks[item_id] = int(profile.data.inventory.stacks[item_id]) - 1
		run.consumed[item_id] = consumed + 1
		profile.data.active_run = run
		return true
	, "supply_consumed", "补给已使用。")
	if result.ok:
		var run: Dictionary = profile.data.active_run
		result.remaining = int(run.supplies.get(item_id, 0)) - int(run.consumed.get(item_id, 0))
		result.stock_remaining = stack_count(item_id)
	return result

func _failure(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":code,"message":message}
