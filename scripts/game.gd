# The match referee: builds the arena, spawns everyone, applies damage,
# and decides the winner. All authority lives here, on the host.
extends Node3D

const ARENA_SIZE := 280.0
const ROAD_WIDTH := 14.0
const SIDEWALK_WIDTH := 4.0
const BUILDING_INSET := 22.0
const BOUNDARY_MARGIN := 6.0
const PLAYER_SPAWN := Vector3(0.0, 0.5, 20.0)
const BOT_SPAWN_MIN := 75.0
const BOT_SPAWN_MAX := 115.0

var match_over := false
var _win_accum := 0.0

@onready var players: Node3D = Node3D.new()

func _ready() -> void:
	name = "Game"
	_build_environment()
	_build_arena()
	players.name = "Players"
	add_child(players)

	add_child(load("res://scenes/hud.tscn").instantiate())

	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--smoke" or arg == "--botmatch" or arg.begins_with("--shot"):
			Net.bot_count = maxi(Net.bot_count, 5)

	if multiplayer.is_server():
		_spawn_player(1)
		for index in Net.bot_count:
			_spawn_bot(index)
		multiplayer.peer_connected.connect(_on_peer_joined)
		multiplayer.peer_disconnected.connect(_on_peer_left)
	_handle_cli_flags(args)

# --- spawning ----------------------------------------------------------------

func _spawn_bot_position(index: int, total: int) -> Vector3:
	var slots := maxi(total, 1)
	var angle := TAU * float(index) / float(slots) + PI * 0.35
	var radius := lerpf(BOT_SPAWN_MIN, BOT_SPAWN_MAX,
		float((index * 2 + 1) % 5) / 4.0)
	return Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)

func _on_peer_joined(peer_id: int) -> void:
	# tell the newcomer about everyone already here…
	for body in players.get_children():
		if body.name.begins_with("Player_"):
			_spawn_remote_player.rpc_id(peer_id, int(str(body.name).split("_")[1]))
		else:
			_spawn_remote_bot.rpc_id(peer_id, int(str(body.name).split("_")[1]))
	# …then spawn their body everywhere
	_spawn_player(peer_id)

func _on_peer_left(peer_id: int) -> void:
	var body := players.get_node_or_null("Player_%d" % peer_id)
	if body:
		body.queue_free()

func _spawn_player(peer_id: int) -> void:
	_spawn_remote_player.rpc(peer_id)
	_spawn_remote_player(peer_id)

func _spawn_bot(index: int) -> void:
	_spawn_remote_bot.rpc(index)
	_spawn_remote_bot(index)

@rpc("authority", "call_remote", "reliable")
func _spawn_remote_player(peer_id: int) -> void:
	if players.has_node("Player_%d" % peer_id):
		return
	var body: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	body.name = "Player_%d" % peer_id
	body.position = PLAYER_SPAWN
	players.add_child(body)
	body.set_multiplayer_authority(peer_id)
	body.add_to_group("characters")
	body.add_to_group("players")

@rpc("authority", "call_remote", "reliable")
func _spawn_remote_bot(index: int) -> void:
	if players.has_node("Bot_%d" % index):
		return
	var body: CharacterBody3D = load("res://scenes/bot.tscn").instantiate()
	body.name = "Bot_%d" % index
	body.position = _spawn_bot_position(index, Net.bot_count)
	players.add_child(body)
	body.set_multiplayer_authority(1)
	body.add_to_group("characters")
	body.add_to_group("bots")

# --- damage (host = referee) -----------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_hit(target_path: NodePath, damage: int) -> void:
	if not multiplayer.is_server():
		return
	apply_hit(target_path, mini(damage, Weapon.DAMAGE))

func apply_hit(target_path: NodePath, damage: int) -> void:
	var target := _find_character(get_node_or_null(target_path))
	if target and not target.is_dead():
		target.health.apply_damage(damage)

func _find_character(node: Node) -> BaseCharacter:
	# The path may point at a child mesh/collision; walk up to the owning body.
	var current := node
	while current:
		if current is BaseCharacter:
			return current
		current = current.get_parent()
	return null

