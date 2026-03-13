extends Node2D

signal room_cleared
signal door_used(door)

var room_width: float = 1200.0
var room_height: float = 700.0
var enemies: Array = []
var doors: Array = []
var is_cleared: bool = false
var room_level: int = 1

var tile_size: int = 16
var grid_cols: int = 0
var grid_rows: int = 0
var grid: Array = []  # 2D array: 1 = solid rock, 0 = open/air

var floor_y: float
var ceiling_y: float

# Colors
var rock_color: Color = Color(0.6, 0.48, 0.25)
var rock_dark: Color = Color(0.45, 0.35, 0.18)
var rock_light: Color = Color(0.75, 0.6, 0.32)
var surface_color: Color = Color(0.8, 0.65, 0.3)
var bg_color: Color = Color(0.04, 0.03, 0.02)

# Torch
var torch_positions: Array = []
var dark_zones: Array = []
var platforms: Array = []  # For spawn positions
var caves: Array = []      # For main.gd compatibility

var torch_script = preload("res://scripts/torch.gd")
var portal_script = preload("res://scripts/skeleton_portal.gd")

# Portal system
var portals: Array = []
var portal_spawn_timer: float = 0.0
var portal_spawn_interval: float = 8.0
var player_ref: CharacterBody2D = null

# Chests
var chests: Array = []

func _ready():
	grid_cols = int(room_width / tile_size)
	grid_rows = int(room_height / tile_size)
	floor_y = room_height - tile_size * 2
	ceiling_y = tile_size * 2

func setup(level: int, enemy_scene: PackedScene, p_player_ref: CharacterBody2D):
	room_level = level
	player_ref = p_player_ref
	_set_biome(level)
	_generate_cave()
	_build_collision()
	_place_torches()
	_calculate_dark_zones()
	_spawn_enemies(enemy_scene, p_player_ref)
	_spawn_door()
	portal_spawn_timer = randf_range(4.0, 7.0)
	portal_spawn_interval = max(5.0, 10.0 - room_level * 0.5)

func _set_biome(level: int):
	match (level - 1) % 4:
		0:  # Golden cave
			rock_color = Color(0.6, 0.48, 0.25)
			rock_dark = Color(0.45, 0.35, 0.18)
			rock_light = Color(0.75, 0.6, 0.32)
			surface_color = Color(0.82, 0.68, 0.32)
			bg_color = Color(0.04, 0.03, 0.02)
		1:  # Purple dungeon
			rock_color = Color(0.4, 0.32, 0.5)
			rock_dark = Color(0.3, 0.24, 0.4)
			rock_light = Color(0.55, 0.45, 0.65)
			surface_color = Color(0.6, 0.5, 0.7)
			bg_color = Color(0.03, 0.02, 0.04)
		2:  # Red cave
			rock_color = Color(0.6, 0.35, 0.25)
			rock_dark = Color(0.45, 0.25, 0.18)
			rock_light = Color(0.75, 0.45, 0.3)
			surface_color = Color(0.8, 0.5, 0.32)
			bg_color = Color(0.04, 0.02, 0.02)
		3:  # Blue ice cave
			rock_color = Color(0.4, 0.5, 0.6)
			rock_dark = Color(0.3, 0.38, 0.48)
			rock_light = Color(0.55, 0.65, 0.75)
			surface_color = Color(0.6, 0.72, 0.82)
			bg_color = Color(0.02, 0.03, 0.04)

