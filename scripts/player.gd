extends CharacterBody2D

signal health_changed(new_health)
signal died

@export var speed: float = 100.0
@export var jump_force: float = -300.0
@export var max_health: int = 5
@export var attack_damage: int = 1
@export var attack_cooldown: float = 0.22

var health: int
var gravity: float = 650.0
var facing_right: bool = true
var is_attacking: bool = false
var is_shielding: bool = false
var can_attack: bool = true
var attack_timer: float = 0.0
var attack_anim_timer: float = 0.0
var invincible: bool = false
var invincible_timer: float = 0.0
var is_dead: bool = false

# Dodge roll
var is_rolling: bool = false
var roll_timer: float = 0.0
var roll_duration: float = 0.3
var roll_speed: float = 220.0
var roll_cooldown_timer: float = 0.0
var roll_cooldown: float = 0.5
var roll_direction: float = 0.0
var normal_collision_mask: int = 0

# Swing combo
var swing_index: int = 0
var combo_reset_timer: float = 0.0
var combo_reset_time: float = 0.5

# Ledge grab
var is_grabbing_ledge: bool = false
var ledge_target_y: float = 0.0
var climb_timer: float = 0.0
var climb_duration: float = 0.25

# Wall slide / wall jump
var is_wall_sliding: bool = false
var wall_slide_speed: float = 40.0
var wall_jump_force: Vector2 = Vector2(180, -280)
var wall_dir: int = 0  # -1 left wall, 1 right wall, 0 none
var wall_jump_cooldown: float = 0.0

var attack_area: Area2D
var attack_shape: CollisionShape2D

func _ready():
	health = max_health
	normal_collision_mask = 4 | 8  # walls + doors

	var body_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(10, 22)
	body_shape.shape = rect
	body_shape.position = Vector2(0, -11)
	add_child(body_shape)

	attack_area = Area2D.new()
	attack_area.collision_layer = 16
	attack_area.collision_mask = 2
	attack_area.monitoring = true
	attack_area.monitorable = false
	add_child(attack_area)

	attack_shape = CollisionShape2D.new()
	var attack_rect = RectangleShape2D.new()
	attack_rect.size = Vector2(22, 18)
	attack_shape.shape = attack_rect
	attack_shape.position = Vector2(15, -11)
	attack_shape.disabled = true
	attack_area.add_child(attack_shape)

	attack_area.body_entered.connect(_on_attack_hit)

	collision_layer = 1
	collision_mask = normal_collision_mask

func _process(delta):
	if is_dead:
		return

	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0:
			can_attack = true

	if is_attacking:
		attack_anim_timer -= delta
		if attack_anim_timer <= 0:
			is_attacking = false
			attack_shape.disabled = true

	if invincible and not is_rolling:
		invincible_timer -= delta
		if invincible_timer <= 0:
			invincible = false

	# Roll
	if is_rolling:
		roll_timer -= delta
		if roll_timer <= 0:
			is_rolling = false
			invincible = false
			collision_layer = 1
			collision_mask = normal_collision_mask

	if roll_cooldown_timer > 0:
		roll_cooldown_timer -= delta

	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta

	# Combo reset
	if combo_reset_timer > 0:
		combo_reset_timer -= delta
		if combo_reset_timer <= 0:
			swing_index = 0

	# Ledge climb
	if is_grabbing_ledge:
		climb_timer -= delta
		if climb_timer <= 0:
			is_grabbing_ledge = false
			position.y = ledge_target_y - 12
			velocity = Vector2.ZERO

	queue_redraw()