# --- win condition ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not multiplayer.is_server() or match_over:
		return
	_win_accum += delta
	if _win_accum < 1.0:
		return
	_win_accum = 0.0
	var alive: Array[Node] = []
	for body in get_tree().get_nodes_in_group("characters"):
		if not body.is_dead():
			alive.append(body)
	if alive.size() == 1 and players.get_child_count() >= 2:
		_announce_winner.rpc(alive[0].display_name)
		_announce_winner(alive[0].display_name)
	elif alive.is_empty() and players.get_child_count() >= 1:
		_announce_winner.rpc("Nobody")
		_announce_winner("Nobody")

@rpc("authority", "call_remote", "reliable")
func _announce_winner(winner: String) -> void:
	if match_over:
		return
	match_over = true
	get_tree().call_group("hud", "show_winner", winner)
	await get_tree().create_timer(8.0).timeout
	Net.back_to_menu()

# --- arena building ---------------------------------------------------------------

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -48, 0)
	sun.light_color = Color(0.72, 0.66, 0.58)
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 120, 0)
	fill.light_color = Color(0.45, 0.48, 0.55)
	fill.light_energy = 0.2
	add_child(fill)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.33, 0.38)
	sky_mat.sky_horizon_color = Color(0.42, 0.38, 0.34)
	sky_mat.ground_horizon_color = Color(0.22, 0.20, 0.18)
	sky_mat.ground_bottom_color = Color(0.12, 0.11, 0.10)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = sky_mat
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.38, 0.36, 0.34)
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.48, 0.44, 0.40)
	environment.fog_density = 0.008
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.92
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 0.72
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

func _build_arena() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var half := ARENA_SIZE / 2.0
	_build_ground(half)
	_build_street_rubble(rng, half)
	_build_surrounding_buildings(rng, half)
	_build_invisible_bounds(half)
	_scatter_debris(rng, half)

func _build_ground(half: float) -> void:
	var dirt := Color(0.26, 0.24, 0.21)
	var asphalt := Color(0.18, 0.17, 0.16)
	var asphalt_worn := Color(0.24, 0.22, 0.20)
	var sidewalk := Color(0.34, 0.33, 0.31)
	var curb := Color(0.30, 0.28, 0.26)
	var road_len := ARENA_SIZE * 0.92
	var road_x := ROAD_WIDTH / 2.0 + SIDEWALK_WIDTH

	_add_surface(Vector3(0, -0.35, 0), Vector3(ARENA_SIZE, 0.7, ARENA_SIZE), dirt, 0.95)
	_add_surface(Vector3(0, 0.02, 0), Vector3(ROAD_WIDTH, 0.06, road_len), asphalt, 0.92)
	_add_surface(Vector3(0, 0.05, 0), Vector3(ROAD_WIDTH * 0.35, 0.04, road_len * 0.8),
		asphalt_worn, 0.88)
	_add_surface(Vector3(-road_x, 0.04, 0), Vector3(SIDEWALK_WIDTH, 0.08, road_len), sidewalk, 0.85)
	_add_surface(Vector3(road_x, 0.04, 0), Vector3(SIDEWALK_WIDTH, 0.08, road_len), sidewalk, 0.85)
	_add_surface(Vector3(-(road_x + 0.5), 0.06, 0), Vector3(0.5, 0.1, road_len), curb, 0.8)
	_add_surface(Vector3(road_x + 0.5, 0.06, 0), Vector3(0.5, 0.1, road_len), curb, 0.8)

func _build_street_rubble(rng: RandomNumberGenerator, half: float) -> void:
	var rubble := Color(0.38, 0.35, 0.32)
	var road_x := ROAD_WIDTH / 2.0 + SIDEWALK_WIDTH
	for index in 40:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(road_x - 1.0, road_x + 7.0)
		var z := rng.randf_range(-half + 20, half - 20)
		var size := Vector3(
			rng.randf_range(0.6, 2.8), rng.randf_range(0.3, 1.2), rng.randf_range(0.6, 2.4))
		_add_surface(Vector3(x, size.y / 2, z), size,
			rubble.darkened(rng.randf_range(0.0, 0.2)), 0.98)

