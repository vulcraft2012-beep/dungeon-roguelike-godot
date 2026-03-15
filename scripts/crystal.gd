extends Node2D

signal crystal_destroyed
signal crystal_survived

var health: int = 3
var max_health: int = 3
var is_destroyed: bool = false

func _ready():
	pass

func take_damage(amount: int, _knockback_dir: Vector2 = Vector2.ZERO):
	if is_destroyed:
		return
	health -= amount
	queue_redraw()
	if health <= 0:
		is_destroyed = true
		crystal_destroyed.emit()
		queue_redraw()

func _process(_delta):
	if not is_destroyed:
		queue_redraw()

func _draw():
	if is_destroyed:
		# Broken shards on ground
		draw_rect(Rect2(-7, -3, 4, 4), Color(0.3, 0.7, 0.9, 0.4))
		draw_rect(Rect2(3, -2, 3, 3), Color(0.2, 0.6, 0.8, 0.3))
		draw_rect(Rect2(-2, -4, 3, 5), Color(0.35, 0.75, 0.95, 0.35))
		draw_rect(Rect2(-5, 0, 10, 2), Color(0.25, 0.5, 0.6, 0.2))
		# "DESTROYED" text
		draw_string(ThemeDB.fallback_font, Vector2(-28, -16),
			"DESTROYED", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(1, 0.2, 0.2, 0.7))
		return

	var t = Time.get_ticks_msec() * 0.003
	var glow = 0.15 + sin(t) * 0.05

	# Ground glow ring
	draw_circle(Vector2(0, 0), 22, Color(0.3, 0.8, 1.0, glow * 0.5))

	# Outer glow
	draw_circle(Vector2(0, -14), 18, Color(0.3, 0.8, 1.0, glow))
	draw_circle(Vector2(0, -14), 12, Color(0.4, 0.85, 1.0, glow + 0.05))

	# Crystal body - polygon
	var points = PackedVector2Array([
		Vector2(-8, 0), Vector2(-6, -10), Vector2(-3, -22),
		Vector2(0, -28), Vector2(3, -22), Vector2(6, -10), Vector2(8, 0)
	])
	draw_colored_polygon(points, Color(0.4, 0.85, 1.0, 0.85))

	# Inner highlight
	var inner = PackedVector2Array([
		Vector2(-3, -4), Vector2(-2, -14), Vector2(0, -22),
		Vector2(2, -14), Vector2(3, -4)
	])
	draw_colored_polygon(inner, Color(0.7, 0.95, 1.0, 0.5))

	# Facet lines
	draw_line(Vector2(-6, -10), Vector2(0, -14), Color(1, 1, 1, 0.2), 1.0)
	draw_line(Vector2(6, -10), Vector2(0, -14), Color(1, 1, 1, 0.2), 1.0)
	draw_line(Vector2(0, -28), Vector2(0, -14), Color(1, 1, 1, 0.15), 1.0)

	# Sparkle effect
	var sparkle_y = -14 + sin(t * 3) * 8
	var sparkle_x = cos(t * 2) * 4
	draw_circle(Vector2(sparkle_x, sparkle_y), 1.5, Color(1, 1, 1, 0.6 + sin(t * 5) * 0.3))

	# HP indicators
	for i in max_health:
		var col = Color(0, 1, 0.3, 0.7) if i < health else Color(0.3, 0.3, 0.3, 0.4)
		draw_circle(Vector2(-6 + i * 6, 6), 2.5, col)

	# "DEFEND" text with pulse
	var alpha = 0.6 + sin(t * 2) * 0.3
	draw_string(ThemeDB.fallback_font, Vector2(-22, -34),
		"DEFEND!", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(1, 0.9, 0.3, alpha))

	# HP text
	draw_string(ThemeDB.fallback_font, Vector2(-10, 16),
		str(health) + "/" + str(max_health), HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color(0.7, 1, 0.7, 0.8))
