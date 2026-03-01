package main

import "core:math"
import "core:math/linalg"
import "vendor:sdl2"
import "core:log"
import "core:slice"

Direction :: enum {
	None, Up, UpRight, Right, DownRight, Down, DownLeft, Left, UpLeft,
}

AnimState :: enum {
	Idle, Moving, Attacking,
}

Player :: enum {
	Player1, Player2,
}

EntityType :: enum {
	Unit, Building,
}

UnitClass :: enum {
	Combat_Tank,
}

BuildingClass :: enum {
	None, Power_Plant, Barracks,
}

Entity :: struct {
	player:      Player,
	type:        EntityType,
	unit_class:  UnitClass,
	building_class: BuildingClass,
	pos:         Vec2,
	target_pos:  Vec2,
	tex:         ^sdl2.Texture,
	rotation:    f64,
	base_sprite_pos: IVec2,
	state:       AnimState,
	frame_idx:   int,
	frame_timer: f32,
	anim_speed:  f32,
	current_dir: Direction,
	path:        [dynamic]IVec2,
	sight_radius: int,
	velocity:    Vec2,
	radius:      f32,
	max_speed:   f32,
	stuck_timer: f32,
	is_static:   bool,
	hp:            int,
	max_hp:        int,
	damage:        int,
	attack_range:  f32,
	attack_timer:  f32,
	attack_speed:  f32,
	combat_target: ^Entity,
}

Projectile :: struct {
	owner:   Player,
	pos:     Vec2,
	dir:     Vec2,
	speed:   f32,
	damage:  int,
	active:  bool,
	target:  ^Entity,
}

get_anim_info :: proc(state: AnimState) -> (row_offset: i32, num_frames: int) {
	switch state {
	case .Idle:      return 0, 1
	case .Moving:    return 0, 8
	case .Attacking: return 0, 1
	}
	return 0, 1
}

init_unit_stats :: proc(ctx: ^CTX, e: ^Entity, class: UnitClass) {
	e.unit_class, e.tex, e.base_sprite_pos, e.anim_speed = class, ctx.units_tex, {0,0}, 0.1
	e.hp, e.max_hp, e.damage, e.attack_range, e.attack_speed, e.sight_radius = 100, 100, 10, 150.0, 1.0, 5
	e.radius, e.max_speed, e.is_static = 16.0, 100.0, false
}

spawn_unit :: proc(ctx: ^CTX, x, y: int, player: Player, class: UnitClass = .Combat_Tank) {
	if x < 0 || x >= MAP_WIDTH || y < 0 || y >= MAP_HEIGHT || game_map[y * MAP_WIDTH + x].occupier != nil { return }
	e := new(Entity)
	e.player, e.type, e.pos = player, .Unit, Vec2{f32(x * 32), f32(y * 32)}
	e.target_pos, e.state, e.frame_idx, e.current_dir, e.path, e.velocity = e.pos, .Idle, 0, .Up, make([dynamic]IVec2), {0,0}
	init_unit_stats(ctx, e, class)
	game_map[y * MAP_WIDTH + x].occupier, _ = e, append(&ctx.entities, e)
}

init_building_stats :: proc(ctx: ^CTX, e: ^Entity, class: BuildingClass) {
	e.building_class, e.tex, e.hp, e.max_hp, e.damage, e.attack_range, e.sight_radius, e.radius, e.max_speed, e.is_static = class, ctx.tileset, 500, 500, 0, 0, 6, 16.0, 0.0, true
	switch class {
	case .Power_Plant: e.base_sprite_pos, e.hp, e.max_hp = {12, 0}, 400, 400
	case .Barracks:    e.base_sprite_pos, e.hp, e.max_hp = {12, 2}, 450, 450
	case .None:        e.base_sprite_pos = {0, 0}
	}
}

spawn_building :: proc(ctx: ^CTX, x, y: i32, player: Player, class: BuildingClass = .Power_Plant) {
	if x < 0 || x >= MAP_WIDTH || y < 0 || y >= MAP_HEIGHT || game_map[y * MAP_WIDTH + x].occupier != nil { return }
	e := new(Entity)
	e.player, e.type, e.pos = player, .Building, Vec2{f32(x * 32), f32(y * 32)}
	e.target_pos, e.state, e.frame_idx, e.anim_speed, e.current_dir, e.path = e.pos, .Idle, 0, 0.0, .None, make([dynamic]IVec2)
	init_building_stats(ctx, e, class)
	game_map[y * MAP_WIDTH + x].occupier, _ = e, append(&ctx.entities, e)
	log.infof("Spawned %v at %d, %d", class, x, y)
}

