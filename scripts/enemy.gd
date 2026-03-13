extends CharacterBody2D

signal died(enemy)

# Enemy types
enum EnemyClass { ARCHER, CROSSBOW, THROWER, SHIELDMAN }

@export var enemy_class: int = EnemyClass.SHIELDMAN
@export var speed: float = 35.0
@export var max_health: int = 3
@export var damage: int = 1
@export var detection_range: float = 150.0
@export var attack_range: float = 20.0
@export var attack_cooldown: float = 1.5

var health: int
var gravity: float = 650.0
var player: CharacterBody2D = null
var can_attack: bool = true
var attack_timer: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var is_hit: bool = false
var hit_flash_timer: float = 0.0
var facing_right: bool = false
var patrol_dir: float = 1.0
var patrol_timer: float = 0.0
var is_attacking_melee: bool = false
var melee_anim_timer: float = 0.0
var is_blocking: bool = false

# Shield stun mechanic
var shield_hit_count: int = 0
var shield_hits_to_stun: int = 3
var is_stunned: bool = false
var stun_timer: float = 0.0
var stun_duration: float = 2.0

# Projectile scene reference
var projectile_script = preload("res://scripts/projectile.gd")

func _ready():
	health = max_health

	var body_shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(10, 20)
	body_shape.shape = rect
	body_shape.position = Vector2(0, -10)
	add_child(body_shape)

	collision_layer = 2
	collision_mask = 4 | 1  # walls + player

	# Contact damage area
	var hurt_area = Area2D.new()
	hurt_area.collision_layer = 0
	hurt_area.collision_mask = 1
	var hurt_shape = CollisionShape2D.new()
	var hurt_rect = RectangleShape2D.new()
	hurt_rect.size = Vector2(12, 22)
	hurt_shape.shape = hurt_rect
	hurt_shape.position = Vector2(0, -10)
	hurt_area.add_child(hurt_shape)
	add_child(hurt_area)

	if enemy_class == EnemyClass.SHIELDMAN:
		hurt_area.body_entered.connect(_on_touch_player)

	_setup_class()

func setup(p_class: int, p_health: int, p_speed: float, p_damage: int):
	enemy_class = p_class
	max_health = p_health
	health = max_health
	speed = p_speed
	damage = p_damage
	_setup_class()

func _setup_class():
	match enemy_class:
		EnemyClass.ARCHER:
			attack_range = 160.0
			attack_cooldown = 2.0
			speed = 25.0
		EnemyClass.CROSSBOW:
			attack_range = 180.0
			attack_cooldown = 3.0
			speed = 20.0
		EnemyClass.THROWER:
			attack_range = 120.0
			attack_cooldown = 2.5
			speed = 30.0
		EnemyClass.SHIELDMAN:
			attack_range = 22.0
			attack_cooldown = 1.2
			speed = 40.0
			max_health += 2
			health = max_health

func _process(delta):
	# Stun timer
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
			shield_hit_count = 0
			is_blocking = false
		queue_redraw()
		return  # Don't process anything else while stunned

	if not can_attack:
		attack_timer -= delta
		if attack_timer <= 0:
			can_attack = true

	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false

	if is_attacking_melee:
		melee_anim_timer -= delta
		if melee_anim_timer <= 0:
			is_attacking_melee = false

	patrol_timer -= delta
	if patrol_timer <= 0:
		patrol_dir *= -1
		patrol_timer = randf_range(2.0, 4.0)

	queue_redraw()

func _physics_process(delta):
	velocity.y += gravity * delta

	# Stunned - no movement, just stand there
	if is_stunned:
		velocity.x = 0
		if knockback_velocity.length() > 10:
			velocity.x = knockback_velocity.x
			knockback_velocity *= 0.85
		else:
			knockback_velocity = Vector2.ZERO
		move_and_slide()
		return

	var move_x = 0.0
	var dist_to_player = INF
	var dir_to_player = Vector2.ZERO

	if player and is_instance_valid(player):
		dir_to_player = player.global_position - global_position
		dist_to_player = dir_to_player.length()
		facing_right = dir_to_player.x > 0

		if dist_to_player < detection_range:
			match enemy_class:
				EnemyClass.ARCHER, EnemyClass.CROSSBOW:
					if dist_to_player < attack_range * 0.5:
						move_x = -sign(dir_to_player.x) * speed
					elif dist_to_player > attack_range:
						move_x = sign(dir_to_player.x) * speed * 0.6
					if dist_to_player < attack_range and can_attack:
						_ranged_attack(dir_to_player)

				EnemyClass.THROWER:
					if dist_to_player < attack_range * 0.4:
						move_x = -sign(dir_to_player.x) * speed
					elif dist_to_player > attack_range * 0.8:
						move_x = sign(dir_to_player.x) * speed * 0.5
					if dist_to_player < attack_range and can_attack:
						_throw_attack(dir_to_player)

				EnemyClass.SHIELDMAN:
					is_blocking = dist_to_player < 60
					if dist_to_player > attack_range:
						move_x = sign(dir_to_player.x) * speed
					elif can_attack:
						_melee_attack()
		else:
			move_x = patrol_dir * speed * 0.3
			facing_right = patrol_dir > 0
	else:
		move_x = patrol_dir * speed * 0.3
		facing_right = patrol_dir > 0

	if knockback_velocity.length() > 10:
		velocity.x = knockback_velocity.x
		knockback_velocity *= 0.85
	else:
		knockback_velocity = Vector2.ZERO
		velocity.x = move_x

	move_and_slide()

	if is_on_wall():
		patrol_dir *= -1
		patrol_timer = randf_range(2.0, 4.0)

