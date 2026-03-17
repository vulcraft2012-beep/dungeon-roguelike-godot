extends CharacterBody2D
# Portal Eye Monster - based on the psychedelic eye creature design
# A swirling portal opens, revealing a giant eye that shoots arrows
# Kill it while the portal is open (5 seconds after each shot)

signal skeleton_died(portal)

var player: CharacterBody2D = null
var portal_open: bool = false
var portal_timer: float = 0.0
var portal_duration: float = 5.0
var shoot_cooldown: float = 2.0
var shoot_timer: float = 0.0
var skeleton_health: int = 60
var max_skeleton_health: int = 60
var is_dead: bool = false
var spawn_anim: float = 0.0
var death_anim: float = 0.0
var facing_right: bool = false
var damage: int = 20
var gravity_val: float = 650.0
var is_hit: bool = false
var hit_timer: float = 0.0

# Eye animation
var eye_angle: float = 0.0  # Where the eye is looking
var iris_pulse: float = 0.0
var portal_rotation: float = 0.0
var blink_timer: float = 0.0
var blink_state: float = 0.0  # 0 = open, 1 = closed
var tentacle_phase: float = 0.0

# Portal ring colors (rainbow cycle)
var ring_hue: float = 0.0

# Particles
var particles: Array = []

var projectile_script = preload("res://scripts/projectile.gd")

func _ready():
	collision_layer = 2  # enemy layer - player attack area can detect us
	collision_mask = 4    # walls only

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 14
	shape.shape = circle
	shape.position = Vector2(0, -14)
	add_child(shape)

func setup(p_player: CharacterBody2D, p_damage: int = 1):
	player = p_player
	damage = p_damage

func open_portal():
	portal_open = true
	portal_timer = portal_duration
	spawn_anim = 0.0
	shoot_timer = 1.2
	is_dead = false

	if player and is_instance_valid(player):
		facing_right = player.global_position.x > global_position.x

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	if not portal_open or is_dead:
		return

	skeleton_health -= amount
	is_hit = true
	hit_timer = 0.15

	# Small knockback
	velocity = knockback_dir * 40

	if skeleton_health <= 0:
		is_dead = true
		death_anim = 0.0

func _process(delta):
	if is_dead:
		death_anim += delta * 2.5
		if death_anim >= 1.0:
			skeleton_died.emit(self)
			queue_free()
		queue_redraw()
		return

	portal_rotation += delta * 2.5
	ring_hue = fmod(ring_hue + delta * 0.3, 1.0)
	tentacle_phase += delta * 3.0
	iris_pulse += delta * 4.0

	if is_hit:
		hit_timer -= delta
		if hit_timer <= 0:
			is_hit = false

	# Blink occasionally
	blink_timer -= delta
	if blink_timer <= 0:
		blink_timer = randf_range(2.0, 5.0)
		blink_state = 1.0
	if blink_state > 0:
		blink_state = max(0, blink_state - delta * 8)

	if portal_open:
		spawn_anim = min(spawn_anim + delta * 3.0, 1.0)
		portal_timer -= delta
		shoot_timer -= delta

		# Track player with eye
		if player and is_instance_valid(player):
			var dir = (player.global_position - global_position).normalized()
			var target_angle = dir.angle()
			eye_angle = lerp_angle(eye_angle, target_angle, delta * 5)
			facing_right = player.global_position.x > global_position.x

		if shoot_timer <= 0 and spawn_anim >= 0.8:
			_shoot_arrow()
			shoot_timer = shoot_cooldown

		if portal_timer <= 0:
			portal_open = false
			_despawn()

	# Spawn particles
	if portal_open and randf() < 0.4:
		var angle = randf() * TAU
		particles.append({
			"pos": Vector2(cos(angle) * 20, sin(angle) * 20 - 14),
			"life": 0.6,
			"vel": Vector2(cos(angle + PI) * 15, sin(angle + PI) * 15),
			"hue": randf()
		})

	# Update particles
	var i = particles.size() - 1
	while i >= 0:
		particles[i].life -= delta
		particles[i].pos += particles[i].vel * delta
		if particles[i].life <= 0:
			particles.remove_at(i)
		i -= 1

	queue_redraw()

