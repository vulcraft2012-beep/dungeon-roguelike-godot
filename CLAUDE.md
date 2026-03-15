# Dungeon Roguelike — Godot 4.2

2D pixel roguelike, side-view (platformer), castle/cave dungeon setting.
All graphics are drawn **programmatically via `_draw()`** — no sprite assets.

## Project structure

```
scenes/       — .tscn scene files (player, enemy, lockpick_minigame, main)
scripts/      — GDScript logic
  main.gd         — game manager: creates player, room, camera, darkness, HUD
  player.gd       — player controller
  room.gd         — cave generation + enemy/portal/chest/torch spawning + door challenges
  enemy.gd        — 4 enemy classes + spear variant + crystal targeting
  skeleton_portal.gd — Portal Eye Monster
  projectile.gd   — arrow, bolt, hammer, grenade
  torch.gd        — PointLight2D torch with flicker
  door.gd         — locked door with [E] interact, dynamic labels
  crystal.gd      — defense crystal for level 3 challenge
  lockpick_minigame.gd
  hud.gd
  game_over.gd
  explosion_effect.gd
```

## Collision layers (bitmask values)

| Layer | Value | Purpose |
|-------|-------|---------|
| 1 | 1 | player |
| 2 | 2 | enemies |
| 3 | 4 | walls / floors (all cave tiles) |
| 4 | 8 | doors |
| 5 | 16 | player_attack hitbox |

## Player controls

- **WASD / Arrow keys** — move
- **Space** — jump / wall jump
- **LMB** — sword attack (3-hit combo)
- **RMB** — shield
- **Shift** — dodge roll (phases through enemies: collision_layer = 0 during roll)

## Key mechanics

- **Wall slide**: raycasts detect layer 4 walls, fall slows to 40 px/s
- **Wall jump**: `velocity = Vector2(-wall_dir * 180, -280)`, 0.15s cooldown
- **Ledge grab**: vertical raycasts downward from ahead position + headroom check
- **Roll phasing**: `collision_layer = 0` during roll (enemies detect layer 1)
- **Sword combo**: 3 hits, 0.22s cooldown, 0.55x speed during attack
- **Shield**: blocks projectiles, pushes melee enemies back

## Enemies

| Class | Enum | Notes |
|-------|------|-------|
| Archer | 0 | ranged, keeps distance |
| Crossbow | 1 | fires 3-bolt spread |
| Thrower | 2 | hammers or grenades (AoE) |
| Shieldman | 3 | melee, blocks; 3 shield hits → 2s stun; max 1-2 per room |

Weighted spawn: Archer=3, Thrower=3, Crossbow=2, Shieldman=1

### Spear Shieldman variant
- `is_spear = true` on SHIELDMAN class
- attack_range = 40 (vs 22 normal), longer spear thrust
- Used as door guardians on level 2, 5, 8...

### Crystal targeting
- `crystal_target` on enemy → enemy moves to and attacks ONLY the crystal
- Used for crystal defense challenge on level 3, 6, 9...

## Portal Eye Monster (skeleton_portal.gd)

- Extends `CharacterBody2D`, collision_layer = 2
- Spawned via `CharacterBody2D.new()` in room.gd (NOT Node2D.new())
- Lives 5 seconds after portal opens, can be killed during that window
- Has `take_damage(amount, knockback_dir)` called directly by player attack Area2D
- Psychedelic rainbow eye design with tentacles, blinking, death shatter
- Shoots arrows at player every 2s

## Cave generation (room.gd)

- Tile grid: 75×43 tiles at 16px = 1200×700 room
- Algorithm: random fill → cellular automata (4 passes) → carve key rooms → carve path → branches
- Key rooms: start (bottom-left), door (top-right), 3-6 branches (dead ends + chests)
- Collision: merged horizontal runs of solid tiles → StaticBody2D (collision_layer = 4)
- Chests: Area2D, touching gives +2 HP
- 4 biome themes cycling every 4 levels

## Lighting

- `CanvasModulate` (global darkness) — gets darker each level
- `PointLight2D` on each torch + on player
- Enemies and portals spawn in dark zones (away from torches)

## Door challenges (per level)

| Level pattern | Challenge | Details |
|---------------|-----------|---------|
| 1, 4, 7... | Lockpick | Level 1 = difficulty 4; others = min(level, 5) |
| 2, 5, 8... | Guardians | 2 spear shieldmen spawn at door, kill both to pass |
| 3, 6, 9... | Crystal | Crystal (3+ HP) spawns, 4 enemies attack it, defend to pass |

## Scaling

- Enemy speed: `30 + level * 5` per level
- Enemy damage: `1 + level/3`, **doubled at level 5+**
- Cave fill_rate: `0.48 + level * 0.006` (tighter passages)
- Guardian/crystal enemies also scale with level

## Known patterns / gotchas

- Enemy `died` signal passes the enemy as argument: `signal died(enemy)`
- Door signal: `signal door_interact(door)`
- Portal signal: `signal skeleton_died(portal)`
- Room `challenge_complete` signal emitted when guardians/crystal challenge done
- Player `heal(amount)` clamps to max_health and emits `health_changed`
- Room `caves` array must be populated before main.gd accesses it in `_load_room()`
- `_draw()` is called once (static room); call `queue_redraw()` only on state change (e.g. chest opens)
- `crystal.gd` extends Node2D, has `take_damage()`, signals `crystal_destroyed`/`crystal_survived`
