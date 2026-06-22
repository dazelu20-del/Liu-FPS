# Headless rule tests (task-23.md §9): damage math and ammo.
# Run: godot --headless res://tests/test_rules.tscn
extends Node

var failures := 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok - ", label)
	else:
		failures += 1
		push_error("FAIL - " + label)

func _ready() -> void:
	_test_weapon()
	_test_health()
	if failures == 0:
		print("ALL RULE TESTS PASSED")
		get_tree().quit(0)
	else:
		print("%d RULE TESTS FAILED" % failures)
		get_tree().quit(1)

func _test_weapon() -> void:
	var weapon := Weapon.new()
	check(weapon.fire(0.0), "first shot fires")
	check(not weapon.fire(0.05), "cooldown blocks 0.05s later")
	check(weapon.fire(0.2), "fires again after cooldown")
	check(weapon.ammo == 28, "two shots used two rounds")
	for index in range(28):
		weapon.fire(1.0 + index)
	check(weapon.ammo == 0, "magazine empties")
	check(not weapon.fire(100.0), "empty mag cannot fire")
	weapon.start_reload(100.0)
	check(weapon.is_reloading(100.5), "reload takes time")
	weapon.update(101.3)
	check(weapon.ammo == Weapon.MAG_SIZE, "reload refills to 30")

func _test_health() -> void:
	var health := Health.new()
	add_child(health)            # needs a tree for rpc(call_local)
	var deaths := []
	health.died.connect(func(): deaths.append(true))
	health.apply_damage(25)
	check(health.hp == 75, "25 damage leaves 75 hp")
	health.apply_damage(80)
	check(health.hp == 0, "hp clamps at 0")
	check(deaths.size() == 1, "died fires exactly once")
	health.apply_damage(10)
	check(health.hp == 0, "the dead take no damage")
