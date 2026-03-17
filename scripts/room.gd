extends Node2D

signal room_cleared
signal door_used(door)
signal challenge_complete

var room_width: float = 3200.0
var room_height: float = 1360.0
var enemies: Array = []
var doors: Array = []
var is_cleared: bool = false
var room_level: int = 1
var is_boss_room: bool = false
var golem_boss = null
var golem_script = preload("res://scripts/golem.gd")
var lava_y: float = 0.0  # Y position of lava surface in boss room

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
var crystal_script = preload("res://scripts/crystal.gd")

# Portal system
var portals: Array = []
var portal_spawn_timer: float = 0.0
var portal_spawn_interval: float = 8.0
var player_ref: CharacterBody2D = null

# Chests
var chests: Array = []

# Ore blocks (for lockpick crafting)
var ore_blocks: Array = []  # {x, y, mined, area}
var pickaxe_enemy: CharacterBody2D = null  # The mob that drops pickaxe

# Crafting stations in start cave
var craft_stations: Array = []  # {type, x, y, area}
var player_near_station: String = ""  # "", "furnace", "anvil", "grate"
var grate_used_this_level: bool = false

# Gold ore blocks (separate from iron ore)
var gold_ore_blocks: Array = []  # {x, y, mined, area}

# Pearl enemy (drops pearl on death)
var pearl_enemy: CharacterBody2D = null

# Trial room (every 2 levels)
var trial_heart_pos: Vector2 = Vector2.ZERO
var trial_heart_area: Area2D = null
var trial_active: bool = false
var trial_complete: bool = false
var trial_enemies: Array = []
var player_near_heart: bool = false
signal trial_completed

# Door challenge system
# "lockpick" = normal lockpick, "guardians" = kill spear shieldmen, "crystal" = defend crystal
var challenge_type: String = "lockpick"
var challenge_started: bool = false
var challenge_complete_flag: bool = false
var reachable_set: Dictionary = {}  # Tiles reachable from start (for spawn validation)
var door_guardians: Array = []
var crystal_node: Node2D = null
var crystal_attackers: Array = []

func _ready():
	grid_cols = int(room_width / tile_size)
	grid_rows = int(room_height / tile_size)
	floor_y = room_height - tile_size * 2
	ceiling_y = tile_size * 2

func setup(level: int, enemy_scene: PackedScene, p_player_ref: CharacterBody2D):
	room_level = level
	player_ref = p_player_ref

	# Boss level 5 — special arena (compact room, not the large map)
	if level == 5:
		is_boss_room = true
		room_width = 1200.0
		room_height = 700.0
		grid_cols = int(room_width / tile_size)
		grid_rows = int(room_height / tile_size)
		floor_y = room_height - tile_size * 2
		_setup_boss_room()
		return

	_set_biome(level)
	_determine_challenge_type()
	_generate_cave()
	_build_collision()
	_place_torches()
	_calculate_dark_zones()
	_spawn_enemies(enemy_scene, p_player_ref)
	_spawn_ore_blocks()
	_spawn_gold_ore()
	if challenge_type == "lockpick":
		_spawn_pickaxe_mob(enemy_scene, p_player_ref)
	if room_level % 4 == 0:  # Pearl enemy every 4 levels
		_spawn_pearl_enemy(enemy_scene, p_player_ref)
	_spawn_craft_stations()
	if room_level % 2 == 0:  # Trial room every 2 levels
		_spawn_trial_heart()
	_spawn_door()
	portal_spawn_timer = randf_range(4.0, 7.0)
	portal_spawn_interval = max(5.0, 10.0 - room_level * 0.5)

func _setup_boss_room():
	# Compact arena for golem boss fight — platforms close enough to jump between
	rock_color = Color(0.5, 0.3, 0.2)
	rock_dark = Color(0.35, 0.2, 0.12)
	rock_light = Color(0.65, 0.4, 0.25)
	surface_color = Color(0.7, 0.45, 0.28)
	bg_color = Color(0.06, 0.02, 0.01)

	lava_y = room_height - 60

	# Initialize empty grid
	grid.clear()
	for r in grid_rows:
		var row = []
		for c in grid_cols:
			row.append(0)
		grid.append(row)

	# Solid borders (walls + ceiling)
	for r in grid_rows:
		for c in grid_cols:
			if r < 3 or r >= grid_rows - 1 or c < 2 or c >= grid_cols - 2:
				grid[r][c] = 1

	# Compact platform layout (centered, gaps ~4-5 tiles = jumpable)
	#        [P3]          row-18 (top center)
	#    [P2]    [P4]      row-14 (mid sides)
	#      [P1][P5]        row-10 (bottom, close together)
	#     ===LAVA===

	var plat_data = [
		{"r": grid_rows - 10, "c": 24, "w": 12},  # P1 - bottom left (player start)
		{"r": grid_rows - 14, "c": 20, "w": 12},  # P2 - mid left
		{"r": grid_rows - 18, "c": 29, "w": 14},  # P3 - top center (wide)
		{"r": grid_rows - 14, "c": 40, "w": 12},  # P4 - mid right
		{"r": grid_rows - 10, "c": 38, "w": 12},  # P5 - bottom right (golem)
	]

	for pd in plat_data:
		for dc in pd.w:
			var nc = pd.c + dc
			if nc >= 0 and nc < grid_cols:
				grid[pd.r][nc] = 1
		# Add thickness (2 tiles)
		for dc in pd.w:
			var nc = pd.c + dc
			if nc >= 0 and nc < grid_cols and pd.r + 1 < grid_rows:
				grid[pd.r + 1][nc] = 1

	# Small stepping stones between platforms for easier navigation
	# Between P1 and P5 (bridge)
	for dc in 4:
		var nc = 35 + dc
		if nc < grid_cols:
			grid[grid_rows - 10][nc] = 1
			grid[grid_rows - 9][nc] = 1
	# Step between P2 and P3
	for dc in 3:
		var nc = 27 + dc
		if nc < grid_cols:
			grid[grid_rows - 16][nc] = 1
	# Step between P3 and P4
	for dc in 3:
		var nc = 38 + dc
		if nc < grid_cols:
			grid[grid_rows - 16][nc] = 1

	# Lava floor (solid for collision but drawn as lava)
	var lava_row = grid_rows - 4
	for c in grid_cols:
		for r in range(lava_row, grid_rows):
			grid[r][c] = 1

	# Build collision
	_build_collision()

	# Caves array for compatibility
	caves.append({
		"x": float(plat_data[0].c * tile_size + plat_data[0].w * tile_size / 2),
		"y": float((plat_data[0].r - 2) * tile_size),
		"w": 160.0, "h": 32.0,
		"type": "start",
		"floor_y": float(plat_data[0].r * tile_size)
	})

	# Spawn golem on platform 5
	golem_boss = CharacterBody2D.new()
	golem_boss.set_script(golem_script)
	golem_boss.position = Vector2(
		(plat_data[4].c + plat_data[4].w / 2) * tile_size,
		plat_data[4].r * tile_size - 1
	)
	golem_boss.setup(player_ref)
	golem_boss.golem_defeated.connect(_on_golem_defeated)
	add_child(golem_boss)

	# No normal enemies, no door
	is_cleared = false

	# Add torches on platforms
	for pd in [plat_data[0], plat_data[2], plat_data[4]]:
		var torch = Node2D.new()
		torch.set_script(torch_script)
		var tx = (pd.c + pd.w / 2) * tile_size
		var ty = pd.r * tile_size - 8
		torch.position = Vector2(tx, ty)
		torch_positions.append(Vector2(tx, ty))
		add_child(torch)

func _on_golem_defeated():
	is_cleared = true
	room_cleared.emit()
	# Spawn a door to next level
	_spawn_door()
	# Move door to a reachable platform
	if doors.size() > 0:
		var door_x = 28 * tile_size + 6 * tile_size  # Center platform
		var door_y = (grid_rows - 22) * tile_size - 14
		doors[0].position = Vector2(door_x, door_y)

