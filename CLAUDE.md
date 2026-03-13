# Dungeon Roguelike — Godot 4.2

2D pixel roguelike, side-view (platformer), castle/cave dungeon setting.
All graphics are drawn **programmatically via `_draw()`** — no sprite assets.

## Project structure

```
scenes/       — .tscn scene files (player, enemy, lockpick_minigame, main)
scripts/      — GDScript logic
  main.gd         — game manager: creates player, room, camera, darkness, HUD
  player.gd       — player controller
  room.gd         — cave generation + enemy/portal/chest/torch spawning
  enemy.gd        — 4 enemy classes
  skeleton_portal.gd — Portal Eye Monster
  projectile.gd   — arrow, bolt, hammer, grenade
  torch.gd        — PointLight2D torch with flicker
  door.gd         — locked door with [E] interact
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

## Known patterns / gotchas

- Enemy `died` signal passes the enemy as argument: `signal died(enemy)`
- Door signal: `signal door_interact(door)`
- Portal signal: `signal skeleton_died(portal)`
- Player `heal(amount)` clamps to max_health and emits `health_changed`
- Room `caves` array must be populated before main.gd accesses it in `_load_room()`
- `_draw()` is called once (static room); call `queue_redraw()` only on state change (e.g. chest opens)
