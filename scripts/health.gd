# A character's hit points. Damage is only ever applied on the host;
# the result is broadcast so every screen shows the same number.
class_name Health
extends Node

signal changed(hp: int)
signal died

const MAX_HP := 100

var hp := MAX_HP

func is_dead() -> bool:
	return hp <= 0

func apply_damage(amount: int) -> void:
	# Host-only entry point (the referee). Broadcast the result to everyone.
	if not multiplayer.is_server() or is_dead():
		return
	_set_hp.rpc(maxi(hp - amount, 0))

@rpc("authority", "call_local", "reliable")
func _set_hp(value: int) -> void:
	var was_alive := not is_dead()
	hp = value
	changed.emit(hp)
	if was_alive and is_dead():
		died.emit()