func _determine_challenge_type():
	# Level 1: hard lockpick (difficulty 4)
	# Level 2: spear shieldmen guardians
	# Level 3: crystal defense
	# Level 4+: lockpick (normal scaling)
	# Pattern repeats: 5=guardians, 6=crystal, 7+=lockpick, etc.
	var cycle = (room_level - 1) % 3
	match cycle:
		0:  # Levels 1, 4, 7...
			challenge_type = "lockpick"
		1:  # Levels 2, 5, 8...
			challenge_type = "guardians"
		2:  # Levels 3, 6, 9...
			challenge_type = "crystal"

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
	# Large map = slightly lower fill for more open areas
	var fill_rate = 0.45 + room_level * 0.005
	fill_rate = minf(fill_rate, 0.54)
	for r in range(4, grid_rows - 4):
		for c in range(4, grid_cols - 4):
			if randf() > fill_rate:
				grid[r][c] = 0

	# Cellular automata smoothing (5 iterations for smoother large caves)
	for iteration in 5:
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

	# Ensure borders are solid (4 tiles thick for large map)
	for r in grid_rows:
		for c in grid_cols:
			if r < 4 or r >= grid_rows - 4 or c < 4 or c >= grid_cols - 4:
				grid[r][c] = 1

	# === CARVE KEY AREAS (spread across the large map) ===

	# Start area (bottom-left)
	var start_r = grid_rows - 9
	var start_c = 7
	_carve_room(start_r, start_c, 7, 4)
	_make_floor(start_r + 4, start_c - 1, 9)

	caves.append({
		"x": float(start_c * tile_size + tile_size * 3),
		"y": float(start_r * tile_size),
		"w": 112.0, "h": 64.0,
		"type": "start",
		"floor_y": float((start_r + 4) * tile_size)
	})

	# Door area (top-right corner — far from start)
	var door_r = 8
	var door_c = grid_cols - 14
	_carve_room(door_r, door_c, 7, 4)
	_make_floor(door_r + 4, door_c - 1, 9)

	caves.append({
		"x": float(door_c * tile_size + tile_size * 3),
		"y": float(door_r * tile_size),
		"w": 112.0, "h": 64.0,
		"type": "door",
		"floor_y": float((door_r + 4) * tile_size)
	})

	# === MAJOR ROUTE: winding path from start to door ===
	_carve_path(start_r, start_c + 3, door_r, door_c + 3)

	# === SECONDARY ROUTES: alternative paths through the map ===
	# Mid-left hub
	var hub1_r = grid_rows / 2
	var hub1_c = grid_cols / 4
	_carve_room(hub1_r, hub1_c, 8, 5)
	_make_floor(hub1_r + 5, hub1_c - 1, 10)
	caves.append({
		"x": float(hub1_c * tile_size + tile_size * 4),
		"y": float(hub1_r * tile_size),
		"w": 128.0, "h": 80.0,
		"type": "normal",
		"floor_y": float((hub1_r + 5) * tile_size)
	})
	_carve_path(start_r, start_c + 3, hub1_r, hub1_c + 4)

	# Mid-right hub
	var hub2_r = grid_rows / 2 - 5
	var hub2_c = grid_cols * 3 / 4
	_carve_room(hub2_r, hub2_c, 8, 5)
	_make_floor(hub2_r + 5, hub2_c - 1, 10)
	caves.append({
		"x": float(hub2_c * tile_size + tile_size * 4),
		"y": float(hub2_r * tile_size),
		"w": 128.0, "h": 80.0,
		"type": "normal",
		"floor_y": float((hub2_r + 5) * tile_size)
	})
	_carve_path(hub1_r, hub1_c + 4, hub2_r, hub2_c + 4)
	_carve_path(hub2_r, hub2_c + 4, door_r, door_c + 3)

	# Top-left area (vertical climb)
	var top_left_r = 10
	var top_left_c = grid_cols / 5
	_carve_room(top_left_r, top_left_c, 6, 4)
	_make_floor(top_left_r + 4, top_left_c - 1, 8)
	caves.append({
		"x": float(top_left_c * tile_size + tile_size * 3),
		"y": float(top_left_r * tile_size),
		"w": 96.0, "h": 64.0,
		"type": "normal",
		"floor_y": float((top_left_r + 4) * tile_size)
	})
	_carve_path(hub1_r, hub1_c + 4, top_left_r, top_left_c + 3)

	# Bottom-right area
	var bot_right_r = grid_rows - 12
	var bot_right_c = grid_cols * 3 / 4 + 10
	bot_right_c = mini(bot_right_c, grid_cols - 15)
	_carve_room(bot_right_r, bot_right_c, 6, 4)
	_make_floor(bot_right_r + 4, bot_right_c - 1, 8)
	caves.append({
		"x": float(bot_right_c * tile_size + tile_size * 3),
		"y": float(bot_right_r * tile_size),
		"w": 96.0, "h": 64.0,
		"type": "normal",
		"floor_y": float((bot_right_r + 4) * tile_size)
	})
	_carve_path(start_r, start_c + 3, bot_right_r, bot_right_c + 3)
	_carve_path(bot_right_r, bot_right_c + 3, hub2_r, hub2_c + 4)

	# === MANY BRANCHES with dead ends, chests, combat rooms ===
	var num_branches = randi_range(8, 12 + room_level)
	num_branches = mini(num_branches, 18)
	var chest_count = 0
	var max_chests = 2 + room_level / 2
	max_chests = mini(max_chests, 5)
	for b in num_branches:
		var origin_r = 0
		var origin_c = 0
		var found = false
		for attempt in 60:
			origin_r = randi_range(8, grid_rows - 8)
			origin_c = randi_range(8, grid_cols - 8)
			if grid[origin_r][origin_c] == 0:
				found = true
				break

		if not found:
			continue

		# Random walk to create branch (longer for big map)
		var br = origin_r
		var bc = origin_c
		var dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]]
		var dir = dirs[randi() % 4]
		var branch_len = randi_range(10, 25)

		for s in branch_len:
			br += dir[0]
			bc += dir[1]
			br = clampi(br, 5, grid_rows - 6)
			bc = clampi(bc, 5, grid_cols - 6)

			# Carve 3-wide with headroom
			for dr in range(-2, 2):
				for dc in range(-1, 2):
					var nr = br + dr
					var nc = bc + dc
					if nr > 4 and nr < grid_rows - 4 and nc > 4 and nc < grid_cols - 4:
						grid[nr][nc] = 0

			if randf() < 0.2:
				dir = dirs[randi() % 4]

		# End room (varied sizes)
		var room_w = randi_range(4, 8)
		var room_h = randi_range(2, 5)
		_carve_room(br - 1, bc - 1, room_w, room_h)
		_make_floor(br + room_h, bc - 2, room_w + 2)

		var cave_type = "dead_end"
		if chest_count < max_chests and randf() < 0.35:
			cave_type = "chest"
			chest_count += 1

		caves.append({
			"x": float(bc * tile_size),
			"y": float(br * tile_size),
			"w": float(room_w * tile_size),
			"h": float(room_h * tile_size),
			"type": cave_type,
			"floor_y": float((br + room_h) * tile_size)
		})

		if cave_type == "chest":
			_place_chest(float(bc * tile_size), float((br + room_h) * tile_size) - 10)

	# Add extra combat rooms scattered across the map
	var mid_rooms = randi_range(5, 10)
	for m in mid_rooms:
		var mr = randi_range(10, grid_rows - 10)
		var mc = randi_range(10, grid_cols - 10)
		var rw = randi_range(5, 10)
		var rh = randi_range(3, 5)
		_carve_room(mr, mc, rw, rh)
		_make_floor(mr + rh, mc - 1, rw + 2)

		caves.append({
			"x": float(mc * tile_size + tile_size),
			"y": float(mr * tile_size),
			"w": float(rw * tile_size),
			"h": float(rh * tile_size),
			"type": "normal",
			"floor_y": float((mr + rh) * tile_size)
		})

	# Smoothing pass for organic edges
	var smooth_grid = []
	for r in grid_rows:
		var row = []
		for c in grid_cols:
			row.append(grid[r][c])
		smooth_grid.append(row)

	for r in range(4, grid_rows - 4):
		for c in range(4, grid_cols - 4):
			var n = _count_neighbors(r, c)
			if n >= 6:
				smooth_grid[r][c] = 1
			elif n <= 2:
				smooth_grid[r][c] = 0

	grid = smooth_grid

	# Re-enforce borders
	for r in grid_rows:
		for c in grid_cols:
			if r < 4 or r >= grid_rows - 4 or c < 4 or c >= grid_cols - 4:
				grid[r][c] = 1

	# Re-ensure key rooms are open after smoothing
	_carve_room(start_r, start_c, 7, 4)
	_make_floor(start_r + 4, start_c - 1, 9)
	_carve_room(door_r, door_c, 7, 4)
	_make_floor(door_r + 4, door_c - 1, 9)
	_carve_room(hub1_r, hub1_c, 8, 5)
	_make_floor(hub1_r + 5, hub1_c - 1, 10)
	_carve_room(hub2_r, hub2_c, 8, 5)
	_make_floor(hub2_r + 5, hub2_c - 1, 10)

	# Flood fill from start to find disconnected caves, re-carve paths to them
	_ensure_all_caves_reachable(start_r, start_c)

	# Ensure minimum headroom above all floors so player can jump
	_ensure_headroom()

	# Add stepping stones in tall open shafts so player can climb out
	_add_stepping_stones()

	# Extract platforms list for spawn positioning
	_extract_floor_positions()

	# Compute reachable tiles for spawn validation
	reachable_set = _get_reachable_tiles()

	# Remove unreachable caves so enemies/items never spawn in sealed areas
	var valid_caves: Array = []
	for cave in caves:
		var cr = clampi(int(cave.y / tile_size), 0, grid_rows - 1)
		var cc = clampi(int(cave.x / tile_size), 0, grid_cols - 1)
		var key = cr * grid_cols + cc
		if reachable_set.has(key) or cave.type == "start":
			valid_caves.append(cave)
	caves = valid_caves

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
	var max_steps = 1200  # Larger map needs more steps

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

		# Carve 4-wide tunnel with extra headroom
		for dr in range(-2, 2):
			for dc in range(-1, 2):
				var nr = r + dr
				var nc = c + dc
				if nr > 2 and nr < grid_rows - 3 and nc > 2 and nc < grid_cols - 3:
					grid[nr][nc] = 0