func _generate_cave():
	grid.clear()
	caves.clear()
	platforms.clear()
	chests.clear()

	# Initialize grid - all solid
	for r in grid_rows:
		var row = []
		for c in grid_cols:
			row.append(1)
		grid.append(row)

	# Random fill - carve out open spaces
	var fill_rate = 0.48 + room_level * 0.003
	fill_rate = minf(fill_rate, 0.55)
	for r in range(3, grid_rows - 3):
		for c in range(3, grid_cols - 3):
			if randf() > fill_rate:
				grid[r][c] = 0

	# Cellular automata smoothing (4 iterations)
	for iteration in 4:
		var new_grid = []
		for r in grid_rows:
			var row = []
			for c in grid_cols:
				row.append(grid[r][c])
			new_grid.append(row)

		for r in range(1, grid_rows - 1):
			for c in range(1, grid_cols - 1):
				var neighbors = _count_neighbors(r, c)
				if neighbors >= 5:
					new_grid[r][c] = 1
				elif neighbors <= 3:
					new_grid[r][c] = 0

		grid = new_grid

	# Ensure borders are solid (3 tiles thick)
	for r in grid_rows:
		for c in grid_cols:
			if r < 3 or r >= grid_rows - 3 or c < 3 or c >= grid_cols - 3:
				grid[r][c] = 1

	# === CARVE KEY AREAS ===

	# Start area (bottom-left) - carve a room
	var start_r = grid_rows - 7
	var start_c = 5
	_carve_room(start_r, start_c, 5, 3)
	# Floor under start
	_make_floor(start_r + 3, start_c - 1, 7)

	caves.append({
		"x": float(start_c * tile_size + tile_size * 2),
		"y": float(start_r * tile_size),
		"w": 80.0, "h": 48.0,
		"type": "start",
		"floor_y": float((start_r + 3) * tile_size)
	})

	# Door area (top-right) - carve a room
	var door_r = 6
	var door_c = grid_cols - 10
	_carve_room(door_r, door_c, 5, 3)
	_make_floor(door_r + 3, door_c - 1, 7)

	caves.append({
		"x": float(door_c * tile_size + tile_size * 2),
		"y": float(door_r * tile_size),
		"w": 80.0, "h": 48.0,
		"type": "door",
		"floor_y": float((door_r + 3) * tile_size)
	})

	# Ensure connectivity: carve a winding path from start to door
	_carve_path(start_r, start_c + 2, door_r, door_c + 2)

	# Add branching paths with dead ends and chest rooms
	var num_branches = randi_range(3, 4 + room_level / 2)
	num_branches = mini(num_branches, 6)
	var chest_count = 0
	var max_chests = 1 + room_level / 3
	max_chests = mini(max_chests, 3)

	for b in num_branches:
		# Pick a random open tile as branch origin
		var origin_r = 0
		var origin_c = 0
		var found = false
		for attempt in 40:
			origin_r = randi_range(6, grid_rows - 6)
			origin_c = randi_range(6, grid_cols - 6)
			if grid[origin_r][origin_c] == 0:
				found = true
				break

		if not found:
			continue

		# Random walk to create branch
		var br = origin_r
		var bc = origin_c
		var dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]]
		var dir = dirs[randi() % 4]
		var branch_len = randi_range(6, 14)

		for s in branch_len:
			br += dir[0]
			bc += dir[1]
			br = clampi(br, 3, grid_rows - 4)
			bc = clampi(bc, 3, grid_cols - 4)

			# Carve 2x2
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					var nr = br + dr
					var nc = bc + dc
					if nr > 2 and nr < grid_rows - 3 and nc > 2 and nc < grid_cols - 3:
						grid[nr][nc] = 0

			# Occasional direction change
			if randf() < 0.25:
				dir = dirs[randi() % 4]

		# End room
		_carve_room(br - 1, bc - 1, 4, 3)
		_make_floor(br + 2, bc - 2, 6)

		var cave_type = "dead_end"
		if chest_count < max_chests and randf() < 0.45:
			cave_type = "chest"
			chest_count += 1

		caves.append({
			"x": float(bc * tile_size),
			"y": float(br * tile_size),
			"w": 64.0, "h": 48.0,
			"type": cave_type,
			"floor_y": float((br + 2) * tile_size)
		})

		if cave_type == "chest":
			_place_chest(float(bc * tile_size), float((br + 2) * tile_size) - 10)

	# Add a few extra middle rooms for combat space
	var mid_rooms = randi_range(2, 4)
	for m in mid_rooms:
		var mr = randi_range(8, grid_rows - 8)
		var mc = randi_range(8, grid_cols - 8)
		_carve_room(mr, mc, randi_range(4, 7), randi_range(2, 4))
		_make_floor(mr + 3, mc - 1, randi_range(5, 9))

		caves.append({
			"x": float(mc * tile_size + tile_size),
			"y": float(mr * tile_size),
			"w": 80.0, "h": 60.0,
			"type": "normal",
			"floor_y": float((mr + 3) * tile_size)
		})

	# Run one more smoothing pass for organic edges
	var smooth_grid = []
	for r in grid_rows:
		var row = []
		for c in grid_cols:
			row.append(grid[r][c])
		smooth_grid.append(row)

	for r in range(3, grid_rows - 3):
		for c in range(3, grid_cols - 3):
			var n = _count_neighbors(r, c)
			if n >= 6:
				smooth_grid[r][c] = 1
			elif n <= 2:
				smooth_grid[r][c] = 0

	grid = smooth_grid

	# Re-enforce borders
	for r in grid_rows:
		for c in grid_cols:
			if r < 3 or r >= grid_rows - 3 or c < 3 or c >= grid_cols - 3:
				grid[r][c] = 1

	# Re-ensure key rooms are open
	_carve_room(start_r, start_c, 5, 3)
	_make_floor(start_r + 3, start_c - 1, 7)
	_carve_room(door_r, door_c, 5, 3)
	_make_floor(door_r + 3, door_c - 1, 7)

	# Extract platforms list for spawn positioning
	_extract_floor_positions()

