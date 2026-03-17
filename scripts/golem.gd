extends CharacterBody2D

signal golem_defeated

enum Phase { ROAR, ROCKS, TIRED, ANGRY_ROCKS, TIRED2, DEATH }

var phase: int = Phase.ROAR
var phase_timer: float = 0.0
var health: int = 80
var max_health: int = 80
var hits_in_tired: int = 0  # Track hits during tired phase (max 2)
var is_dead: bool = false
var player: CharacterBody2D = null
var gravity_val: float = 650.0
var facing_right: bool = false

# Rock attack
var rock_timer: float = 0.0
var rock_interval: float = 0.8
var rocks: Array = []  # Active falling rocks

# Roar animation
var roar_anim: float = 0.0

# Death animation
var death_anim: float = 0.0

# Angry mode (faster rocks)
var is_angry: bool = false

# Hit flash
var is_hit: bool = false
var hit_timer: float = 0.0

# Body shake when angry
var shake_offset: Vector2 = Vector2.ZERO

var projectile_script = preload("res://scripts/projectile.gd")

func _ready():
	collision_layer = 2  # enemy layer
	collision_mask = 4   # walls

	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(28, 40)
	shape.shape = rect
	shape.position = Vector2(0, -20)
	add_child(shape)

func setup(p_player: CharacterBody2D):
	player = p_player
	_start_phase(Phase.ROAR)

func _start_phase(new_phase: int):
	phase = new_phase
	hits_in_tired = 0

	match phase:
		Phase.ROAR:
			phase_timer = 2.0
			roar_anim = 0.0
		Phase.ROCKS:
			phase_timer = 5.0
			rock_timer = 0.5
			rock_interval = 0.8
		Phase.TIRED:
			phase_timer = 4.0  # Window to hit (2 hits allowed)
		Phase.ANGRY_ROCKS:
			phase_timer = 6.0
			rock_timer = 0.3
			rock_interval = 0.5
			is_angry = true
		Phase.TIRED2:
			phase_timer = 4.0
		Phase.DEATH:
			is_dead = true
			death_anim = 0.0

func _process(delta):
	if is_dead:
		death_anim += delta
		if death_anim >= 2.0:
			golem_defeated.emit()
			queue_free()
		queue_redraw()
		return

	phase_timer -= delta

	if is_hit:
		hit_timer -= delta
		if hit_timer <= 0:
			is_hit = false

	# Face player
	if player and is_instance_valid(player):
		facing_right = player.global_position.x > global_position.x

	match phase:
		Phase.ROAR:
			roar_anim += delta
			if phase_timer <= 0:
				_start_phase(Phase.ROCKS)
		Phase.ROCKS:
			rock_timer -= delta
			if rock_timer <= 0:
				_spawn_rock()
				rock_timer = rock_interval
			if phase_timer <= 0:
				_start_phase(Phase.TIRED)
		Phase.TIRED:
			if phase_timer <= 0 or hits_in_tired >= 2:
				_start_phase(Phase.ANGRY_ROCKS)
		Phase.ANGRY_ROCKS:
			rock_timer -= delta
			if rock_timer <= 0:
				_spawn_rock()
				rock_timer = rock_interval
			if phase_timer <= 0:
				_start_phase(Phase.TIRED2)
		Phase.TIRED2:
			if phase_timer <= 0 or hits_in_tired >= 2:
				# If still alive, restart cycle
				if health > 0:
					is_angry = false
					_start_phase(Phase.ROAR)

	# Angry shake
	if is_angry and phase != Phase.TIRED2:
		shake_offset = Vector2(randf_range(-2, 2), randf_range(-1, 1))
	else:
		shake_offset = Vector2.ZERO

	# Update rocks
	_update_rocks(delta)

	queue_redraw()