func _physics_process(delta):
	if is_dead:
		return

	# Ledge climbing - no physics
	if is_grabbing_ledge:
		velocity = Vector2.ZERO
		position.y = lerp(position.y, ledge_target_y - 12, delta * 12)
		return

	velocity.y += gravity * delta

	if is_rolling:
		velocity.x = roll_direction * roll_speed
		move_and_slide()
		return

	var dir = 0.0
	if Input.is_action_pressed("move_left"):
		dir = -1.0
		if not is_attacking:
			facing_right = false
	elif Input.is_action_pressed("move_right"):
		dir = 1.0
		if not is_attacking:
			facing_right = true

	var current_speed = speed
	if is_shielding:
		current_speed *= 0.35
	if is_attacking:
		current_speed *= 0.55

	velocity.x = dir * current_speed

	# Wall slide detection
	is_wall_sliding = false
	wall_dir = 0
	if not is_on_floor() and is_on_wall() and velocity.y > 0 and wall_jump_cooldown <= 0:
		# Check which wall we're touching
		if Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
			var space = get_world_2d().direct_space_state
			# Check left
			var ql = PhysicsRayQueryParameters2D.create(
				global_position + Vector2(0, -10),
				global_position + Vector2(-8, -10), 4)
			var rl = space.intersect_ray(ql)
			# Check right
			var qr = PhysicsRayQueryParameters2D.create(
				global_position + Vector2(0, -10),
				global_position + Vector2(8, -10), 4)
			var rr = space.intersect_ray(qr)

			if not rl.is_empty() and Input.is_action_pressed("move_left"):
				is_wall_sliding = true
				wall_dir = -1
			elif not rr.is_empty() and Input.is_action_pressed("move_right"):
				is_wall_sliding = true
				wall_dir = 1

	if is_wall_sliding:
		velocity.y = min(velocity.y, wall_slide_speed)
		# Face away from wall
		facing_right = wall_dir < 0

	# Jump on Space
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up"):
		if is_on_floor():
			velocity.y = jump_force
		elif is_wall_sliding:
			# Wall jump - jump away from wall
			velocity.x = -wall_dir * wall_jump_force.x
			velocity.y = wall_jump_force.y
			is_wall_sliding = false
			facing_right = wall_dir < 0
			wall_jump_cooldown = 0.15  # Brief cooldown to prevent re-sticking

	var side = 1 if facing_right else -1
	attack_shape.position.x = 15 * side

	move_and_slide()

	# Ledge detection
	if not is_on_floor() and velocity.y > 0 and not is_rolling and not is_wall_sliding:
		_check_ledge_grab()

func _check_ledge_grab():
	var side = 1 if facing_right else -1
	var space = get_world_2d().direct_space_state

	var check_x = global_position.x + side * 10

	# Ray downward from ahead to find platform top
	var feet_from = Vector2(check_x, global_position.y - 20)
	var feet_to = Vector2(check_x, global_position.y + 5)
	var q1 = PhysicsRayQueryParameters2D.create(feet_from, feet_to, 4)
	var r1 = space.intersect_ray(q1)

	if r1.is_empty():
		return

	var platform_y = r1.position.y

	var diff = global_position.y - platform_y
	if diff < -5 or diff > 25:
		return

	if platform_y < 35:
		return

	# Headroom check
	var head_from = Vector2(check_x, platform_y - 5)
	var head_to = Vector2(check_x, platform_y - 28)
	var q2 = PhysicsRayQueryParameters2D.create(head_from, head_to, 4)
	var r2 = space.intersect_ray(q2)

	if not r2.is_empty():
		return

	# Edge check - no platform directly below us
	var above_from = Vector2(global_position.x, platform_y - 5)
	var above_to = Vector2(global_position.x, platform_y + 5)
	var q3 = PhysicsRayQueryParameters2D.create(above_from, above_to, 4)
	var r3 = space.intersect_ray(q3)

	if not r3.is_empty() and abs(r3.position.y - platform_y) < 4:
		return

	is_grabbing_ledge = true
	ledge_target_y = platform_y
	climb_timer = climb_duration
	velocity = Vector2.ZERO

func _unhandled_input(event):
	if is_dead:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if can_attack and not is_shielding and not is_rolling and not is_grabbing_ledge:
				_do_attack()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if not is_rolling and not is_grabbing_ledge:
				is_shielding = event.pressed

	# Dodge roll on Shift
	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT:
		if not is_rolling and roll_cooldown_timer <= 0 and not is_shielding and not is_grabbing_ledge:
			_do_roll()

func _do_attack():
	is_attacking = true
	can_attack = false
	attack_timer = attack_cooldown
	attack_anim_timer = 0.15
	attack_shape.disabled = false

	combo_reset_timer = combo_reset_time

	for body in attack_area.get_overlapping_bodies():
		_on_attack_hit(body)

	swing_index = (swing_index + 1) % 3

func _do_roll():
	is_rolling = true
	roll_timer = roll_duration
	roll_cooldown_timer = roll_cooldown
	invincible = true

	collision_layer = 0
	collision_mask = 4

	if Input.is_action_pressed("move_left"):
		roll_direction = -1.0
	elif Input.is_action_pressed("move_right"):
		roll_direction = 1.0
	else:
		roll_direction = 1.0 if facing_right else -1.0

	is_attacking = false
	is_shielding = false
	attack_shape.disabled = true