func _ensure_headroom():
	# Scan all floor tiles — if ceiling is too close above, remove blocks
	# Player needs ~5 tiles (80px) of headroom to jump (jump_force=-300, gravity=650)
	var min_headroom = 5

	for r in range(5, grid_rows - 4):
		for c in range(5, grid_cols - 5):
			# Check if this is a floor surface (solid with open above)
			if grid[r][c] == 1 and grid[r - 1][c] == 0:
				# Count open tiles above this floor
				var headroom = 0
				for h in range(1, min_headroom + 2):
					if r - h < 3:
						break
					if grid[r - h][c] == 0:
						headroom += 1
					else:
						break

				# If headroom is too small, carve upward
				if headroom < min_headroom and headroom > 0:
					for h in range(1, min_headroom + 1):
						var tr = r - h
						if tr > 3 and tr < grid_rows - 3:
							grid[tr][c] = 0
							# Also widen 1 tile to each side for comfort
							if c - 1 > 3:
								grid[tr][c - 1] = 0
							if c + 1 < grid_cols - 3:
								grid[tr][c + 1] = 0

	# Also ensure all carved paths have minimum 3-wide vertical clearance
	# Scan for narrow horizontal pinch points (single-tile gaps)
	for r in range(4, grid_rows - 4):
		for c in range(4, grid_cols - 4):
			if grid[r][c] == 0:
				# Check vertical clearance
				var above_solid = r - 1 >= 0 and grid[r - 1][c] == 1
				var below_solid = r + 1 < grid_rows and grid[r + 1][c] == 1
				if above_solid and below_solid:
					# Single tile gap — too narrow, expand
					if r - 1 > 3:
						grid[r - 1][c] = 0
					if r + 1 < grid_rows - 3:
						grid[r + 1][c] = 0

func _add_stepping_stones():
	# Place sparse stepping stones in tall open shafts so player can climb out.
	# Only place in very tall gaps, skip every other column, and ensure 3+ tiles
	# open on each side so passages stay clear.
	var min_gap_to_fix = 8  # Only fix gaps taller than 8 tiles (very tall shafts)
	var stone_interval = 5  # Place a stone every 5 tiles vertically

	for c in range(6, grid_cols - 6, 3):  # Every 3rd column only — much fewer stones
		var open_run = 0
		var run_start_r = -1

		for r in range(3, grid_rows - 3):
			if grid[r][c] == 0:
				if open_run == 0:
					run_start_r = r
				open_run += 1
			else:
				if open_run > min_gap_to_fix:
					var bottom_r = r - 1
					var top_r = run_start_r
					var stone_r = bottom_r - stone_interval
					while stone_r > top_r + 3:
						# Check passage isn't blocked: need 3+ open tiles on left OR right
						var left_open = 0
						var right_open = 0
						for dc in range(1, 4):
							if c - dc > 2 and grid[stone_r][c - dc] == 0:
								left_open += 1
							if c + dc < grid_cols - 3 and grid[stone_r][c + dc] == 0:
								right_open += 1

						# Only place if there's clear passage around it
						var has_passage = left_open >= 2 or right_open >= 2
						# Check above and below are open (don't seal vertically)
						var vert_clear = true
						if stone_r - 1 >= 0 and grid[stone_r - 1][c] == 1:
							vert_clear = false
						if stone_r + 1 < grid_rows and grid[stone_r + 1][c] == 1:
							vert_clear = false

						if has_passage and vert_clear:
							grid[stone_r][c] = 1  # Just 1 tile wide — minimal blockage

						stone_r -= stone_interval
				open_run = 0
				run_start_r = -1

func _ensure_all_caves_reachable(start_r: int, start_c: int):
	# Flood fill from start position
	var visited = {}
	var queue = [[start_r, start_c]]
	visited[start_r * grid_cols + start_c] = true

	while queue.size() > 0:
		var cell = queue.pop_front()
		var cr = cell[0]
		var cc = cell[1]

		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nr = cr + d[0]
			var nc = cc + d[1]
			if nr < 0 or nr >= grid_rows or nc < 0 or nc >= grid_cols:
				continue
			var key = nr * grid_cols + nc
			if visited.has(key):
				continue
			if grid[nr][nc] == 0:
				visited[key] = true
				queue.append([nr, nc])

	# Check each cave room — if not reachable, carve a path to it
	for cave in caves:
		var cave_r = int(cave.y / tile_size)
		var cave_c = int(cave.x / tile_size)
		cave_r = clampi(cave_r, 3, grid_rows - 4)
		cave_c = clampi(cave_c, 3, grid_cols - 4)
		var key = cave_r * grid_cols + cave_c
		if not visited.has(key):
			# Carve a path from start to this cave
			_carve_path(start_r, start_c, cave_r, cave_c)
			# Re-flood from this cave to mark newly connected areas
			var q2 = [[cave_r, cave_c]]
			visited[key] = true
			while q2.size() > 0:
				var cell = q2.pop_front()
				for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var nr2 = cell[0] + d[0]
					var nc2 = cell[1] + d[1]
					if nr2 < 0 or nr2 >= grid_rows or nc2 < 0 or nc2 >= grid_cols:
						continue
					var k2 = nr2 * grid_cols + nc2
					if not visited.has(k2) and grid[nr2][nc2] == 0:
						visited[k2] = true
						q2.append([nr2, nc2])

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
	var gives_blade = randf() < 0.5
	chests.append({"x": cx, "y": cy, "opened": false, "blade": gives_blade})

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
				if chests[idx].blade:
					if player_ref.has_blade:
						player_ref.attack_damage += 20
					else:
						player_ref.has_blade = true
				else:
					player_ref.heal(40)
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

	# Torches along some platforms (more for larger map)
	var placed = 0
	var max_torches = max(8, 14 - room_level / 2)
	for p in platforms:
		if p.w > 60 and randf() < 0.12 and placed < max_torches:
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
	# More enemies for larger map
	var enemy_count = 6 + room_level * 2
	enemy_count = mini(enemy_count, 20)

	var weighted_classes: Array = []
	weighted_classes.append([0, 3])  # ARCHER
	if room_level >= 2:
		weighted_classes.append([2, 3])  # THROWER
	if room_level >= 3:
		weighted_classes.append([1, 2])  # CROSSBOW
	weighted_classes.append([3, 1])  # SHIELDMAN

	var shieldman_count = 0
	var max_shieldmen = 2 + (room_level / 3)
	max_shieldmen = mini(max_shieldmen, 4)

	for i in enemy_count:
		var enemy = enemy_scene.instantiate()
		var eclass = _pick_weighted(weighted_classes)

		if eclass == 3:
			if shieldman_count >= max_shieldmen:
				eclass = weighted_classes[0][0]
			else:
				shieldman_count += 1

		var hp = (2 + room_level) * 20
		var spd = 30.0 + room_level * 5  # Faster scaling per level
		var dmg = 20 * (1 + room_level / 3)
		# Level 5+: enemies deal 2x damage
		if room_level >= 5:
			dmg *= 2
		if eclass == 3:
			hp += 40

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
	# Pick a random non-start cave, verify position is reachable
	var spawn_caves = caves.filter(func(c): return c.type != "start" and c.type != "chest")
	if spawn_caves.size() == 0:
		spawn_caves = caves.filter(func(c): return c.type != "start")
	if spawn_caves.size() == 0:
		spawn_caves = caves

	for attempt in 30:
		var cave = spawn_caves[randi() % spawn_caves.size()]
		var px = cave.x + randf_range(-20, 20)
		var py = cave.floor_y - 1

		# Check that the grid cell is reachable from start
		if reachable_set.size() > 0:
			var gr = clampi(int(py / tile_size), 0, grid_rows - 1)
			var gc = clampi(int(px / tile_size), 0, grid_cols - 1)
			var key = gr * grid_cols + gc
			if reachable_set.has(key):
				return Vector2(px, py)
			# Try one tile above (enemy stands on floor, check above floor)
			var key_above = (gr - 1) * grid_cols + gc
			if gr > 0 and reachable_set.has(key_above):
				return Vector2(px, py)
		else:
			return Vector2(px, py)

	# Fallback: use start cave
	for cave in caves:
		if cave.type == "start":
			return Vector2(cave.x, cave.floor_y - 1)
	return Vector2(60, floor_y - 1)

