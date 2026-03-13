extends Node2D

var timer: float = 0.4
var max_timer: float = 0.4

func _process(delta):
	timer -= delta
	if timer <= 0:
		queue_free()
	queue_redraw()

func _draw():
	var progress = 1.0 - (timer / max_timer)
	var radius = lerp(5.0, 35.0, progress)
	var alpha = lerp(0.9, 0.0, progress)

	draw_circle(Vector2.ZERO, radius, Color(1, 0.6, 0.1, alpha))
	draw_circle(Vector2.ZERO, radius * 0.6, Color(1, 0.9, 0.3, alpha * 0.8))
	draw_circle(Vector2.ZERO, radius * 0.3, Color(1, 1, 0.8, alpha * 0.6))

	# Sparks
	for i in 8:
		var angle = (PI * 2.0 / 8) * i + progress * 2
		var dist = radius * 1.2
		var spark_pos = Vector2(cos(angle), sin(angle)) * dist
		draw_circle(spark_pos, 2.0 * (1.0 - progress), Color(1, 0.5, 0, alpha))
