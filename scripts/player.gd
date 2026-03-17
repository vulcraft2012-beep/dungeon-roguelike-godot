extends CharacterBody2D

signal health_changed(new_health)
signal died

@export var speed: float = 100.0
@export var jump_force: float = -300.0
@export var max_health: int = 100
@export var attack_damage: int = 20
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

# Attack direction: 0 = horizontal, 1 = up, -1 = down
var attack_direction: int = 0

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

# Heal ability (H key)
var heal_charges: int = 3
var max_heal_charges: int = 3
var heal_amount: int = 20

# Blade upgrade (from chests)
var has_blade: bool = false

# Lockpick item (crafted from ore)
var has_lockpick: bool = false

# Pickaxe (drops from special mob)
var has_pickaxe: bool = false
var using_pickaxe: bool = false  # Q to switch weapon

# Ore mining progress (legacy, used for lockpick crafting)
var ore_mined: int = 0
var ore_needed: int = 6

# New resource system
var iron_ore: int = 0
var gold_ore: int = 0
var iron_ingot: int = 0
var gold_ingot: int = 0
var has_pearl: bool = false

# Amulet (heals 1 HP every 10s)
var has_amulet: bool = false
var amulet_timer: float = 0.0
var amulet_heal_interval: float = 10.0

# Flask (from grate, heals 20 HP on F)
var has_flask: bool = false
var flask_charges: int = 0

# Sword tier: 0=normal, 1=blade, 2=merged
var sword_tier: int = 0

var blade_cooldown: float = 0.12  # faster than normal 0.22

var attack_area: Area2D
var attack_shape: CollisionShape2D
var body_collision: CollisionShape2D

func _ready():
	health = max_health
	normal_collision_mask = 4 | 8  # walls + doors

	body_collision = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(10, 22)
	body_collision.shape = rect
	body_collision.position = Vector2(0, -11)
	add_child(body_collision)

	attack_area = Area2D.new()
	attack_area.collision_layer = 16
	attack_area.collision_mask = 2
	attack_area.monitoring = true
	attack_area.monitorable = true
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
			# Restore normal collision size
			body_collision.shape.size = Vector2(10, 22)
			body_collision.position = Vector2(0, -11)

	if roll_cooldown_timer > 0:
		roll_cooldown_timer -= delta

	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta

	# Combo reset
	if combo_reset_timer > 0:
		combo_reset_timer -= delta
		if combo_reset_timer <= 0:
			swing_index = 0

	# Amulet passive heal
	if has_amulet and health < max_health and not is_dead:
		amulet_timer -= delta
		if amulet_timer <= 0:
			amulet_timer = amulet_heal_interval
			heal(1)

	# Ledge grab — just hang, wait for player input (handled in _physics_process)

	queue_redraw()

func _physics_process(delta):
	if is_dead:
		return

	# Ledge climbing - easy jump off in any direction
	if is_grabbing_ledge:
		# A or D alone = jump off to that side (no need for Space)
		if Input.is_action_just_pressed("move_left"):
			is_grabbing_ledge = false
			facing_right = false
			velocity = Vector2(-180, -250)
			return
		elif Input.is_action_just_pressed("move_right"):
			is_grabbing_ledge = false
			facing_right = true
			velocity = Vector2(180, -250)
			return
		# Space or W = climb up onto the ledge
		elif Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("move_up"):
			is_grabbing_ledge = false
			position.y = ledge_target_y - 14
			velocity = Vector2(0, -60)
			return
		# S = drop down
		elif Input.is_action_just_pressed("move_down"):
			is_grabbing_ledge = false
			velocity = Vector2(0, 50)
			return
		else:
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
		elif not is_rolling and velocity.y > 0:
			# Try ledge grab only on Space press while falling
			_check_ledge_grab()

	var side = 1 if facing_right else -1
	# Only update attack position when not attacking (attack sets its own position)
	if not is_attacking:
		attack_shape.position = Vector2(15 * side, -11)

	move_and_slide()

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
			if can_attack and not is_rolling and not is_grabbing_ledge:
				_do_attack()

	# Dodge roll on Shift
	if event is InputEventKey and event.pressed and event.keycode == KEY_SHIFT:
		if not is_rolling and roll_cooldown_timer <= 0 and not is_grabbing_ledge:
			_do_roll()

	# Weapon switch: 1 = sword/blade, 2 = pickaxe
	if event is InputEventKey and event.pressed and event.keycode == KEY_1:
		using_pickaxe = false
	if event is InputEventKey and event.pressed and event.keycode == KEY_2:
		if has_pickaxe:
			using_pickaxe = true

	# Heal on H
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		if heal_charges > 0 and health < max_health and not is_dead:
			heal_charges -= 1
			heal(heal_amount)

	# Flask on F
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if has_flask and flask_charges > 0 and health < max_health and not is_dead:
			flask_charges -= 1
			heal(20)

