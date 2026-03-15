extends Node2D

var player_scene = preload("res://scenes/player.tscn")
var enemy_scene = preload("res://scenes/enemy.tscn")
var lockpick_scene = preload("res://scenes/lockpick_minigame.tscn")

var player: CharacterBody2D
var current_room: Node2D
var lockpick_ui: Control
var hud: CanvasLayer
var game_over_screen: CanvasLayer
var current_level: int = 1
var pending_door = null
var camera: Camera2D

# Global darkness overlay
var darkness: CanvasModulate

func _ready():
	# Camera
	camera = Camera2D.new()
	camera.zoom = Vector2(1.5, 1.5)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)

	# Canvas modulate for global darkness
	darkness = CanvasModulate.new()
	darkness.color = Color(0.15, 0.12, 0.1)
	add_child(darkness)

	# HUD
	var hud_script = load("res://scripts/hud.gd")
	hud = CanvasLayer.new()
	hud.set_script(hud_script)
	add_child(hud)

	# Game Over
	var go_script = load("res://scripts/game_over.gd")
	game_over_screen = CanvasLayer.new()
	game_over_screen.set_script(go_script)
	add_child(game_over_screen)
	game_over_screen.restart_game.connect(_restart_game)

	# Lockpick UI
	lockpick_ui = lockpick_scene.instantiate()
	var lockpick_canvas = CanvasLayer.new()
	lockpick_canvas.layer = 10
	lockpick_canvas.add_child(lockpick_ui)
	add_child(lockpick_canvas)
	lockpick_ui.lockpick_success.connect(_on_lockpick_success)
	lockpick_ui.lockpick_failed.connect(_on_lockpick_failed)

	_start_game()

func _start_game():
	current_level = 1
	_create_player()
	_load_room()

func _create_player():
	player = player_scene.instantiate()
	player.position = Vector2(60, 400)
	player.add_to_group("player")
	add_child(player)
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)

	# Camera follows player
	var remote = RemoteTransform2D.new()
	remote.remote_path = camera.get_path()
	player.add_child(remote)

	# Player carries a small light
	var player_light = PointLight2D.new()
	player_light.color = Color(0.9, 0.85, 0.7)
	player_light.energy = 0.6
	player_light.texture = _create_light_texture()
	player_light.texture_scale = 1.8
	player_light.position = Vector2(0, -10)
	player.add_child(player_light)

	hud.update_health(player.health, player.max_health)

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

func _load_room():
	if current_room:
		current_room.queue_free()
		await current_room.tree_exited

	var room_script = load("res://scripts/room.gd")
	current_room = Node2D.new()
	current_room.set_script(room_script)
	add_child(current_room)
	move_child(current_room, 0)

	current_room.setup(current_level, enemy_scene, player)
	current_room.room_cleared.connect(_on_room_cleared)
	current_room.door_used.connect(_on_door_used)
	current_room.challenge_complete.connect(_on_challenge_complete)

	# Player starts in the start cave
	var start_cave = null
	for cave in current_room.caves:
		if cave.type == "start":
			start_cave = cave
			break
	if start_cave:
		player.position = Vector2(start_cave.x, start_cave.floor_y - 1)
	else:
		player.position = Vector2(60, current_room.floor_y - 1)
	player.velocity = Vector2.ZERO

	# Reset per-level items
	player.has_lockpick = false
	player.ore_mined = 0
	# Keep pickaxe if already obtained, but reset on new game
	if current_room.challenge_type != "lockpick" and current_room.challenge_type != "crystal":
		player.using_pickaxe = false

	# Adjust darkness based on level
	var dark_factor = max(0.08, 0.18 - current_level * 0.012)
	darkness.color = Color(dark_factor + 0.05, dark_factor + 0.02, dark_factor)

	hud.update_level(current_level)
	hud.update_enemies(current_room.enemies.size())
	hud.show_message("Level " + str(current_level), 2.0)

func _process(_delta):
	if current_room and not current_room.is_cleared:
		hud.update_enemies(current_room.enemies.size())

func _on_room_cleared():
	hud.update_enemies(0)
	hud.show_message("Room Cleared! Find the door!", 3.0)

func _on_door_used(door):
	if not current_room.is_cleared:
		hud.show_message("Kill all enemies first!", 2.0)
		return

	pending_door = door

	match current_room.challenge_type:
		"lockpick":
			if not player.has_lockpick:
				hud.show_message("Find the pickaxe! Mine 6 ore to craft a lockpick!", 3.0)
				pending_door = null
				return
			var diff = current_room.get_lockpick_difficulty()
			lockpick_ui.start_lockpick(diff)
		"guardians":
			if current_room.challenge_complete_flag:
				_complete_door()
			elif not current_room.challenge_started:
				current_room.start_guardian_challenge(enemy_scene)
				hud.show_message("KILL THE GUARDIANS!", 3.0)
			else:
				hud.show_message("Kill the guardians first!", 2.0)
		"crystal":
			if current_room.challenge_complete_flag:
				_complete_door()
			elif not current_room.challenge_started or (current_room.crystal_node and current_room.crystal_node.is_destroyed):
				if player.ore_mined < player.ore_needed:
					hud.show_message("Mine 6 ore to craft the crystal!", 3.0)
					pending_door = null
					return
				current_room.start_crystal_placement()
				hud.show_message("CRYSTAL PLACED! DEFEND IT!", 3.0)
			else:
				hud.show_message("Defend the crystal!", 2.0)

func _on_challenge_complete():
	hud.show_message("Challenge Complete!", 2.0)
	await get_tree().create_timer(0.5).timeout
	if pending_door:
		_complete_door()
	elif current_room.doors.size() > 0:
		pending_door = current_room.doors[0]
		_complete_door()

func _complete_door():
	if pending_door:
		pending_door.unlock()
		pending_door = null
		hud.show_message("Door Unlocked!", 1.5)
		player.heal(1)
		await get_tree().create_timer(1.0).timeout
		current_level += 1
		_load_room()

func _on_lockpick_success():
	_complete_door()

func _on_lockpick_failed():
	pending_door = null
	hud.show_message("Lockpick broken! Try again...", 2.0)

func _on_player_health_changed(new_health):
	hud.update_health(new_health)

func _on_player_died():
	# Small delay before showing game over so death feels impactful
	await get_tree().create_timer(0.5).timeout
	game_over_screen.show_game_over(current_level)

func _restart_game():
	if player:
		player.queue_free()
		player = null
	if current_room:
		current_room.queue_free()
		current_room = null

	await get_tree().process_frame
	await get_tree().process_frame

	_start_game()