func _building_palette() -> Array[Color]:
	return [
		Color(0.62, 0.54, 0.36),
		Color(0.44, 0.47, 0.40),
		Color(0.36, 0.27, 0.21),
		Color(0.51, 0.50, 0.47),
		Color(0.57, 0.49, 0.38),
	]

func _build_surrounding_buildings(rng: RandomNumberGenerator, half: float) -> void:
	var inset := BUILDING_INSET
	# Rows on all four sides facing inward toward the player.
	_build_ruined_row_x(rng, -half + inset, 1.0)
	_build_ruined_row_x(rng, half - inset, -1.0)
	_build_ruined_row_z(rng, -half + inset, 1.0)
	_build_ruined_row_z(rng, half - inset, -1.0)

func _build_ruined_row_x(rng: RandomNumberGenerator, row_z: float, face: float) -> void:
	var palette := _building_palette()
	var x := -ARENA_SIZE / 2.0 + 24.0
	while x < ARENA_SIZE / 2.0 - 24.0:
		var width := rng.randf_range(11.0, 17.0)
		var floors := rng.randi_range(3, 5)
		var color: Color = palette[rng.randi() % palette.size()]
		_add_ruined_building_x(rng, Vector3(x + width / 2.0, 0, row_z), width, floors,
			color, face)
		x += width + rng.randf_range(2.0, 5.0)

func _build_ruined_row_z(rng: RandomNumberGenerator, row_x: float, face: float) -> void:
	var palette := _building_palette()
	var z := -ARENA_SIZE / 2.0 + 24.0
	while z < ARENA_SIZE / 2.0 - 24.0:
		var width := rng.randf_range(11.0, 17.0)
		var floors := rng.randi_range(3, 5)
		var color: Color = palette[rng.randi() % palette.size()]
		_add_ruined_building_z(rng, Vector3(row_x, 0, z + width / 2.0), width, floors,
			color, face)
		z += width + rng.randf_range(2.0, 5.0)

func _build_invisible_bounds(half: float) -> void:
	var wall_h := 14.0
	var thick := 4.0
	var edge := half - BOUNDARY_MARGIN
	var span := ARENA_SIZE - BOUNDARY_MARGIN * 2.0
	_add_collision_wall(Vector3(0, wall_h / 2.0, -edge), Vector3(span, wall_h, thick))
	_add_collision_wall(Vector3(0, wall_h / 2.0, edge), Vector3(span, wall_h, thick))
	_add_collision_wall(Vector3(-edge, wall_h / 2.0, 0), Vector3(thick, wall_h, span))
	_add_collision_wall(Vector3(edge, wall_h / 2.0, 0), Vector3(thick, wall_h, span))

func _add_collision_wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)