func _spawn_door():
	var door_script_res = load("res://scripts/door.gd")
	var door = StaticBody2D.new()
	door.set_script(door_script_res)
	door.difficulty = mini(room_level, 5)

	# Set door label based on challenge type
	if is_boss_room:
		door.door_label = "[E] Continue"
	else:
		match challenge_type:
			"lockpick":
				door.door_label = "[E] Pick Lock (need lockpick)"
			"guardians":
				door.door_label = "[E] Summon Guardians"
			"crystal":
				door.door_label = "[E] Place Crystal (need ore)"

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
	# Always check station/heart proximity (even after room cleared)
	var old_station = player_near_station
	var old_heart = player_near_heart
	if craft_stations.size() > 0:
		_check_station_proximity()
	if trial_heart_pos != Vector2.ZERO:
		_check_heart_proximity()
	# Only redraw when proximity state CHANGES (not every frame)
	if player_near_station != old_station or player_near_heart != old_heart:
		queue_redraw()

	# Boss room lava damage
	if is_boss_room and player_ref and is_instance_valid(player_ref):
		if player_ref.global_position.y > lava_y - 5:
			player_ref.take_damage(10, Vector2(0, -1))

	if is_boss_room:
		queue_redraw()  # Boss room is small (1200x700), OK to redraw
		return

	if is_cleared:
		return

	portal_spawn_timer -= delta
	if portal_spawn_timer <= 0:
		_spawn_portal()
		portal_spawn_timer = portal_spawn_interval + randf_range(-1.5, 1.5)

func _spawn_portal():
	if not player_ref or not is_instance_valid(player_ref):
		return
	if portals.size() >= 3:
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
	portal.setup(player_ref, 20 * (1 + room_level / 3))
	portal.skeleton_health = (2 + room_level / 2) * 20
	portal.max_skeleton_health = portal.skeleton_health
	add_child(portal)
	portals.append(portal)
	portal.skeleton_died.connect(_on_portal_died)
	portal.open_portal()

func _on_portal_died(portal):
	portals.erase(portal)

func _on_enemy_died(enemy):
	# Check for pickaxe drop
	if enemy.drops_pickaxe and player_ref and is_instance_valid(player_ref):
		player_ref.has_pickaxe = true
		player_ref.using_pickaxe = true  # Auto-equip
	# Check for pearl drop
	_check_pearl_drop(enemy)
	enemies.erase(enemy)
	if enemies.size() == 0:
		is_cleared = true
		room_cleared.emit()

func _on_door_interact(door):
	door_used.emit(door)

# === DOOR CHALLENGES ===

func get_lockpick_difficulty() -> int:
	# Level 1: difficulty 4 (hard like level 4)
	if room_level == 1:
		return 4
	return mini(room_level, 5)

func start_guardian_challenge(enemy_scene: PackedScene):
	if challenge_started and not challenge_complete_flag:
		return
	challenge_started = true
	challenge_complete_flag = false

	# Clean up old guardians
	for g in door_guardians:
		if is_instance_valid(g):
			g.queue_free()
	door_guardians.clear()

	# Find door position
	var door_pos = Vector2(600, 350)
	if doors.size() > 0:
		door_pos = doors[0].global_position

	# Spawn 2 spear shieldmen on each side of door
	for i in 2:
		var guardian = enemy_scene.instantiate()
		var side = -1 if i == 0 else 1
		guardian.is_spear = true

		var hp = (3 + room_level / 2) * 20
		var spd = 30.0 + room_level * 3
		var dmg = 20 * (1 + room_level / 3)
		if room_level >= 5:
			dmg *= 2

		guardian.setup(3, hp, spd, dmg)  # 3 = SHIELDMAN
		guardian.player = player_ref
		guardian.position = door_pos + Vector2(side * 40, 0)
		add_child(guardian)
		door_guardians.append(guardian)
		guardian.died.connect(_on_guardian_died)

func _on_guardian_died(enemy):
	door_guardians.erase(enemy)
	if door_guardians.size() == 0:
		challenge_complete_flag = true
		challenge_complete.emit()

func start_crystal_challenge(enemy_scene: PackedScene):
	# Clean up old challenge
	if crystal_node and is_instance_valid(crystal_node):
		crystal_node.queue_free()
	for a in crystal_attackers:
		if is_instance_valid(a):
			a.queue_free()
	crystal_attackers.clear()

	challenge_started = true
	challenge_complete_flag = false

	# Find door position
	var door_pos = Vector2(600, 350)
	if doors.size() > 0:
		door_pos = doors[0].global_position

	# Spawn crystal near door
	crystal_node = Node2D.new()
	crystal_node.set_script(crystal_script)
	crystal_node.position = door_pos + Vector2(-20, 0)
	# 240 HP = each of 4 enemies needs 3 hits to break it (4*3*20=240), scales with level
	crystal_node.health = 240 + room_level * 20
	crystal_node.max_health = crystal_node.health
	add_child(crystal_node)
	crystal_node.crystal_destroyed.connect(_on_crystal_destroyed)

	# Spawn 4 random enemies that attack ONLY the crystal
	var enemy_classes = [0, 2, 3]  # ARCHER, THROWER, SHIELDMAN
	if room_level >= 3:
		enemy_classes.append(1)  # CROSSBOW

	for i in 4:
		var attacker = enemy_scene.instantiate()
		var eclass = enemy_classes[randi() % enemy_classes.size()]

		var hp = (2 + room_level) * 20
		var spd = 30.0 + room_level * 4
		var dmg = 20  # Crystal attackers deal 20 damage to crystal (20x scale)
		if eclass == 3:
			hp += 40

		attacker.setup(eclass, hp, spd, dmg)
		attacker.player = player_ref
		attacker.crystal_target = crystal_node  # They attack ONLY the crystal

		# Spawn from edges of the room
		var spawn_pos = _get_spawn_position()
		# Ensure they spawn away from crystal
		if spawn_pos.distance_to(crystal_node.position) < 100:
			spawn_pos = _get_spawn_position()
		attacker.position = spawn_pos
		add_child(attacker)
		crystal_attackers.append(attacker)
		attacker.died.connect(_on_crystal_attacker_died)

func _on_crystal_attacker_died(enemy):
	crystal_attackers.erase(enemy)
	if crystal_attackers.size() == 0:
		if crystal_node and is_instance_valid(crystal_node) and not crystal_node.is_destroyed:
			challenge_complete_flag = true
			challenge_complete.emit()

