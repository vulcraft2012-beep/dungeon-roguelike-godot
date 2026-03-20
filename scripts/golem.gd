extends CharacterBody2D

signal golem_defeated

enum Phase { ROAR, RADIAL, TIRED, ANGRY, TIRED2, DEATH }

var phase: int = Phase.ROAR
var phase_timer: float = 0.0
var health: int = 120
var max_health: int = 120
var hits_in_tired: int = 0
var is_dead: bool = false
var player: CharacterBody2D = null
var facing_right: bool = false

# Meteors
var rock_timer: float = 0.0
var rock_interval: float = 0.6
var rocks: Array = []
var has_been_hit: bool = false  # After first hit, adds overhead rocks too

# Roar animation
var roar_anim: float = 0.0

# Death animation
var death_anim: float = 0.0

# Angry mode
var is_angry: bool = false

# Hit flash
var is_hit: bool = false
var hit_timer: float = 0.0

# Body shake
var shake_offset: Vector2 = Vector2.ZERO

# Radial attack animation
var radial_anim: float = 0.0

# Melee slam when player gets too close
var slam_cooldown: float = 0.0
var slam_anim: float = 0.0
var is_slamming: bool = false

func _ready():
	collision_layer = 2  # enemy layer
	collision_mask = 4   # walls

	# HUGE collision box
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(70, 100)
	shape.shape = rect
	shape.position = Vector2(0, -50)
	add_child(shape)

func setup(p_player: CharacterBody2D):
	player = p_player
	_start_phase(Phase.ROAR)

func _start_phase(new_phase: int):
	phase = new_phase
	hits_in_tired = 0

	match phase:
		Phase.ROAR:
			phase_timer = 2.5
			roar_anim = 0.0
		Phase.RADIAL:
			phase_timer = 6.0
			rock_timer = 0.3
			rock_interval = 0.6 if not is_angry else 0.35
			radial_anim = 0.0
		Phase.TIRED:
			phase_timer = 3.5
		Phase.ANGRY:
			phase_timer = 7.0
			rock_timer = 0.2
			rock_interval = 0.35
			is_angry = true
			radial_anim = 0.0
		Phase.TIRED2:
			phase_timer = 3.5
		Phase.DEATH:
			is_dead = true
			death_anim = 0.0

func _process(delta):
	if is_dead:
		death_anim += delta
		if death_anim >= 2.5:
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
				_start_phase(Phase.RADIAL)
		Phase.RADIAL:
			radial_anim += delta
			rock_timer -= delta
			if rock_timer <= 0:
				_spawn_radial_burst()
				rock_timer = rock_interval
			if phase_timer <= 0:
				_start_phase(Phase.TIRED)
		Phase.TIRED:
			if phase_timer <= 0 or hits_in_tired >= 2:
				_start_phase(Phase.ANGRY)
		Phase.ANGRY:
			radial_anim += delta
			rock_timer -= delta
			if rock_timer <= 0:
				_spawn_radial_burst()
				# After being hit once, also rain from above
				if has_been_hit:
					_spawn_overhead_rock()
				rock_timer = rock_interval
			if phase_timer <= 0:
				_start_phase(Phase.TIRED2)
		Phase.TIRED2:
			if phase_timer <= 0 or hits_in_tired >= 2:
				if health > 0:
					is_angry = false
					_start_phase(Phase.ROAR)

	# Melee slam — hit player if too close
	if slam_cooldown > 0:
		slam_cooldown -= delta
	if is_slamming:
		slam_anim += delta
		if slam_anim >= 0.3:
			is_slamming = false
	if slam_cooldown <= 0 and not is_dead and player and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		if dist < 65:
			is_slamming = true
			slam_anim = 0.0
			slam_cooldown = 1.2
			var dir = (player.global_position - global_position).normalized()
			var dmg = 20 if not is_angry else 35
			player.take_damage(dmg, dir)
			player.velocity = dir * 350 + Vector2(0, -150)

	# Angry shake
	if is_angry and phase != Phase.TIRED2:
		shake_offset = Vector2(randf_range(-3, 3), randf_range(-2, 2))
	else:
		shake_offset = Vector2.ZERO

	_update_rocks(delta)
	queue_redraw()