func _physics_process(delta):
	velocity.y += gravity_val * delta
	velocity.x *= 0.9
	move_and_slide()

func _shoot_arrow():
	if not player or not is_instance_valid(player):
		return

	var dir = (player.global_position + Vector2(0, -10) - global_position - Vector2(0, -14)).normalized()

	var proj = Area2D.new()
	proj.set_script(projectile_script)
	proj.projectile_type = 0  # ARROW
	proj.direction = dir
	proj.damage = damage
	proj.global_position = global_position + Vector2(0, -14) + dir * 18
	proj.rotation = dir.angle()
	get_tree().current_scene.add_child(proj)

	# Recoil
	velocity = -dir * 30

func _despawn():
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self):
		skeleton_died.emit(self)
		queue_free()

func _draw():
	var alpha = spawn_anim if portal_open else max(0, 1.0 - death_anim * 2)
	if alpha <= 0:
		return

	# Hit flash
	var flash = 1.0 if is_hit else 0.0

	# === PORTAL RING (outer swirling rainbow ring) ===
	_draw_portal_ring(alpha)

	# === TENTACLES coming from portal edges ===
	if spawn_anim > 0.3:
		_draw_tentacles(alpha)

	# === THE EYE ===
	if spawn_anim > 0.2:
		var eye_alpha = clampf((spawn_anim - 0.2) / 0.5, 0, 1) * alpha
		_draw_eye(eye_alpha, flash)

	# === PARTICLES ===
	for p in particles:
		var c = Color.from_hsv(p.hue, 0.8, 1.0, p.life * alpha)
		draw_circle(p.pos, 1.5 * p.life, c)

	# === TIMER INDICATOR ===
	if portal_open:
		var time_frac = portal_timer / portal_duration
		var tc = Color(0.2, 1, 0.2, 0.7) if time_frac > 0.3 else Color(1, 0.2, 0.1, 0.9)
		draw_arc(Vector2(0, -34), 6, 0, TAU * time_frac, 16, tc, 2.0)

	# === HEALTH BAR ===
	if portal_open and not is_dead and skeleton_health < max_skeleton_health:
		var bar_w = 20.0
		var bar_h = 2.0
		var hp_frac = float(skeleton_health) / max_skeleton_health
		draw_rect(Rect2(-bar_w / 2, -38, bar_w, bar_h), Color(0.2, 0, 0, 0.6))
		draw_rect(Rect2(-bar_w / 2, -38, bar_w * hp_frac, bar_h), Color(0.9, 0.2, 0.1, 0.8))

	# === DEATH EFFECT ===
	if is_dead:
		_draw_death_effect()

