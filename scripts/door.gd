extends StaticBody2D

signal door_interact(door)

@export var difficulty: int = 1
@export var is_locked: bool = true

var player_nearby: bool = false
var interact_area: Area2D

func _ready():
	collision_layer = 8
	collision_mask = 0

	# Door collision (vertical door on the side)
	var body_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(8, 28)
	body_shape.shape = rect
	body_shape.position = Vector2(0, -14)
	add_child(body_shape)

	# Interaction area
	interact_area = Area2D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = 1
	var interact_shape = CollisionShape2D.new()
	var interact_rect = RectangleShape2D.new()
	interact_rect.size = Vector2(28, 36)
	interact_shape.shape = interact_rect
	interact_shape.position = Vector2(-8, -14)
	interact_area.add_child(interact_shape)
	add_child(interact_area)

	interact_area.body_entered.connect(_on_player_enter)
	interact_area.body_exited.connect(_on_player_exit)

func _on_player_enter(_body):
	player_nearby = true
	queue_redraw()

func _on_player_exit(_body):
	player_nearby = false
	queue_redraw()

func _unhandled_input(event):
	if not player_nearby or not is_locked:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		door_interact.emit(self)
		get_viewport().set_input_as_handled()

func unlock():
	is_locked = false
	collision_layer = 0
	for child in get_children():
		if child is CollisionShape2D:
			child.disabled = true
	queue_redraw()

func _draw():
	if is_locked:
		# Wooden door frame
		draw_rect(Rect2(-6, -30, 12, 32), Color(0.3, 0.25, 0.18))
		# Door planks
		draw_rect(Rect2(-5, -29, 10, 30), Color(0.42, 0.32, 0.18))
		draw_line(Vector2(-1, -29), Vector2(-1, 1), Color(0.35, 0.25, 0.12), 0.5)
		draw_line(Vector2(2, -29), Vector2(2, 1), Color(0.35, 0.25, 0.12), 0.5)
		# Metal bands
		draw_rect(Rect2(-5, -28, 10, 2), Color(0.4, 0.38, 0.35))
		draw_rect(Rect2(-5, -18, 10, 2), Color(0.4, 0.38, 0.35))
		draw_rect(Rect2(-5, -8, 10, 2), Color(0.4, 0.38, 0.35))
		# Lock
		draw_circle(Vector2(3, -15), 2, Color(0.7, 0.6, 0.15))
		draw_rect(Rect2(2, -14, 2, 3), Color(0.6, 0.5, 0.1))
		# Keyhole
		draw_circle(Vector2(3, -15), 1, Color(0.1, 0.1, 0.1))
		# Arch top
		draw_arc(Vector2(0, -29), 6, PI, 0, 8, Color(0.35, 0.3, 0.22), 2.0)

		if player_nearby:
			draw_string(ThemeDB.fallback_font, Vector2(-24, -36),
				"[E] Pick Lock", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(1, 1, 0.5))
	else:
		# Open door - dark opening
		draw_rect(Rect2(-6, -30, 12, 32), Color(0.02, 0.02, 0.02))
		# Door frame only
		draw_rect(Rect2(-6, -30, 2, 32), Color(0.3, 0.25, 0.18))
		draw_rect(Rect2(4, -30, 2, 32), Color(0.3, 0.25, 0.18))
		draw_arc(Vector2(0, -29), 6, PI, 0, 8, Color(0.35, 0.3, 0.22), 2.0)