func _count_neighbors(r: int, c: int) -> int:
	var count = 0
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			if dr == 0 and dc == 0:
				continue
			var nr = r + dr
			var nc = c + dc
			if nr < 0 or nr >= grid_rows or nc < 0 or nc >= grid_cols:
				count += 1
			elif grid[nr][nc] == 1:
				count += 1
	return count

func _carve_room(r: int, c: int, w: int, h: int):
	for dr in range(-h, h + 1):
		for dc in range(-1, w + 1):
			var nr = r + dr
			var nc = c + dc
			if nr > 2 and nr < grid_rows - 3 and nc > 2 and nc < grid_cols - 3:
				grid[nr][nc] = 0

func _make_floor(r: int, c: int, w: int):
	for dc in range(w):
		var nc = c + dc
		if nc > 2 and nc < grid_cols - 3 and r > 2 and r < grid_rows - 3:
			grid[r][nc] = 1

func _carve_path(sr: int, sc: int, er: int, ec: int):
	var r = sr
	var c = sc
	var max_steps = 600

	for step in max_steps:
		if abs(r - er) <= 2 and abs(c - ec) <= 2:
			break

		# Bias toward target with some randomness
		var choices = []
		if r > er:
			choices.append([-1, 0])
			choices.append([-1, 0])
		elif r < er:
			choices.append([1, 0])
			choices.append([1, 0])
		if c > ec:
			choices.append([0, -1])
			choices.append([0, -1])
		elif c < ec:
			choices.append([0, 1])
			choices.append([0, 1])
		# Random
		choices.append([randi_range(-1, 1), randi_range(-1, 1)])

		var choice = choices[randi() % choices.size()]
		r += choice[0]
		c += choice[1]
		r = clampi(r, 3, grid_rows - 4)
		c = clampi(c, 3, grid_cols - 4)

		# Carve 3-wide tunnel
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var nr = r + dr
				var nc = c + dc
				if nr > 2 and nr < grid_rows - 3 and nc > 2 and nc < grid_cols - 3:
					grid[nr][nc] = 0

func _extract_floor_positions():
	platforms.clear()
	for r in range(1, grid_rows):
		var run_start = -1
		for c in range(grid_cols):
			var is_floor = grid[r][c] == 1 and r > 0 and grid[r - 1][c] == 0
			if is_floor:
				if run_start == -1:
					run_start = c
			else:
				if run_start != -1:
					platforms.append({
						"x": float(run_start * tile_size),
						"y": float(r * tile_size),
						"w": float((c - run_start) * tile_size)
					})
					run_start = -1
		if run_start != -1:
			platforms.append({
				"x": float(run_start * tile_size),
				"y": float(r * tile_size),
				"w": float((grid_cols - run_start) * tile_size)
			})

