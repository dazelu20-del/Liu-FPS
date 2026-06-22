# Procedural rifle meshes — FPS viewmodel for the local player and a smaller
# world gun other players see instead of the KayKit sword/shield props.
class_name FpsGun
extends RefCounted

const MELEE_NAME_HINTS := [
	"sword", "shield", "dagger", "staff", "axe", "bow", "wand",
	"knife", "crossbow", "throwable",
]

static func strip_melee_weapons(model: Node) -> void:
	_visit_melee(model)

static func _visit_melee(node: Node) -> void:
	if node is MeshInstance3D:
		var lower := node.name.to_lower()
		for hint in MELEE_NAME_HINTS:
			if hint in lower:
				node.visible = false
				break
	for child in node.get_children():
		_visit_melee(child)

static func build_viewmodel(camera: Camera3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Viewmodel"
	root.position = Vector3(0.28, -0.2, -0.42)
	root.rotation_degrees = Vector3(0.0, -8.0, 0.0)
	camera.add_child(root)
	_build_rifle(root, 1.0)
	return root

static func build_world_gun(model: Node3D) -> Node3D:
	var mount := Node3D.new()
	mount.name = "WorldGun"
	var hand := model.find_child("hand.r", true, false) as Node3D
	if hand:
		mount.position = Vector3(0.04, 0.02, -0.08)
		mount.rotation_degrees = Vector3(-78.0, -4.0, 8.0)
		hand.add_child(mount)
	else:
		mount.position = Vector3(0.22, 0.92, -0.38)
		mount.rotation_degrees = Vector3(-12.0, -6.0, 0.0)
		model.add_child(mount)
	_build_rifle(mount, 0.55)
	return mount

static func muzzle_node(gun_root: Node3D) -> Node3D:
	return gun_root.get_node("Muzzle") as Node3D

static func _build_rifle(parent: Node3D, scale: float) -> void:
	var metal := _metal_mat()
	var dark := _dark_mat()

	var receiver := _box(Vector3(0.07, 0.1, 0.32) * scale, metal)
	receiver.position = Vector3(0.0, 0.0, -0.04 * scale)
	parent.add_child(receiver)

	var barrel := _cylinder(0.018 * scale, 0.36 * scale, metal)
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0.0, 0.02 * scale, -0.28 * scale)
	parent.add_child(barrel)

	var handguard := _box(Vector3(0.06, 0.06, 0.18) * scale, dark)
	handguard.position = Vector3(0.0, -0.01 * scale, -0.18 * scale)
	parent.add_child(handguard)

	var mag := _box(Vector3(0.045, 0.12, 0.07) * scale, dark)
	mag.position = Vector3(0.0, -0.1 * scale, 0.02 * scale)
	mag.rotation_degrees.x = 8.0
	parent.add_child(mag)

	var grip := _box(Vector3(0.05, 0.1, 0.05) * scale, dark)
	grip.position = Vector3(0.0, -0.08 * scale, 0.1 * scale)
	grip.rotation_degrees.x = 18.0
	parent.add_child(grip)

	var stock := _box(Vector3(0.055, 0.08, 0.16) * scale, dark)
	stock.position = Vector3(0.0, 0.01 * scale, 0.2 * scale)
	parent.add_child(stock)

	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.02 * scale, -0.46 * scale)
	parent.add_child(muzzle)

static func _metal_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.34, 0.36)
	mat.metallic = 0.85
	mat.roughness = 0.35
	return mat

static func _dark_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.14, 0.15)
	mat.metallic = 0.4
	mat.roughness = 0.55
	return mat

static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	return mesh

static func _cylinder(radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	mesh.mesh = cyl
	mesh.material_override = mat
	return mesh
