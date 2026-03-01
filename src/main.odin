package main

import "core:log"
import "core:math"
import "core:slice"
import "core:strings"
import "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

WINDOW_TITLE  :: "Odin Dune II Clone"
WINDOW_WIDTH  :: 1024
WINDOW_HEIGHT :: 768
TILE_SIZE     :: 32

MenuState :: enum { None, Building, Barracks }

CTX :: struct {
	window:       ^sdl2.Window,
	renderer:     ^sdl2.Renderer,
	font:         ^ttf.Font,
	tileset:      ^sdl2.Texture,
	units_tex:    ^sdl2.Texture,
	selected_entities: [dynamic]^Entity,
	entities:          [dynamic]^Entity,
	projectiles:       [dynamic]Projectile,
	fog_map:           [MAP_WIDTH * MAP_HEIGHT]FogStatus,
	current_menu:      MenuState,
	is_dragging:       bool,
	is_targeting:      bool,
	drag_start:        Vec2,
	current_mouse_pos: Vec2,
	offset_x, offset_y: i32,
	should_close: bool,
	current_fps:  int,
}

init_sdl :: proc(ctx: ^CTX) -> bool {
	if sdl2.Init(sdl2.INIT_VIDEO) < 0 { return false }
	if img.Init(img.INIT_PNG) == nil { return false }
	if ttf.Init() < 0 { return false }
	sdl2.SetHint(sdl2.HINT_RENDER_SCALE_QUALITY, "nearest")
	ctx.window = sdl2.CreateWindow(WINDOW_TITLE, sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED, WINDOW_WIDTH, WINDOW_HEIGHT, sdl2.WINDOW_SHOWN | sdl2.WINDOW_FULLSCREEN_DESKTOP)
	ctx.renderer = sdl2.CreateRenderer(ctx.window, -1, sdl2.RENDERER_ACCELERATED + sdl2.RENDERER_PRESENTVSYNC)
	sdl2.RenderSetLogicalSize(ctx.renderer, WINDOW_WIDTH, WINDOW_HEIGHT)
	return true
}

load_texture :: proc(ctx: ^CTX, path: string) -> ^sdl2.Texture {
	c_path := strings.clone_to_cstring(path, context.temp_allocator)
	tex := img.LoadTexture(ctx.renderer, c_path)
	if tex != nil { sdl2.SetTextureBlendMode(tex, .BLEND) }
	return tex
}

cleanup :: proc(ctx: ^CTX) {
	if ctx.font != nil { ttf.CloseFont(ctx.font) }
	sdl2.DestroyRenderer(ctx.renderer)
	sdl2.DestroyWindow(ctx.window)
	for e in ctx.entities { delete(e.path); free(e) }
	delete(ctx.selected_entities); delete(ctx.entities); delete(ctx.projectiles)
	ttf.Quit(); img.Quit(); sdl2.Quit()
}

dune_ctx := CTX{}

main :: proc() {
	context.logger = log.create_console_logger()
	if !init_sdl(&dune_ctx) { return }
	defer cleanup(&dune_ctx)

	dune_ctx.tileset = load_texture(&dune_ctx, "assets/tileset2_32x32.png")
	dune_ctx.units_tex = load_texture(&dune_ctx, "assets/tank_32x32.png")
	dune_ctx.font = ttf.OpenFont("assets/OpenSans-Regular.ttf", 16) // Added missing font load
	
	init_map(&dune_ctx)
	spawn_unit(&dune_ctx, 10, 10, .Player1); spawn_unit(&dune_ctx, 15, 10, .Player1); spawn_unit(&dune_ctx, 12, 10, .Player2)

	lc := sdl2.GetPerformanceCounter()
	fr, freq := 0, f64(sdl2.GetPerformanceFrequency())
	ta: f64 = 0

	for !dune_ctx.should_close {
		cc := sdl2.GetPerformanceCounter()
		dt := f32(f64(cc - lc) / freq); lc = cc
		fr += 1; ta += f64(dt)
		if ta >= 1.0 { dune_ctx.current_fps, fr, ta = fr, 0, ta - 1.0; log.info("FPS:", dune_ctx.current_fps) }

		handle_events(&dune_ctx); handle_camera(&dune_ctx)
		sdl2.SetRenderDrawColor(dune_ctx.renderer, 0, 0, 0, 255); sdl2.RenderClear(dune_ctx.renderer)
		
		draw_map(&dune_ctx)
		for e in dune_ctx.entities { update_entity(&dune_ctx, e, dt) }
		update_projectiles(&dune_ctx, dt); update_fog(&dune_ctx)
		
		slice.sort_by(dune_ctx.entities[:], proc(i, j: ^Entity) -> bool { return i.pos.y < j.pos.y })
		for e in dune_ctx.entities { draw_entity(&dune_ctx, e) }
		for p in dune_ctx.projectiles {
			r := sdl2.Rect{dune_ctx.offset_x + i32(p.pos.x), dune_ctx.offset_y + i32(p.pos.y), 4, 4}
			sdl2.SetRenderDrawColor(dune_ctx.renderer, 255, 255, 0, 255); sdl2.RenderFillRect(dune_ctx.renderer, &r)
		}
		for e in dune_ctx.selected_entities { draw_selected_box(&dune_ctx, e) }
		if dune_ctx.is_dragging { draw_mouse_select_box(&dune_ctx) }
		draw_ui(&dune_ctx); draw_minimap(&dune_ctx)
		sdl2.RenderPresent(dune_ctx.renderer)
	}
}