func _build_collision():
	# Merge solid tiles into horizontal runs per row for efficient collision
	for r in grid_rows:
		var run_start = -1
		for c in range(grid_cols + 1):
			var is_solid = c < grid_cols and grid[r][c] == 1
			if is_solid:
				if run_start == -1:
					run_start = c
			else:
				if run_start != -1:
					var x = run_start * tile_size
					var y = r * tile_size
					var w = (c - run_start) * tile_size
					var h = tile_size
					_add_wall(Vector2(x + w / 2.0, y + h / 2.0), Vector2(w, h))
					run_start = -1

func _add_wall(pos: Vector2, size: Vector2):
	var wall = StaticBody2D.new()
	wall.position = pos
	wall.collision_layer = 4  # walls layer
	wall.collision_mask = 0
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	wall.add_child(shape)
	add_child(wall)

func _place_chest(cx: float, cy: float):
	chests.append({"x": cx, "y": cy, "opened": false})

	var chest_area = Area2D.new()
	chest_area.position = Vector2(cx, cy)
	chest_area.collision_layer = 0
	chest_area.collision_mask = 1
	var cs = CollisionShape2D.new()
	var cr = RectangleShape2D.new()
	cr.size = Vector2(20, 16)
	cs.shape = cr
	chest_area.add_child(cs)
	add_child(chest_area)

	var chest_idx = chests.size() - 1
	chest_area.body_entered.connect(_on_chest_touched.bind(chest_idx))

func _on_chest_touched(body, idx: int):
	if body.is_in_group("player") and idx < chests.size():
		if not chests[idx].opened:
			chests[idx].opened = true
			if player_ref and is_instance_valid(player_ref):
				player_ref.heal(2)
			queue_redraw()

func _place_torches():
	torch_positions.clear()

	# Place torches in cave rooms
	for cave in caves:
		if cave.type == "start" or randf() < 0.5:
			var torch = Node2D.new()
			torch.set_script(torch_script)
			var tx = cave.x + randf_range(-20, 20)
			var ty = cave.y - 10
			torch.position = Vector2(tx, ty)
			torch.on_wall_right = randf() > 0.5
			torch_positions.append(Vector2(tx, ty))
			add_child(torch)

	# Torches along some platforms
	var placed = 0
	var max_torches = max(3, 6 - room_level / 2)
	for p in platforms:
		if p.w > 60 and randf() < 0.15 and placed < max_torches:
			var torch = Node2D.new()
			torch.set_script(torch_script)
			var tx = p.x + p.w / 2
			var ty = p.y - 5
			torch.position = Vector2(tx, ty)
			torch.on_wall_right = true
			torch_positions.append(Vector2(tx, ty))
			add_child(torch)
			placed += 1

func _calculate_dark_zones():
	dark_zones.clear()
	var light_radius = 80.0
	var scan_step = 20.0
	var x = 60.0

	while x < room_width - 60:
		var min_dist = INF
		for tp in torch_positions:
			var d = abs(tp.x - x)
			if d < min_dist:
				min_dist = d

		if min_dist > light_radius:
			var zone_start = x
			while x < room_width - 60:
				min_dist = INF
				for tp in torch_positions:
					var d = abs(tp.x - x)
					if d < min_dist:
						min_dist = d
				if min_dist <= light_radius:
					break
				x += scan_step
			dark_zones.append({"x": zone_start, "w": x - zone_start})
		x += scan_step