func _ranged_attack(dir: Vector2):
	can_attack = false
	attack_timer = attack_cooldown

	match enemy_class:
		EnemyClass.ARCHER:
			_spawn_projectile(0, dir.normalized())
		EnemyClass.CROSSBOW:
			var base_dir = dir.normalized()
			_spawn_projectile(1, base_dir)
			_spawn_projectile(1, base_dir.rotated(0.15))
			_spawn_projectile(1, base_dir.rotated(-0.15))

func _throw_attack(dir: Vector2):
	can_attack = false
	attack_timer = attack_cooldown

	var rand = randf()
	if rand < 0.5:
		_spawn_projectile(2, dir.normalized() + Vector2(0, -0.3))
	else:
		_spawn_projectile(3, dir.normalized() + Vector2(0, -0.4))

func _spawn_projectile(type: int, dir: Vector2):
	var proj = Area2D.new()
	proj.set_script(projectile_script)
	proj.projectile_type = type
	proj.direction = dir.normalized()
	proj.damage = damage
	proj.global_position = global_position + Vector2(0, -10) + dir.normalized() * 10
	proj.rotation = dir.angle()
	get_tree().current_scene.add_child(proj)

func _melee_attack():
	can_attack = false
	attack_timer = attack_cooldown
	is_attacking_melee = true
	melee_anim_timer = 0.25

	if player and is_instance_valid(player):
		var dist = global_position.distance_to(player.global_position)
		if dist < attack_range + 10:
			var dir = (player.global_position - global_position).normalized()
			player.take_damage(damage, dir)

func _on_touch_player(body):
	if body.has_method("take_damage") and can_attack and enemy_class == EnemyClass.SHIELDMAN and not is_stunned:
		_melee_attack()

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	# Stunned enemies take full damage, no blocking
	if is_stunned:
		health -= amount
		is_hit = true
		hit_flash_timer = 0.15
		knockback_velocity = knockback_dir * 100
		knockback_velocity.y = -60
		if health <= 0:
			died.emit(self)
			queue_free()
		return

	# Shieldman blocks from front
	if enemy_class == EnemyClass.SHIELDMAN and is_blocking:
		var attack_from_front = (facing_right and knockback_dir.x > 0) or (not facing_right and knockback_dir.x < 0)
		if attack_from_front:
			# Shield hit! Count it
			shield_hit_count += 1
			knockback_velocity = knockback_dir * 50
			is_hit = true
			hit_flash_timer = 0.1

			if shield_hit_count >= shield_hits_to_stun:
				# STUNNED! Shield breaks temporarily
				is_stunned = true
				stun_timer = stun_duration
				is_blocking = false
				knockback_velocity = knockback_dir * 100
				knockback_velocity.y = -50
			return

	health -= amount
	is_hit = true
	hit_flash_timer = 0.15
	knockback_velocity = knockback_dir * 130
	knockback_velocity.y = -80

	if health <= 0:
		died.emit(self)
		queue_free()

func _draw():
	var s = 1 if facing_right else -1

	match enemy_class:
		EnemyClass.ARCHER: _draw_archer(s)
		EnemyClass.CROSSBOW: _draw_crossbow(s)
		EnemyClass.THROWER: _draw_thrower(s)
		EnemyClass.SHIELDMAN: _draw_shieldman(s)

	# Hit flash overlay
	if is_hit:
		draw_rect(Rect2(-6, -22, 12, 22), Color(1, 1, 1, 0.5))

	# Stun stars
	if is_stunned:
		var t = Time.get_ticks_msec() * 0.003
		for i in 3:
			var angle = t + i * TAU / 3
			var sx = cos(angle) * 8
			var sy = -26 + sin(angle * 2) * 2
			_draw_star(Vector2(sx, sy), 2.5, Color(1, 1, 0.3, 0.9))

		# Shield crack indicator
		if enemy_class == EnemyClass.SHIELDMAN:
			var shield_x = s * 9
			# Cracks on shield area
			draw_line(Vector2(shield_x - 2, -18), Vector2(shield_x + 1, -12), Color(0.9, 0.8, 0.2, 0.7), 1.0)
			draw_line(Vector2(shield_x, -16), Vector2(shield_x - 2, -8), Color(0.9, 0.8, 0.2, 0.7), 1.0)