func _draw_portal_ring(alpha: float):
	# Swirling rainbow ring like the image
	var cx = 0.0
	var cy = -14.0
	var segments = 36
	var outer_r = 20.0 * spawn_anim
	var inner_r = 14.0 * spawn_anim

	for i in segments:
		var a1 = (float(i) / segments) * TAU + portal_rotation
		var a2 = (float(i + 1) / segments) * TAU + portal_rotation

		# Rainbow color cycling per segment
		var hue = fmod(ring_hue + float(i) / segments, 1.0)
		var color = Color.from_hsv(hue, 0.9, 1.0, alpha * 0.8)

		var p1 = Vector2(cx + cos(a1) * outer_r, cy + sin(a1) * outer_r)
		var p2 = Vector2(cx + cos(a2) * outer_r, cy + sin(a2) * outer_r)
		draw_line(p1, p2, color, 3.0)

		# Inner ring glow
		var p3 = Vector2(cx + cos(a1) * inner_r, cy + sin(a1) * inner_r)
		var p4 = Vector2(cx + cos(a2) * inner_r, cy + sin(a2) * inner_r)
		var inner_color = Color.from_hsv(fmod(hue + 0.5, 1.0), 0.6, 1.0, alpha * 0.4)
		draw_line(p3, p4, inner_color, 1.5)

	# Swirl lines connecting inner to outer
	for i in 6:
		var a = (float(i) / 6) * TAU + portal_rotation * 1.5
		var p_inner = Vector2(cx + cos(a) * inner_r * 0.5, cy + sin(a) * inner_r * 0.5)
		var p_outer = Vector2(cx + cos(a + 0.3) * outer_r, cy + sin(a + 0.3) * outer_r)
		var swirl_hue = fmod(ring_hue + float(i) / 6 + 0.2, 1.0)
		draw_line(p_inner, p_outer, Color.from_hsv(swirl_hue, 0.7, 0.9, alpha * 0.3), 1.5)

	# Dark void center
	draw_circle(Vector2(cx, cy), inner_r * 0.7, Color(0.02, 0.0, 0.05, alpha * 0.9))

func _draw_tentacles(alpha: float):
	var cx = 0.0
	var cy = -14.0
	var num_tentacles = 6

	for t in num_tentacles:
		var base_angle = (float(t) / num_tentacles) * TAU + portal_rotation * 0.3
		var tentacle_len = 12.0 + sin(tentacle_phase + t * 1.5) * 4

		var segments = 5
		var prev_pos = Vector2(cx + cos(base_angle) * 16, cy + sin(base_angle) * 16)

		for s in segments:
			var frac = float(s + 1) / segments
			var wave = sin(tentacle_phase * 2 + t * 2 + s) * 3 * frac
			var angle_offset = wave * 0.1
			var seg_angle = base_angle + angle_offset
			var seg_len = tentacle_len * frac

			var next_pos = prev_pos + Vector2(cos(seg_angle) * (tentacle_len / segments), sin(seg_angle) * (tentacle_len / segments))
			next_pos += Vector2(sin(tentacle_phase + t + s * 0.5) * wave, cos(tentacle_phase + t + s * 0.3) * wave)

			var thickness = (1.0 - frac) * 2.5 + 0.5
			var hue = fmod(ring_hue + float(t) / num_tentacles + frac * 0.3, 1.0)
			var col = Color.from_hsv(hue, 0.6, 0.7, alpha * 0.7 * (1.0 - frac * 0.5))
			draw_line(prev_pos, next_pos, col, thickness)
			prev_pos = next_pos