func _spawn_enemies(enemy_scene: PackedScene, p_player_ref: CharacterBody2D):
	var enemy_count = 3 + room_level
	enemy_count = mini(enemy_count, 10)

	var weighted_classes: Array = []
	weighted_classes.append([0, 3])  # ARCHER
	if room_level >= 2:
		weighted_classes.append([2, 3])  # THROWER
	if room_level >= 3:
		weighted_classes.append([1, 2])  # CROSSBOW
	weighted_classes.append([3, 1])  # SHIELDMAN

	var shieldman_count = 0
	var max_shieldmen = 1 + (room_level / 4)
	max_shieldmen = mini(max_shieldmen, 2)

	for i in enemy_count:
		var enemy = enemy_scene.instantiate()
		var eclass = _pick_weighted(weighted_classes)

		if eclass == 3:
			if shieldman_count >= max_shieldmen:
				eclass = weighted_classes[0][0]
			else:
				shieldman_count += 1

		var hp = 2 + room_level
		var spd = 30.0 + room_level * 3
		var dmg = 1 + (room_level / 3)
		if eclass == 3:
			hp += 2

		enemy.setup(eclass, hp, spd, dmg)
		enemy.player = p_player_ref

		var pos = _get_spawn_position()
		enemy.position = pos
		add_child(enemy)
		enemies.append(enemy)
		enemy.died.connect(_on_enemy_died)

func _pick_weighted(weighted: Array) -> int:
	var total_weight = 0
	for w in weighted:
		total_weight += w[1]
	var roll = randi() % total_weight
	var accumulated = 0
	for w in weighted:
		accumulated += w[1]
		if roll < accumulated:
			return w[0]
	return weighted[0][0]

func _get_spawn_position() -> Vector2:
	# Pick a random non-start cave
	var spawn_caves = caves.filter(func(c): return c.type != "start" and c.type != "chest")
	if spawn_caves.size() == 0:
		spawn_caves = caves.filter(func(c): return c.type != "start")
	if spawn_caves.size() == 0:
		spawn_caves = caves

	var cave = spawn_caves[randi() % spawn_caves.size()]
	var px = cave.x + randf_range(-20, 20)
	var py = cave.floor_y - 1
	return Vector2(px, py)

func _spawn_door():
	var door_script_res = load("res://scripts/door.gd")
	var door = StaticBody2D.new()
	door.set_script(door_script_res)
	door.difficulty = mini(room_level, 5)

	var door_cave = null
	for cave in caves:
		if cave.type == "door":
			door_cave = cave
			break

	if door_cave:
		door.position = Vector2(door_cave.x, door_cave.floor_y - 14)
	else:
		var best = caves[0]
		for cave in caves:
			if cave.x > best.x:
				best = cave
		door.position = Vector2(best.x, best.floor_y - 14)

	add_child(door)
	doors.append(door)
	door.door_interact.connect(_on_door_interact)

func _process(delta):
	if is_cleared:
		return

	portal_spawn_timer -= delta
	if portal_spawn_timer <= 0:
		_spawn_portal()
		portal_spawn_timer = portal_spawn_interval + randf_range(-1.5, 1.5)

func _spawn_portal():
	if not player_ref or not is_instance_valid(player_ref):
		return
	if portals.size() >= 2:
		return

	var portal = CharacterBody2D.new()
	portal.set_script(portal_script)

	var spawn_caves = caves.filter(func(c): return c.type != "chest")
	if spawn_caves.size() == 0:
		spawn_caves = caves

	var cave = spawn_caves[randi() % spawn_caves.size()]
	var px = cave.x + randf_range(-15, 15)
	var py = cave.floor_y - 1

	if Vector2(px, py).distance_to(player_ref.global_position) < 80:
		cave = spawn_caves[randi() % spawn_caves.size()]
		px = cave.x + randf_range(-15, 15)
		py = cave.floor_y - 1

	portal.position = Vector2(px, py)
	portal.setup(player_ref, 1 + room_level / 3)
	portal.skeleton_health = 2 + room_level / 2
	add_child(portal)
	portals.append(portal)
	portal.skeleton_died.connect(_on_portal_died)
	portal.open_portal()

