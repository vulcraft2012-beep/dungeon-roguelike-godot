extends Area2D

enum Type { ARROW, BOLT, HAMMER, GRENADE }

var projectile_type: int = Type.ARROW
var direction: Vector2 = Vector2.RIGHT
var speed: float = 150.0
var damage: int = 1
var gravity_affect: float = 0.0
var lifetime: float = 4.0
var has_hit: bool = false
var rotation_speed: float = 0.0

# For grenade
var explode_timer: float = 0.0
var is_grenade: bool = false
var explosion_radius: float = 40.0

func _ready():
	collision_layer = 0
	collision_mask = 1 | 4  # player + walls

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()

	match projectile_type:
		Type.ARROW:
			circle.radius = 3
			speed = 180.0
			gravity_affect = 30.0
		Type.BOLT:
			circle.radius = 3
			speed = 220.0
			gravity_affect = 15.0
		Type.HAMMER:
			circle.radius = 5
			speed = 130.0
			gravity_affect = 200.0
			rotation_speed = 8.0
			damage = 2
		Type.GRENADE:
			circle.radius = 4
			speed = 120.0
			gravity_affect = 300.0
			is_grenade = true
			explode_timer = 1.5
			damage = 2

	shape.shape = circle
	add_child(shape)

	body_entered.connect(_on_hit)

func setup(p_type: int, dir: Vector2, p_damage: int = 1):
	projectile_type = p_type
	direction = dir.normalized()
	damage = p_damage

func _physics_process(delta):
	if has_hit:
		return

	direction.y += gravity_affect * delta / speed
	position += direction * speed * delta
	rotation += rotation_speed * delta

	lifetime -= delta

	if is_grenade:
		explode_timer -= delta
		if explode_timer <= 0:
			_explode()
			return

	if lifetime <= 0:
		queue_free()

	queue_redraw()

func _on_hit(body):
	if has_hit:
		return

	if is_grenade:
		_explode()
		return

	if body.has_method("take_damage"):
		var kb = direction.normalized()
		body.take_damage(damage, kb)

	has_hit = true
	queue_free()

func _explode():
	has_hit = true
	# Damage player if nearby
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p.global_position.distance_to(global_position) < explosion_radius:
			if p.has_method("take_damage"):
				var dir = (p.global_position - global_position).normalized()
				p.take_damage(damage, dir)

	# Visual explosion effect - spawn particles node
	var explosion = Node2D.new()
	explosion.set_script(load("res://scripts/explosion_effect.gd"))
	explosion.global_position = global_position
	get_parent().add_child(explosion)

	queue_free()

func _draw():
	if has_hit:
		return

	match projectile_type:
		Type.ARROW:
			draw_line(Vector2(-8, 0), Vector2(4, 0), Color(0.5, 0.35, 0.15), 1.5)
			draw_line(Vector2(4, 0), Vector2(6, 0), Color(0.6, 0.6, 0.65), 1.5)
			# Fletching
			draw_line(Vector2(-8, 0), Vector2(-10, -2), Color(0.7, 0.7, 0.7), 1.0)
			draw_line(Vector2(-8, 0), Vector2(-10, 2), Color(0.7, 0.7, 0.7), 1.0)
		Type.BOLT:
			draw_line(Vector2(-6, 0), Vector2(4, 0), Color(0.4, 0.3, 0.1), 2.0)
			draw_line(Vector2(4, 0), Vector2(6, 0), Color(0.55, 0.55, 0.6), 2.0)
			draw_line(Vector2(4, -2), Vector2(6, 0), Color(0.55, 0.55, 0.6), 1.0)
			draw_line(Vector2(4, 2), Vector2(6, 0), Color(0.55, 0.55, 0.6), 1.0)
		Type.HAMMER:
			# Handle
			draw_line(Vector2(-6, 0), Vector2(2, 0), Color(0.5, 0.35, 0.15), 2.0)
			# Head
			draw_rect(Rect2(2, -4, 6, 8), Color(0.5, 0.5, 0.55))
			draw_rect(Rect2(3, -3, 4, 6), Color(0.6, 0.6, 0.65))
		Type.GRENADE:
			draw_circle(Vector2.ZERO, 4, Color(0.3, 0.3, 0.3))
			draw_circle(Vector2.ZERO, 3, Color(0.4, 0.35, 0.3))
			# Fuse
			var fuse_glow = Color(1, 0.5, 0, 0.8) if fmod(explode_timer, 0.3) < 0.15 else Color(1, 0.2, 0, 0.5)
			draw_line(Vector2(0, -4), Vector2(2, -7), fuse_glow, 1.5)
			draw_circle(Vector2(2, -7), 2, fuse_glow)