func _physics_process(_delta):
	# Golem doesn't move — fixed in center
	pass

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	if is_dead:
		return

	if phase != Phase.TIRED and phase != Phase.TIRED2:
		is_hit = true
		hit_timer = 0.1
		return

	health -= amount
	hits_in_tired += 1
	has_been_hit = true
	is_hit = true
	hit_timer = 0.2

	if health <= 0:
		_start_phase(Phase.DEATH)

func _spawn_radial_burst():
	if not player or not is_instance_valid(player):
		return

	# Spawn meteors FROM the golem in multiple directions
	var num_rocks = 5 if not is_angry else 8
	# Slight rotation each burst so patterns shift
	var base_angle = radial_anim * 1.3 + randf_range(-0.3, 0.3)
	var spd = 180.0 + (50.0 if is_angry else 0.0)

	for i in num_rocks:
		var angle = base_angle + (float(i) / num_rocks) * TAU
		var dir = Vector2(cos(angle), sin(angle))
		# Spawn from golem's body edge
		var spawn_pos = global_position + Vector2(0, -50) + dir * 40

		var rock = {
			"x": spawn_pos.x,
			"y": spawn_pos.y,
			"dir_x": dir.x * spd,
			"dir_y": dir.y * spd,
			"warning_timer": 0.25,
			"target_x": spawn_pos.x + dir.x * 200,
			"target_y": spawn_pos.y + dir.y * 200,
			"hit": false,
			"is_overhead": false,
		}
		rocks.append(rock)

func _spawn_overhead_rock():
	if not player or not is_instance_valid(player):
		return

	# Rain from above targeting player position
	var target_x = player.global_position.x + randf_range(-20, 20)
	var spawn_pos = Vector2(target_x, global_position.y - 250)
	var target_pos = player.global_position + Vector2(0, -10)
	var dir = (target_pos - spawn_pos).normalized()
	var spd = 250.0

	var rock = {
		"x": spawn_pos.x,
		"y": spawn_pos.y,
		"dir_x": dir.x * spd,
		"dir_y": dir.y * spd,
		"warning_timer": 0.4,
		"target_x": target_pos.x,
		"target_y": target_pos.y,
		"hit": false,
		"is_overhead": true,
	}
	rocks.append(rock)

func _update_rocks(delta):
	var to_remove = []
	for i in rocks.size():
		var rock = rocks[i]
		if rock.warning_timer > 0:
			rock.warning_timer -= delta
			continue

		rock.x += rock.dir_x * delta
		rock.y += rock.dir_y * delta

		# Hit player
		if not rock.hit and player and is_instance_valid(player):
			var dist = Vector2(rock.x, rock.y).distance_to(player.global_position + Vector2(0, -10))
			if dist < 14:
				rock.hit = true
				var dmg = 15 if not is_angry else 25
				var dir = (player.global_position - Vector2(rock.x, rock.y)).normalized()
				player.take_damage(dmg, dir)

		# Remove if far away
		var dist_from_golem = Vector2(rock.x, rock.y).distance_to(global_position)
		if dist_from_golem > 500:
			to_remove.append(i)

	to_remove.reverse()
	for idx in to_remove:
		rocks.remove_at(idx)

	# Cap active rocks to prevent lag
	while rocks.size() > 40:
		rocks.pop_front()

