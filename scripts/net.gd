# Autoload "Net" — hosting, joining, and the keyboard/mouse input map.
# The host (peer id 1) is always the referee: damage, zone, and wins
# only ever happen on the host. Clients ask; the host decides.
extends Node

const PORT := 9999
const MAX_PLAYERS := 16

var bot_count := 0
var player_name := "Player"

func _ready() -> void:
	_setup_input_actions()
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _reset("Connection failed"))
	multiplayer.server_disconnected.connect(func(): _reset("Host left"))

# --- entry points (called by the main menu) --------------------------------

func host_match(bots: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	bot_count = bots
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func solo_match(bots: int) -> void:
	host_match(bots)          # solo is just a match nobody else joined

func join_match(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	peer.create_client(ip, PORT)
	multiplayer.multiplayer_peer = peer  # wait for connected_to_server

func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func back_to_menu() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _reset(reason: String) -> void:
	push_warning(reason)
	back_to_menu()

# --- input map in code (reproducible — no editor clicks needed) -------------

func _setup_input_actions() -> void:
	_key_action("move_forward", KEY_W)
	_key_action("move_back", KEY_S)
	_key_action("move_left", KEY_A)
	_key_action("move_right", KEY_D)
	_key_action("jump", KEY_SPACE)
	_key_action("sprint", KEY_SHIFT)
	_key_action("reload", KEY_R)
	_key_action("toggle_mouse", KEY_ESCAPE)
	_key_action("toggle_camera", KEY_V)
	var shoot := InputEventMouseButton.new()
	shoot.button_index = MOUSE_BUTTON_LEFT
	_event_action("shoot", shoot)

func _key_action(action: String, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	_event_action(action, event)

func _event_action(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, event)
