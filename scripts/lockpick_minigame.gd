extends Control

signal lockpick_success
signal lockpick_failed

@export var rotation_speed: float = 3.0  # radians per second
@export var num_gaps: int = 3
@export var gap_size: float = 0.4  # radians - size of each gap
@export var circle_radius: float = 60.0
@export var bar_length: float = 55.0
@export var difficulty: int = 1  # 1-5, affects speed and gap count

var bar_angle: float = 0.0
var gaps: Array = []  # Array of gap center angles
var gaps_hit: Array = []  # Which gaps have been successfully hit
var is_active: bool = false
var time_limit: float = 15.0
var time_remaining: float = 15.0
var lockpick_attempts: int = 3
var current_gap_index: int = 0  # Which gap needs to be hit next

func _ready():
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_lockpick(p_difficulty: int = 1):
	difficulty = p_difficulty
	_setup_difficulty()
	_generate_gaps()
	bar_angle = 0.0
	current_gap_index = 0
	gaps_hit.clear()
	for i in num_gaps:
		gaps_hit.append(false)
	time_remaining = time_limit
	is_active = true
	visible = true
	get_tree().paused = true

func _setup_difficulty():
	match difficulty:
		1:
			num_gaps = 2
			gap_size = 0.5
			rotation_speed = 2.5
			time_limit = 20.0
		2:
			num_gaps = 3
			gap_size = 0.4
			rotation_speed = 3.0
			time_limit = 18.0
		3:
			num_gaps = 3
			gap_size = 0.35
			rotation_speed = 3.5
			time_limit = 15.0
		4:
			num_gaps = 4
			gap_size = 0.3
			rotation_speed = 4.0
			time_limit = 12.0
		5:
			num_gaps = 4
			gap_size = 0.25
			rotation_speed = 5.0
			time_limit = 10.0

func _generate_gaps():
	gaps.clear()
	var min_spacing = PI * 2.0 / num_gaps * 0.6
	for i in num_gaps:
		var base_angle = (PI * 2.0 / num_gaps) * i
		var jitter = randf_range(-0.3, 0.3)
		gaps.append(fmod(base_angle + jitter + PI * 2.0, PI * 2.0))

func _process(delta):
	if not is_active:
		return

	# Rotate the bar
	bar_angle += rotation_speed * delta
	bar_angle = fmod(bar_angle, PI * 2.0)

	# Timer
	time_remaining -= delta
	if time_remaining <= 0:
		_fail()
		return

	queue_redraw()

func _unhandled_input(event):
	if not is_active:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_try_pick()
		get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_fail()
		get_viewport().set_input_as_handled()

func _try_pick():
	# Check if bar is in the current gap
	var target_gap = gaps[current_gap_index]
	var angle_diff = abs(_angle_diff(bar_angle, target_gap))

	if angle_diff < gap_size / 2.0:
		# Hit the gap!
		gaps_hit[current_gap_index] = true
		current_gap_index += 1

		if current_gap_index >= num_gaps:
			# All gaps hit - success!
			_success()
	else:
		# Missed - penalty
		lockpick_attempts -= 1
		if lockpick_attempts <= 0:
			_fail()
		else:
			# Speed up as penalty
			rotation_speed += 0.5

func _angle_diff(a: float, b: float) -> float:
	var diff = fmod(a - b + PI * 3.0, PI * 2.0) - PI
	return diff

func _success():
	is_active = false
	get_tree().paused = false
	visible = false
	lockpick_success.emit()

func _fail():
	is_active = false
	get_tree().paused = false
	visible = false
	lockpick_failed.emit()

