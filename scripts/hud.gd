extends CanvasLayer

var health_max: int = 5
var health_current: int = 5
var current_level: int = 1
var enemies_remaining: int = 0
var message_text: String = ""
var message_timer: float = 0.0

@onready var draw_node: Control

func _ready():
	draw_node = Control.new()
	draw_node.anchors_preset = Control.PRESET_FULL_RECT
	draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_node.draw.connect(_on_draw)
	add_child(draw_node)

func _process(delta):
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			message_text = ""
	draw_node.queue_redraw()

func update_health(current: int, max_hp: int = -1):
	health_current = current
	if max_hp > 0:
		health_max = max_hp

func update_level(level: int):
	current_level = level

func update_enemies(count: int):
	enemies_remaining = count

func show_message(text: String, duration: float = 2.0):
	message_text = text
	message_timer = duration

func _on_draw():
	# Health hearts
	for i in health_max:
		var x = 10 + i * 14
		var y = 10
		if i < health_current:
			_draw_heart(draw_node, Vector2(x, y), Color(0.9, 0.1, 0.1))
		else:
			_draw_heart(draw_node, Vector2(x, y), Color(0.3, 0.1, 0.1))

	# Level indicator
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, 35),
		"Level: " + str(current_level), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# Enemies remaining
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, 50),
		"Enemies: " + str(enemies_remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))

	# Challenge type indicator
	var room = _get_room()
	if room:
		var challenge_text = ""
		var challenge_color = Color(0.8, 0.8, 0.8, 0.6)
		match room.challenge_type:
			"lockpick":
				challenge_text = "Door: Lockpick"
				challenge_color = Color(0.9, 0.8, 0.3, 0.6)
			"guardians":
				if room.challenge_complete_flag:
					challenge_text = "Guardians: DEFEATED"
					challenge_color = Color(0.3, 0.9, 0.3, 0.8)
				elif room.challenge_started:
					challenge_text = "Guardians: " + str(room.door_guardians.size()) + " left"
					challenge_color = Color(1, 0.4, 0.3, 0.8)
				else:
					challenge_text = "Door: Guardians"
					challenge_color = Color(0.9, 0.5, 0.2, 0.6)
			"crystal":
				if room.challenge_complete_flag:
					challenge_text = "Crystal: DEFENDED"
					challenge_color = Color(0.3, 0.9, 0.3, 0.8)
				elif room.challenge_started and room.crystal_node and not room.crystal_node.is_destroyed:
					challenge_text = "Crystal: " + str(room.crystal_attackers.size()) + " attackers | HP: " + str(room.crystal_node.health)
					challenge_color = Color(0.4, 0.85, 1.0, 0.8)
				elif room.challenge_started and room.crystal_node and room.crystal_node.is_destroyed:
					challenge_text = "Crystal: DESTROYED (retry at door)"
					challenge_color = Color(1, 0.2, 0.2, 0.8)
				else:
					challenge_text = "Door: Mine ore -> Place Crystal"
					challenge_color = Color(0.4, 0.85, 1.0, 0.6)

		# Level 5+ damage warning
		if current_level >= 5:
			challenge_text += "  [2x DMG!]"

		draw_node.draw_string(ThemeDB.fallback_font, Vector2(draw_node.size.x - 220, 15),
			challenge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, challenge_color)

	# Heal charges
	var player = _get_player()
	if player:
		# Heal charges (green circles)
		for i in player.heal_charges:
			draw_node.draw_circle(Vector2(12 + i * 10, 62), 4, Color(0.3, 0.9, 0.3, 0.8))
			draw_node.draw_circle(Vector2(12 + i * 10, 62), 2.5, Color(0.5, 1.0, 0.5, 0.9))
		if player.heal_charges > 0:
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(42, 66),
				"[H] Heal", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.8, 0.4, 0.7))

		# Blade indicator + damage
		if player.has_blade:
			var blade_text = "BLADE"
			if player.attack_damage > 1:
				blade_text += " DMG:" + str(player.attack_damage)
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(110, 66),
				blade_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.85, 1.0, 0.9))

		# Pickaxe / Ore / Lockpick status
		var status_y = 80
		if player.has_pickaxe:
			var weapon_text = "[2] Pickaxe" if player.using_pickaxe else "[1] Sword"
			var weapon_col = Color(0.8, 0.6, 0.3, 0.9) if player.using_pickaxe else Color(0.7, 0.7, 0.8, 0.7)
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, status_y),
				weapon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, weapon_col)

		# Ore progress
		var room = _get_room()
		if room and (room.challenge_type == "lockpick" or room.challenge_type == "crystal"):
			var ore_text = "Ore: " + str(player.ore_mined) + "/" + str(player.ore_needed)
			var ore_col = Color(0.8, 0.7, 0.4, 0.8)
			if player.ore_mined >= player.ore_needed:
				ore_col = Color(0.3, 0.9, 0.3, 0.9)
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(90, status_y),
				ore_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ore_col)

		# Lockpick indicator
		if player.has_lockpick:
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(170, status_y),
				"LOCKPICK READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.8, 0.3, 0.9))

	# Controls hint (bottom)
	var hint_y = draw_node.size.y - 12
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, hint_y),
		"LMB:Attack  Shift:Roll  Space:Jump  H:Heal  1:Sword 2:Pick  E:Door", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.5, 0.7))

	# Message
	if message_text != "":
		var msg_alpha = min(message_timer, 1.0)
		draw_node.draw_string(ThemeDB.fallback_font,
			Vector2(320 - message_text.length() * 3, 60),
			message_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14,
			Color(1, 1, 0.5, msg_alpha))

func _get_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
	return null

func _get_room():
	var main = get_parent()
	if main and "current_room" in main:
		return main.current_room
	return null

func _draw_heart(node: Control, pos: Vector2, color: Color):
	var pixels = [
		Vector2(1, 0), Vector2(2, 0), Vector2(4, 0), Vector2(5, 0),
		Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(3, 1), Vector2(4, 1), Vector2(5, 1), Vector2(6, 1),
		Vector2(0, 2), Vector2(1, 2), Vector2(2, 2), Vector2(3, 2), Vector2(4, 2), Vector2(5, 2), Vector2(6, 2),
		Vector2(1, 3), Vector2(2, 3), Vector2(3, 3), Vector2(4, 3), Vector2(5, 3),
		Vector2(2, 4), Vector2(3, 4), Vector2(4, 4),
		Vector2(3, 5),
	]
	for p in pixels:
		node.draw_rect(Rect2(pos + p * 1.5, Vector2(1.5, 1.5)), color)