func _on_crystal_destroyed():
	# Crystal was destroyed — challenge failed
	# Attackers keep wandering, player can interact with door to retry
	pass

# === ORE & PICKAXE SYSTEM ===

func _spawn_ore_blocks():
	ore_blocks.clear()
	# Iron: 6 on lockpick/crystal levels, 1 on others
	var ore_count = 6 if (challenge_type == "lockpick" or challenge_type == "crystal") else 1
	var placed = 0
	var attempts = 0

	# First, flood fill from start to know which open tiles are reachable
	var reachable = {}
	var start_cave = null
	for cave in caves:
		if cave.type == "start":
			start_cave = cave
			break
	if start_cave:
		var sr = int(start_cave.y / tile_size)
		var sc = int(start_cave.x / tile_size)
		sr = clampi(sr, 0, grid_rows - 1)
		sc = clampi(sc, 0, grid_cols - 1)
		var queue = [[sr, sc]]
		reachable[sr * grid_cols + sc] = true
		while queue.size() > 0:
			var cell = queue.pop_front()
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nr2 = cell[0] + d[0]
				var nc2 = cell[1] + d[1]
				if nr2 < 0 or nr2 >= grid_rows or nc2 < 0 or nc2 >= grid_cols:
					continue
				var k = nr2 * grid_cols + nc2
				if not reachable.has(k) and grid[nr2][nc2] == 0:
					reachable[k] = true
					queue.append([nr2, nc2])

	while placed < ore_count and attempts < 300:
		attempts += 1
		var r = randi_range(5, grid_rows - 5)
		var c = randi_range(5, grid_cols - 5)

		# Must be solid tile with open space ABOVE it (floor surface = visible block)
		if grid[r][c] != 1:
			continue
		if r <= 1 or grid[r - 1][c] != 0:
			continue  # Not a floor surface — skip buried blocks

		# The open space above must be REACHABLE (connected to main cave)
		var above_key = (r - 1) * grid_cols + c
		if not reachable.has(above_key):
			continue

		# Check not too close to other ore (spread them out)
		var too_close = false
		for ore in ore_blocks:
			if Vector2(ore.x, ore.y).distance_to(Vector2(c * tile_size + 8, r * tile_size + 8)) < 80:
				too_close = true
				break
		if too_close:
			continue

		var ox = float(c * tile_size + 8)
		var oy = float(r * tile_size + 8)

		# Create Area2D for ore detection (detects player attack layer 16)
		var ore_area = Area2D.new()
		ore_area.collision_layer = 0
		ore_area.collision_mask = 16  # player_attack
		var oshape = CollisionShape2D.new()
		var orect = RectangleShape2D.new()
		orect.size = Vector2(16, 16)
		oshape.shape = orect
		ore_area.add_child(oshape)
		ore_area.position = Vector2(ox, oy)
		add_child(ore_area)

		var ore_idx = placed
		ore_blocks.append({"x": ox, "y": oy, "mined": false, "area": ore_area, "r": r, "c": c})
		ore_area.area_entered.connect(_on_ore_hit.bind(ore_idx))
		placed += 1

func _on_ore_hit(attacker_area: Area2D, ore_idx: int):
	if ore_idx >= ore_blocks.size():
		return
	if ore_blocks[ore_idx].mined:
		return
	if not player_ref or not is_instance_valid(player_ref):
		return
	if not player_ref.using_pickaxe or not player_ref.is_attacking:
		return

	# Mine the ore!
	ore_blocks[ore_idx].mined = true
	if ore_blocks[ore_idx].area and is_instance_valid(ore_blocks[ore_idx].area):
		ore_blocks[ore_idx].area.queue_free()
	player_ref.ore_mined += 1
	player_ref.iron_ore += 1

	# All ore mined on lockpick level = lockpick crafted (legacy behavior)
	if challenge_type == "lockpick" and player_ref.ore_mined >= player_ref.ore_needed:
		player_ref.has_lockpick = true

	queue_redraw()

func _spawn_pickaxe_mob(enemy_scene: PackedScene, p_player_ref: CharacterBody2D):
	var enemy = enemy_scene.instantiate()
	# Make it a thrower (visually distinct) with pickaxe drop
	var hp = (3 + room_level) * 20
	var spd = 25.0 + room_level * 3
	var dmg = 20
	enemy.setup(0, hp, spd, dmg)  # ARCHER class but with pickaxe flag
	enemy.player = p_player_ref
	enemy.drops_pickaxe = true

	# Spawn in a reachable spot, not too far from start
	var pos = _get_spawn_position()
	for attempt in 10:
		var candidate = _get_spawn_position()
		# Prefer positions closer to start area
		var start_cave = null
		for cave in caves:
			if cave.type == "start":
				start_cave = cave
				break
		if start_cave and candidate.distance_to(Vector2(start_cave.x, start_cave.floor_y)) < pos.distance_to(Vector2(start_cave.x, start_cave.floor_y)):
			pos = candidate

	enemy.position = pos
	add_child(enemy)
	enemies.append(enemy)
	enemy.died.connect(_on_enemy_died)
	pickaxe_enemy = enemy

func _on_pickaxe_enemy_died():
	if player_ref and is_instance_valid(player_ref):
		player_ref.has_pickaxe = true

# === GOLD ORE ===

func _spawn_gold_ore():
	gold_ore_blocks.clear()
	# Gold: 1 every 2 levels
	if room_level % 2 != 0:
		return

	# Reuse reachable set from ore spawning
	var reachable = _get_reachable_tiles()
	var attempts = 0

	while gold_ore_blocks.size() < 1 and attempts < 200:
		attempts += 1
		var r = randi_range(5, grid_rows - 5)
		var c = randi_range(5, grid_cols - 5)

		if grid[r][c] != 1:
			continue
		if r <= 1 or grid[r - 1][c] != 0:
			continue
		var above_key = (r - 1) * grid_cols + c
		if not reachable.has(above_key):
			continue

		# Not near iron ore
		var too_close = false
		for ore in ore_blocks:
			if Vector2(ore.x, ore.y).distance_to(Vector2(c * tile_size + 8, r * tile_size + 8)) < 60:
				too_close = true
				break
		if too_close:
			continue

		var ox = float(c * tile_size + 8)
		var oy = float(r * tile_size + 8)

		var ore_area = Area2D.new()
		ore_area.collision_layer = 0
		ore_area.collision_mask = 16
		var oshape = CollisionShape2D.new()
		var orect = RectangleShape2D.new()
		orect.size = Vector2(16, 16)
		oshape.shape = orect
		ore_area.add_child(oshape)
		ore_area.position = Vector2(ox, oy)
		add_child(ore_area)

		gold_ore_blocks.append({"x": ox, "y": oy, "mined": false, "area": ore_area, "r": r, "c": c})
		ore_area.area_entered.connect(_on_gold_ore_hit.bind(0))

func _on_gold_ore_hit(attacker_area: Area2D, ore_idx: int):
	if ore_idx >= gold_ore_blocks.size():
		return
	if gold_ore_blocks[ore_idx].mined:
		return
	if not player_ref or not is_instance_valid(player_ref):
		return
	if not player_ref.using_pickaxe or not player_ref.is_attacking:
		return

	gold_ore_blocks[ore_idx].mined = true
	if gold_ore_blocks[ore_idx].area and is_instance_valid(gold_ore_blocks[ore_idx].area):
		gold_ore_blocks[ore_idx].area.queue_free()
	player_ref.gold_ore += 1
	queue_redraw()

func _get_reachable_tiles() -> Dictionary:
	var reachable = {}
	var start_cave = null
	for cave in caves:
		if cave.type == "start":
			start_cave = cave
			break
	if not start_cave:
		return reachable
	var sr = clampi(int(start_cave.y / tile_size), 0, grid_rows - 1)
	var sc = clampi(int(start_cave.x / tile_size), 0, grid_cols - 1)
	var queue = [[sr, sc]]
	reachable[sr * grid_cols + sc] = true
	while queue.size() > 0:
		var cell = queue.pop_front()
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nr2 = cell[0] + d[0]
			var nc2 = cell[1] + d[1]
			if nr2 < 0 or nr2 >= grid_rows or nc2 < 0 or nc2 >= grid_cols:
				continue
			var k = nr2 * grid_cols + nc2
			if not reachable.has(k) and grid[nr2][nc2] == 0:
				reachable[k] = true
				queue.append([nr2, nc2])
	return reachable

