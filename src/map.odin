package main

import "core:math"
import "vendor:sdl2"
import "core:os"
import "core:log"

TerrainType :: enum {
	Sand,
	Rock,
	Spice,
}

FogStatus :: enum u8 {
	Hidden,
	Explored,
	Visible,
}

Tile :: struct {
	terrain:  TerrainType,
	tile_id:  int,      // Index in the tileset texture (Column N)
	occupier: ^Entity,
	pos: IVec2
}

// Global Map Data
MAP_WIDTH  :: 64
MAP_HEIGHT :: 64
game_map: [MAP_WIDTH * MAP_HEIGHT]Tile

init_map :: proc(ctx: ^CTX) {
	data, ok := os.read_entire_file("assets/level.dat")
	if !ok {
		log.error("Failed to load assets/level.dat")
		return
	}
	defer delete(data)

	x, y := 0, 0
	for b in data {
		if b == '\n' || b == '\r' {
			if x > 0 {
				y += 1
				x = 0
			}
			continue
		}
		if x >= MAP_WIDTH || y >= MAP_HEIGHT { continue }

		tile_idx := int(b) - 49
		if tile_idx < 0 { tile_idx = 0 }

		idx := y * MAP_WIDTH + x
		game_map[idx].tile_id = tile_idx
		game_map[idx].pos = {i32(x), i32(y)}
		
		if tile_idx == 0 { game_map[idx].terrain = .Sand }
		else { game_map[idx].terrain = .Rock }

		x += 1
	}
	log.info("Map loaded successfully.")
}

draw_map :: proc(ctx: ^CTX) {
	if ctx.tileset == nil { return }

	SRC_SIZE :: 32
	for tile in game_map {
		src := sdl2.Rect{
			x = i32(tile.tile_id) * SRC_SIZE,
			y = 0,
			w = SRC_SIZE,
			h = SRC_SIZE,
		}

		dst_x, dst_y := grid_to_screen(ctx, tile.pos.x, tile.pos.y)
		dst := sdl2.Rect{x = dst_x, y = dst_y, w = TILE_SIZE, h = TILE_SIZE}

		idx := tile.pos.y * MAP_WIDTH + tile.pos.x
		fog := ctx.fog_map[idx]
		
		if fog == .Hidden {
			sdl2.SetRenderDrawColor(ctx.renderer, 0, 0, 0, 255)
			sdl2.RenderFillRect(ctx.renderer, &dst)
		} else {
			if fog == .Explored {
				sdl2.SetTextureColorMod(ctx.tileset, 100, 100, 100)
			} else {
				sdl2.SetTextureColorMod(ctx.tileset, 255, 255, 255)
			}
			sdl2.RenderCopy(ctx.renderer, ctx.tileset, &src, &dst)
		}
	}
}

update_fog :: proc(ctx: ^CTX) {
	for i in 0..<len(ctx.fog_map) {
		if ctx.fog_map[i] == .Visible { ctx.fog_map[i] = .Explored }
	}

	for e in ctx.entities {
		if e.player != .Player1 { continue }
		grid_pos := world_to_grid(e.pos)
		radius := e.sight_radius
		for dy := -radius; dy <= radius; dy += 1 {
			for dx := -radius; dx <= radius; dx += 1 {
				if dx*dx + dy*dy <= radius*radius {
					tx, ty := grid_pos.x + i32(dx), grid_pos.y + i32(dy)
					if tx >= 0 && tx < MAP_WIDTH && ty >= 0 && ty < MAP_HEIGHT {
						ctx.fog_map[ty * MAP_WIDTH + tx] = .Visible
					}
				}
			}
		}
	}
}
