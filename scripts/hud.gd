# Health, ammo, alive count, crosshair, and the win screen.
# Everything talks to the HUD through the "hud" group — no hard wiring.
# All controls are anchored, so the HUD survives any window size.
extends CanvasLayer

const GREEN := Color(0.3, 0.8, 0.35)
const RED := Color(0.9, 0.25, 0.2)
const BAR_WIDTH := 240.0

var _hp_fill: ColorRect
var _hp_text: Label
var _ammo: Label
var _alive: Label
var _message: Label
var _hit_marker: Label
var _reticle: Control
var _overlay: ColorRect

func _ready() -> void:
	add_to_group("hud")
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	_build_hp_bar()
	_ammo = _label(Control.PRESET_BOTTOM_RIGHT, "30 / 30", 30,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_alive = _label(Control.PRESET_TOP_RIGHT, "", 22,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_message = _label(Control.PRESET_CENTER, "", 42,
		HORIZONTAL_ALIGNMENT_CENTER)
	_message.offset_top = -160
	_message.offset_bottom = -100
	_hit_marker = _label(Control.PRESET_CENTER, "✕", 30,
		HORIZONTAL_ALIGNMENT_CENTER)
	_hit_marker.offset_top = -64
	_hit_marker.offset_bottom = -24
	_hit_marker.modulate.a = 0.0
	_build_crosshair()

func _process(_delta: float) -> void:
	_hit_marker.modulate.a = maxf(_hit_marker.modulate.a - _delta * 3.0, 0.0)
	if _reticle:
		_reticle.visible = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var alive := 0
	for body in get_tree().get_nodes_in_group("characters"):
		if not body.is_dead():
			alive += 1
	_alive.text = "%d alive" % alive

# --- group API (called from anywhere via call_group) ---------------------------

func set_hp(hp: int) -> void:
	_hp_fill.size.x = BAR_WIDTH * hp / 100.0
	_hp_fill.color = RED if hp < 35 else GREEN
	_hp_text.text = str(hp)

func set_ammo(ammo: int, reloading: bool) -> void:
	_ammo.text = "Reloading…" if reloading else "%d / 30" % ammo

func show_hit_marker() -> void:
	_hit_marker.modulate.a = 1.0

func flash_message(text: String) -> void:
	_message.text = text
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(func(): if _message.text == text: _message.text = "")

func show_death() -> void:
	_overlay.visible = true
	_message.text = "You are down — spectating"

func show_winner(winner: String) -> void:
	_overlay.visible = true
	_message.text = "🏆  WINNER:  %s" % winner

# --- widget builders ------------------------------------------------------------

func _build_hp_bar() -> void:
	var back := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", style)
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = 24
	back.offset_right = 24 + BAR_WIDTH + 8
	back.offset_top = -56
	back.offset_bottom = -34
	add_child(back)
	_hp_fill = ColorRect.new()
	_hp_fill.color = GREEN
	_hp_fill.position = Vector2(4, 4)
	_hp_fill.size = Vector2(BAR_WIDTH, 14)
	back.add_child(_hp_fill)
	_hp_text = Label.new()
	_hp_text.text = "100"
	_hp_text.add_theme_font_size_override("font_size", 16)
	_hp_text.add_theme_color_override("font_color", Color.WHITE)
	_hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hp_text.add_theme_constant_override("outline_size", 4)
	_hp_text.position = Vector2(BAR_WIDTH + 16, -2)
	back.add_child(_hp_text)

func _label(preset: int, text: String, size: int, alignment: int,
		backdrop := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = alignment
	if backdrop:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.35)
		style.set_corner_radius_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		label.add_theme_stylebox_override("normal", style)
	if preset == Control.PRESET_CENTER_TOP:
		# a full-width strip along the top; the container centers the pill
		var strip := CenterContainer.new()
		strip.anchor_right = 1.0
		strip.offset_top = 12
		strip.offset_bottom = 52
		strip.add_child(label)
		add_child(strip)
		return label
	add_child(label)
	label.set_anchors_preset(preset)
	match preset:
		Control.PRESET_TOP_RIGHT:
			label.offset_left = -360
			label.offset_right = -24
			label.offset_top = 16
		Control.PRESET_BOTTOM_RIGHT:
			label.offset_left = -360
			label.offset_right = -24
			label.offset_top = -64
			label.offset_bottom = -24
		Control.PRESET_CENTER:
			label.offset_left = -400
			label.offset_right = 400
	return label

func _build_crosshair() -> void:
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_crosshair)
	add_child(_reticle)

func _draw_crosshair() -> void:
	const GAP := 5.0
	const ARM := 10.0
	const WHITE := Color(1, 1, 1, 0.95)
	const OUTLINE := Color(0, 0, 0, 0.85)
	var center := Vector2.ZERO
	for width in [3.0, 1.5]:
		var color := OUTLINE if width == 3.0 else WHITE
		_reticle.draw_line(center + Vector2(-GAP - ARM, 0),
			center + Vector2(-GAP, 0), color, width, true)
		_reticle.draw_line(center + Vector2(GAP, 0),
			center + Vector2(GAP + ARM, 0), color, width, true)
		_reticle.draw_line(center + Vector2(0, -GAP - ARM),
			center + Vector2(0, -GAP), color, width, true)
		_reticle.draw_line(center + Vector2(0, GAP),
			center + Vector2(0, GAP + ARM), color, width, true)
	# tiny center dot so aim point is obvious
	_reticle.draw_circle(center, 2.0, OUTLINE)
	_reticle.draw_circle(center, 1.0, WHITE)