func _do_attack():
	is_attacking = true
	can_attack = false
	attack_timer = blade_cooldown if has_blade else attack_cooldown
	attack_anim_timer = 0.12 if has_blade else 0.15
	attack_shape.disabled = false

	# Determine attack direction based on held keys
	if Input.is_action_pressed("move_up"):
		attack_direction = 1  # up
	elif Input.is_action_pressed("move_down") and not is_on_floor():
		attack_direction = -1  # down (only in air)
	else:
		attack_direction = 0  # horizontal

	# Position attack hitbox based on direction
	var side = 1 if facing_right else -1
	match attack_direction:
		1:  # up
			attack_shape.position = Vector2(0, -28)
			attack_shape.shape.size = Vector2(18, 22)
		-1:  # down
			attack_shape.position = Vector2(0, 6)
			attack_shape.shape.size = Vector2(18, 22)
		_:  # horizontal
			attack_shape.position = Vector2(15 * side, -11)
			attack_shape.shape.size = Vector2(22, 18)

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

	# Shrink collision to 1 tile height (16px) so player can roll through gaps
	body_collision.shape.size = Vector2(10, 10)
	body_collision.position = Vector2(0, -5)

	if Input.is_action_pressed("move_left"):
		roll_direction = -1.0
	elif Input.is_action_pressed("move_right"):
		roll_direction = 1.0
	else:
		roll_direction = 1.0 if facing_right else -1.0

	is_attacking = false
	attack_shape.disabled = true

func _on_attack_hit(body):
	if body.has_method("take_damage") and is_attacking:
		var dmg = attack_damage
		# Pickaxe deals very low damage to monsters (incentivize switching)
		if using_pickaxe:
			dmg = max(5, dmg / 4)

		var dir = 1.0 if body.global_position.x > global_position.x else -1.0
		var knockback = Vector2(dir, -0.3).normalized()
		# Adjust knockback direction for vertical attacks
		if attack_direction == 1:  # up
			knockback = Vector2(dir * 0.3, -1.0).normalized()
		elif attack_direction == -1:  # down
			knockback = Vector2(dir * 0.3, 0.8).normalized()

		body.take_damage(dmg, knockback)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	if invincible or is_rolling or is_dead:
		return

	health -= amount
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
	# Roll animation — flat/compressed (fits through 1-tile gaps)
	if is_rolling:
		var roll_progress = 1.0 - (roll_timer / roll_duration)
		var roll_angle = roll_progress * TAU * 2.0
		var s = 1 if roll_direction > 0 else -1
		# Flat rolling ball — only ~10px tall (1 tile = 16px)
		draw_circle(Vector2(0, -5), 6, Color(0.35, 0.35, 0.4))
		draw_circle(Vector2(0, -5), 4.5, Color(0.42, 0.42, 0.48))
		# Spinning limb indicator
		var lx = cos(roll_angle) * 4
		var ly = sin(roll_angle) * 4
		draw_line(Vector2(0, -5), Vector2(lx, -5 + ly), Color(0.6, 0.6, 0.65), 2.0)
		# Speed trail
		draw_line(Vector2(-s * 8, -7), Vector2(-s * 14, -7), Color(1, 1, 1, 0.2), 1.0)
		draw_line(Vector2(-s * 7, -3), Vector2(-s * 12, -3), Color(1, 1, 1, 0.15), 1.0)
		# Dust particles
		if fmod(roll_progress * 10, 1.0) < 0.5:
			draw_circle(Vector2(-s * 6, -1), 1.5, Color(0.6, 0.5, 0.3, 0.3))
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

	# --- WEAPON ---
	if using_pickaxe:
		_draw_pickaxe(s)
	else:
		_draw_sword(s)

	# --- HEAL CHARGES indicator ---
	if heal_charges > 0:
		for i in heal_charges:
			draw_circle(Vector2(-6 + i * 5, -28), 2, Color(0.3, 0.9, 0.3, 0.6))

