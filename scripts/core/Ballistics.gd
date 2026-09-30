class_name Ballistics
extends RefCounted

const DT := 1.0 / 120.0
const GRAVITY := 620.0
const WIND_ACCEL := 22.0
const RADIUS := 24.0
const WIDTH := 1280.0
const STEP := 8.0
const BOTTOM := 557.0

static func terrain() -> PackedFloat32Array:
	var values := PackedFloat32Array()
	for i in range(161):
		var x := i * STEP
		values.append(486.0 + sin(x * 0.006) * 22.0 + sin(x * 0.016 + 0.8) * 12.0)
	return values

static func terrain_variant(kind: String) -> PackedFloat32Array:
	var values := terrain()
	for i in range(values.size()):
		var x := float(i) * STEP
		match kind:
			"tree_bridge": values[i] = 495.0 - 36.0 * exp(-pow((x - 640.0) / 360.0, 2.0)) + sin(x * 0.012) * 5.0
			"spore_corridor": values[i] = 500.0 - 42.0 * exp(-pow((x - 275.0) / 150.0, 2.0)) - 18.0 * exp(-pow((x - 930.0) / 210.0, 2.0)) + sin(x * 0.026) * 10.0
			"moss_guardian": values[i] = 505.0 - 68.0 * exp(-pow((x - 795.0) / 205.0, 2.0)) + 16.0 * exp(-pow((x - 250.0) / 125.0, 2.0))
			"mine_entrance": values[i] = 515.0 - 92.0 * exp(-pow((x - 210.0) / 150.0, 2.0)) + 58.0 * exp(-pow((x - 1010.0) / 190.0, 2.0))
			"mine_fracture": values[i] = 500.0 - 34.0 * sin(x * 0.018) - 28.0 * exp(-pow((x - 640.0) / 120.0, 2.0))
			"mine_furnace": values[i] = 510.0 - 55.0 * exp(-pow((x - 720.0) / 260.0, 2.0)) + 10.0 * sin(x * 0.01)
			# Sky Ruins uses three deliberately separate height fields.  They share the
			# stone-ground rendering, but their ridges make each encounter read and play
			# differently before any encounter mechanic is applied.
			"sky_corridor": values[i] = 508.0 - 34.0 * exp(-pow((x - 260.0) / 170.0, 2.0)) + 30.0 * exp(-pow((x - 760.0) / 240.0, 2.0)) + 9.0 * sin(x * 0.019)
			"sky_altar": values[i] = 500.0 - 53.0 * exp(-pow((x - 330.0) / 170.0, 2.0)) - 53.0 * exp(-pow((x - 950.0) / 170.0, 2.0)) + 43.0 * exp(-pow((x - 640.0) / 115.0, 2.0))
			"sky_lord": values[i] = 512.0 - 78.0 * exp(-pow((x - 640.0) / 265.0, 2.0)) + 18.0 * sin(x * 0.010 + 0.4) + 10.0 * sin(x * 0.027)
	return values

static func height_at(heights: PackedFloat32Array, x: float) -> float:
	var index := clampf(x / STEP, 0.0, float(heights.size() - 1))
	var left := int(index)
	return lerpf(heights[left], heights[mini(left + 1, heights.size() - 1)], index - left)

static func carve(heights: PackedFloat32Array, center: Vector2, radius: float, depth: float = 30.0) -> PackedFloat32Array:
	var result := heights.duplicate()
	for i in range(result.size()):
		var distance := absf(i * STEP - center.x)
		if distance < radius:
			result[i] = minf(BOTTOM, result[i] + sqrt(1.0 - pow(distance / radius, 2.0)) * depth)
	return result

static func velocity(angle: float, power: float, facing: int, weapon: String, mode: String) -> Vector2:
	var speed := GameData.launch_speed(weapon, mode, power)
	return Vector2(cos(deg_to_rad(angle)) * facing, -sin(deg_to_rad(angle))) * speed

static func step(pos: Vector2, vel: Vector2, wind: float, tracking_target: Variant = null) -> Dictionary:
	if tracking_target is Vector2 and pos.distance_to(tracking_target) < 230.0:
		vel = vel.lerp(pos.direction_to(tracking_target) * vel.length(), 5.0 * DT)
	vel += Vector2(wind * WIND_ACCEL, GRAVITY) * DT
	return {"pos": pos + vel * DT, "vel": vel}

static func collision(from: Vector2, to: Vector2, heights: PackedFloat32Array, targets: Array, owner: int, age: float) -> Dictionary:
	var segments := maxi(1, int(ceil(from.distance_to(to) / 3.0)))
	for n in range(1, segments + 1):
		var point := from.lerp(to, float(n) / segments)
		for i in range(targets.size()):
			if i == owner and age < 0.22:
				continue
			if float(targets[i].hp) > 0.0 and point.distance_to(targets[i].pos) <= RADIUS + 4.0:
				return {"kind": "fighter", "pos": point, "target": i}
		if point.x >= 0.0 and point.x <= WIDTH and point.y >= height_at(heights, point.x):
			return {"kind": "ground", "pos": point, "target": -1}
	if to.x < -80.0 or to.x > WIDTH + 80.0 or to.y > 820.0 or age > 10.0:
		return {"kind": "out", "pos": to, "target": -1}
	return {}

static func trace(origin: Vector2, vel: Vector2, wind: float, heights: PackedFloat32Array, targets: Array, owner: int, tracker: bool = false) -> Dictionary:
	var pos := origin
	var points := PackedVector2Array([origin])
	for i in range(1201):
		var next := step(pos, vel, wind, targets[1 - owner].pos if tracker else null)
		var hit := collision(pos, next.pos, heights, targets, owner, (i + 1) * DT)
		pos = next.pos
		vel = next.vel
		if i % 6 == 0:
			points.append(pos)
		if not hit.is_empty():
			points.append(hit.pos)
			return {"points": points, "hit": hit, "time": (i + 1) * DT}
	return {"points": points, "hit": {"kind": "out", "pos": pos, "target": -1}, "time": 10.0}
