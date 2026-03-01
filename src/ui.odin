package main

import "core:math"
import "vendor:sdl2"
import ttf "vendor:sdl2/ttf"
import "core:strings"

// --- UI Constants ---
MINIMAP_SIZE  :: 128
MINIMAP_PAD   :: 10
MINIMAP_X     :: WINDOW_WIDTH - MINIMAP_SIZE - MINIMAP_PAD
MINIMAP_Y     :: WINDOW_HEIGHT - MINIMAP_SIZE - MINIMAP_PAD
MINIMAP_SCALE :: 2 // 1 tile = 2x2 pixels

draw_ui :: proc(ctx: ^CTX) {
	if ctx.current_menu == .Building {
		W :: 150
		H :: 100
		X :: WINDOW_WIDTH - W - 10
		Y :: WINDOW_HEIGHT - H - 150 
		
		ui_rect := sdl2.Rect{x = X, y = Y, w = W, h = H}
		sdl2.SetRenderDrawColor(ctx.renderer, 50, 50, 50, 200)
		sdl2.RenderFillRect(ctx.renderer, &ui_rect)
		sdl2.SetRenderDrawColor(ctx.renderer, 255, 255, 255, 255)
		sdl2.RenderDrawRect(ctx.renderer, &ui_rect)
		
		color := sdl2.Color{255, 255, 255, 255}
		render_text(ctx, "BUILD MENU:", X + 5, Y + 5, color)
		render_text(ctx, "[P] Power Plant", X + 5, Y + 30, color)
		render_text(ctx, "[B] Barracks", X + 5, Y + 55, color)
		render_text(ctx, "[ESC] Cancel", X + 5, Y + 80, color)
	} else if ctx.current_menu == .Barracks {
		W :: 150
		H :: 75
		X :: WINDOW_WIDTH - W - 10
		Y :: WINDOW_HEIGHT - H - 150
		
		ui_rect := sdl2.Rect{x = X, y = Y, w = W, h = H}
		sdl2.SetRenderDrawColor(ctx.renderer, 50, 50, 50, 200)
		sdl2.RenderFillRect(ctx.renderer, &ui_rect)
		sdl2.SetRenderDrawColor(ctx.renderer, 255, 255, 255, 255)
		sdl2.RenderDrawRect(ctx.renderer, &ui_rect)
		
		color := sdl2.Color{255, 255, 255, 255}
		render_text(ctx, "BARRACKS MENU:", X + 5, Y + 5, color)
		render_text(ctx, "[T] Build Tank", X + 5, Y + 30, color)
		render_text(ctx, "[ESC] Close", X + 5, Y + 55, color)
	}
}

draw_selected_box :: proc(ctx: ^CTX, e: ^Entity) {
	sx := ctx.offset_x + i32(e.pos.x)
	sy := ctx.offset_y + i32(e.pos.y)

	// Selection Box
	r := sdl2.Rect{x=sx, y=sy, w=TILE_SIZE, h=TILE_SIZE}
	sdl2.SetRenderDrawColor(ctx.renderer, 0, 255, 0, 255) // Green
	sdl2.RenderDrawRect(ctx.renderer, &r)
	
	// Health Bar
	if e.max_hp > 0 {
		BAR_WIDTH  :: 28
		BAR_HEIGHT :: 4
		OFFSET_Y   :: 2 // Pixels below sprite
		
		bar_x := sx + (TILE_SIZE - BAR_WIDTH) / 2
		bar_y := sy + TILE_SIZE + OFFSET_Y
		
		// Background (Red)
		bg := sdl2.Rect{x=bar_x, y=bar_y, w=BAR_WIDTH, h=BAR_HEIGHT}
		sdl2.SetRenderDrawColor(ctx.renderer, 255, 0, 0, 255)
		sdl2.RenderFillRect(ctx.renderer, &bg)
		
		// Foreground (Green) - based on HP pct
		pct := f32(e.hp) / f32(e.max_hp)
		pct = math.clamp(pct, 0.0, 1.0)
		fg_w := i32(f32(BAR_WIDTH) * pct)
		
		fg := sdl2.Rect{x=bar_x, y=bar_y, w=fg_w, h=BAR_HEIGHT}
		sdl2.SetRenderDrawColor(ctx.renderer, 0, 255, 0, 255)
		sdl2.RenderFillRect(ctx.renderer, &fg)
	}
}

