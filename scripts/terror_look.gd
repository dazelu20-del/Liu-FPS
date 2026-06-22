# Bot appearance: black head only.
class_name TerrorLook
extends RefCounted

const BLACK_HEAD := Color(0.05, 0.05, 0.05)
const TAN_BODY := Color(0.74, 0.58, 0.40)

static func apply(model: Node3D) -> void:
	_hide_extra_gear(model)
	_tint_meshes(model)

static func _hide_extra_gear(node: Node) -> void:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		if ("cape" in lower or "knife" in lower or "crossbow" in lower
				or "throwable" in lower):
			node.visible = false
	for child in node.get_children():
		_hide_extra_gear(child)

static func _tint_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		if lower.ends_with("_head") or lower == "rogue_head" or lower == "knight_head":
			(node as MeshInstance3D).material_override = _mat(BLACK_HEAD)
		elif "body" in lower:
			(node as MeshInstance3D).material_override = _mat(TAN_BODY)
	for child in node.get_children():
		_tint_meshes(child)

static func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
