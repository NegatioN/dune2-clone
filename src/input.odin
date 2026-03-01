package main

import "core:math"
import "core:math/linalg"
import "vendor:sdl2"
import "core:log"

handle_events :: proc(ctx: ^CTX) {
	e: sdl2.Event
	for sdl2.PollEvent(&e) {
		#partial switch e.type {
		case .QUIT:
			ctx.should_close = true
		case .KEYDOWN:
			if e.key.keysym.sym == .ESCAPE {
				if ctx.current_menu != .None { ctx.current_menu = .None }
				else if ctx.is_targeting { ctx.is_targeting = false }
				else { ctx.should_close = true }
			} else if ctx.current_menu == .Building {
				gp := world_to_grid(ctx.current_mouse_pos)
				#partial switch e.key.keysym.sym {
				case .P: spawn_building(ctx, gp.x, gp.y, .Player1, .Power_Plant); ctx.current_menu = .None
				case .B: spawn_building(ctx, gp.x, gp.y, .Player1, .Barracks);    ctx.current_menu = .None
				}
			} else if ctx.current_menu == .Barracks {
				if e.key.keysym.sym == .T {
					b: ^Entity
					for s in ctx.selected_entities { if s.type == .Building && s.building_class == .Barracks { b = s; break } }
					if b != nil {
						if sp, ok := find_spawn_pos(world_to_grid(b.pos)); ok { spawn_unit(ctx, int(sp.x), int(sp.y), .Player1) }
					}
				}
			} else if e.key.keysym.sym == .A {
				if len(ctx.selected_entities) > 0 { ctx.is_targeting = true }
			} else if e.key.keysym.sym == .B { ctx.current_menu = .Building }
		case .MOUSEBUTTONDOWN:
			wp := screen_to_world(ctx, e.button.x, e.button.y)
			if ctx.is_targeting {
				if e.button.button == sdl2.BUTTON_LEFT {
					if t := get_entity_at(ctx, wp); t != nil { issue_attack_order(ctx, t) }
					ctx.is_targeting = false
				} else if e.button.button == sdl2.BUTTON_RIGHT { ctx.is_targeting = false }
				return
			}
			if e.button.button == sdl2.BUTTON_LEFT { ctx.is_dragging, ctx.drag_start = true, wp; clear(&ctx.selected_entities) }
			else if e.button.button == sdl2.BUTTON_RIGHT { handle_movement(ctx, world_to_grid(wp)) }
		case .MOUSEBUTTONUP:
			if e.button.button == sdl2.BUTTON_LEFT && ctx.is_dragging {
				ctx.is_dragging = false
				handle_box_selection(ctx, ctx.drag_start, screen_to_world(ctx, e.button.x, e.button.y))
			}
		case .MOUSEMOTION:
			ctx.current_mouse_pos = screen_to_world(ctx, e.motion.x, e.motion.y)
		}
	}
}

handle_camera :: proc(ctx: ^CTX) {
	keys := sdl2.GetKeyboardState(nil)
	if keys[sdl2.Scancode.RIGHT] > 0 { ctx.offset_x -= 8 }
	if keys[sdl2.Scancode.LEFT]  > 0 { ctx.offset_x += 8 }
	if keys[sdl2.Scancode.DOWN]  > 0 { ctx.offset_y -= 8 }
	if keys[sdl2.Scancode.UP]    > 0 { ctx.offset_y += 8 }
	ctx.offset_x = math.clamp(ctx.offset_x, -(i32(MAP_WIDTH) * 32 - 800), 0)
	ctx.offset_y = math.clamp(ctx.offset_y, -(i32(MAP_HEIGHT) * 32 - 600), 0)
}

find_spawn_pos :: proc(bg: IVec2) -> (IVec2, bool) {
	for r in 1..=3 {
		for dy := -r; dy <= r; dy += 1 {
			for dx := -r; dx <= r; dx += 1 {
				if abs(dx) != r && abs(dy) != r { continue }
				t := bg + {i32(dx), i32(dy)}
				if t.x >= 0 && t.x < MAP_WIDTH && t.y >= 0 && t.y < MAP_HEIGHT {
					if is_traversable(t) && game_map[t.y * MAP_WIDTH + t.x].occupier == nil { return t, true }
				}
			}
		}
	}
	return {0,0}, false
}

get_entity_at :: proc(ctx: ^CTX, wp: Vec2) -> ^Entity {
	p := sdl2.Point{i32(wp.x), i32(wp.y)}
	for u in ctx.entities {
		if sdl2.PointInRect(&p, &sdl2.Rect{i32(u.pos.x), i32(u.pos.y), 32, 32}) { return u }
	}
	return nil
}

issue_attack_order :: proc(ctx: ^CTX, t: ^Entity) {
	for u in ctx.selected_entities {
		if u != t && u.player != t.player { u.combat_target, u.is_static = t, false; clear(&u.path) }
	}
}

handle_single_selection :: proc(ctx: ^CTX, wp: Vec2) {
	if u := get_entity_at(ctx, wp); u != nil {
		append(&ctx.selected_entities, u)
		ctx.current_menu = (u.type == .Building && u.building_class == .Barracks) ? .Barracks : .None
	} else { ctx.current_menu = .None }
}

handle_box_selection :: proc(ctx: ^CTX, s, e: Vec2) {
	mx, mx2, my, my2 := math.min(s.x, e.x), math.max(s.x, e.x), math.min(s.y, e.y), math.max(s.y, e.y)
	if mx2 - mx < 2 && my2 - my < 2 { handle_single_selection(ctx, s); return }
	ctx.current_menu = .None
	for u in ctx.entities {
		c := u.pos + 16
		if c.x >= mx && c.x <= mx2 && c.y >= my && c.y <= my2 { append(&ctx.selected_entities, u) }
	}
}

handle_movement :: proc(ctx: ^CTX, gp: IVec2) {
	for u in ctx.selected_entities {
		if u.type == .Building { continue }
		if p := find_path(world_to_grid(u.pos), gp); p != nil {
			delete(u.path); u.path, u.target_pos, u.combat_target, u.is_static = p, Vec2{f32(p[0].x * 32), f32(p[0].y * 32)}, nil, false
		}
	}
}