func _on_portal_died(portal):
	portals.erase(portal)

func _on_enemy_died(enemy):
	enemies.erase(enemy)
	if enemies.size() == 0:
		is_cleared = true
		room_cleared.emit()

func _on_door_interact(door):
	door_used.emit(door)

# === DRAWING ===

func _tile_shade(r: int, c: int) -> float:
	# Deterministic pseudo-random shade per tile
	var n = (r * 127 + c * 311 + room_level * 37)
	return fmod(abs(sin(float(n) * 0.7134)) * 43758.5453, 1.0) * 0.06 - 0.03

func _draw():
	# Dark background
	draw_rect(Rect2(0, 0, room_width, room_height), bg_color)

	# Draw solid rock tiles
	_draw_solid_tiles()

	# Draw surface highlights (floors, walls)
	_draw_surface_edges()

	# Decorations
	_draw_decorations()

	# Chests
	_draw_chests()

func _draw_solid_tiles():
	# Draw merged horizontal runs of solid tiles
	for r in grid_rows:
		var run_start = -1
		for c in range(grid_cols + 1):
			var is_solid = c < grid_cols and grid[r][c] == 1
			if is_solid:
				if run_start == -1:
					run_start = c
			else:
				if run_start != -1:
					var x = run_start * tile_size
					var y = r * tile_size
					var w = (c - run_start) * tile_size

					# Base color for the run
					draw_rect(Rect2(x, y, w, tile_size), rock_color)

					# Individual tile shading for texture
					for tc in range(run_start, c):
						var shade = _tile_shade(r, tc)
						var col = Color(
							rock_dark.r + shade + 0.03,
							rock_dark.g + shade + 0.02,
							rock_dark.b + shade
						)
						draw_rect(Rect2(tc * tile_size + 1, y + 1, tile_size - 2, tile_size - 2), col)

					run_start = -1

func _draw_surface_edges():
	# Floor surfaces - bright top edge where solid meets open above
	for r in range(1, grid_rows):
		for c in range(grid_cols):
			if grid[r][c] == 1 and grid[r - 1][c] == 0:
				# This is a floor surface tile
				draw_rect(Rect2(c * tile_size, r * tile_size, tile_size, 2), surface_color)
				# Slightly lighter tile top
				draw_rect(Rect2(c * tile_size + 1, r * tile_size + 2, tile_size - 2, 3),
					Color(rock_light.r, rock_light.g, rock_light.b, 0.5))

	# Ceiling surfaces - dark bottom edge where solid meets open below
	for r in range(0, grid_rows - 1):
		for c in range(grid_cols):
			if grid[r][c] == 1 and grid[r + 1][c] == 0:
				draw_rect(Rect2(c * tile_size, (r + 1) * tile_size - 2, tile_size, 2),
					Color(rock_dark.r - 0.05, rock_dark.g - 0.05, rock_dark.b - 0.03))

	# Left wall surfaces (solid with open to right)
	for r in range(grid_rows):
		for c in range(0, grid_cols - 1):
			if grid[r][c] == 1 and grid[r][c + 1] == 0:
				draw_rect(Rect2((c + 1) * tile_size - 2, r * tile_size, 2, tile_size),
					Color(rock_light.r - 0.05, rock_light.g - 0.05, rock_light.b - 0.03, 0.6))

	# Right wall surfaces (solid with open to left)
	for r in range(grid_rows):
		for c in range(1, grid_cols):
			if grid[r][c] == 1 and grid[r][c - 1] == 0:
				draw_rect(Rect2(c * tile_size, r * tile_size, 2, tile_size),
					Color(rock_dark.r, rock_dark.g, rock_dark.b, 0.6))

