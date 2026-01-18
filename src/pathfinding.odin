package main

import "core:math"
import "core:math/linalg"
import "core:slice"

PathNode :: struct {
	pos:     IVec2,
	g_score: f32,
	f_score: f32,
}

is_traversable :: proc(pos: IVec2) -> bool {
	if pos.x < 0 || pos.x >= MAP_WIDTH || pos.y < 0 || pos.y >= MAP_HEIGHT {
		return false
	}
	idx := pos.y * MAP_WIDTH + pos.x
	tile := game_map[idx]
	
	// Anything occupying a tile makes it untraversable for pathing
	if tile.occupier != nil {
		return false
	}
	
	// Only Sand and Rock are traversable
	if tile.terrain != .Sand && tile.terrain != .Rock {
		return false
	}

	return true
}

find_path :: proc(start, target: IVec2) -> [dynamic]IVec2 {
	if start == target { return nil }
	
	// Basic target validity (bounds and static terrain)
	if target.x < 0 || target.x >= MAP_WIDTH || target.y < 0 || target.y >= MAP_HEIGHT {
		return nil
	}
	target_tile := game_map[target.y * MAP_WIDTH + target.x]
	if target_tile.terrain != .Sand && target_tile.terrain != .Rock { return nil }
	
	// We don't allow pathing onto buildings, but we allow pathing onto units 
	// (so you can command a unit to move to an occupied spot and it gets as close as possible).
	if target_tile.occupier != nil && target_tile.occupier.type == .Building {
		return nil
	}

	open_set := make([dynamic]PathNode)
	closed_set := make(map[IVec2]bool)
	came_from := make(map[IVec2]IVec2)
	g_score := make(map[IVec2]f32)
	
	defer {
		delete(open_set)
		delete(closed_set)
		delete(came_from)
		delete(g_score)
	}

	start_node := PathNode{
		pos = start,
		g_score = 0,
		f_score = heuristic(start, target),
	}
	append(&open_set, start_node)
	g_score[start] = 0

	for len(open_set) > 0 {
		// Find node with lowest f_score
		best_idx := 0
		for i in 1..<len(open_set) {
			if open_set[i].f_score < open_set[best_idx].f_score {
				best_idx = i
			}
		}

		current := open_set[best_idx]
		if current.pos == target {
			// Reconstruct path
			path := make([dynamic]IVec2)
			curr := target
			for curr != start {
				append(&path, curr)
				curr = came_from[curr]
			}
			// Reverse path
			for i := 0; i < len(path) / 2; i += 1 {
				path[i], path[len(path)-1-i] = path[len(path)-1-i], path[i]
			}
			return path
		}

		unordered_remove(&open_set, best_idx)
		closed_set[current.pos] = true

		// Neighbors
		for dx := -1; dx <= 1; dx += 1 {
			for dy := -1; dy <= 1; dy += 1 {
				if dx == 0 && dy == 0 { continue }
				
				neighbor_pos := current.pos + IVec2{i32(dx), i32(dy)}
				
				// Standard traversability check, but allow the final target even if occupied
				if !is_traversable(neighbor_pos) && neighbor_pos != target { continue }
				if neighbor_pos in closed_set { continue }

				// Diagonal movement constraint: 
				// Prevent cutting corners if cardinal neighbors are blocked
				if dx != 0 && dy != 0 {
					cardinal_1 := current.pos + IVec2{i32(dx), 0}
					cardinal_2 := current.pos + IVec2{0, i32(dy)}
					if !is_traversable(cardinal_1) || !is_traversable(cardinal_2) {
						continue
					}
				}

				// Diagonal cost
				cost := f32(1.0)
				if dx != 0 && dy != 0 {
					cost = 1.414
				}

				tentative_g_score := g_score[current.pos] + cost
				
				if neighbor_g, ok := g_score[neighbor_pos]; !ok || tentative_g_score < neighbor_g {
					came_from[neighbor_pos] = current.pos
					g_score[neighbor_pos] = tentative_g_score
					
					f := tentative_g_score + heuristic(neighbor_pos, target)
					
					// Update or add to open set
					found := false
					for i in 0..<len(open_set) {
						if open_set[i].pos == neighbor_pos {
							open_set[i].f_score = f
							found = true
							break
						}
					}
					if !found {
						append(&open_set, PathNode{pos = neighbor_pos, g_score = tentative_g_score, f_score = f})
					}
				}
			}
		}
	}

	return nil
}

heuristic :: proc(a, b: IVec2) -> f32 {
	return f32(math.sqrt(f32((a.x-b.x)*(a.x-b.x) + (a.y-b.y)*(a.y-b.y))))
}