func _add_ruined_building_x(rng: RandomNumberGenerator, base: Vector3, width: float,
		floors: int, wall_color: Color, face: float) -> void:
	var floor_h := 3.1
	var depth := rng.randf_range(9.0, 12.0)
	var interior := wall_color.darkened(0.22)
	var frame := wall_color.darkened(0.12)
	var z := base.z + face * depth / 2.0
	for floor in floors:
		var y := float(floor) * floor_h + floor_h / 2.0
		var damage := rng.randf()
		var slab_w := width * lerpf(0.95, 0.55, damage * 0.35)
		_add_surface(Vector3(base.x, y - floor_h / 2.0 + 0.12, z),
			Vector3(slab_w, 0.22, depth * 0.92), interior, 0.9)

		var wall_h := floor_h * rng.randf_range(0.65, 1.0)
		if floor == floors - 1:
			wall_h *= rng.randf_range(0.35, 0.75)
		_add_surface(Vector3(base.x, y - (floor_h - wall_h) / 2.0, z + face * depth / 2.0),
			Vector3(width, wall_h, 0.45), wall_color, 0.82)

		var side_w := width * rng.randf_range(0.25, 0.4)
		_add_surface(
			Vector3(base.x - width / 2.0 + side_w / 2.0, y, z + face * depth * 0.15),
			Vector3(side_w, wall_h * 0.9, depth * 0.35), frame, 0.85)
		_add_surface(
			Vector3(base.x + width / 2.0 - side_w / 2.0, y, z + face * depth * 0.15),
			Vector3(side_w, wall_h * 0.9, depth * 0.35), frame, 0.85)

		for _i in rng.randi_range(2, 5):
			var wx := base.x + rng.randf_range(-width / 2.5, width / 2.5)
			var wy := y + rng.randf_range(-floor_h / 3.0, floor_h / 3.5)
			_add_surface(Vector3(wx, wy, z + face * (depth / 2.0 + 0.2)),
				Vector3(rng.randf_range(1.0, 2.2), rng.randf_range(1.2, 2.4), 0.35),
				Color(0.08, 0.07, 0.06), 0.75)

	for _chunk in rng.randi_range(2, 5):
		var cx := base.x + rng.randf_range(-width / 2.5, width / 2.5)
		var cz := z + rng.randf_range(-depth / 3.0, depth / 3.0)
		var size := Vector3(rng.randf_range(1.5, 4.0), rng.randf_range(0.5, 1.8),
			rng.randf_range(1.5, 3.5))
		_add_surface(Vector3(cx, float(floors) * floor_h + size.y / 2.0, cz),
			size, wall_color.darkened(rng.randf_range(0.1, 0.35)), 0.95)

	for _pile in rng.randi_range(3, 7):
		var px := base.x + rng.randf_range(-width / 2.0, width / 2.0)
		var pz := z - face * (depth / 2.0 + rng.randf_range(1.0, 3.5))
		var psize := Vector3(rng.randf_range(0.8, 3.0), rng.randf_range(0.4, 1.4),
			rng.randf_range(0.8, 2.5))
		_add_surface(Vector3(px, psize.y / 2.0, pz), psize,
			Color(0.40, 0.37, 0.33), 0.98)

func _add_ruined_building_z(rng: RandomNumberGenerator, base: Vector3, width: float,
		floors: int, wall_color: Color, face: float) -> void:
	var floor_h := 3.1
	var depth := rng.randf_range(9.0, 12.0)
	var interior := wall_color.darkened(0.22)
	var frame := wall_color.darkened(0.12)
	var x := base.x + face * depth / 2.0
	for floor in floors:
		var y := float(floor) * floor_h + floor_h / 2.0
		var damage := rng.randf()
		var slab_w := width * lerpf(0.95, 0.55, damage * 0.35)
		_add_surface(Vector3(x, y - floor_h / 2.0 + 0.12, base.z),
			Vector3(depth * 0.92, 0.22, slab_w), interior, 0.9)

		var wall_h := floor_h * rng.randf_range(0.65, 1.0)
		if floor == floors - 1:
			wall_h *= rng.randf_range(0.35, 0.75)
		_add_surface(Vector3(x + face * depth / 2.0, y - (floor_h - wall_h) / 2.0, base.z),
			Vector3(0.45, wall_h, width), wall_color, 0.82)

		var side_w := width * rng.randf_range(0.25, 0.4)
		_add_surface(
			Vector3(x + face * depth * 0.15, y, base.z - width / 2.0 + side_w / 2.0),
			Vector3(depth * 0.35, wall_h * 0.9, side_w), frame, 0.85)
		_add_surface(
			Vector3(x + face * depth * 0.15, y, base.z + width / 2.0 - side_w / 2.0),
			Vector3(depth * 0.35, wall_h * 0.9, side_w), frame, 0.85)

		for _i in rng.randi_range(2, 5):
			var wz := base.z + rng.randf_range(-width / 2.5, width / 2.5)
			var wy := y + rng.randf_range(-floor_h / 3.0, floor_h / 3.5)
			_add_surface(Vector3(x + face * (depth / 2.0 + 0.2), wy, wz),
				Vector3(0.35, rng.randf_range(1.2, 2.4), rng.randf_range(1.0, 2.2)),
				Color(0.08, 0.07, 0.06), 0.75)

	for _chunk in rng.randi_range(2, 5):
		var cx := x + rng.randf_range(-depth / 3.0, depth / 3.0)
		var cz := base.z + rng.randf_range(-width / 2.5, width / 2.5)
		var size := Vector3(rng.randf_range(1.5, 3.5), rng.randf_range(0.5, 1.8),
			rng.randf_range(1.5, 4.0))
		_add_surface(Vector3(cx, float(floors) * floor_h + size.y / 2.0, cz),
			size, wall_color.darkened(rng.randf_range(0.1, 0.35)), 0.95)

	for _pile in rng.randi_range(3, 7):
		var px := x - face * (depth / 2.0 + rng.randf_range(1.0, 3.5))
		var pz := base.z + rng.randf_range(-width / 2.0, width / 2.0)
		var psize := Vector3(rng.randf_range(0.8, 2.5), rng.randf_range(0.4, 1.4),
			rng.randf_range(0.8, 3.0))
		_add_surface(Vector3(px, psize.y / 2.0, pz), psize,
			Color(0.40, 0.37, 0.33), 0.98)