# === PEARL ENEMY ===

func _spawn_pearl_enemy(enemy_scene: PackedScene, p_player_ref: CharacterBody2D):
	var enemy = enemy_scene.instantiate()
	var hp = (3 + room_level) * 20
	var spd = 25.0 + room_level * 3
	var dmg = 20
	# Random class, but visually distinct
	enemy.setup(2, hp, spd, dmg)  # THROWER
	enemy.player = p_player_ref
	enemy.drops_pearl = true

	var pos = _get_spawn_position()
	enemy.position = pos
	add_child(enemy)
	enemies.append(enemy)
	enemy.died.connect(_on_enemy_died)
	pearl_enemy = enemy

func _check_pearl_drop(enemy):
	if enemy == pearl_enemy and player_ref and is_instance_valid(player_ref):
		player_ref.has_pearl = true

# === CRAFTING STATIONS ===

func _spawn_craft_stations():
	craft_stations.clear()
	player_near_station = ""
	grate_used_this_level = false

	# Find start cave
	var start_cave = null
	for cave in caves:
		if cave.type == "start":
			start_cave = cave
			break
	if not start_cave:
		return

	var base_x = start_cave.x
	var floor_y = start_cave.floor_y

	# Place 3 stations in start cave: furnace (left), anvil (center), grate (right)
	var stations_data = [
		{"type": "furnace", "x": base_x - 20, "y": floor_y - 10},
		{"type": "anvil", "x": base_x + 10, "y": floor_y - 10},
		{"type": "grate", "x": base_x + 40, "y": floor_y - 10},
	]

	for data in stations_data:
		var area = Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 1  # Detect player
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(30, 30)
		shape.shape = rect
		area.add_child(shape)
		area.position = Vector2(data.x, data.y)
		add_child(area)

		var station = {"type": data.type, "x": data.x, "y": data.y, "area": area}
		craft_stations.append(station)

		var station_type = data.type
		area.body_entered.connect(_on_station_entered.bind(station_type))
		area.body_exited.connect(_on_station_exited.bind(station_type))

func _on_station_entered(body, station_type: String):
	if body.is_in_group("player"):
		player_near_station = station_type

func _on_station_exited(body, station_type: String):
	if body.is_in_group("player") and player_near_station == station_type:
		player_near_station = ""

func _check_station_proximity():
	# Direct proximity check — more reliable than Area2D signals
	if not player_ref or not is_instance_valid(player_ref):
		player_near_station = ""
		return
	var found = ""
	for station in craft_stations:
		var dist = player_ref.global_position.distance_to(Vector2(station.x, station.y))
		if dist < 30:
			found = station.type
			break
	player_near_station = found

func _check_heart_proximity():
	# Direct proximity check for trial heart
	if not player_ref or not is_instance_valid(player_ref):
		player_near_heart = false
		return
	if trial_heart_pos == Vector2.ZERO or trial_active or trial_complete:
		player_near_heart = false
		return
	var dist = player_ref.global_position.distance_to(trial_heart_pos)
	player_near_heart = dist < 30

signal craft_message(text: String)
signal open_craft_menu_request(station_type: String)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		# Crafting stations — open menu via signal to main.gd
		if player_near_station != "":
			open_craft_menu_request.emit(player_near_station)
			get_viewport().set_input_as_handled()
			return
		# Trial heart
		if player_near_heart and not trial_active and not trial_complete:
			start_trial()
			craft_message.emit("TRIAL STARTED! Survive!")
			get_viewport().set_input_as_handled()
			return

func try_craft() -> String:
	# Called from main.gd when player presses E near a station
	if not player_ref or not is_instance_valid(player_ref):
		return ""

	match player_near_station:
		"furnace":
			if player_ref.iron_ore > 0:
				player_ref.iron_ore -= 1
				player_ref.iron_ingot += 1
				return "Smelted iron ingot!"
			elif player_ref.gold_ore > 0:
				player_ref.gold_ore -= 1
				player_ref.gold_ingot += 1
				return "Smelted gold ingot!"
			else:
				return "Need ore to smelt!"
		"anvil":
			# Priority: lockpick > amulet > sword merge
			if player_ref.iron_ingot > 0 and player_ref.has_pickaxe:
				player_ref.iron_ingot -= 1
				player_ref.has_lockpick = true
				return "Crafted lockpick!"
			elif player_ref.gold_ingot > 0 and player_ref.has_pearl:
				player_ref.gold_ingot -= 1
				player_ref.has_pearl = false
				player_ref.has_amulet = true
				player_ref.amulet_timer = player_ref.amulet_heal_interval
				return "Crafted amulet! +1 HP/10s"
			elif player_ref.iron_ingot > 0 and player_ref.has_blade and player_ref.sword_tier < 2:
				player_ref.iron_ingot -= 1
				player_ref.sword_tier = 2
				player_ref.attack_damage += 20
				return "Merged sword! +20 DMG"
			else:
				return "Need materials! (ingot+pickaxe/pearl/blade)"
		"grate":
			if not grate_used_this_level:
				grate_used_this_level = true
				player_ref.has_flask = true
				player_ref.flask_charges += 3
				return "Filled flask! +3 charges [F]"
			else:
				return "Grate already used this level!"
	return ""

func try_craft_recipe(station_type: String, recipe_index: int) -> String:
	if not player_ref or not is_instance_valid(player_ref):
		return ""

	match station_type:
		"furnace":
			match recipe_index:
				0:  # Iron Ore → Iron Ingot
					if player_ref.iron_ore > 0:
						player_ref.iron_ore -= 1
						player_ref.iron_ingot += 1
						return "Smelted Iron Ingot!"
					return "Need Iron Ore!"
				1:  # Gold Ore → Gold Ingot
					if player_ref.gold_ore > 0:
						player_ref.gold_ore -= 1
						player_ref.gold_ingot += 1
						return "Smelted Gold Ingot!"
					return "Need Gold Ore!"
		"anvil":
			match recipe_index:
				0:  # Iron Ingot + Pickaxe → Lockpick
					if player_ref.iron_ingot > 0 and player_ref.has_pickaxe:
						player_ref.iron_ingot -= 1
						player_ref.has_lockpick = true
						return "Crafted Lockpick!"
					return "Need Iron Ingot + Pickaxe!"
				1:  # Iron Ingot + Blade → Merged Sword
					if player_ref.iron_ingot > 0 and player_ref.has_blade and player_ref.sword_tier < 2:
						player_ref.iron_ingot -= 1
						player_ref.sword_tier = 2
						player_ref.attack_damage += 20
						return "Merged Sword! +20 DMG!"
					return "Need Iron Ingot + Blade!"
				2:  # Gold Ingot + Pearl → Amulet
					if player_ref.gold_ingot > 0 and player_ref.has_pearl:
						player_ref.gold_ingot -= 1
						player_ref.has_pearl = false
						player_ref.has_amulet = true
						player_ref.amulet_timer = player_ref.amulet_heal_interval
						return "Crafted Amulet! +1 HP/10s"
					return "Need Gold Ingot + Pearl!"
		"grate":
			match recipe_index:
				0:  # Fill Flask
					if not grate_used_this_level:
						grate_used_this_level = true
						player_ref.has_flask = true
						player_ref.flask_charges += 3
						return "Filled Flask! +3 charges [F]"
					return "Already used this level!"
	return ""

# === TRIAL ROOM ===

func _spawn_trial_heart():
	# Find a dead_end cave to use as trial room
	var trial_cave = null
	for cave in caves:
		if cave.type == "dead_end":
			trial_cave = cave
			break
	if not trial_cave:
		# Use any non-start, non-door cave
		for cave in caves:
			if cave.type != "start" and cave.type != "door":
				trial_cave = cave
				break
	if not trial_cave:
		return

	trial_cave.type = "trial"
	trial_heart_pos = Vector2(trial_cave.x, trial_cave.floor_y - 12)

	# Create heart Area2D
	trial_heart_area = Area2D.new()
	trial_heart_area.collision_layer = 0
	trial_heart_area.collision_mask = 1
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	trial_heart_area.add_child(shape)
	trial_heart_area.position = trial_heart_pos
	add_child(trial_heart_area)
	trial_heart_area.body_entered.connect(_on_heart_entered)
	trial_heart_area.body_exited.connect(_on_heart_exited)

