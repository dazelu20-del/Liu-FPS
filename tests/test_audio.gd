# Headless audio tests: prove the gunshot sound is wired up and actually
# starts playing when a character fires. Run:
#   godot --headless res://tests/test_audio.tscn
extends Node

var failures := 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("  ok - ", label)
	else:
		failures += 1
		push_error("FAIL - " + label)

func _ready() -> void:
	_test_master_bus()
	_test_sample_loads()
	_test_player_configured()
	_test_flash_triggers_playback()
	_test_rapid_fire_always_plays()
	if failures == 0:
		print("ALL AUDIO TESTS PASSED")
		get_tree().quit(0)
	else:
		print("%d AUDIO TESTS FAILED" % failures)
		get_tree().quit(1)

func _test_master_bus() -> void:
	var idx := AudioServer.get_bus_index("Master")
	check(idx != -1, "Master audio bus exists")
	if idx == -1:
		return
	check(not AudioServer.is_bus_mute(idx), "Master bus is not muted")
	check(AudioServer.get_bus_volume_db(idx) > -80.0,
		"Master bus volume is above silence")

func _test_sample_loads() -> void:
	var stream: AudioStream = load("res://assets/sounds/gunshot.wav")
	check(stream != null, "gunshot.wav loads as an AudioStream")
	var reload: AudioStream = load("res://assets/sounds/reload.wav")
	check(reload != null, "reload.wav loads as an AudioStream")

func _test_player_configured() -> void:
	# build a real character body so its _build_body() runs and creates the sfx player
	var body: BaseCharacter = preload("res://scenes/bot.tscn").instantiate()
	add_child(body)
	var sfx: AudioStreamPlayer3D = body.find_child("GunSfx", true, false)
	check(sfx != null, "character has an AudioStreamPlayer3D for gunfire")
	if sfx == null:
		body.queue_free()
		return
	check(sfx.stream != null, "gun sound stream is assigned")
	check(sfx.unit_size > 0.0, "sound carries (unit_size > 0)")
	check(sfx.max_polyphony > 1, "polyphonic voices enabled (no rapid-fire drop)")
	check(sfx.attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED,
		"spatial attenuation is enabled")
	body.queue_free()

func _test_flash_triggers_playback() -> void:
	var body: BaseCharacter = preload("res://scenes/bot.tscn").instantiate()
	add_child(body)
	var sfx: AudioStreamPlayer3D = body.find_child("GunSfx", true, false)
	if sfx == null:
		body.queue_free()
		check(false, "flash test skipped (no sfx node)")
		return
	# flash_muzzle is the single hook both players and bots use on fire
	body.flash_muzzle()
	# give the audio server a tick to register playback
	await get_tree().process_frame
	check(sfx.playing, "flash_muzzle() starts the gunshot playing")
	check(body._shoot_flash.light_energy > 0.0,
		"flash_muzzle() also triggers the muzzle light")
	body.queue_free()

func _test_rapid_fire_always_plays() -> void:
	# The player fires faster than the gunshot clip lasts. Every shot must
	# retrigger playback, or rapid fire goes silent mid-burst.
	var body: BaseCharacter = preload("res://scenes/bot.tscn").instantiate()
	add_child(body)
	var sfx: AudioStreamPlayer3D = body.find_child("GunSfx", true, false)
	if sfx == null:
		body.queue_free()
		check(false, "rapid-fire test skipped (no sfx node)")
		return
	var every_shot_played := true
	for i in 8:
		body.flash_muzzle()
		await get_tree().process_frame
		if not sfx.playing:
			every_shot_played = false
	check(every_shot_played,
		"every shot in an 8-round burst retriggers the gunshot")
	body.queue_free()