update_entity :: proc(ctx: ^CTX, e: ^Entity, dt: f32) {
	prev_grid_pos := world_to_grid(e.pos)
	if e.combat_target != nil {
		exists := false
		for u in ctx.entities { if u == e.combat_target { exists = true; break } }
		if !exists { e.combat_target = nil } else { e.target_pos = e.combat_target.pos }
	}

	if e.type == .Unit {
		pv, dist := Vec2{0,0}, linalg.distance(e.pos, e.target_pos)
		if e.combat_target != nil && dist <= e.attack_range {
			e.state, e.is_static = .Attacking, true
			if e.attack_timer += dt; e.attack_timer >= e.attack_speed {
				e.attack_timer = 0
				append(&ctx.projectiles, Projectile{e.player, e.pos + 16, linalg.normalize(e.combat_target.pos - e.pos), 300, e.damage, true, e.combat_target})
			}
		} else if dist > 30.0 {
			e.is_static, pv = false, linalg.normalize(e.target_pos - e.pos) * e.max_speed
		} else if len(e.path) > 0 {
			ordered_remove(&e.path, 0)
			if len(e.path) > 0 { e.target_pos = Vec2{f32(e.path[0].x * 32), f32(e.path[0].y * 32)} }
		} else { e.is_static = true }

		for i in 0..<2 { e.velocity = solve_rvo(ctx, e, pv) }
		if linalg.length(e.velocity) < 2.0 { e.velocity = {0,0} }
		if linalg.length(e.velocity) > 5.0 {
			e.state = .Moving
			angle := math.atan2(e.velocity.y, e.velocity.x)
			deg := math.to_degrees(angle) + (angle < 0 ? 360 : 0)
			off :: 22.5
			if deg >= 360 - off || deg < off { e.current_dir = .Right }
			else if deg < 45 + off { e.current_dir = .DownRight }
			else if deg < 90 + off { e.current_dir = .Down }
			else if deg < 135 + off { e.current_dir = .DownLeft }
			else if deg < 180 + off { e.current_dir = .Left }
			else if deg < 225 + off { e.current_dir = .UpLeft }
			else if deg < 270 + off { e.current_dir = .Up }
			else { e.current_dir = .UpRight }
		} else if e.state != .Attacking { e.state = .Idle }

		e.pos += e.velocity * dt
		resolve_collisions(e)
	}

	new_grid_pos := world_to_grid(e.pos)
	if new_grid_pos != prev_grid_pos {
		old_idx := prev_grid_pos.y * MAP_WIDTH + prev_grid_pos.x
		if old_idx >= 0 && old_idx < len(game_map) && game_map[old_idx].occupier == e { game_map[old_idx].occupier = nil }
		new_idx := new_grid_pos.y * MAP_WIDTH + new_grid_pos.x
		if new_idx >= 0 && new_idx < len(game_map) { game_map[new_idx].occupier = e }
	}
	if e.frame_timer += dt; e.frame_timer >= e.anim_speed {
		e.frame_timer = 0
		_, n := get_anim_info(e.state)
		e.frame_idx = (e.frame_idx + 1) % n
	}
}

update_projectiles :: proc(ctx: ^CTX, dt: f32) {
	for i := 0; i < len(ctx.projectiles); {
		p := &ctx.projectiles[i]
		if p.target != nil {
			exists := false
			for u in ctx.entities { if u == p.target { exists = true; break } }
			if exists { p.dir = linalg.normalize(p.target.pos + 16 - p.pos) } else { p.target = nil }
		}
		p.pos += p.dir * p.speed * dt
		hit := false
		if p.target != nil {
			u := p.target
			if linalg.distance(p.pos, u.pos + 16) < 16.0 {
				u.hp -= p.damage
				if u.hp <= 0 {
					gp := world_to_grid(u.pos)
					if idx := gp.y * MAP_WIDTH + gp.x; idx >= 0 && idx < len(game_map) && game_map[idx].occupier == u { game_map[idx].occupier = nil }
					for ex, ei in ctx.entities { if ex == u { unordered_remove(&ctx.entities, ei); break } }
					for sx, si in ctx.selected_entities { if sx == u { unordered_remove(&ctx.selected_entities, si); break } }
					delete(u.path); free(u)
				}
				hit = true
			}
		}
		if hit { unordered_remove(&ctx.projectiles, i) } else { i += 1 }
	}
}

draw_entity :: proc(ctx: ^CTX, entity: ^Entity) {
	gp := world_to_grid(entity.pos)
	if entity.player != .Player1 && ctx.fog_map[gp.y * MAP_WIDTH + gp.x] != .Visible { return }
	sx, sy := ctx.offset_x + i32(entity.pos.x), ctx.offset_y + i32(entity.pos.y)
	dst := sdl2.Rect{sx, sy, 32, 32}
	src_x, src_y: i32
	flip: sdl2.RendererFlip
	if entity.current_dir == .None {
		src_x, src_y = i32(entity.base_sprite_pos.x) * 32, i32(entity.base_sprite_pos.y) * 32
	} else {
		row, f := get_direction_info(entity.current_dir)
		_, nf := get_anim_info(entity.state)
		src_x, src_y, flip = i32(entity.frame_idx % nf) * 32, row * 32, f
	}
	sdl2.SetTextureColorMod(entity.tex, 255, 255, 255)
	if entity.tex != nil { sdl2.RenderCopyEx(ctx.renderer, entity.tex, &sdl2.Rect{src_x, src_y, 32, 32}, &dst, entity.rotation, nil, flip) }
	r, g, b: u8
	switch entity.player {
	case .Player1: r, g, b = 0, 0, 255
	case .Player2: r, g, b = 255, 0, 0
	}
	sdl2.SetRenderDrawColor(ctx.renderer, r, g, b, 255)
	sdl2.RenderFillRect(ctx.renderer, &sdl2.Rect{sx + 2, sy + 2, 4, 4})
}

get_direction_info :: proc(dir: Direction) -> (row: i32, flip: sdl2.RendererFlip) {
	switch dir {
	case .Up:        return 0, .NONE
	case .UpRight:   return 1, .NONE
	case .Right:     return 2, .NONE
	case .DownRight: return 1, .VERTICAL
	case .Down:      return 0, .VERTICAL
	case .DownLeft:  return 1, .VERTICAL + .HORIZONTAL
	case .Left:      return 2, .HORIZONTAL
	case .UpLeft:    return 1, .HORIZONTAL
	case .None:      return 0, .NONE
	}
	return 0, .NONE
}
