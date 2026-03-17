extends CanvasLayer

var health_max: int = 100
var health_current: int = 100
var current_level: int = 1
var enemies_remaining: int = 0
var message_text: String = ""
var message_timer: float = 0.0

# Crafting animation
var is_crafting: bool = false
var craft_timer: float = 0.0
var craft_duration: float = 2.5
var craft_item: String = ""  # "lockpick" or "crystal"

signal crafting_done
signal craft_recipe_selected(station_type: String, recipe_index: int)

# Crafting menu (Minecraft-style)
var craft_menu_open: bool = false
var craft_menu_station: String = ""  # "furnace", "anvil", "grate"
var craft_menu_selected: int = 0  # Currently highlighted recipe

@onready var draw_node: Control

func _ready():
	draw_node = Control.new()
	draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_node.draw.connect(_on_draw)
	add_child(draw_node)

func _process(delta):
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			message_text = ""
	if is_crafting:
		craft_timer -= delta
		if craft_timer <= 0:
			is_crafting = false
			crafting_done.emit()
	draw_node.queue_redraw()

func start_crafting(item: String):
	is_crafting = true
	craft_timer = craft_duration
	craft_item = item

func open_craft_menu(station_type: String):
	craft_menu_open = true
	craft_menu_station = station_type
	craft_menu_selected = 0

func close_craft_menu():
	craft_menu_open = false
	craft_menu_station = ""
	# Unfreeze player
	var player = _get_player()
	if player:
		player.is_dead = false

func is_menu_open() -> bool:
	return craft_menu_open

func _get_recipes(station: String, player) -> Array:
	# Returns array of {name, ingredients, can_craft, result_desc}
	var recipes = []
	if not player:
		return recipes

	match station:
		"furnace":
			recipes.append({
				"name": "Iron Ingot",
				"ingredients": "Iron Ore x1",
				"can_craft": player.iron_ore > 0,
				"result_desc": "Smelt iron ore into ingot"
			})
			recipes.append({
				"name": "Gold Ingot",
				"ingredients": "Gold Ore x1",
				"can_craft": player.gold_ore > 0,
				"result_desc": "Smelt gold ore into ingot"
			})
		"anvil":
			recipes.append({
				"name": "Lockpick",
				"ingredients": "Iron Ingot + Pickaxe",
				"can_craft": player.iron_ingot > 0 and player.has_pickaxe,
				"result_desc": "Craft a lockpick for doors"
			})
			recipes.append({
				"name": "Merged Sword",
				"ingredients": "Iron Ingot + Blade",
				"can_craft": player.iron_ingot > 0 and player.has_blade and player.sword_tier < 2,
				"result_desc": "Forge a stronger sword (+20 DMG)"
			})
			recipes.append({
				"name": "Amulet",
				"ingredients": "Gold Ingot + Pearl",
				"can_craft": player.gold_ingot > 0 and player.has_pearl,
				"result_desc": "Heals 1 HP every 10 seconds"
			})
		"grate":
			var room = _get_room()
			var grate_used = room.grate_used_this_level if room else false
			recipes.append({
				"name": "Fill Flask",
				"ingredients": "Grate liquid",
				"can_craft": not grate_used,
				"result_desc": "Flask +3 charges [F to use]"
			})
	return recipes

