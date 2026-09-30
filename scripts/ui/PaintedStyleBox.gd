class_name PaintedStyleBox
extends StyleBox

# Styles.painted_box supplies this atlas's 80px source border; 64 is only the
# fallback for callers that do not override it. Compact controls need a much
# thinner on-screen frame, so this custom nine-slice keeps the borders independent.
var texture: Texture2D
var source_region := Rect2(0, 0, 512, 512)
var source_border := 64.0
var target_border := 12.0
var modulate_color := Color.WHITE

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var horizontal := minf(target_border, rect.size.x * 0.5)
	var vertical := minf(target_border, rect.size.y * 0.5)
	var source_horizontal := minf(source_border, source_region.size.x * 0.5)
	var source_vertical := minf(source_border, source_region.size.y * 0.5)
	var xs := PackedFloat32Array([rect.position.x, rect.position.x + horizontal, rect.end.x - horizontal, rect.end.x])
	var ys := PackedFloat32Array([rect.position.y, rect.position.y + vertical, rect.end.y - vertical, rect.end.y])
	var us := PackedFloat32Array([source_region.position.x, source_region.position.x + source_horizontal, source_region.end.x - source_horizontal, source_region.end.x])
	var vs := PackedFloat32Array([source_region.position.y, source_region.position.y + source_vertical, source_region.end.y - source_vertical, source_region.end.y])
	var texture_rid := texture.get_rid()
	for row in range(3):
		for column in range(3):
			var destination := Rect2(Vector2(xs[column], ys[row]), Vector2(xs[column + 1] - xs[column], ys[row + 1] - ys[row]))
			var source := Rect2(Vector2(us[column], vs[row]), Vector2(us[column + 1] - us[column], vs[row + 1] - vs[row]))
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, destination, texture_rid, source, modulate_color, false, true)
