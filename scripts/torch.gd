extends Node2D

var flicker_timer: float = 0.0
var flicker_offset: float = 0.0
var base_energy: float = 1.0
var light: PointLight2D
var on_wall_right: bool = false  # which side of wall

func _ready():
	# Create PointLight2D
	light = PointLight2D.new()
	light.color = Color(1.0, 0.75, 0.35)
	light.energy = base_energy
	light.texture = _create_light_texture()
	light.texture_scale = 2.5
	light.shadow_enabled = true
	light.shadow_filter = PointLight2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 2.0
	add_child(light)

	flicker_offset = randf() * 100.0

func _create_light_texture() -> GradientTexture2D:
	var tex = GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)

	var grad = Gradient.new()
	grad.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	tex.gradient = grad

	return tex

func _process(delta):
	flicker_timer += delta
	var flicker = sin(flicker_timer * 8 + flicker_offset) * 0.15 + sin(flicker_timer * 13 + flicker_offset * 2) * 0.1
	light.energy = base_energy + flicker
	light.texture_scale = 2.5 + flicker * 0.3

	queue_redraw()

func _draw():
	var s = 1 if on_wall_right else -1

	# Wall mount bracket
	draw_rect(Rect2(-s * 2, -2, 4 * s, 3), Color(0.35, 0.25, 0.12))

	# Stick
	draw_rect(Rect2(s * 2, -8, 2, 10), Color(0.4, 0.28, 0.12))

	# Flame
	var flicker_x = sin(flicker_timer * 10 + flicker_offset) * 1.5
	var flicker_y = sin(flicker_timer * 7 + flicker_offset) * 1.0

	# Outer flame
	draw_circle(Vector2(s * 3 + flicker_x, -10 + flicker_y), 4, Color(1, 0.5, 0.1, 0.7))
	# Middle flame
	draw_circle(Vector2(s * 3 + flicker_x * 0.5, -11 + flicker_y * 0.5), 3, Color(1, 0.7, 0.2, 0.8))
	# Inner flame
	draw_circle(Vector2(s * 3, -10), 2, Color(1, 0.95, 0.5, 0.9))
	# Flame tip
	draw_circle(Vector2(s * 3 + flicker_x * 0.3, -14 + flicker_y * 0.3), 1.5, Color(1, 0.8, 0.3, 0.5))
