# The rifle's state machine — pure logic, no nodes, so tests can run it
# headless. (task-23.md §7: 25 dmg, 0.15 s cooldown, 30 rounds, 1.2 s reload)
class_name Weapon
extends RefCounted

const DAMAGE := 25
const COOLDOWN := 0.15
const MAG_SIZE := 30
const RELOAD_TIME := 1.2

var ammo := MAG_SIZE
var _next_shot_at := 0.0
var _reload_done_at := -1.0

func is_reloading(now: float) -> bool:
	return now < _reload_done_at

func can_fire(now: float) -> bool:
	return ammo > 0 and now >= _next_shot_at and not is_reloading(now)

func fire(now: float) -> bool:
	if not can_fire(now):
		return false
	ammo -= 1
	_next_shot_at = now + COOLDOWN
	return true

func start_reload(now: float) -> bool:
	if ammo == MAG_SIZE or is_reloading(now):
		return false
	_reload_done_at = now + RELOAD_TIME
	return true

func update(now: float) -> void:
	if _reload_done_at > 0.0 and now >= _reload_done_at:
		ammo = MAG_SIZE
		_reload_done_at = -1.0