func _draw():
	var s = 1 if facing_right else -1
	var ox = shake_offset.x
	var oy = shake_offset.y

	if is_dead:
		_draw_death()
		return

	# Hit flash (blocked)
	if is_hit and phase != Phase.TIRED and phase != Phase.TIRED2:
		draw_circle(Vector2(ox, -50 + oy), 55, Color(0.6, 0.6, 0.7, 0.25))

	# === HUGE GOLEM BODY ===

	# Legs (massive stone pillars)
	draw_rect(Rect2(-25 + ox, -14 + oy, 18, 18), Color(0.4, 0.38, 0.32))
	draw_rect(Rect2(7 + ox, -14 + oy, 18, 18), Color(0.4, 0.38, 0.32))
	# Feet (wide stone blocks)
	draw_rect(Rect2(-30 + ox, 2 + oy, 24, 6), Color(0.45, 0.42, 0.35))
	draw_rect(Rect2(6 + ox, 2 + oy, 24, 6), Color(0.45, 0.42, 0.35))

	# Torso (massive stone block)
	draw_rect(Rect2(-35 + ox, -70 + oy, 70, 60), Color(0.5, 0.47, 0.4))
	draw_rect(Rect2(-32 + ox, -67 + oy, 64, 54), Color(0.55, 0.52, 0.45))
	# Cracks
	draw_line(Vector2(-20 + ox, -60 + oy), Vector2(-8 + ox, -35 + oy), Color(0.35, 0.33, 0.28), 1.5)
	draw_line(Vector2(12 + ox, -65 + oy), Vector2(20 + ox, -40 + oy), Color(0.35, 0.33, 0.28), 1.5)
	draw_line(Vector2(-5 + ox, -55 + oy), Vector2(10 + ox, -45 + oy), Color(0.38, 0.35, 0.3), 1.0)

	# Glowing rune in chest (big, pulsing)
	var rune_pulse = sin(Time.get_ticks_msec() * 0.005) * 0.2 + 0.8
	var rune_col = Color(1, 0.5, 0.1, 0.7 * rune_pulse) if is_angry else Color(0.3, 0.8, 0.4, 0.6 * rune_pulse)
	if phase == Phase.TIRED or phase == Phase.TIRED2:
		rune_col = Color(0.2, 0.5, 1.0, 0.9)
	draw_rect(Rect2(-8 + ox, -55 + oy, 16, 16), rune_col)
	# Rune cross
	draw_line(Vector2(0 + ox, -58 + oy), Vector2(0 + ox, -36 + oy), rune_col * 0.7, 2.0)
	draw_line(Vector2(-12 + ox, -47 + oy), Vector2(12 + ox, -47 + oy), rune_col * 0.7, 2.0)
	# Rune glow
	draw_circle(Vector2(ox, -47 + oy), 12, Color(rune_col.r, rune_col.g, rune_col.b, 0.15))

	# Arms (thick stone, animated)
	var arm_angle = sin(Time.get_ticks_msec() * 0.003) * 0.1
	if phase == Phase.ROAR:
		arm_angle = sin(roar_anim * 8) * 0.4
	elif phase == Phase.TIRED or phase == Phase.TIRED2:
		arm_angle = 0.6  # Arms drooping
	elif phase == Phase.RADIAL or phase == Phase.ANGRY:
		arm_angle = sin(radial_anim * 5) * 0.3  # Throwing motion

	# Left arm
	draw_rect(Rect2(-50 + ox, -65 + oy, 18, 40), Color(0.48, 0.45, 0.38))
	# Right arm
	draw_rect(Rect2(32 + ox, -65 + oy, 18, 40), Color(0.48, 0.45, 0.38))
	# Fists (huge) — slam animation pushes fists forward/down
	var fist_y = -28 + int(arm_angle * 15)
	if is_slamming:
		var slam_t = slam_anim / 0.3
		fist_y += int(slam_t * 25)
	draw_rect(Rect2(-55 + ox, fist_y + oy, 22, 16), Color(0.52, 0.48, 0.4))
	draw_rect(Rect2(33 + ox, fist_y + oy, 22, 16), Color(0.52, 0.48, 0.4))

	# Slam shockwave effect
	if is_slamming and slam_anim > 0.1:
		var wave_r = (slam_anim - 0.1) / 0.2 * 60
		var wave_a = 1.0 - (slam_anim - 0.1) / 0.2
		draw_arc(Vector2(ox, oy), wave_r, 0, TAU, 24, Color(1, 0.6, 0.2, wave_a * 0.5), 2.0)

	# Shoulder pads (stone spikes)
	draw_rect(Rect2(-42 + ox, -72 + oy, 14, 10), Color(0.45, 0.42, 0.36))
	draw_rect(Rect2(28 + ox, -72 + oy, 14, 10), Color(0.45, 0.42, 0.36))

	# Head (stone block with horns)
	draw_rect(Rect2(-18 + ox, -95 + oy, 36, 26), Color(0.5, 0.47, 0.4))
	draw_rect(Rect2(-16 + ox, -93 + oy, 32, 22), Color(0.55, 0.52, 0.45))
	# Horns
	draw_rect(Rect2(-22 + ox, -100 + oy, 6, 12), Color(0.42, 0.4, 0.34))
	draw_rect(Rect2(16 + ox, -100 + oy, 6, 12), Color(0.42, 0.4, 0.34))
	# Eyes (large, glowing)
	var eye_col = Color(1, 0.3, 0.1, 0.9) if is_angry else Color(0.8, 0.6, 0.1, 0.8)
	if phase == Phase.TIRED or phase == Phase.TIRED2:
		eye_col = Color(0.3, 0.3, 0.5, 0.5)
	draw_rect(Rect2(-12 + ox, -88 + oy, 6, 5), eye_col)
	draw_rect(Rect2(6 + ox, -88 + oy, 6, 5), eye_col)
	# Eye glow
	draw_circle(Vector2(-9 + ox, -85 + oy), 5, Color(eye_col.r, eye_col.g, eye_col.b, 0.2))
	draw_circle(Vector2(9 + ox, -85 + oy), 5, Color(eye_col.r, eye_col.g, eye_col.b, 0.2))
	# Brow
	draw_rect(Rect2(-14 + ox, -93 + oy, 28, 3), Color(0.42, 0.4, 0.34))
	# Mouth (open during roar/attack)
	if phase == Phase.ROAR or phase == Phase.RADIAL or phase == Phase.ANGRY:
		draw_rect(Rect2(-8 + ox, -78 + oy, 16, 8), Color(0.15, 0.05, 0.02))
		# Teeth
		for t_i in 4:
			draw_rect(Rect2(-6 + t_i * 4 + ox, -78 + oy, 2, 3), Color(0.6, 0.58, 0.5))

	# Roar effect (shockwave rings)
	if phase == Phase.ROAR:
		var roar_alpha = sin(roar_anim * 6) * 0.4
		draw_circle(Vector2(ox, -50 + oy), 50 + roar_anim * 15, Color(1, 0.5, 0.2, max(0, roar_alpha)))
		draw_circle(Vector2(ox, -50 + oy), 40 + roar_anim * 20, Color(1, 0.4, 0.1, max(0, roar_alpha * 0.5)))

	# Tired effect (dizzy stars)
	if phase == Phase.TIRED or phase == Phase.TIRED2:
		var t = Time.get_ticks_msec() * 0.004
		for i in 4:
			var angle = t + i * TAU / 4
			var star_x = cos(angle) * 25 + ox
			var star_y = -100 + sin(angle * 2) * 4 + oy
			draw_circle(Vector2(star_x, star_y), 3, Color(1, 1, 0.3, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(-30, -108),
			"VULNERABLE!", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.3, 0.8, 1.0, 0.9))

	# HP bar (wide, above head)
	var bar_w = 80.0
	var hp_frac = float(health) / max_health
	draw_rect(Rect2(-bar_w / 2, -115, bar_w, 6), Color(0.2, 0, 0, 0.7))
	var hp_col = Color(0.9, 0.2, 0.1) if hp_frac < 0.5 else Color(0.8, 0.5, 0.1)
	draw_rect(Rect2(-bar_w / 2, -115, bar_w * hp_frac, 6), hp_col)

	# === DRAW METEORS ===
	for rock in rocks:
		var rel_x = rock.x - global_position.x
		var rel_y = rock.y - global_position.y
		if rock.warning_timer > 0:
			var warn_alpha = sin(rock.warning_timer * 20) * 0.5 + 0.5
			if rock.is_overhead:
				# Overhead: crosshair at target
				var rel_tx = rock.target_x - global_position.x
				var rel_ty = rock.target_y - global_position.y
				draw_circle(Vector2(rel_tx, rel_ty), 8, Color(1, 0.2, 0.1, warn_alpha * 0.4))
				draw_line(Vector2(rel_tx - 6, rel_ty), Vector2(rel_tx + 6, rel_ty),
					Color(1, 0.3, 0.1, warn_alpha * 0.6), 1.0)
				draw_line(Vector2(rel_tx, rel_ty - 6), Vector2(rel_tx, rel_ty + 6),
					Color(1, 0.3, 0.1, warn_alpha * 0.6), 1.0)
			else:
				# Radial: glowing orb at golem body edge
				draw_circle(Vector2(rel_x, rel_y), 6, Color(1, 0.5, 0.1, warn_alpha * 0.7))
				draw_circle(Vector2(rel_x, rel_y), 9, Color(1, 0.4, 0.05, warn_alpha * 0.2))
		else:
			# Flying meteor
			var col = Color(0.8, 0.35, 0.1) if rock.is_overhead else Color(0.6, 0.5, 0.35)
			draw_rect(Rect2(rel_x - 5, rel_y - 5, 10, 10), col)
			draw_rect(Rect2(rel_x - 4, rel_y - 4, 8, 8), Color(col.r + 0.15, col.g + 0.1, col.b + 0.05))
			# Fire trail
			var trail_x = rel_x - rock.dir_x * 0.025
			var trail_y = rel_y - rock.dir_y * 0.025
			draw_circle(Vector2(trail_x, trail_y), 4, Color(1, 0.5, 0.1, 0.35))
			var trail_x2 = rel_x - rock.dir_x * 0.05
			var trail_y2 = rel_y - rock.dir_y * 0.05
			draw_circle(Vector2(trail_x2, trail_y2), 3, Color(1, 0.4, 0.05, 0.2))