func _unhandled_input(event):
	if not craft_menu_open:
		return

	if event is InputEventKey and event.pressed:
		var recipes = _get_recipes(craft_menu_station, _get_player())
		match event.keycode:
			KEY_ESCAPE, KEY_E:
				close_craft_menu()
				get_viewport().set_input_as_handled()
			KEY_W, KEY_UP:
				craft_menu_selected = max(0, craft_menu_selected - 1)
				get_viewport().set_input_as_handled()
			KEY_S, KEY_DOWN:
				craft_menu_selected = min(recipes.size() - 1, craft_menu_selected + 1)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_SPACE:
				if craft_menu_selected >= 0 and craft_menu_selected < recipes.size():
					if recipes[craft_menu_selected].can_craft:
						craft_recipe_selected.emit(craft_menu_station, craft_menu_selected)
						# Re-check recipes after crafting
				get_viewport().set_input_as_handled()
			KEY_1:
				if recipes.size() > 0 and recipes[0].can_craft:
					craft_menu_selected = 0
					craft_recipe_selected.emit(craft_menu_station, 0)
				get_viewport().set_input_as_handled()
			KEY_2:
				if recipes.size() > 1 and recipes[1].can_craft:
					craft_menu_selected = 1
					craft_recipe_selected.emit(craft_menu_station, 1)
				get_viewport().set_input_as_handled()
			KEY_3:
				if recipes.size() > 2 and recipes[2].can_craft:
					craft_menu_selected = 2
					craft_recipe_selected.emit(craft_menu_station, 2)
				get_viewport().set_input_as_handled()

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
	var screen_size = draw_node.get_viewport_rect().size
	# === TOP-LEFT: HP BAR ===
	var bar_w = 160.0
	var bar_h = 14.0
	# Dark background panel
	draw_node.draw_rect(Rect2(5, 3, bar_w + 80, 22), Color(0, 0, 0, 0.5))

	# Health bar background
	draw_node.draw_rect(Rect2(10, 6, bar_w, bar_h), Color(0.25, 0.05, 0.05, 0.8))
	# Health bar fill
	var hp_frac = float(health_current) / max(health_max, 1)
	var bar_color = Color(0.9, 0.15, 0.1) if hp_frac > 0.3 else Color(1.0, 0.3, 0.1)
	if hp_frac > 0.6:
		bar_color = Color(0.2, 0.8, 0.2)
	draw_node.draw_rect(Rect2(10, 6, bar_w * hp_frac, bar_h), bar_color)
	# Bar border
	draw_node.draw_rect(Rect2(10, 6, bar_w, bar_h), Color(0.6, 0.6, 0.6, 0.4), false, 1.0)
	# Heart icon
	_draw_heart(draw_node, Vector2(12, 8), Color(0.9, 0.1, 0.1))

	# Numeric HP text
	var hp_text = str(health_current) + "/" + str(health_max)
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(bar_w + 15, 18),
		hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.3, 0.3))

	# === SECOND ROW: Level + Enemies ===
	draw_node.draw_rect(Rect2(5, 27, 160, 16), Color(0, 0, 0, 0.4))
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, 39),
		"Level: " + str(current_level), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(80, 39),
		"Enemies: " + str(enemies_remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))

	# === THIRD ROW: Heal + Blade ===
	var player = _get_player()
	if player:
		draw_node.draw_rect(Rect2(5, 45, 200, 16), Color(0, 0, 0, 0.35))
		# Heal charges (green circles)
		for i in player.heal_charges:
			draw_node.draw_circle(Vector2(12 + i * 10, 53), 4, Color(0.3, 0.9, 0.3, 0.8))
			draw_node.draw_circle(Vector2(12 + i * 10, 53), 2.5, Color(0.5, 1.0, 0.5, 0.9))
		if player.heal_charges > 0:
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(42, 57),
				"[H] Heal", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.8, 0.4, 0.7))

		# Blade/sword tier indicator + damage
		if player.has_blade or player.sword_tier > 0:
			var blade_text = ""
			match player.sword_tier:
				0: blade_text = "BLADE"
				1: blade_text = "BLADE"
				2: blade_text = "MERGED"
			if player.attack_damage > 20:
				blade_text += " DMG:" + str(player.attack_damage)
			var blade_col = Color(1, 0.6, 0.2, 0.9) if player.sword_tier >= 2 else Color(0.4, 0.85, 1.0, 0.9)
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(110, 57),
				blade_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, blade_col)

		# Flask charges
		if player.has_flask and player.flask_charges > 0:
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(180, 57),
				"[F]x" + str(player.flask_charges), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.3, 0.8, 0.9, 0.8))

		# Amulet indicator
		if player.has_amulet:
			draw_node.draw_circle(Vector2(210, 53), 4, Color(0.9, 0.7, 0.2, 0.7))
			draw_node.draw_circle(Vector2(210, 53), 2, Color(1, 0.9, 0.4, 0.9))

		# === FOURTH ROW: Pickaxe / Ore / Lockpick ===
		if player.has_pickaxe or _has_ore_level():
			draw_node.draw_rect(Rect2(5, 63, 250, 16), Color(0, 0, 0, 0.35))
			var row_y = 75

			if player.has_pickaxe:
				var weapon_text = "[2] Pickaxe" if player.using_pickaxe else "[1] Sword"
				var weapon_col = Color(0.8, 0.6, 0.3, 0.9) if player.using_pickaxe else Color(0.7, 0.7, 0.8, 0.7)
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, row_y),
					weapon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, weapon_col)

			# Ore progress (legacy lockpick crafting)
			if _has_ore_level():
				var ore_text = "Ore: " + str(player.ore_mined) + "/" + str(player.ore_needed)
				var ore_col = Color(0.8, 0.7, 0.4, 0.8)
				if player.ore_mined >= player.ore_needed:
					ore_col = Color(0.3, 0.9, 0.3, 0.9)
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(90, row_y),
					ore_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ore_col)

			# Lockpick indicator
			if player.has_lockpick:
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(160, row_y),
					"LOCKPICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.9, 0.8, 0.3, 0.9))

		# === FIFTH ROW: Resources (iron, gold, pearl, ingots) ===
		var has_resources = player.iron_ore > 0 or player.gold_ore > 0 or player.iron_ingot > 0 or player.gold_ingot > 0 or player.has_pearl
		if has_resources:
			draw_node.draw_rect(Rect2(5, 81, 300, 16), Color(0, 0, 0, 0.35))
			var rx = 10
			var ry = 93
			if player.iron_ore > 0:
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(rx, ry),
					"Fe:" + str(player.iron_ore), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.65, 0.55, 0.8))
				rx += 35
			if player.iron_ingot > 0:
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(rx, ry),
					"Fe bar:" + str(player.iron_ingot), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.75, 0.6, 0.9))
				rx += 50
			if player.gold_ore > 0:
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(rx, ry),
					"Au:" + str(player.gold_ore), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.85, 0.2, 0.8))
				rx += 35
			if player.gold_ingot > 0:
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(rx, ry),
					"Au bar:" + str(player.gold_ingot), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.9, 0.3, 0.9))
				rx += 50
			if player.has_pearl:
				draw_node.draw_string(ThemeDB.fallback_font, Vector2(rx, ry),
					"Pearl", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.9, 1.0, 0.9))

	# === TOP-RIGHT: Challenge/Boss info ===
	var cur_room = _get_room()
	if cur_room and cur_room.is_boss_room and cur_room.golem_boss and is_instance_valid(cur_room.golem_boss):
		var golem = cur_room.golem_boss
		var boss_cx = screen_size.x / 2
		# Boss HP bar (centered at top)
		var boss_bar_w = 200.0
		draw_node.draw_rect(Rect2(boss_cx - boss_bar_w / 2 - 2, 5, boss_bar_w + 4, 18), Color(0, 0, 0, 0.6))
		var boss_hp_frac = float(golem.health) / golem.max_health
		var boss_hp_col = Color(0.9, 0.3, 0.1) if boss_hp_frac < 0.5 else Color(0.8, 0.5, 0.1)
		draw_node.draw_rect(Rect2(boss_cx - boss_bar_w / 2, 7, boss_bar_w * boss_hp_frac, 14), boss_hp_col)
		draw_node.draw_rect(Rect2(boss_cx - boss_bar_w / 2, 7, boss_bar_w, 14), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(boss_cx - 20, 19),
			"GOLEM", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(1, 0.8, 0.3))
		# Phase text
		var phase_text = ""
		match golem.phase:
			0: phase_text = "ROAR!"
			1: phase_text = "ROCKS!"
			2: phase_text = "TIRED (" + str(2 - golem.hits_in_tired) + " hits left)"
			3: phase_text = "ANGRY ROCKS!"
			4: phase_text = "TIRED (" + str(2 - golem.hits_in_tired) + " hits left)"
			5: phase_text = "DEFEATED"
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(boss_cx - 30, 34),
			phase_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1, 1, 0.5, 0.8))
	elif cur_room:
		var challenge_text = ""
		var challenge_color = Color(0.8, 0.8, 0.8, 0.6)
		match cur_room.challenge_type:
			"lockpick":
				challenge_text = "Door: Lockpick"
				challenge_color = Color(0.9, 0.8, 0.3, 0.6)
			"guardians":
				if cur_room.challenge_complete_flag:
					challenge_text = "Guardians: DEFEATED"
					challenge_color = Color(0.3, 0.9, 0.3, 0.8)
				elif cur_room.challenge_started:
					challenge_text = "Guardians: " + str(cur_room.door_guardians.size()) + " left"
					challenge_color = Color(1, 0.4, 0.3, 0.8)
				else:
					challenge_text = "Door: Guardians"
					challenge_color = Color(0.9, 0.5, 0.2, 0.6)
			"crystal":
				if cur_room.challenge_complete_flag:
					challenge_text = "Crystal: DEFENDED"
					challenge_color = Color(0.3, 0.9, 0.3, 0.8)
				elif cur_room.challenge_started and cur_room.crystal_node and not cur_room.crystal_node.is_destroyed:
					challenge_text = "Crystal: " + str(cur_room.crystal_attackers.size()) + " attackers | HP: " + str(cur_room.crystal_node.health)
					challenge_color = Color(0.4, 0.85, 1.0, 0.8)
				elif cur_room.challenge_started and cur_room.crystal_node and cur_room.crystal_node.is_destroyed:
					challenge_text = "Crystal: DESTROYED (retry)"
					challenge_color = Color(1, 0.2, 0.2, 0.8)
				else:
					challenge_text = "Door: Mine ore -> Place Crystal"
					challenge_color = Color(0.4, 0.85, 1.0, 0.6)

		if current_level >= 5:
			challenge_text += "  [2x DMG!]"

		var cx = screen_size.x - 230
		draw_node.draw_rect(Rect2(cx - 5, 3, 235, 16), Color(0, 0, 0, 0.4))
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(cx, 15),
			challenge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, challenge_color)

		# Trial info
		if cur_room.trial_active:
			var trial_text = "TRIAL: " + str(cur_room.trial_enemies.size()) + " enemies left"
			draw_node.draw_rect(Rect2(cx - 5, 21, 235, 16), Color(0, 0, 0, 0.4))
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(cx, 33),
				trial_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.3, 0.3, 0.9))
		elif cur_room.trial_complete:
			draw_node.draw_rect(Rect2(cx - 5, 21, 235, 16), Color(0, 0, 0, 0.4))
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(cx, 33),
				"TRIAL COMPLETE!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 1, 0.3, 0.8))

	# Controls hint (bottom)
	var hint_y = screen_size.y - 12
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(10, hint_y),
		"LMB:Attack  Shift:Roll  Space:Jump  H:Heal  F:Flask  1:Sword 2:Pick  E:Interact", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.5, 0.7))

	# === CRAFTING ANIMATION ===
	if is_crafting:
		var progress = 1.0 - (craft_timer / craft_duration)
		var cx = screen_size.x / 2
		var cy = screen_size.y / 2 - 30

		# Dark overlay
		draw_node.draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), Color(0, 0, 0, 0.55))

		# "CRAFTING" title at top
		var title_col = Color(1, 0.85, 0.3, 0.9 + sin(Time.get_ticks_msec() * 0.006) * 0.1)
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(cx - 40, 40),
			"CRAFTING", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, title_col)

		# Item name below
		var item_name = "Lockpick" if craft_item == "lockpick" else "Crystal"
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(cx - 30, 62),
			item_name, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.8, 0.8, 0.8, 0.8))

		# Anvil base
		draw_node.draw_rect(Rect2(cx - 20, cy + 15, 40, 6), Color(0.35, 0.35, 0.38))
		draw_node.draw_rect(Rect2(cx - 14, cy + 21, 28, 10), Color(0.3, 0.3, 0.33))
		draw_node.draw_rect(Rect2(cx - 8, cy + 31, 16, 6), Color(0.28, 0.28, 0.3))

		# Hammer animation (swinging down)
		var hammer_angle = sin(progress * TAU * 4) * 0.8
		var hammer_base = Vector2(cx + 25, cy - 10)
		var hammer_end = hammer_base + Vector2(cos(-1.2 + hammer_angle) * 22, sin(-1.2 + hammer_angle) * 22)
		draw_node.draw_line(hammer_base, hammer_end, Color(0.5, 0.35, 0.15), 3.0)
		# Hammer head
		var h_dir = (hammer_end - hammer_base).normalized()
		var h_perp = Vector2(-h_dir.y, h_dir.x)
		draw_node.draw_line(hammer_end - h_perp * 6, hammer_end + h_perp * 6, Color(0.5, 0.5, 0.55), 4.0)

		# Sparks on hit (when hammer is near bottom)
		if sin(progress * TAU * 4) < -0.3:
			for i in 4:
				var spark_x = cx + randf_range(-15, 15)
				var spark_y = cy + randf_range(5, 15)
				draw_node.draw_circle(Vector2(spark_x, spark_y), randf_range(1, 2.5), Color(1, 0.7 + randf() * 0.3, 0.2, 0.8))

		# Ore pieces around anvil (shrinking as progress goes)
		var ore_count = int((1.0 - progress) * 6)
		for i in ore_count:
			var ox = cx - 35 + i * 12
			var oy = cy + 20
			draw_node.draw_rect(Rect2(ox, oy, 6, 6), Color(0.55, 0.45, 0.3, 0.7))
			draw_node.draw_rect(Rect2(ox + 1, oy + 1, 2, 2), Color(0.8, 0.7, 0.5, 0.5))

		# Crafted item appearing (fades in during last 30%)
		if progress > 0.7:
			var item_alpha = (progress - 0.7) / 0.3
			if craft_item == "lockpick":
				# Lockpick shape
				var lx = cx
				var ly = cy + 8
				draw_node.draw_line(Vector2(lx - 8, ly), Vector2(lx + 5, ly), Color(0.8, 0.7, 0.4, item_alpha), 2.5)
				draw_node.draw_line(Vector2(lx + 5, ly), Vector2(lx + 5, ly + 4), Color(0.8, 0.7, 0.4, item_alpha), 2.0)
				draw_node.draw_line(Vector2(lx + 2, ly), Vector2(lx + 2, ly + 3), Color(0.8, 0.7, 0.4, item_alpha), 1.5)
				# Glow
				draw_node.draw_circle(Vector2(lx, ly), 10, Color(1, 0.9, 0.4, item_alpha * 0.25))
			else:
				# Crystal shape
				var lx = cx
				var ly = cy + 5
				var pts = PackedVector2Array([
					Vector2(lx, ly - 10), Vector2(lx + 7, ly - 3),
					Vector2(lx + 5, ly + 6), Vector2(lx - 5, ly + 6),
					Vector2(lx - 7, ly - 3)
				])
				draw_node.draw_colored_polygon(pts, Color(0.3, 0.8, 1.0, item_alpha * 0.8))
				draw_node.draw_circle(Vector2(lx, ly), 12, Color(0.4, 0.9, 1.0, item_alpha * 0.2))

		# Progress bar
		var craft_bw = 120
		var craft_bx = cx - craft_bw / 2
		var craft_by = cy + 50
		draw_node.draw_rect(Rect2(craft_bx, craft_by, craft_bw, 8), Color(0.2, 0.2, 0.2, 0.8))
		draw_node.draw_rect(Rect2(craft_bx + 1, craft_by + 1, (craft_bw - 2) * progress, 6), Color(1, 0.75, 0.2, 0.9))

	# === CRAFTING MENU ===
	if craft_menu_open:
		_draw_craft_menu(screen_size)

	# Message
	if message_text != "":
		var msg_alpha = min(message_timer, 1.0)
		draw_node.draw_string(ThemeDB.fallback_font,
			Vector2(320 - message_text.length() * 3, 60),
			message_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14,
			Color(1, 1, 0.5, msg_alpha))

