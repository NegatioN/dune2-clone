package main

import "core:math"
import "core:math/linalg"

PathNode :: struct { pos: IVec2, g_score, f_score: f32 }

is_traversable :: proc(pos: IVec2) -> bool {
	if pos.x < 0 || pos.x >= MAP_WIDTH || pos.y < 0 || pos.y >= MAP_HEIGHT { return false }
	tile := game_map[pos.y * MAP_WIDTH + pos.x]
	return (tile.occupier == nil || tile.occupier.type != .Building) && (tile.terrain == .Sand || tile.terrain == .Rock)
}

find_path :: proc(start, target: IVec2) -> [dynamic]IVec2 {
	if start == target || !is_traversable(target) { return nil }
	open_set := make([dynamic]PathNode); defer delete(open_set)
	came_from := make(map[IVec2]IVec2); defer delete(came_from)
	g_score := make(map[IVec2]f32); defer delete(g_score)
	append(&open_set, PathNode{start, 0, heuristic(start, target)})
	g_score[start] = 0

	for len(open_set) > 0 {
		best_idx := 0
		for i in 1..<len(open_set) { if open_set[i].f_score < open_set[best_idx].f_score { best_idx = i } }
		curr := open_set[best_idx]
		if curr.pos == target {
			path := make([dynamic]IVec2)
			for p := target; p != start; p = came_from[p] { append(&path, p) }
			for i in 0..<len(path)/2 { path[i], path[len(path)-1-i] = path[len(path)-1-i], path[i] }
			return path
		}
		unordered_remove(&open_set, best_idx)
		for dx := -1; dx <= 1; dx += 1 {
			for dy := -1; dy <= 1; dy += 1 {
				if (dx == 0 && dy == 0) || (dx != 0 && dy != 0 && (!is_traversable(curr.pos + {i32(dx), 0}) || !is_traversable(curr.pos + {0, i32(dy)}))) { continue }
				np := curr.pos + {i32(dx), i32(dy)}
				if (!is_traversable(np) && np != target) { continue }
				tg := g_score[curr.pos] + (dx != 0 && dy != 0 ? 1.414 : 1.0)
				if g, ok := g_score[np]; !ok || tg < g {
					came_from[np], g_score[np] = curr.pos, tg
					append(&open_set, PathNode{np, tg, tg + heuristic(np, target)})
				}
			}
		}
	}
	return nil
}

heuristic :: proc(a, b: IVec2) -> f32 { return linalg.length(Vec2{f32(a.x-b.x), f32(a.y-b.y)}) }

// --- RVO / Mini-ORCA ---

solve_rvo :: proc(ctx: ^CTX, e: ^Entity, pref_v: Vec2) -> Vec2 {
	best_v, best_s := Vec2{0,0}, score_v(ctx, e, {0,0}, pref_v)
	for i in 0..<24 {
		ang := f32(i) * (math.PI * 2.0 / 24.0)
		for mag in ([3]f32{1.0, 0.5, 0.25} * e.max_speed) {
			v := Vec2{math.cos(ang), math.sin(ang)} * mag
			if s := score_v(ctx, e, v, pref_v); s > best_s { best_v, best_s = v, s }
		}
	}
	return best_v
}

score_v :: proc(ctx: ^CTX, e: ^Entity, v, pref_v: Vec2) -> f32 {
	score := -linalg.distance(v, pref_v) - (linalg.length(pref_v) < 0.1 ? linalg.length(v) * 2.0 : 0)
	gp := world_to_grid(e.pos)
	for dy := -1; dy <= 1; dy += 1 {
		for dx := -1; dx <= 1; dx += 1 {
			o := game_map[math.clamp(gp.y+i32(dy), 0, MAP_HEIGHT-1) * MAP_WIDTH + math.clamp(gp.x+i32(dx), 0, MAP_WIDTH-1)].occupier
			if o == nil || o == e { continue }
			rp, rv, rad := o.pos - e.pos, v - (o.velocity + (o.is_static ? 0 : 0.5) * (e.velocity - o.velocity)), e.radius + o.radius
			d := linalg.length(rp)
			if d < rad - 2.0 { 
				score -= 20000.0 - linalg.dot(v, linalg.normalize(e.pos - o.pos)) * 100.0
				continue 
			}
			a, b, c := linalg.dot(rv, rv), -2.0 * linalg.dot(rp, rv), linalg.dot(rp, rp) - rad*rad
			if a > 0.001 && b*b - 4*a*c > 0 {
				if t := (-b - math.sqrt(b*b - 4*a*c)) / (2.0 * a); t > 0 && t < 2.0 { score -= (2.0 - t) * 2000.0 }
			}
			if rp.x * rv.y - rp.y * rv.x < 0 { score += 5.0 }
		}
	}
	return score
}

resolve_collisions :: proc(e: ^Entity) {
	gp := world_to_grid(e.pos)
	for dy := -1; dy <= 1; dy += 1 {
		for dx := -1; dx <= 1; dx += 1 {
			o := game_map[math.clamp(gp.y+i32(dy), 0, MAP_HEIGHT-1) * MAP_WIDTH + math.clamp(gp.x+i32(dx), 0, MAP_WIDTH-1)].occupier
			if o == nil || o == e { continue }
			if d := linalg.distance(e.pos, o.pos); d < e.radius + o.radius {
				dir := d > 0.01 ? linalg.normalize(e.pos - o.pos) : Vec2{math.cos(f32(uintptr(e))), math.sin(f32(uintptr(e)))}
				e.pos += dir * (e.radius + o.radius - d) * (o.is_static ? 1.0 : 0.5)
			}
		}
	}
}