func _draw_death():
	var progress = death_anim / 2.5
	var alpha = 1.0 - progress

	# Pieces flying outward (more pieces for bigger golem)
	var num_pieces = 20
	for i in num_pieces:
		var angle = (float(i) / num_pieces) * TAU + death_anim * 1.5
		var dist = progress * 120
		var px = cos(angle) * dist
		var py = sin(angle) * dist - 50 + progress * 60
		var sz = (1.0 - progress) * 12 + 3

		var col = Color(0.5, 0.47, 0.4, alpha)
		draw_rect(Rect2(px - sz / 2, py - sz / 2, sz, sz), col)

	# Central flash (bigger)
	draw_circle(Vector2(0, -50), 40 * (1.0 - progress), Color(1, 0.6, 0.2, alpha * 0.5))

	# Rune energy explosion
	for i in 8:
		var a = (float(i) / 8) * TAU + death_anim * 3
		var end = Vector2(cos(a) * progress * 150, sin(a) * progress * 150 - 50)
		draw_line(Vector2(0, -50), end, Color(1, 0.5, 0.1, alpha * 0.4), 2.5)

	# Screen shake effect text
	if progress < 0.3:
		draw_string(ThemeDB.fallback_font, Vector2(-20, -120),
			"DEFEATED!", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(1, 0.8, 0.3, alpha))