func _draw_star(pos: Vector2, size: float, color: Color):
	# Simple 4-point star
	draw_line(pos + Vector2(-size, 0), pos + Vector2(size, 0), color, 1.5)
	draw_line(pos + Vector2(0, -size), pos + Vector2(0, size), color, 1.5)
	draw_line(pos + Vector2(-size * 0.6, -size * 0.6), pos + Vector2(size * 0.6, size * 0.6), color, 1.0)
	draw_line(pos + Vector2(size * 0.6, -size * 0.6), pos + Vector2(-size * 0.6, size * 0.6), color, 1.0)

func _draw_archer(s: int):
	# Legs
	draw_rect(Rect2(-3, -3, 3, 4), Color(0.3, 0.22, 0.15))
	draw_rect(Rect2(1, -3, 3, 4), Color(0.3, 0.22, 0.15))
	# Body
	draw_rect(Rect2(-4, -14, 8, 12), Color(0.35, 0.28, 0.18))
	draw_rect(Rect2(-3, -13, 6, 5), Color(0.25, 0.2, 0.12))
	# Hood
	draw_rect(Rect2(-4, -20, 8, 7), Color(0.3, 0.25, 0.15))
	draw_rect(Rect2(-3, -19, 6, 5), Color(0.25, 0.2, 0.12))
	# Eye
	draw_rect(Rect2(s * 1, -17, 2, 1), Color(0.9, 0.3, 0.2))
	# Bow
	var bow_x = s * 7
	draw_arc(Vector2(bow_x, -12), 8, -PI/2 * s + PI/2, PI/2 * s + PI/2, 12, Color(0.5, 0.35, 0.15), 1.5)
	draw_line(Vector2(bow_x, -20), Vector2(bow_x, -4), Color(0.7, 0.7, 0.7), 0.5)
	# Quiver on back
	draw_rect(Rect2(-s * 5, -18, 3, 10), Color(0.4, 0.28, 0.12))

func _draw_crossbow(s: int):
	# Legs
	draw_rect(Rect2(-3, -3, 3, 4), Color(0.22, 0.22, 0.25))
	draw_rect(Rect2(1, -3, 3, 4), Color(0.22, 0.22, 0.25))
	# Heavy armor body
	draw_rect(Rect2(-5, -15, 10, 13), Color(0.3, 0.3, 0.35))
	draw_rect(Rect2(-4, -14, 8, 6), Color(0.38, 0.38, 0.42))
	# Head with half-helm
	draw_rect(Rect2(-4, -21, 8, 7), Color(0.85, 0.7, 0.5))
	draw_rect(Rect2(-4, -21, 8, 3), Color(0.4, 0.4, 0.45))
	# Eyes
	draw_rect(Rect2(s * 1, -19, 2, 1), Color(0.2, 0.2, 0.2))
	# Crossbow
	var cx = s * 8
	draw_rect(Rect2(cx - 2, -13, 4, 2), Color(0.4, 0.3, 0.15))
	draw_line(Vector2(cx, -13), Vector2(cx - 4 * s, -17), Color(0.4, 0.4, 0.4), 1.5)
	draw_line(Vector2(cx, -13), Vector2(cx - 4 * s, -9), Color(0.4, 0.4, 0.4), 1.5)
	draw_line(Vector2(cx - 4 * s, -17), Vector2(cx - 4 * s, -9), Color(0.6, 0.6, 0.6), 0.5)
	# Bolt rack on belt
	for i in 3:
		draw_line(Vector2(-s * 3 + i * 2, -4), Vector2(-s * 3 + i * 2, -1), Color(0.5, 0.4, 0.2), 1.0)