func _draw():
	if not is_active:
		return

	var center = size / 2.0

	# Dark overlay
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7))

	# Title
	draw_string(ThemeDB.fallback_font, Vector2(center.x - 60, center.y - circle_radius - 30),
		"LOCKPICKING", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)

	# Instructions
	draw_string(ThemeDB.fallback_font, Vector2(center.x - 80, center.y + circle_radius + 25),
		"SPACE - pick", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.7, 0.7, 0.7))

	# Circle outline
	_draw_circle_outline(center, circle_radius, 2.0, Color(0.4, 0.4, 0.4))

	# Draw gaps on the circle
	for i in num_gaps:
		var gap_angle = gaps[i]
		var gap_color: Color

		if gaps_hit[i]:
			gap_color = Color(0, 1, 0, 0.8)  # Green - already hit
		elif i == current_gap_index:
			gap_color = Color(1, 1, 0, 0.8)  # Yellow - current target
		else:
			gap_color = Color(0.6, 0.6, 0.6, 0.5)  # Grey - future target

		# Draw gap as an arc highlight
		var gap_start = gap_angle - gap_size / 2.0
		var gap_segments = 8
		for s in gap_segments:
			var a1 = gap_start + (gap_size / gap_segments) * s
			var a2 = gap_start + (gap_size / gap_segments) * (s + 1)
			var p1 = center + Vector2(cos(a1), sin(a1)) * circle_radius
			var p2 = center + Vector2(cos(a2), sin(a2)) * circle_radius
			draw_line(p1, p2, gap_color, 4.0)

		# Draw gap marker (small diamond)
		var gap_pos = center + Vector2(cos(gap_angle), sin(gap_angle)) * circle_radius
		var diamond_size = 4.0
		var diamond_points = PackedVector2Array([
			gap_pos + Vector2(0, -diamond_size),
			gap_pos + Vector2(diamond_size, 0),
			gap_pos + Vector2(0, diamond_size),
			gap_pos + Vector2(-diamond_size, 0),
		])
		draw_colored_polygon(diamond_points, gap_color)

	# Draw rotating bar (the pick)
	var bar_end = center + Vector2(cos(bar_angle), sin(bar_angle)) * bar_length
	var bar_color = Color(1, 0.8, 0.2)  # Golden pick
	draw_line(center, bar_end, bar_color, 3.0)

	# Bar tip
	draw_circle(bar_end, 3.0, bar_color)

	# Center dot
	draw_circle(center, 4.0, Color(0.5, 0.5, 0.5))

	# Draw attempts remaining (lockpick icons)
	for i in lockpick_attempts:
		var pick_x = center.x - 20 + i * 15
		var pick_y = center.y + circle_radius + 40
		draw_line(Vector2(pick_x, pick_y), Vector2(pick_x, pick_y + 10), Color(0.7, 0.7, 0.7), 2.0)
		draw_line(Vector2(pick_x, pick_y + 10), Vector2(pick_x + 4, pick_y + 8), Color(0.7, 0.7, 0.7), 2.0)

	# Timer bar
	var timer_width = 120.0
	var timer_x = center.x - timer_width / 2.0
	var timer_y = center.y - circle_radius - 15
	draw_rect(Rect2(timer_x, timer_y, timer_width, 6), Color(0.3, 0.3, 0.3))
	var timer_fill = (time_remaining / time_limit) * timer_width
	var timer_color = Color(0, 1, 0) if time_remaining / time_limit > 0.3 else Color(1, 0, 0)
	draw_rect(Rect2(timer_x, timer_y, timer_fill, 6), timer_color)

	# Gap counter
	var counter_text = str(current_gap_index) + "/" + str(num_gaps)
	draw_string(ThemeDB.fallback_font, Vector2(center.x - 10, center.y + 5),
		counter_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

func _draw_circle_outline(center: Vector2, radius: float, width: float, color: Color):
	var segments = 32
	for i in segments:
		var a1 = (PI * 2.0 / segments) * i
		var a2 = (PI * 2.0 / segments) * (i + 1)
		var p1 = center + Vector2(cos(a1), sin(a1)) * radius
		var p2 = center + Vector2(cos(a2), sin(a2)) * radius
		draw_line(p1, p2, color, width)