func _on_heart_entered(body):
	if body.is_in_group("player"):
		player_near_heart = true

func _on_heart_exited(body):
	if body.is_in_group("player"):
		player_near_heart = false

func start_trial():
	if trial_active or trial_complete:
		return
	trial_active = true
	trial_enemies.clear()

	var enemy_scene_ref = load("res://scenes/enemy.tscn")

	# Spawn crossbow enemies from left and right
	for side in [-1, 1]:
		var cb = enemy_scene_ref.instantiate()
		var hp = (3 + room_level) * 20
		var spd = 25.0 + room_level * 3
		var dmg = 20 * (1 + room_level / 3)
		if room_level >= 5:
			dmg *= 2
		cb.setup(1, hp, spd, dmg)  # CROSSBOW
		cb.player = player_ref
		cb.position = trial_heart_pos + Vector2(side * 80, 0)
		add_child(cb)
		trial_enemies.append(cb)
		cb.died.connect(_on_trial_enemy_died)

	# Spawn 2-3 random enemies
	var extra = randi_range(2, 3)
	for i in extra:
		var e = enemy_scene_ref.instantiate()
		var eclass = [0, 2, 3][randi() % 3]
		var hp = (2 + room_level) * 20
		var spd = 30.0 + room_level * 4
		var dmg = 20 * (1 + room_level / 3)
		if room_level >= 5:
			dmg *= 2
		if eclass == 3:
			hp += 40
		e.setup(eclass, hp, spd, dmg)
		e.player = player_ref
		var angle = randf() * TAU
		e.position = trial_heart_pos + Vector2(cos(angle) * 60, sin(angle) * 30)
		add_child(e)
		trial_enemies.append(e)
		e.died.connect(_on_trial_enemy_died)

	# Remove heart visual
	if trial_heart_area and is_instance_valid(trial_heart_area):
		trial_heart_area.queue_free()
		trial_heart_area = null

func _on_trial_enemy_died(enemy):
	trial_enemies.erase(enemy)
	if trial_enemies.size() == 0 and trial_active:
		trial_active = false
		trial_complete = true
		trial_completed.emit()

# === CRYSTAL PLACEMENT (Level 3 challenge) ===

func start_crystal_placement():
	# Player places crystal at their current position using mined ore
	if not player_ref or not is_instance_valid(player_ref):
		return
	if player_ref.ore_mined < player_ref.ore_needed:
		return

	challenge_started = true
	challenge_complete_flag = false

	# Spawn crystal at player position
	crystal_node = Node2D.new()
	crystal_node.set_script(crystal_script)
	crystal_node.position = player_ref.global_position + Vector2(0, -5)
	# 240 HP = each of 4 enemies needs 3 hits (4*3*20=240), scales with level
	crystal_node.health = 240 + room_level * 20
	crystal_node.max_health = crystal_node.health
	add_child(crystal_node)
	crystal_node.crystal_destroyed.connect(_on_crystal_destroyed)

	# Spawn 4 enemies that attack ONLY the crystal, near the crystal
	var enemy_scene_ref = load("res://scenes/enemy.tscn")
	var enemy_classes = [0, 2, 3]
	if room_level >= 3:
		enemy_classes.append(1)

	for i in 4:
		var attacker = enemy_scene_ref.instantiate()
		var eclass = enemy_classes[randi() % enemy_classes.size()]
		var hp = (2 + room_level) * 20
		var spd = 30.0 + room_level * 4
		var dmg = 20
		if eclass == 3:
			hp += 40
		attacker.setup(eclass, hp, spd, dmg)
		attacker.player = player_ref
		attacker.crystal_target = crystal_node

		# Spawn near crystal (within 60-120 px)
		var angle = randf() * TAU
		var dist = randf_range(60, 120)
		var spawn_pos = crystal_node.position + Vector2(cos(angle) * dist, sin(angle) * dist * 0.5)
		# Clamp to room bounds
		spawn_pos.x = clampf(spawn_pos.x, 50, room_width - 50)
		spawn_pos.y = clampf(spawn_pos.y, 50, room_height - 50)
		attacker.position = spawn_pos
		add_child(attacker)
		crystal_attackers.append(attacker)
		attacker.died.connect(_on_crystal_attacker_died)

	# Reset player ore (used up to make crystal)
	player_ref.ore_mined = 0

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

	# Boss room lava
	if is_boss_room:
		_draw_lava()

	# Decorations
	if not is_boss_room:
		_draw_decorations()

	# Ore blocks
	_draw_ore_blocks()

	# Gold ore blocks
	_draw_gold_ore_blocks()

	# Crafting stations
	_draw_craft_stations()

	# Trial heart
	_draw_trial_heart()

	# Chests
	_draw_chests()

func _draw_solid_tiles():
	# Draw merged horizontal runs of solid tiles (optimized: no per-tile shading)
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
					# Single draw call per run — much faster on large maps
					draw_rect(Rect2(x, y, w, tile_size), rock_color)
					# Subtle inner shade (1 draw per run, not per tile)
					draw_rect(Rect2(x + 1, y + 1, w - 2, tile_size - 2), rock_dark)
					run_start = -1

func _draw_surface_edges():
	# Optimized: merge floor/ceiling edges into horizontal runs
	var ceil_col = Color(rock_dark.r - 0.05, rock_dark.g - 0.05, rock_dark.b - 0.03)
	var light_col = Color(rock_light.r, rock_light.g, rock_light.b, 0.5)

	# Floor surfaces — merged runs
	for r in range(1, grid_rows):
		var run_start = -1
		for c in range(grid_cols + 1):
			var is_floor = c < grid_cols and grid[r][c] == 1 and grid[r - 1][c] == 0
			if is_floor:
				if run_start == -1:
					run_start = c
			else:
				if run_start != -1:
					var x = run_start * tile_size
					var w = (c - run_start) * tile_size
					draw_rect(Rect2(x, r * tile_size, w, 2), surface_color)
					draw_rect(Rect2(x + 1, r * tile_size + 2, w - 2, 3), light_col)
					run_start = -1

	# Ceiling surfaces — merged runs
	for r in range(0, grid_rows - 1):
		var run_start = -1
		for c in range(grid_cols + 1):
			var is_ceil = c < grid_cols and grid[r][c] == 1 and grid[r + 1][c] == 0
			if is_ceil:
				if run_start == -1:
					run_start = c
			else:
				if run_start != -1:
					var x = run_start * tile_size
					var w = (c - run_start) * tile_size
					draw_rect(Rect2(x, (r + 1) * tile_size - 2, w, 2), ceil_col)
					run_start = -1

	# Right wall surfaces (solid with open to left)
	for r in range(grid_rows):
		for c in range(1, grid_cols):
			if grid[r][c] == 1 and grid[r][c - 1] == 0:
				draw_rect(Rect2(c * tile_size, r * tile_size, 2, tile_size),
					Color(rock_dark.r, rock_dark.g, rock_dark.b, 0.6))

func _draw_lava():
	if not is_boss_room:
		return
	var lava_row = grid_rows - 4
	var ly = float(lava_row * tile_size)
	var t = Time.get_ticks_msec() * 0.002

	# Lava glow above surface
	draw_rect(Rect2(0, ly - 8, room_width, 8), Color(1, 0.3, 0.05, 0.15))

	# Lava surface (animated waves)
	for c in range(0, int(room_width), 4):
		var wave = sin(t + c * 0.05) * 3
		var col_a = Color(1, 0.4, 0.05, 0.9)
		var col_b = Color(1, 0.6, 0.1, 0.8)
		var col = col_a if fmod(float(c) * 0.1 + t, 2.0) < 1.0 else col_b
		draw_rect(Rect2(c, ly + wave, 4, 3), col)

	# Lava body
	draw_rect(Rect2(0, ly + 3, room_width, room_height - ly), Color(0.8, 0.25, 0.02))
	# Bright spots
	for i in 10:
		var bx = fmod(float(i) * 137.0 + t * 20, room_width)
		var by = ly + 8 + sin(t * 0.5 + i) * 5
		draw_circle(Vector2(bx, by), 6, Color(1, 0.6, 0.1, 0.3))

	# "GOLEM" boss name
	if golem_boss and is_instance_valid(golem_boss) and not golem_boss.is_dead:
		draw_string(ThemeDB.fallback_font, Vector2(room_width / 2 - 30, 30),
			"GOLEM", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.9, 0.4, 0.1, 0.8))

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