func _draw_thrower(s: int):
	# Legs
	draw_rect(Rect2(-3, -3, 3, 4), Color(0.28, 0.2, 0.15))
	draw_rect(Rect2(1, -3, 3, 4), Color(0.28, 0.2, 0.15))
	# Body
	draw_rect(Rect2(-5, -16, 10, 14), Color(0.4, 0.3, 0.2))
	draw_rect(Rect2(-4, -15, 8, 6), Color(0.45, 0.35, 0.22))
	# Bandolier
	draw_line(Vector2(-4, -15), Vector2(4, -8), Color(0.3, 0.25, 0.15), 2.0)
	draw_circle(Vector2(-2, -9), 2, Color(0.3, 0.3, 0.3))
	draw_circle(Vector2(2, -10), 2, Color(0.3, 0.3, 0.3))
	# Head
	draw_rect(Rect2(-4, -22, 8, 7), Color(0.85, 0.7, 0.5))
	# Bandana
	draw_rect(Rect2(-4, -22, 8, 3), Color(0.6, 0.15, 0.1))
	# Eye
	draw_rect(Rect2(s * 1, -20, 2, 2), Color(0.15, 0.15, 0.15))
	# Hammer in hand
	var hx = s * 8
	draw_line(Vector2(hx, -14), Vector2(hx, -6), Color(0.45, 0.3, 0.12), 2.0)
	draw_rect(Rect2(hx - 3, -17, 6, 4), Color(0.5, 0.5, 0.55))

func _draw_shieldman(s: int):
	# Legs with greaves
	draw_rect(Rect2(-4, -3, 3, 4), Color(0.35, 0.35, 0.38))
	draw_rect(Rect2(1, -3, 3, 4), Color(0.35, 0.35, 0.38))
	# Heavy plate armor body
	draw_rect(Rect2(-5, -16, 10, 14), Color(0.4, 0.4, 0.45))
	draw_rect(Rect2(-4, -15, 8, 7), Color(0.48, 0.48, 0.52))
	# Shoulder pads
	draw_rect(Rect2(-6, -16, 3, 4), Color(0.45, 0.45, 0.5))
	draw_rect(Rect2(3, -16, 3, 4), Color(0.45, 0.45, 0.5))
	# Full helm
	draw_rect(Rect2(-4, -22, 8, 7), Color(0.45, 0.45, 0.5))
	draw_rect(Rect2(-4, -22, 8, 2), Color(0.52, 0.52, 0.56))
	# Visor slit
	draw_rect(Rect2(-3 + s, -19, 5, 1), Color(0.08, 0.08, 0.1))

	# Eyes glow based on state
	if is_stunned:
		# Dazed eyes - swirly
		draw_rect(Rect2(s - 1, -19, 3, 1), Color(0.8, 0.8, 0.2))
	else:
		draw_rect(Rect2(s, -19, 2, 1), Color(0.6, 0.15, 0.1))

	# Shield
	if is_blocking and not is_stunned:
		var sx = s * 9
		draw_rect(Rect2(sx - 4, -20, 7, 17), Color(0.5, 0.15, 0.1))
		draw_rect(Rect2(sx - 3, -19, 5, 15), Color(0.55, 0.2, 0.12))
		draw_rect(Rect2(sx - 1, -15, 2, 2), Color(0.7, 0.6, 0.2))
		# Shield hit indicators
		if shield_hit_count > 0:
			for i in shield_hit_count:
				var crack_y = -17 + i * 5
				draw_line(Vector2(sx - 2, crack_y), Vector2(sx + 2, crack_y + 3), Color(0.3, 0.1, 0.05), 1.0)
		# Rivets
		draw_circle(Vector2(sx, -18), 1, Color(0.6, 0.55, 0.3))
		draw_circle(Vector2(sx, -6), 1, Color(0.6, 0.55, 0.3))
	elif is_stunned:
		# Shield lowered/dropped during stun
		var sx = s * 5
		draw_rect(Rect2(sx - 3, -6, 6, 7), Color(0.45, 0.12, 0.08, 0.7))

	# Sword - horizontal swing like player
	if is_attacking_melee:
		var swing_progress = 1.0 - (melee_anim_timer / 0.25)
		var base = Vector2(s * 5, -12)
		var angle = lerp(-0.6, 1.0, swing_progress) * s
		var tip = base + Vector2(cos(angle) * 18, sin(angle) * 8 - 2)
		draw_line(base, tip, Color(0.8, 0.8, 0.85), 2.5)
		draw_line(base + Vector2(0, -3), base + Vector2(0, 3), Color(0.6, 0.5, 0.2), 2.0)
	elif not is_stunned:
		draw_line(Vector2(s * 6, -16), Vector2(s * 7, -3), Color(0.7, 0.7, 0.78), 2.0)
		draw_line(Vector2(s * 4, -16), Vector2(s * 8, -16), Color(0.5, 0.4, 0.2), 1.5)
	else:
		# Sword drooping during stun
		draw_line(Vector2(s * 5, -8), Vector2(s * 8, 0), Color(0.6, 0.6, 0.65), 2.0)