func _physics_process(delta):
	velocity.y += gravity_val * delta
	velocity.x = 0
	move_and_slide()

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	if is_dead:
		return

	# Only take damage during tired phases
	if phase != Phase.TIRED and phase != Phase.TIRED2:
		# Blocked! Show shield effect
		is_hit = true
		hit_timer = 0.1
		return

	health -= amount
	hits_in_tired += 1
	is_hit = true
	hit_timer = 0.2
	velocity = knockback_dir * 30

	if health <= 0:
		_start_phase(Phase.DEATH)

func _spawn_rock():
	if not player or not is_instance_valid(player):
		return

	# Rock aims directly at player's current position (precise targeting)
	var target_pos = player.global_position + Vector2(0, -10)
	var spawn_y = global_position.y - 180

	# Calculate direction from spawn point to player
	var spawn_x = target_pos.x + randf_range(-8, 8)  # Very slight randomness
	var dir = Vector2(target_pos.x - spawn_x, target_pos.y - spawn_y).normalized()
	var spd = 220.0 + (60.0 if is_angry else 0.0)

	var rock = {
		"x": spawn_x,
		"y": spawn_y,
		"dir_x": dir.x * spd,  # Velocity components (aimed at player)
		"dir_y": dir.y * spd,
		"speed": spd,
		"active": true,
		"warning_timer": 0.5,  # Warning before launch — time to dodge
		"target_x": target_pos.x,
		"target_y": target_pos.y,
		"hit": false,
	}
	rocks.append(rock)

func _update_rocks(delta):
	var to_remove = []
	for i in rocks.size():
		var rock = rocks[i]
		if rock.warning_timer > 0:
			rock.warning_timer -= delta
			continue

		# Move along aimed direction
		rock.x += rock.dir_x * delta
		rock.y += rock.dir_y * delta

		# Check collision with player
		if not rock.hit and player and is_instance_valid(player):
			var dist = Vector2(rock.x, rock.y).distance_to(player.global_position + Vector2(0, -10))
			if dist < 16:
				rock.hit = true
				var dmg = 20 if not is_angry else 30
				var dir = (player.global_position - Vector2(rock.x, rock.y)).normalized()
				player.take_damage(dmg, dir)

		# Remove if far from golem (out of arena)
		var dist_from_golem = Vector2(rock.x, rock.y).distance_to(global_position)
		if dist_from_golem > 400 or rock.y > global_position.y + 120:
			to_remove.append(i)

	# Remove from back to front
	to_remove.reverse()
	for idx in to_remove:
		rocks.remove_at(idx)