draw_mouse_select_box :: proc(ctx: ^CTX) {
	start_x := ctx.offset_x + i32(ctx.drag_start.x)
	start_y := ctx.offset_y + i32(ctx.drag_start.y)

	curr_x := ctx.offset_x + i32(ctx.current_mouse_pos.x)
	curr_y := ctx.offset_y + i32(ctx.current_mouse_pos.y)

	min_x := min(start_x, curr_x)
	min_y := min(start_y, curr_y)
	w := abs(curr_x - start_x)
	h := abs(curr_y - start_y)

	rect := sdl2.Rect{x=min_x, y=min_y, w=w, h=h}
	sdl2.SetRenderDrawColor(ctx.renderer, 0, 255, 0, 255)
	sdl2.RenderDrawRect(ctx.renderer, &rect)
}

draw_minimap :: proc(ctx: ^CTX) {
	bg_rect := sdl2.Rect{
		x = MINIMAP_X,
		y = MINIMAP_Y,
		w = MINIMAP_SIZE,
		h = MINIMAP_SIZE,
	}
	sdl2.SetRenderDrawColor(ctx.renderer, 0, 0, 0, 255)
	sdl2.RenderFillRect(ctx.renderer, &bg_rect)
	
	for tile in game_map {
		idx := tile.pos.y * MAP_WIDTH + tile.pos.x
		fog := ctx.fog_map[idx]
		if fog == .Hidden { continue }

		r, g, b: u8
		if tile.occupier != nil && (tile.occupier.player == .Player1 || fog == .Visible) {
			switch tile.occupier.player {
			case .Player1:  r, g, b = 0, 0, 255 
			case .Player2:  r, g, b = 255, 0, 0 
			}
		} else {
			switch tile.terrain {
			case .Sand:  r, g, b = 194, 125, 60
			case .Rock:  r, g, b = 80, 80, 80
			case .Spice: r, g, b = 255, 140, 0
			}
			if fog == .Explored { r /= 2; g /= 2; b /= 2; }
		}

		sdl2.SetRenderDrawColor(ctx.renderer, r, g, b, 255)
		pixel_rect := sdl2.Rect{
			x = MINIMAP_X + tile.pos.x * MINIMAP_SCALE,
			y = MINIMAP_Y + tile.pos.y * MINIMAP_SCALE,
			w = MINIMAP_SCALE,
			h = MINIMAP_SCALE,
		}
		sdl2.RenderFillRect(ctx.renderer, &pixel_rect)
	}

	view_x_grid := f32(-ctx.offset_x) / f32(TILE_SIZE)
	view_y_grid := f32(-ctx.offset_y) / f32(TILE_SIZE)
	view_w_grid := f32(WINDOW_WIDTH) / f32(TILE_SIZE)
	view_h_grid := f32(WINDOW_HEIGHT) / f32(TILE_SIZE)
	
	view_rect := sdl2.Rect{
		x = MINIMAP_X + i32(view_x_grid * f32(MINIMAP_SCALE)),
		y = MINIMAP_Y + i32(view_y_grid * f32(MINIMAP_SCALE)),
		w = i32(view_w_grid * f32(MINIMAP_SCALE)),
		h = i32(view_h_grid * f32(MINIMAP_SCALE)),
	}
	
	sdl2.SetRenderDrawColor(ctx.renderer, 255, 255, 255, 255)
	sdl2.RenderDrawRect(ctx.renderer, &view_rect)
}

render_text :: proc(ctx: ^CTX, text: string, x, y: i32, color: sdl2.Color) {
	if ctx.font == nil { return }
	c_text := strings.clone_to_cstring(text, context.temp_allocator)
	surface := ttf.RenderText_Solid(ctx.font, c_text, color)
	if surface != nil {
		texture := sdl2.CreateTextureFromSurface(ctx.renderer, surface)
		if texture != nil {
			w, h: i32
			sdl2.QueryTexture(texture, nil, nil, &w, &h)
			dst := sdl2.Rect{x = x, y = y, w = w, h = h}
			sdl2.RenderCopy(ctx.renderer, texture, nil, &dst)
			sdl2.DestroyTexture(texture)
		}
		sdl2.FreeSurface(surface)
	}
}