func _draw_eye(alpha: float, flash: float):
	var cx = 0.0
	var cy = -14.0

	# Eyeball (white with slight color)
	var eye_r = 10.0
	draw_circle(Vector2(cx, cy), eye_r, Color(0.95 + flash * 0.05, 0.92, 0.88, alpha))

	# Blood vessels in the eye
	for v in 5:
		var va = (float(v) / 5) * TAU + 0.3
		var v_start = Vector2(cx + cos(va) * eye_r * 0.6, cy + sin(va) * eye_r * 0.6)
		var v_end = Vector2(cx + cos(va) * eye_r * 0.95, cy + sin(va) * eye_r * 0.95)
		draw_line(v_start, v_end, Color(0.8, 0.2, 0.15, alpha * 0.3), 0.5)

	# Iris - rainbow/psychedelic like the image
	var iris_r = 6.0 + sin(iris_pulse) * 0.5
	var look_offset = Vector2(cos(eye_angle) * 2.5, sin(eye_angle) * 2.5)
	var iris_center = Vector2(cx, cy) + look_offset

	# Draw iris rings with rainbow colors (like the reference image)
	for ring in range(6, 0, -1):
		var r = iris_r * (float(ring) / 6)
		var hue = fmod(ring_hue + float(ring) * 0.15 + sin(iris_pulse * 0.5) * 0.1, 1.0)
		var sat = 0.9 - float(ring) * 0.05
		var val = 0.9
		draw_circle(iris_center, r, Color.from_hsv(hue, sat, val, alpha))

	# Iris detail lines (radial pattern like the image)
	for i in 12:
		var a = (float(i) / 12) * TAU
		var line_start = iris_center + Vector2(cos(a) * 2.5, sin(a) * 2.5)
		var line_end = iris_center + Vector2(cos(a) * iris_r, sin(a) * iris_r)
		var line_hue = fmod(ring_hue + float(i) / 12, 1.0)
		draw_line(line_start, line_end, Color.from_hsv(line_hue, 0.7, 0.5, alpha * 0.5), 0.8)

	# Pupil (dark with glow)
	var pupil_r = 2.5 + sin(iris_pulse * 1.5) * 0.3
	draw_circle(iris_center, pupil_r, Color(0.02, 0.0, 0.05, alpha))
	# Pupil glow
	draw_circle(iris_center, pupil_r + 0.5, Color(0.4, 0.0, 0.6, alpha * 0.3))

	# Specular highlight
	draw_circle(iris_center + Vector2(-2, -2), 1.5, Color(1, 1, 1, alpha * 0.6))
	draw_circle(iris_center + Vector2(1.5, -1), 0.8, Color(1, 1, 1, alpha * 0.3))

	# Eyelids (blink animation)
	if blink_state > 0:
		var lid_h = eye_r * blink_state
		# Top eyelid
		draw_circle(Vector2(cx, cy - eye_r + lid_h * 0.5), eye_r * 1.1, Color(0.25, 0.1, 0.3, alpha * blink_state))
		# Bottom eyelid
		draw_circle(Vector2(cx, cy + eye_r - lid_h * 0.5), eye_r * 1.1, Color(0.25, 0.1, 0.3, alpha * blink_state))

	# Eye outline (fleshy edge)
	for i in 24:
		var a1 = (float(i) / 24) * TAU
		var a2 = (float(i + 1) / 24) * TAU
		var wobble = sin(tentacle_phase + i * 0.5) * 0.8
		var r1 = eye_r + 1 + wobble
		var r2 = eye_r + 1 + sin(tentacle_phase + (i + 1) * 0.5) * 0.8
		var ep1 = Vector2(cx + cos(a1) * r1, cy + sin(a1) * r1)
		var ep2 = Vector2(cx + cos(a2) * r2, cy + sin(a2) * r2)
		draw_line(ep1, ep2, Color(0.5, 0.15, 0.2, alpha * 0.8), 1.5)

func _draw_death_effect():
	var cx = 0.0
	var cy = -14.0

	# Shattering effect - eye fragments fly outward
	var num_shards = 10
	for i in num_shards:
		var angle = (float(i) / num_shards) * TAU + death_anim * 2
		var dist = death_anim * 40
		var shard_pos = Vector2(cx + cos(angle) * dist, cy + sin(angle) * dist)
		var shard_alpha = 1.0 - death_anim
		var shard_hue = fmod(ring_hue + float(i) / num_shards, 1.0)
		draw_circle(shard_pos, 3 * shard_alpha, Color.from_hsv(shard_hue, 0.8, 0.9, shard_alpha))

	# Central flash
	var flash_r = death_anim * 25
	draw_circle(Vector2(cx, cy), flash_r, Color(1, 1, 1, (1.0 - death_anim) * 0.5))

	# Purple energy burst
	for i in 6:
		var a = (float(i) / 6) * TAU + death_anim * 5
		var line_end = Vector2(cx + cos(a) * flash_r * 1.5, cy + sin(a) * flash_r * 1.5)
		draw_line(Vector2(cx, cy), line_end, Color(0.6, 0.1, 0.9, (1.0 - death_anim) * 0.6), 2.0)