func _scatter_debris(rng: RandomNumberGenerator, half: float) -> void:
	var burnt := Color(0.16, 0.14, 0.13)
	for index in 18:
		var x := rng.randf_range(-half + 30, half - 30)
		var z := rng.randf_range(-half + 30, half - 30)
		if absf(x) < ROAD_WIDTH / 2.0 + 2.0:
			continue
		var size := Vector3(rng.randf_range(2.0, 6.0), rng.randf_range(1.0, 3.5),
			rng.randf_range(2.0, 5.0))
		_add_surface(Vector3(x, size.y / 2.0, z), size,
			burnt if rng.randf() < 0.25 else Color(0.33, 0.31, 0.28),
			rng.randf_range(0.85, 0.98))

func _add_surface(pos: Vector3, size: Vector3, color: Color, rough: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.metallic = 0.0
	box.material = material
	mesh.mesh = box
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(mesh)
	body.add_child(shape)
	add_child(body)

func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	_add_surface(pos, size, color, 0.9)

# --- automation hooks (smoke tests & screenshots, used by the build) ---------------

func _handle_cli_flags(args: PackedStringArray) -> void:
	if "--smoke" in args:
		await get_tree().create_timer(8.0).timeout
		print("SMOKE OK: game scene ran 8s — players=%d" % players.get_child_count())
		get_tree().quit(0)
	if "--mp-report" in args:
		await get_tree().create_timer(12.0).timeout
		print("MP REPORT: id=%d players=%d" % [
			multiplayer.get_unique_id(), players.get_child_count()])
		get_tree().quit(0)
	if "--botmatch" in args:
		# the playtest from task-23.md §9: a bot match must end with 1 survivor
		var elapsed := 0.0
		while not match_over and elapsed < 180.0:
			await get_tree().create_timer(1.0).timeout
			elapsed += 1.0
		var survivors := 0
		for body in get_tree().get_nodes_in_group("characters"):
			if not body.is_dead():
				survivors += 1
		print("BOTMATCH %s: over=%s survivors=%d after %ds"
			% ["OK" if match_over and survivors <= 1 else "FAIL",
				match_over, survivors, int(elapsed)])
		get_tree().quit(0 if match_over and survivors <= 1 else 1)
	for arg in args:
		if arg.begins_with("--shot="):
			await get_tree().create_timer(1.0).timeout
			# stage the frame: two bots strolling in front of the camera
			var hero := players.get_node_or_null("Player_1")
			if hero:
				hero._set_camera_mode(hero.CameraMode.THIRD_PERSON)
				hero._head.rotation.x = -0.4
				hero._spring.spring_length = 4.0
			for index in 2:
				var bot := players.get_node_or_null("Bot_%d" % index)
				if hero and bot:
					bot.global_position = (hero.global_position
						+ hero.global_transform.basis.z * -(12.0 + index * 5)
						+ Vector3(index * 4 - 2.0, 0, 0))
			await get_tree().create_timer(2.0).timeout
			var image := get_viewport().get_texture().get_image()
			image.save_png(arg.trim_prefix("--shot="))
			print("SCREENSHOT saved")
			get_tree().quit(0)
