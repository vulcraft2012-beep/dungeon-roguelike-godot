extends CanvasLayer

var health_max: int = 5
var health_current: int = 5
var current_level: int = 1
var enemies_remaining: int = 0
var message_text: String = ""
var message_timer: float = 0.0

@onready var draw_node: Control

func _ready():
	draw_node = Control.new()
	draw_node.anchors_preset = Control.PRESET_FULL_RECT
	draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_node.draw.connect(_on_draw)
	add_child(draw_node)

func _process(delta):
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			message_text = ""
	draw_node.queue_redraw()

func update_health(current: int, max_hp: int = -1):
	health_current = current
	if max_hp > 0:
		health_max = max_hp

func update_level(level: int):
	current_level = level

func update_enemies(count: int):
	enemies_remaining = count

func show_message(text: String, duration: float = 2.0):
	message_text = text
	message_timer = duration

func _on_draw():
	# Health hearts
	for i in health_max:
		var x = 10 + i * 14
		var y = 10
		if i < health_current:
			_draw_heart(draw_node, Vector2(x, y), Color(0.9, 0.1, 0.1))
		else:
			_draw_heart(draw_node, Vector2(x, y), Color(0.3, 0.1, 0.1))

	# Level indicator
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, 35),
		"Level: " + str(current_level), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# Enemies remaining
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, 50),
		"Enemies: " + str(enemies_remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))

	# Controls hint (bottom)
	var hint_y = draw_node.size.y - 12
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, hint_y),
		"LMB:Sword  RMB:Shield  Shift:Roll  Space:Jump  E:Door", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.5, 0.7))

	# Message
	if message_text != "":
		var msg_alpha = min(message_timer, 1.0)
		draw_node.draw_string(ThemeDB.fallback_font,
			Vector2(320 - message_text.length() * 3, 60),
			message_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14,
			Color(1, 1, 0.5, msg_alpha))

func _draw_heart(node: Control, pos: Vector2, color: Color):
	var pixels = [
		Vector2(1, 0), Vector2(2, 0), Vector2(4, 0), Vector2(5, 0),
		Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(3, 1), Vector2(4, 1), Vector2(5, 1), Vector2(6, 1),
		Vector2(0, 2), Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2), Vector2(5, 2), Vector2(6, 2),
		Vector2(1, 3), Vector2(2, 3), Vector2(3, 3), Vector2(4, 3), Vector2(5, 3),
		Vector2(2, 4), Vector2(3, 4), Vector2(4, 4),
		Vector2(3, 5),
	]
	for p in pixels:
		node.draw_rect(Rect2(pos + p * 1.5, Vector2(1.5, 1.5)), color)