func _draw_ore_blocks():
	for ore in ore_blocks:
		if ore.mined:
			continue
		var ox = ore.x - 8
		var oy = ore.y - 8
		# Iron ore block - darker rock with metallic specks
		draw_rect(Rect2(ox, oy, 16, 16), Color(0.35, 0.33, 0.3))
		draw_rect(Rect2(ox + 1, oy + 1, 14, 14), Color(0.4, 0.38, 0.35))
		# Iron specks (light metallic)
		draw_rect(Rect2(ox + 3, oy + 3, 3, 2), Color(0.7, 0.65, 0.55))
		draw_rect(Rect2(ox + 9, oy + 5, 2, 3), Color(0.75, 0.7, 0.6))
		draw_rect(Rect2(ox + 5, oy + 10, 3, 2), Color(0.7, 0.65, 0.55))
		draw_rect(Rect2(ox + 11, oy + 11, 2, 2), Color(0.65, 0.6, 0.5))
		# Edge highlight
		draw_rect(Rect2(ox, oy, 16, 1), Color(0.5, 0.48, 0.42))
		# Glow effect
		draw_circle(Vector2(ore.x, ore.y), 10, Color(0.8, 0.7, 0.4, 0.08))

func _draw_gold_ore_blocks():
	for ore in gold_ore_blocks:
		if ore.mined:
			continue
		var ox = ore.x - 8
		var oy = ore.y - 8
		# Gold ore block - darker rock with gold specks
		draw_rect(Rect2(ox, oy, 16, 16), Color(0.4, 0.35, 0.2))
		draw_rect(Rect2(ox + 1, oy + 1, 14, 14), Color(0.45, 0.4, 0.25))
		# Gold specks
		draw_rect(Rect2(ox + 3, oy + 3, 3, 2), Color(1, 0.85, 0.2))
		draw_rect(Rect2(ox + 9, oy + 5, 2, 3), Color(1, 0.9, 0.3))
		draw_rect(Rect2(ox + 5, oy + 10, 3, 2), Color(1, 0.85, 0.2))
		draw_rect(Rect2(ox + 11, oy + 11, 2, 2), Color(0.95, 0.8, 0.15))
		# Edge highlight
		draw_rect(Rect2(ox, oy, 16, 1), Color(1, 0.9, 0.3))
		# Glow effect
		draw_circle(Vector2(ore.x, ore.y), 10, Color(1, 0.85, 0.2, 0.12))

func _draw_craft_stations():
	for station in craft_stations:
		var sx = station.x
		var sy = station.y
		match station.type:
			"furnace":
				# Furnace - stone block with fire
				draw_rect(Rect2(sx - 8, sy - 8, 16, 16), Color(0.4, 0.35, 0.3))
				draw_rect(Rect2(sx - 7, sy - 7, 14, 14), Color(0.5, 0.45, 0.38))
				# Fire opening
				draw_rect(Rect2(sx - 4, sy - 2, 8, 8), Color(0.15, 0.08, 0.05))
				# Fire glow
				var t = Time.get_ticks_msec() * 0.005
				var flicker = 0.5 + sin(t) * 0.2
				draw_rect(Rect2(sx - 3, sy + 1, 6, 4), Color(1, 0.5, 0.1, flicker))
				draw_rect(Rect2(sx - 2, sy - 1, 4, 3), Color(1, 0.8, 0.2, flicker * 0.7))
				# Chimney
				draw_rect(Rect2(sx - 2, sy - 12, 4, 5), Color(0.45, 0.4, 0.35))
			"anvil":
				# Anvil - metal block
				draw_rect(Rect2(sx - 8, sy + 2, 16, 6), Color(0.35, 0.35, 0.38))
				draw_rect(Rect2(sx - 6, sy - 4, 12, 7), Color(0.42, 0.42, 0.46))
				draw_rect(Rect2(sx - 10, sy - 2, 20, 3), Color(0.48, 0.48, 0.52))
				# Horn
				draw_rect(Rect2(sx + 8, sy - 3, 4, 2), Color(0.45, 0.45, 0.5))
				# Highlight
				draw_rect(Rect2(sx - 9, sy - 2, 18, 1), Color(0.6, 0.6, 0.65, 0.5))
			"grate":
				# Grate - iron bars over stone
				draw_rect(Rect2(sx - 8, sy - 2, 16, 10), Color(0.3, 0.28, 0.25))
				# Bars
				for i in 5:
					draw_rect(Rect2(sx - 7 + i * 3, sy - 4, 2, 12), Color(0.5, 0.5, 0.55))
				# Water/liquid glow underneath
				draw_rect(Rect2(sx - 6, sy + 2, 12, 4), Color(0.2, 0.5, 0.7, 0.3))

		# Label when player is near
		if player_near_station == station.type:
			var label = ""
			match station.type:
				"furnace": label = "[E] Smelt"
				"anvil": label = "[E] Craft"
				"grate": label = "[E] Fill Flask"
			draw_string(ThemeDB.fallback_font, Vector2(sx - 20, sy - 18),
				label, HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(1, 1, 0.5, 0.9))

func _draw_trial_heart():
	if trial_complete or trial_active or trial_heart_pos == Vector2.ZERO:
		return
	var hx = trial_heart_pos.x
	var hy = trial_heart_pos.y
	var t = Time.get_ticks_msec() * 0.003
	var pulse = 1.0 + sin(t * 2) * 0.1

	# Glowing heart
	draw_circle(Vector2(hx, hy), 14 * pulse, Color(1, 0.2, 0.3, 0.15))
	# Heart shape using rects
	draw_rect(Rect2(hx - 6, hy - 4, 5, 5), Color(0.9, 0.15, 0.2, 0.9))
	draw_rect(Rect2(hx + 1, hy - 4, 5, 5), Color(0.9, 0.15, 0.2, 0.9))
	draw_rect(Rect2(hx - 7, hy - 6, 6, 4), Color(0.9, 0.15, 0.2, 0.9))
	draw_rect(Rect2(hx + 1, hy - 6, 6, 4), Color(0.9, 0.15, 0.2, 0.9))
	draw_rect(Rect2(hx - 5, hy + 1, 10, 3), Color(0.9, 0.15, 0.2, 0.9))
	draw_rect(Rect2(hx - 3, hy + 4, 6, 2), Color(0.9, 0.15, 0.2, 0.9))
	draw_rect(Rect2(hx - 1, hy + 6, 2, 2), Color(0.9, 0.15, 0.2, 0.9))
	# Highlight
	draw_rect(Rect2(hx - 5, hy - 5, 3, 2), Color(1, 0.5, 0.5, 0.5))

	# Label
	if player_near_heart:
		draw_string(ThemeDB.fallback_font, Vector2(hx - 25, hy - 16),
			"[E] Trial (+50% HP)", HORIZONTAL_ALIGNMENT_CENTER, -1, 8, Color(1, 0.3, 0.3, 0.9))

func _draw_chests():
	for chest in chests:
		var cx = chest.x
		var cy = chest.y
		var is_blade = chest.get("blade", false)

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
			# Glow - blue for blade, gold for heal
			if is_blade:
				draw_circle(Vector2(cx, cy - 4), 12, Color(0.3, 0.7, 1.0, 0.1))
				# Blade icon on chest
				draw_line(Vector2(cx - 4, cy - 7), Vector2(cx + 4, cy - 3), Color(0.4, 0.8, 1.0, 0.5), 1.5)
			else:
				draw_circle(Vector2(cx, cy - 4), 12, Color(1.0, 0.8, 0.2, 0.1))
				# Cross icon (heal)
				draw_rect(Rect2(cx - 1, cy - 7, 2, 4), Color(0.3, 0.9, 0.3, 0.5))
				draw_rect(Rect2(cx - 2, cy - 6, 4, 2), Color(0.3, 0.9, 0.3, 0.5))