func _draw_craft_menu(screen_size: Vector2):
	var player = _get_player()
	var recipes = _get_recipes(craft_menu_station, player)

	# Menu dimensions
	var menu_w = 280.0
	var menu_h = 60.0 + recipes.size() * 40.0
	var mx = screen_size.x / 2 - menu_w / 2
	var my = screen_size.y / 2 - menu_h / 2

	# Dark overlay
	draw_node.draw_rect(Rect2(0, 0, screen_size.x, screen_size.y), Color(0, 0, 0, 0.6))

	# Menu background
	draw_node.draw_rect(Rect2(mx - 2, my - 2, menu_w + 4, menu_h + 4), Color(0.4, 0.35, 0.25, 0.9))
	draw_node.draw_rect(Rect2(mx, my, menu_w, menu_h), Color(0.12, 0.1, 0.08, 0.95))

	# Title bar
	var title_col = Color(0.9, 0.5, 0.1)
	var title_text = ""
	match craft_menu_station:
		"furnace":
			title_text = "FURNACE"
			title_col = Color(1, 0.5, 0.15)
		"anvil":
			title_text = "ANVIL"
			title_col = Color(0.7, 0.7, 0.8)
		"grate":
			title_text = "GRATE"
			title_col = Color(0.3, 0.7, 0.9)

	draw_node.draw_rect(Rect2(mx, my, menu_w, 24), Color(0.2, 0.18, 0.14, 0.9))
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + menu_w / 2 - 25, my + 17),
		title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, title_col)

	# Station icon
	match craft_menu_station:
		"furnace":
			# Fire icon
			draw_node.draw_rect(Rect2(mx + 8, my + 5, 10, 14), Color(0.15, 0.08, 0.05))
			var t = Time.get_ticks_msec() * 0.005
			draw_node.draw_rect(Rect2(mx + 10, my + 9, 6, 8), Color(1, 0.5, 0.1, 0.5 + sin(t) * 0.2))
			draw_node.draw_rect(Rect2(mx + 11, my + 7, 4, 5), Color(1, 0.8, 0.2, 0.4 + sin(t * 1.5) * 0.2))
		"anvil":
			# Anvil icon
			draw_node.draw_rect(Rect2(mx + 8, my + 12, 14, 4), Color(0.48, 0.48, 0.52))
			draw_node.draw_rect(Rect2(mx + 10, my + 8, 10, 5), Color(0.42, 0.42, 0.46))
			draw_node.draw_rect(Rect2(mx + 12, my + 16, 6, 3), Color(0.35, 0.35, 0.38))
		"grate":
			# Grate bars
			for i in 4:
				draw_node.draw_rect(Rect2(mx + 8 + i * 4, my + 6, 2, 12), Color(0.5, 0.5, 0.55))
			draw_node.draw_rect(Rect2(mx + 7, my + 14, 16, 4), Color(0.2, 0.5, 0.7, 0.4))

	# Recipes
	var ry = my + 32
	for i in recipes.size():
		var recipe = recipes[i]
		var is_selected = i == craft_menu_selected
		var can = recipe.can_craft

		# Selection highlight
		if is_selected:
			draw_node.draw_rect(Rect2(mx + 4, ry, menu_w - 8, 36), Color(0.3, 0.25, 0.15, 0.7))
			draw_node.draw_rect(Rect2(mx + 4, ry, 3, 36), title_col)

		# Recipe number
		var num_col = title_col if can else Color(0.4, 0.4, 0.4, 0.5)
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + 12, ry + 14),
			"[" + str(i + 1) + "]", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, num_col)

		# Recipe name
		var name_col = Color(1, 0.95, 0.8) if can else Color(0.5, 0.5, 0.5, 0.6)
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + 38, ry + 14),
			recipe.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, name_col)

		# Ingredients
		var ing_col = Color(0.7, 0.65, 0.5, 0.8) if can else Color(0.4, 0.4, 0.4, 0.5)
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + 38, ry + 28),
			recipe.ingredients, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, ing_col)

		# Result description (right side)
		if is_selected:
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + 160, ry + 28),
				recipe.result_desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.6, 0.8, 0.6, 0.7))

		# Can't craft indicator
		if not can:
			draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + menu_w - 55, ry + 14),
				"NO MAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.8, 0.3, 0.2, 0.6))

		# Separator line
		draw_node.draw_line(Vector2(mx + 8, ry + 36), Vector2(mx + menu_w - 8, ry + 36),
			Color(0.3, 0.25, 0.2, 0.4), 1.0)

		ry += 40

	# Footer
	draw_node.draw_string(ThemeDB.fallback_font, Vector2(mx + 10, my + menu_h - 8),
		"W/S:Select  Enter:Craft  E/Esc:Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.5, 0.6))

	# Player inventory summary (bottom of menu)
	if player:
		var inv_y = my + menu_h - 22
		var inv_x = mx + 10
		draw_node.draw_rect(Rect2(mx + 4, inv_y - 4, menu_w - 8, 14), Color(0.15, 0.12, 0.1, 0.8))
		var inv_parts = []
		if player.iron_ore > 0: inv_parts.append("Fe:" + str(player.iron_ore))
		if player.iron_ingot > 0: inv_parts.append("FeBar:" + str(player.iron_ingot))
		if player.gold_ore > 0: inv_parts.append("Au:" + str(player.gold_ore))
		if player.gold_ingot > 0: inv_parts.append("AuBar:" + str(player.gold_ingot))
		if player.has_pearl: inv_parts.append("Pearl")
		if player.has_pickaxe: inv_parts.append("Pickaxe")
		if player.has_blade: inv_parts.append("Blade")
		var inv_text = " | ".join(inv_parts) if inv_parts.size() > 0 else "No materials"
		draw_node.draw_string(ThemeDB.fallback_font, Vector2(inv_x, inv_y + 6),
			inv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.6, 0.6, 0.5, 0.7))

func _has_ore_level() -> bool:
	var cur_room = _get_room()
	if cur_room:
		return cur_room.challenge_type == "lockpick" or cur_room.challenge_type == "crystal"
	return false

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