func _draw():
	var s = 1 if facing_right else -1
	var ox = shake_offset.x
	var oy = shake_offset.y

	if is_dead:
		_draw_death()
		return

	# Hit flash
	if is_hit and phase != Phase.TIRED and phase != Phase.TIRED2:
		# Shield flash - blocked hit
		draw_circle(Vector2(ox, -20 + oy), 25, Color(0.6, 0.6, 0.7, 0.3))

	# === GOLEM BODY ===
	# Legs (thick stone pillars)
	draw_rect(Rect2(-10 + ox, -6 + oy, 8, 8), Color(0.4, 0.38, 0.32))
	draw_rect(Rect2(2 + ox, -6 + oy, 8, 8), Color(0.4, 0.38, 0.32))
	# Feet
	draw_rect(Rect2(-12 + ox, 0 + oy, 10, 3), Color(0.45, 0.42, 0.35))
	draw_rect(Rect2(2 + ox, 0 + oy, 10, 3), Color(0.45, 0.42, 0.35))

	# Torso (massive stone block)
	draw_rect(Rect2(-14 + ox, -30 + oy, 28, 26), Color(0.5, 0.47, 0.4))
	draw_rect(Rect2(-12 + ox, -28 + oy, 24, 22), Color(0.55, 0.52, 0.45))
	# Crack details
	draw_line(Vector2(-8 + ox, -25 + oy), Vector2(-3 + ox, -15 + oy), Color(0.35, 0.33, 0.28), 1.0)
	draw_line(Vector2(5 + ox, -28 + oy), Vector2(8 + ox, -18 + oy), Color(0.35, 0.33, 0.28), 1.0)
	# Glowing rune in chest
	var rune_col = Color(1, 0.5, 0.1, 0.6) if is_angry else Color(0.3, 0.8, 0.4, 0.5)
	if phase == Phase.TIRED or phase == Phase.TIRED2:
		rune_col = Color(0.2, 0.5, 1.0, 0.8)  # Blue when vulnerable
	draw_rect(Rect2(-3 + ox, -22 + oy, 6, 6), rune_col)
	draw_line(Vector2(0 + ox, -24 + oy), Vector2(0 + ox, -14 + oy), rune_col * 0.8, 1.5)
	draw_line(Vector2(-5 + ox, -19 + oy), Vector2(5 + ox, -19 + oy), rune_col * 0.8, 1.5)

	# Arms (thick stone)
	var arm_angle = sin(Time.get_ticks_msec() * 0.003) * 0.1
	if phase == Phase.ROAR:
		arm_angle = sin(roar_anim * 8) * 0.4
	elif phase == Phase.TIRED or phase == Phase.TIRED2:
		arm_angle = 0.5  # Arms drooping

	# Left arm
	draw_rect(Rect2(-20 + ox, -26 + oy, 7, 18), Color(0.48, 0.45, 0.38))
	# Right arm
	draw_rect(Rect2(13 + ox, -26 + oy, 7, 18), Color(0.48, 0.45, 0.38))
	# Fists
	draw_rect(Rect2(-22 + ox, -10 + int(arm_angle * 10) + oy, 10, 8), Color(0.52, 0.48, 0.4))
	draw_rect(Rect2(12 + ox, -10 + int(arm_angle * 10) + oy, 10, 8), Color(0.52, 0.48, 0.4))

	# Head (smaller stone block)
	draw_rect(Rect2(-8 + ox, -40 + oy, 16, 11), Color(0.5, 0.47, 0.4))
	draw_rect(Rect2(-7 + ox, -39 + oy, 14, 9), Color(0.55, 0.52, 0.45))
	# Eyes (glowing)
	var eye_col = Color(1, 0.3, 0.1, 0.9) if is_angry else Color(0.8, 0.6, 0.1, 0.8)
	if phase == Phase.TIRED or phase == Phase.TIRED2:
		eye_col = Color(0.3, 0.3, 0.5, 0.5)  # Dim when tired
	draw_rect(Rect2(-5 + ox, -37 + oy, 3, 2), eye_col)
	draw_rect(Rect2(2 + ox, -37 + oy, 3, 2), eye_col)
	# Brow
	draw_rect(Rect2(-6 + ox, -39 + oy, 12, 2), Color(0.45, 0.42, 0.36))

	# Roar effect
	if phase == Phase.ROAR:
		var roar_alpha = sin(roar_anim * 6) * 0.4
		draw_circle(Vector2(ox, -20 + oy), 30 + roar_anim * 10, Color(1, 0.5, 0.2, max(0, roar_alpha)))
		# Open mouth
		draw_rect(Rect2(-4 + ox, -33 + oy, 8, 4), Color(0.15, 0.05, 0.02))

	# Tired effect (dizzy stars + slumping)
	if phase == Phase.TIRED or phase == Phase.TIRED2:
		var t = Time.get_ticks_msec() * 0.004
		for i in 3:
			var angle = t + i * TAU / 3
			var star_x = cos(angle) * 14 + ox
			var star_y = -44 + sin(angle * 2) * 3 + oy
			draw_circle(Vector2(star_x, star_y), 2, Color(1, 1, 0.3, 0.8))
		# "VULNERABLE" text
		draw_string(ThemeDB.fallback_font, Vector2(-30, -50),
			"VULNERABLE!", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(0.3, 0.8, 1.0, 0.9))

	# HP bar
	var bar_w = 40.0
	var hp_frac = float(health) / max_health
	draw_rect(Rect2(-bar_w / 2, -52, bar_w, 4), Color(0.2, 0, 0, 0.7))
	var hp_col = Color(0.9, 0.2, 0.1) if hp_frac < 0.5 else Color(0.8, 0.5, 0.1)
	draw_rect(Rect2(-bar_w / 2, -52, bar_w * hp_frac, 4), hp_col)

	# === DRAW ROCKS ===
	for rock in rocks:
		if rock.warning_timer > 0:
			# Warning: flashing line from spawn point to target (shows trajectory)
			var warn_alpha = sin(rock.warning_timer * 16) * 0.5 + 0.5
			var rel_sx = rock.x - global_position.x
			var rel_sy = rock.y - global_position.y
			var rel_tx = rock.target_x - global_position.x
			var rel_ty = rock.target_y - global_position.y
			# Trajectory line
			draw_line(Vector2(rel_sx, rel_sy), Vector2(rel_tx, rel_ty),
				Color(1, 0.2, 0.1, warn_alpha * 0.35), 1.5)
			# Target crosshair
			draw_circle(Vector2(rel_tx, rel_ty), 6, Color(1, 0.2, 0.1, warn_alpha * 0.3))
			draw_line(Vector2(rel_tx - 5, rel_ty), Vector2(rel_tx + 5, rel_ty),
				Color(1, 0.3, 0.1, warn_alpha * 0.5), 1.0)
			draw_line(Vector2(rel_tx, rel_ty - 5), Vector2(rel_tx, rel_ty + 5),
				Color(1, 0.3, 0.1, warn_alpha * 0.5), 1.0)
			# Rock at spawn (glowing, ready to launch)
			draw_circle(Vector2(rel_sx, rel_sy), 5, Color(1, 0.5, 0.2, warn_alpha * 0.6))
		else:
			var rel_x = rock.x - global_position.x
			var rel_y = rock.y - global_position.y
			# Flying rock with trail
			draw_rect(Rect2(rel_x - 6, rel_y - 6, 12, 12), Color(0.5, 0.45, 0.35))
			draw_rect(Rect2(rel_x - 5, rel_y - 5, 10, 10), Color(0.6, 0.55, 0.45))
			# Crack
			draw_line(Vector2(rel_x - 3, rel_y - 3), Vector2(rel_x + 2, rel_y + 2), Color(0.4, 0.35, 0.28), 1.0)
			# Motion trail
			var trail_x = rel_x - rock.dir_x * 0.03
			var trail_y = rel_y - rock.dir_y * 0.03
			draw_circle(Vector2(trail_x, trail_y), 4, Color(0.5, 0.4, 0.3, 0.3))

func _draw_death():
	# Crumbling golem
	var progress = death_anim / 2.0  # 0 to 1 over 2 seconds
	var alpha = 1.0 - progress

	# Pieces flying outward
	var num_pieces = 12
	for i in num_pieces:
		var angle = (float(i) / num_pieces) * TAU + death_anim
		var dist = progress * 60
		var px = cos(angle) * dist
		var py = sin(angle) * dist - 20 + progress * 30  # Gravity
		var size = (1.0 - progress) * 8 + 2

		var col = Color(0.5, 0.47, 0.4, alpha)
		draw_rect(Rect2(px - size / 2, py - size / 2, size, size), col)

	# Central flash
	draw_circle(Vector2(0, -20), 20 * (1.0 - progress), Color(1, 0.6, 0.2, alpha * 0.5))

	# Rune energy release
	for i in 6:
		var a = (float(i) / 6) * TAU + death_anim * 3
		var end = Vector2(cos(a) * progress * 80, sin(a) * progress * 80 - 20)
		draw_line(Vector2(0, -20), end, Color(1, 0.5, 0.1, alpha * 0.4), 2.0)