func _on_attack_hit(body):
	if body.has_method("take_damage") and is_attacking:
		var dir = 1.0 if body.global_position.x > global_position.x else -1.0
		body.take_damage(attack_damage, Vector2(dir, -0.3).normalized())

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	if invincible or is_rolling or is_dead:
		return

	var actual_damage = amount
	if is_shielding:
		var block_side = 1.0 if facing_right else -1.0
		if sign(knockback_dir.x) != sign(block_side):
			actual_damage = 0
			velocity.x = knockback_dir.x * 60
			move_and_slide()
			return

	health -= actual_damage
	health_changed.emit(health)

	velocity = knockback_dir * 140
	velocity.y = -120
	move_and_slide()

	invincible = true
	invincible_timer = 0.8

	if health <= 0:
		is_dead = true
		died.emit()

func heal(amount: int):
	health = min(health + amount, max_health)
	health_changed.emit(health)

func _draw():
	# Roll animation
	if is_rolling:
		var roll_progress = 1.0 - (roll_timer / roll_duration)
		var roll_angle = roll_progress * TAU * 1.5
		var s = 1 if roll_direction > 0 else -1
		draw_circle(Vector2(-s * 6, -8), 8, Color(0.4, 0.6, 0.9, 0.12))
		draw_circle(Vector2(0, -8), 9, Color(0.35, 0.35, 0.4))
		draw_circle(Vector2(0, -8), 7, Color(0.42, 0.42, 0.48))
		var lx = cos(roll_angle) * 6
		var ly = sin(roll_angle) * 6
		draw_line(Vector2(0, -8), Vector2(lx, -8 + ly), Color(0.6, 0.6, 0.65), 2.0)
		draw_line(Vector2(-s * 12, -11), Vector2(-s * 18, -11), Color(1, 1, 1, 0.2), 1.0)
		draw_line(Vector2(-s * 10, -6), Vector2(-s * 16, -6), Color(1, 1, 1, 0.15), 1.0)
		return

	# Wall slide animation
	if is_wall_sliding:
		var s = 1 if facing_right else -1
		var slide_offset = sin(Time.get_ticks_msec() * 0.005) * 1

		# Body pressed against wall
		draw_rect(Rect2(-5, -16, 10, 13), Color(0.35, 0.35, 0.4))
		draw_rect(Rect2(-4, -15, 8, 7), Color(0.42, 0.42, 0.48))
		# Head looking out
		draw_rect(Rect2(-4, -22, 8, 7), Color(0.9, 0.75, 0.55))
		draw_rect(Rect2(-5, -24, 10, 5), Color(0.5, 0.5, 0.55))
		draw_rect(Rect2(s, -21, 2, 1), Color(0.35, 0.65, 0.95))
		# Arms gripping wall
		draw_rect(Rect2(-s * 5, -18, 3, 4), Color(0.9, 0.75, 0.55))
		draw_rect(Rect2(-s * 5, -10, 3, 3), Color(0.9, 0.75, 0.55))
		# Legs bent
		draw_rect(Rect2(-3, -4 + slide_offset, 3, 5), Color(0.25, 0.2, 0.15))
		draw_rect(Rect2(1, -4 - slide_offset, 3, 4), Color(0.25, 0.2, 0.15))
		# Friction sparks
		if fmod(Time.get_ticks_msec(), 200.0) < 100:
			draw_circle(Vector2(-s * 4, -6), 1.5, Color(1, 0.8, 0.3, 0.4))
		return

	# Ledge grab animation
	if is_grabbing_ledge:
		var s = 1 if facing_right else -1
		draw_rect(Rect2(-5, -24, 10, 13), Color(0.35, 0.35, 0.4))
		draw_rect(Rect2(s * 4, -28, 3, 6), Color(0.9, 0.75, 0.55))
		draw_rect(Rect2(-s * 2, -28, 3, 6), Color(0.9, 0.75, 0.55))
		draw_rect(Rect2(-4, -22, 8, 7), Color(0.9, 0.75, 0.55))
		draw_rect(Rect2(-5, -24, 10, 4), Color(0.5, 0.5, 0.55))
		draw_rect(Rect2(-3, -11, 3, 6), Color(0.25, 0.2, 0.15))
		draw_rect(Rect2(1, -11, 3, 5), Color(0.25, 0.2, 0.15))
		return

	if invincible and fmod(invincible_timer, 0.2) < 0.1:
		return

	var s = 1 if facing_right else -1

	# --- LEGS ---
	var leg_anim = sin(Time.get_ticks_msec() * 0.01) * 3 if abs(velocity.x) > 5 else 0
	draw_rect(Rect2(-4, -4, 3, 5 + leg_anim), Color(0.25, 0.2, 0.15))
	draw_rect(Rect2(1, -4, 3, 5 - leg_anim), Color(0.25, 0.2, 0.15))
	draw_rect(Rect2(-5, 0 + leg_anim, 5, 2), Color(0.4, 0.22, 0.1))
	draw_rect(Rect2(0, 0 - leg_anim, 5, 2), Color(0.4, 0.22, 0.1))

	# --- BODY ---
	draw_rect(Rect2(-5, -16, 10, 13), Color(0.35, 0.35, 0.4))
	draw_rect(Rect2(-4, -15, 8, 7), Color(0.42, 0.42, 0.48))
	draw_rect(Rect2(-5, -5, 10, 2), Color(0.45, 0.3, 0.12))
	draw_rect(Rect2(-1, -5, 2, 2), Color(0.75, 0.65, 0.2))

	# --- HEAD ---
	draw_rect(Rect2(-4, -22, 8, 7), Color(0.9, 0.75, 0.55))
	draw_rect(Rect2(-5, -24, 10, 5), Color(0.5, 0.5, 0.55))
	draw_rect(Rect2(-5, -24, 10, 1), Color(0.6, 0.6, 0.65))
	draw_rect(Rect2(-3 + s, -21, 5, 2), Color(0.08, 0.08, 0.1))
	draw_rect(Rect2(s, -21, 2, 1), Color(0.35, 0.65, 0.95))

	# --- SHIELD ---
	if is_shielding:
		var sx = s * 9
		draw_rect(Rect2(sx - 3, -20, 6, 16), Color(0.55, 0.42, 0.2))
		draw_rect(Rect2(sx - 2, -19, 4, 14), Color(0.5, 0.5, 0.58))
		draw_rect(Rect2(sx - 1, -15, 2, 2), Color(0.75, 0.65, 0.2))
		draw_rect(Rect2(sx - 3, -20, 1, 16), Color(0.65, 0.52, 0.25))
		draw_rect(Rect2(sx + 2, -20, 1, 16), Color(0.65, 0.52, 0.25))

	# --- SWORD ---
	if is_attacking:
		var swing_progress = 1.0 - (attack_anim_timer / 0.15)
		var base = Vector2(s * 5, -12)

		match swing_index:
			0:
				var angle = lerp(-0.6, 1.0, swing_progress) * s
				var tip = base + Vector2(cos(angle) * 22, sin(angle) * 6)
				var trail_angle = lerp(-0.6, 1.0, max(0, swing_progress - 0.3)) * s
				var trail_tip = base + Vector2(cos(trail_angle) * 20, sin(trail_angle) * 6)
				draw_line(trail_tip, tip, Color(1, 1, 1, 0.15), 3.0)
				draw_line(base, tip, Color(0.85, 0.85, 0.92), 2.5)
				draw_line(base + Vector2(0, -1), tip + Vector2(0, -1), Color(1, 1, 1, 0.3), 1.0)
				draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.5)
			1:
				var angle = lerp(1.0, -0.6, swing_progress) * s
				var tip = base + Vector2(cos(angle) * 22, sin(angle) * 6)
				var trail_angle = lerp(1.0, -0.6, max(0, swing_progress - 0.3)) * s
				var trail_tip = base + Vector2(cos(trail_angle) * 20, sin(trail_angle) * 6)
				draw_line(trail_tip, tip, Color(1, 1, 1, 0.15), 3.0)
				draw_line(base, tip, Color(0.85, 0.85, 0.92), 2.5)
				draw_line(base + Vector2(0, -1), tip + Vector2(0, -1), Color(1, 1, 1, 0.3), 1.0)
				draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.5)
			2:
				var angle = lerp(-1.2, 0.8, swing_progress) * s
				var tip = base + Vector2(cos(angle) * 24 * s, sin(angle) * 18)
				var trail_angle = lerp(-1.2, 0.8, max(0, swing_progress - 0.25)) * s
				var trail_tip = base + Vector2(cos(trail_angle) * 22 * s, sin(trail_angle) * 18)
				draw_line(trail_tip, tip, Color(1, 0.9, 0.5, 0.2), 4.0)
				draw_line(base, tip, Color(0.9, 0.88, 0.95), 3.0)
				draw_line(base + Vector2(0, -1), tip + Vector2(0, -1), Color(1, 1, 1, 0.4), 1.5)
				draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.5)
	else:
		var sx = s * 7
		draw_line(Vector2(sx, -15), Vector2(sx + s * 8, -10), Color(0.7, 0.7, 0.78), 2.0)
		draw_line(Vector2(sx, -16), Vector2(sx, -12), Color(0.55, 0.42, 0.2), 2.0)