func _draw_sword(s: int):
	var blade_col = Color(0.4, 0.85, 1.0) if has_blade else Color(0.85, 0.85, 0.92)
	var blade_trail = Color(0.3, 0.7, 1.0, 0.2) if has_blade else Color(1, 1, 1, 0.15)
	var blade_glow = Color(0.5, 0.9, 1.0, 0.4) if has_blade else Color(1, 1, 1, 0.3)
	var blade_len = 24 if has_blade else 22
	var anim_dur = 0.12 if has_blade else 0.15

	if is_attacking:
		var swing_progress = 1.0 - (attack_anim_timer / anim_dur)
		var base = Vector2(s * 5, -12)

		if attack_direction == 1:  # UP attack
			var angle = lerp(-1.2, 0.2, swing_progress)
			var tip = base + Vector2(sin(angle) * 6 * s, -cos(angle) * blade_len)
			var trail_angle = lerp(-1.2, 0.2, max(0, swing_progress - 0.3))
			var trail_tip = base + Vector2(sin(trail_angle) * 6 * s, -cos(trail_angle) * (blade_len - 2))
			draw_line(trail_tip, tip, blade_trail, 3.0)
			draw_line(base, tip, blade_col, 2.5)
			draw_line(base + Vector2(-1, 0), tip + Vector2(-1, 0), blade_glow, 1.0)
			draw_line(base + Vector2(-3, 0), base + Vector2(3, 0), Color(0.6, 0.5, 0.2), 2.5)
		elif attack_direction == -1:  # DOWN attack
			var angle = lerp(-0.2, 1.2, swing_progress)
			var tip = base + Vector2(sin(angle) * 6 * s, cos(angle) * blade_len)
			var trail_angle = lerp(-0.2, 1.2, max(0, swing_progress - 0.3))
			var trail_tip = base + Vector2(sin(trail_angle) * 6 * s, cos(trail_angle) * (blade_len - 2))
			draw_line(trail_tip, tip, blade_trail, 3.0)
			draw_line(base, tip, blade_col, 2.5)
			draw_line(base + Vector2(-1, 0), tip + Vector2(-1, 0), blade_glow, 1.0)
			draw_line(base + Vector2(-3, 0), base + Vector2(3, 0), Color(0.6, 0.5, 0.2), 2.5)
		else:  # Horizontal attacks (combo)
			match swing_index:
				0:
					var angle = lerp(-0.6, 1.0, swing_progress) * s
					var tip = base + Vector2(cos(angle) * blade_len, sin(angle) * 6)
					var trail_angle = lerp(-0.6, 1.0, max(0, swing_progress - 0.3)) * s
					var trail_tip = base + Vector2(cos(trail_angle) * (blade_len - 2), sin(trail_angle) * 6)
					draw_line(trail_tip, tip, blade_trail, 3.0)
					draw_line(base, tip, blade_col, 2.5)
					draw_line(base + Vector2(0, -1), tip + Vector2(0, -1), blade_glow, 1.0)
					draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.5)
				1:
					var angle = lerp(1.0, -0.6, swing_progress) * s
					var tip = base + Vector2(cos(angle) * blade_len, sin(angle) * 6)
					var trail_angle = lerp(1.0, -0.6, max(0, swing_progress - 0.3)) * s
					var trail_tip = base + Vector2(cos(trail_angle) * (blade_len - 2), sin(trail_angle) * 6)
					draw_line(trail_tip, tip, blade_trail, 3.0)
					draw_line(base, tip, blade_col, 2.5)
					draw_line(base + Vector2(0, -1), tip + Vector2(0, -1), blade_glow, 1.0)
					draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.5)
				2:
					var angle = lerp(-1.2, 0.8, swing_progress) * s
					var tip = base + Vector2(cos(angle) * (blade_len + 2) * s, sin(angle) * 18)
					var trail_angle = lerp(-1.2, 0.8, max(0, swing_progress - 0.25)) * s
					var trail_tip = base + Vector2(cos(trail_angle) * blade_len * s, sin(trail_angle) * 18)
					draw_line(trail_tip, tip, Color(blade_trail.r, blade_trail.g, blade_trail.b, 0.25), 4.0)
					draw_line(base, tip, blade_col, 3.0)
					draw_line(base + Vector2(0, -1), tip + Vector2(0, -1), blade_glow, 1.5)
					draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.5)
	else:
		var sx = s * 7
		var idle_col = Color(0.5, 0.8, 0.95) if has_blade else Color(0.7, 0.7, 0.78)
		draw_line(Vector2(sx, -15), Vector2(sx + s * 8, -10), idle_col, 2.0)
		draw_line(Vector2(sx, -16), Vector2(sx, -12), Color(0.55, 0.42, 0.2), 2.0)