func _draw_decorations():
	# Stalactites hanging from ceiling surfaces
	for c in range(5, grid_cols - 5, 4):
		for r in range(3, grid_rows - 3):
			if grid[r][c] == 1 and r + 1 < grid_rows and grid[r + 1][c] == 0:
				var shade = _tile_shade(r, c)
				if shade > 0.01:  # Only some ceilings get stalactites
					var sx = c * tile_size + tile_size / 2
					var sy = (r + 1) * tile_size
					var sh = 4 + int(abs(shade) * 200) % 10
					var sw = 2 + int(abs(shade) * 100) % 3
					draw_rect(Rect2(sx - sw / 2, sy, sw, sh),
						Color(rock_dark.r + 0.05, rock_dark.g + 0.04, rock_dark.b + 0.02))
					# Point
					draw_line(Vector2(sx, sy + sh), Vector2(sx, sy + sh + 2),
						Color(rock_dark.r, rock_dark.g, rock_dark.b), 1.0)

	# Moss on some floor tiles
	for c in range(4, grid_cols - 4, 6):
		for r in range(3, grid_rows - 3):
			if grid[r][c] == 1 and r > 0 and grid[r - 1][c] == 0:
				var shade = _tile_shade(r, c + 1)
				if shade < -0.01:
					var mx = c * tile_size
					var mw = tile_size + int(abs(shade) * 200) % (tile_size * 2)
					draw_rect(Rect2(mx, r * tile_size - 1, mw, 2),
						Color(0.2, 0.35, 0.15, 0.3))

	# Skulls on floor in some caves
	if room_level >= 2:
		for cave in caves:
			if cave.type == "dead_end":
				var bx = cave.x
				var by = cave.floor_y
				draw_circle(Vector2(bx, by - 2), 3, Color(0.7, 0.65, 0.55, 0.3))
				draw_rect(Rect2(bx - 2, by - 4, 1, 1), Color(0.1, 0.1, 0.1, 0.3))
				draw_rect(Rect2(bx + 1, by - 4, 1, 1), Color(0.1, 0.1, 0.1, 0.3))

func _draw_chests():
	for chest in chests:
		var cx = chest.x
		var cy = chest.y

		if chest.opened:
			# Open chest body
			draw_rect(Rect2(cx - 8, cy - 4, 16, 10), Color(0.45, 0.3, 0.15))
			draw_rect(Rect2(cx - 7, cy - 3, 14, 8), Color(0.55, 0.38, 0.2))
			# Open lid
			draw_rect(Rect2(cx - 8, cy - 10, 16, 6), Color(0.5, 0.33, 0.17))
			# Metal band
			draw_rect(Rect2(cx - 8, cy - 1, 16, 1), Color(0.6, 0.55, 0.3))
			# Inside dark
			draw_rect(Rect2(cx - 6, cy - 3, 12, 5), Color(0.2, 0.15, 0.08))
			# Sparkle
			var sp_t = sin(Time.get_ticks_msec() * 0.003) * 0.5 + 0.5
			draw_circle(Vector2(cx, cy - 6), 2, Color(1.0, 0.9, 0.3, sp_t * 0.6))
		else:
			# Closed chest body
			draw_rect(Rect2(cx - 8, cy - 4, 16, 10), Color(0.45, 0.3, 0.15))
			draw_rect(Rect2(cx - 7, cy - 3, 14, 8), Color(0.55, 0.38, 0.2))
			# Lid
			draw_rect(Rect2(cx - 9, cy - 8, 18, 5), Color(0.5, 0.33, 0.17))
			draw_rect(Rect2(cx - 8, cy - 7, 16, 3), Color(0.55, 0.38, 0.2))
			# Metal band
			draw_rect(Rect2(cx - 9, cy - 5, 18, 1), Color(0.6, 0.55, 0.3))
			# Lock
			draw_rect(Rect2(cx - 2, cy - 5, 4, 4), Color(0.65, 0.6, 0.3))
			draw_rect(Rect2(cx - 1, cy - 4, 2, 2), Color(0.3, 0.25, 0.1))
			# Glow
			var glow_t = sin(Time.get_ticks_msec() * 0.002) * 0.3 + 0.3
			draw_circle(Vector2(cx, cy - 4), 12, Color(1.0, 0.8, 0.2, glow_t * 0.08))
