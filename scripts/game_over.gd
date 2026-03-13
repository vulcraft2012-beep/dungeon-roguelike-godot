extends CanvasLayer

signal restart_game

var is_active: bool = false
var final_level: int = 1
var panel: Control
var restart_btn: Button

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	panel = Control.new()
	panel.anchors_preset = Control.PRESET_FULL_RECT
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.draw.connect(_on_draw)
	add_child(panel)

	# Restart button
	restart_btn = Button.new()
	restart_btn.text = "RESTART"
	restart_btn.custom_minimum_size = Vector2(120, 36)
	restart_btn.anchors_preset = Control.PRESET_CENTER
	restart_btn.position = Vector2(-60, 30)
	restart_btn.pressed.connect(_on_restart_pressed)

	# Style the button
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.6, 0.12, 0.1)
	style_normal.border_color = Color(0.8, 0.3, 0.2)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(4)
	restart_btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.75, 0.18, 0.12)
	style_hover.border_color = Color(1, 0.4, 0.25)
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(4)
	restart_btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.45, 0.08, 0.06)
	style_pressed.border_color = Color(0.7, 0.25, 0.15)
	style_pressed.set_border_width_all(2)
	style_pressed.set_corner_radius_all(4)
	restart_btn.add_theme_stylebox_override("pressed", style_pressed)

	restart_btn.add_theme_font_size_override("font_size", 14)
	restart_btn.add_theme_color_override("font_color", Color(1, 0.9, 0.8))
	restart_btn.add_theme_color_override("font_hover_color", Color(1, 1, 0.9))

	panel.add_child(restart_btn)
	restart_btn.visible = false

func show_game_over(level: int):
	final_level = level
	is_active = true
	visible = true
	restart_btn.visible = true
	get_tree().paused = true
	panel.queue_redraw()

	# Center button properly
	await get_tree().process_frame
	var vp_size = panel.size
	restart_btn.position = Vector2(vp_size.x / 2 - 60, vp_size.y / 2 + 30)

func _on_restart_pressed():
	_do_restart()

func _unhandled_input(event):
	if not is_active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_do_restart()
		get_viewport().set_input_as_handled()

func _do_restart():
	is_active = false
	visible = false
	restart_btn.visible = false
	get_tree().paused = false
	restart_game.emit()

func _on_draw():
	if not is_active:
		return

	var canvas = panel
	var size = canvas.size

	# Dark overlay
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.85))

	# Skull decoration
	var cx = size.x / 2
	var cy = size.y / 2 - 50
	canvas.draw_circle(Vector2(cx, cy), 14, Color(0.7, 0.65, 0.55))
	canvas.draw_circle(Vector2(cx, cy + 2), 12, Color(0.65, 0.6, 0.5))
	# Eyes
	canvas.draw_circle(Vector2(cx - 5, cy - 2), 3, Color(0.1, 0.1, 0.1))
	canvas.draw_circle(Vector2(cx + 5, cy - 2), 3, Color(0.1, 0.1, 0.1))
	# Nose
	canvas.draw_rect(Rect2(cx - 1, cy + 3, 2, 3), Color(0.2, 0.2, 0.2))
	# Teeth
	for i in 5:
		canvas.draw_rect(Rect2(cx - 6 + i * 3, cy + 9, 2, 3), Color(0.75, 0.7, 0.6))

	# GAME OVER text
	canvas.draw_string(ThemeDB.fallback_font, Vector2(cx - 55, cy + 35),
		"GAME OVER", HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(0.9, 0.15, 0.1))

	# Level reached
	canvas.draw_string(ThemeDB.fallback_font, Vector2(cx - 55, cy + 55),
		"Level " + str(final_level), HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.8, 0.8, 0.8))

	# Hint
	canvas.draw_string(ThemeDB.fallback_font, Vector2(cx - 65, cy + 100),
		"or press [R]", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.5, 0.5, 0.5))