func _draw_pickaxe(s: int):
	if is_attacking:
		var anim_dur = 0.15
		var swing_progress = 1.0 - (attack_anim_timer / anim_dur)
		var base = Vector2(s * 3, -12)

		var angle: float
		var handle_end: Vector2

		if attack_direction == 1:  # UP attack
			angle = lerp(0.5, -1.2, swing_progress)
			handle_end = base + Vector2(sin(angle) * 5 * s, -cos(angle) * 18)
		elif attack_direction == -1:  # DOWN attack
			angle = lerp(-0.5, 1.2, swing_progress)
			handle_end = base + Vector2(sin(angle) * 5 * s, cos(angle) * 18)
		else:  # Horizontal
			angle = lerp(-0.8, 1.2, swing_progress) * s
			handle_end = base + Vector2(cos(angle) * 18, sin(angle) * 8)

		# Handle (brown)
		draw_line(base, handle_end, Color(0.55, 0.35, 0.15), 2.5)
		# Pickaxe head (iron gray) - perpendicular to handle
		var dir_vec = (handle_end - base).normalized()
		var perp = Vector2(-dir_vec.y, dir_vec.x)
		var head_pos = handle_end
		draw_line(head_pos - perp * 5, head_pos + perp * 5, Color(0.6, 0.6, 0.65), 3.0)
		# Point tip
		draw_line(head_pos + perp * 5, head_pos + perp * 7 + dir_vec * 3, Color(0.7, 0.7, 0.75), 2.0)
		# Sparks when mining
		if swing_progress > 0.7:
			draw_circle(handle_end + Vector2(randf_range(-3, 3), randf_range(-3, 3)), 1.5, Color(1, 0.8, 0.3, 0.6))
	else:
		# Idle pickaxe - held over shoulder
		var sx = s * 6
		# Handle
		draw_line(Vector2(sx, -8), Vector2(sx + s * 6, -20), Color(0.55, 0.35, 0.15), 2.5)
		# Head
		var hx = sx + s * 6
		draw_line(Vector2(hx - 4, -22), Vector2(hx + 4, -18), Color(0.6, 0.6, 0.65), 3.0)
		# Point
		draw_line(Vector2(hx + 4, -18), Vector2(hx + 6, -17), Color(0.7, 0.7, 0.75), 2.0)
