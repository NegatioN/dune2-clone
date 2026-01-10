package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:os"
import "core:strings"
import "vendor:sdl2"
import img "vendor:sdl2/image"
import ttf "vendor:sdl2/ttf"

// --- Constants ---
WINDOW_TITLE  :: "Odin Dune II Clone"
WINDOW_WIDTH  :: i32(800)
WINDOW_HEIGHT :: i32(600)
TILE_SIZE     :: 32

// --- Core Types ---

Vec2  :: [2]f32
IVec2 :: [2]int

Direction :: enum {
	None,
	Up,
	Down,
	Left,
	Right,
}

AnimState :: enum {
	Idle,
	Moving,
	Attacking,
}

TerrainType :: enum {
	Sand,
	Rock,
	Spice,
}

Tile :: struct {
	terrain:  TerrainType,
	occupier: ^Entity, // The unit currently on this tile (Dune II rule: 1 unit per tile)
}

// Global Map Data
MAP_WIDTH  :: 64
MAP_HEIGHT :: 64
game_map: [MAP_WIDTH * MAP_HEIGHT]Tile

// Generic Entity
Entity :: struct {
	// Spatial
	pos:         Vec2,     // World position (pixels)
	target_pos:  Vec2,     // Target world position
	
	// Visuals
	tex:         ^sdl2.Texture,
	rotation:    f64,
	
	// Animation
	state:       AnimState,
	frame_idx:   int,
	frame_timer: f32,
	anim_speed:  f32,      // Seconds per frame
	
	// Game Logic
	current_dir: Direction,
}

get_anim_info :: proc(state: AnimState) -> (row: i32, num_frames: int) {
	switch state {
	case .Idle:      return 0, 1
	case .Moving:    return 1, 4
	case .Attacking: return 2, 2
	}
	return 0, 1
}

// Game Context
CTX :: struct {
	window:       ^sdl2.Window,
	renderer:     ^sdl2.Renderer,
	font:         ^ttf.Font,
	
	// Map Data
	map_width:    int,
	map_height:   int,
	offset_x:     i32,
	offset_y:     i32,
	
	// Game State
	should_close: bool,
	current_fps:  int,
}

// --- Initialization ---

init_sdl :: proc(ctx: ^CTX) -> bool {
	if sdl2.Init(sdl2.INIT_VIDEO) < 0 {
		log.errorf("SDL2 Init failed: %s", sdl2.GetError())
		return false
	}

	init_flags := img.Init(img.INIT_PNG | img.INIT_JPG)
	if .PNG not_in init_flags {
		log.errorf("SDL2 Image Init failed: %s", sdl2.GetError())
		return false
	}

	if ttf.Init() < 0 {
		log.errorf("SDL2 TTF Init failed: %s", sdl2.GetError())
		return false
	}

	ctx.window = sdl2.CreateWindow(WINDOW_TITLE,
		sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED,
		WINDOW_WIDTH, WINDOW_HEIGHT, sdl2.WINDOW_SHOWN)
	if ctx.window == nil {
		log.errorf("Window creation failed: %s", sdl2.GetError())
		return false
	}

	// Enable VSync for smooth rendering
	ctx.renderer = sdl2.CreateRenderer(ctx.window, -1, sdl2.RENDERER_ACCELERATED + sdl2.RENDERER_PRESENTVSYNC)
	if ctx.renderer == nil {
		log.errorf("Renderer creation failed: %s", sdl2.GetError())
		return false
	}

	return true
}

load_texture :: proc(ctx: ^CTX, path: string) -> ^sdl2.Texture {
	c_path := strings.clone_to_cstring(path, context.temp_allocator)
	tex := img.LoadTexture(ctx.renderer, c_path)
	if tex == nil {
		log.errorf("Failed to load texture %s: %s", path, sdl2.GetError())
	}
	return tex
}

load_font :: proc(ctx: ^CTX, path: string, size: i32) -> bool {
	c_path := strings.clone_to_cstring(path, context.temp_allocator)
	ctx.font = ttf.OpenFont(c_path, size)
	if ctx.font == nil {
		log.errorf("Failed to load font %s: %s", path, sdl2.GetError())
		return false
	}
	return true
}

cleanup :: proc(ctx: ^CTX) {
	if ctx.font != nil {
		ttf.CloseFont(ctx.font)
	}
	if ctx.renderer != nil {
		sdl2.DestroyRenderer(ctx.renderer)
	}
	if ctx.window != nil {
		sdl2.DestroyWindow(ctx.window)
	}
	ttf.Quit()
	img.Quit()
	sdl2.Quit()
}

// --- Utilities ---

grid_to_screen :: proc(ctx: ^CTX, gx, gy: int) -> (x, y: i32) {
	return ctx.offset_x + i32(gx) * TILE_SIZE, ctx.offset_y + i32(gy) * TILE_SIZE
}

draw_entity :: proc(ctx: ^CTX, entity: ^Entity) {
	// 1. Calculate Destination Rect (Screen Space)
	screen_x := ctx.offset_x + i32(entity.pos.x)
	screen_y := ctx.offset_y + i32(entity.pos.y)

	dst := sdl2.Rect{x = screen_x, y = screen_y, w = TILE_SIZE, h = TILE_SIZE}
	
	// 2. Calculate Source Rect (Animation Frame)
	row, _ := get_anim_info(entity.state)
	src_x := i32(entity.frame_idx) * TILE_SIZE
	src_y := row * TILE_SIZE
	
	src := sdl2.Rect{x = src_x, y = src_y, w = TILE_SIZE, h = TILE_SIZE}

	// 3. Draw
	sdl2.SetTextureColorMod(entity.tex, 255, 255, 255)
	
	// If texture is nil, we might want to draw a debug rect, but for now assuming valid texture
	if entity.tex != nil {
		sdl2.RenderCopyEx(ctx.renderer, entity.tex, &src, &dst, entity.rotation, nil, .NONE)
	} else {
		// Fallback debug draw
		sdl2.SetRenderDrawColor(ctx.renderer, 255, 0, 0, 255)
		sdl2.RenderDrawRect(ctx.renderer, &dst)
	}
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

// --- Main Loop ---

dune_ctx := CTX{}

main :: proc() {
	context.logger = log.create_console_logger()

	if !init_sdl(&dune_ctx) { return }
	defer cleanup(&dune_ctx)

	last_count := sdl2.GetPerformanceCounter()
	freq := sdl2.GetPerformanceFrequency()
	
	frame_counter := 0
	time_accumulator: f64 = 0

	for !dune_ctx.should_close {
		current_count := sdl2.GetPerformanceCounter()
		dt_raw := f64(current_count - last_count) / f64(freq)
		last_count = current_count
		// dt := f32(dt_raw)
		
		// FPS Counter logic
		frame_counter += 1
		time_accumulator += dt_raw
		if time_accumulator >= 1.0 {
			dune_ctx.current_fps = frame_counter
			frame_counter = 0
			time_accumulator -= 1.0
			log.info("FPS:", dune_ctx.current_fps)
		}

		// Basic Input Processing
		e: sdl2.Event
		for sdl2.PollEvent(&e) {
			#partial switch e.type {
			case .QUIT:
				dune_ctx.should_close = true
			case .KEYDOWN:
				if e.key.keysym.sym == .ESCAPE {
					dune_ctx.should_close = true
				}
			}
		}

		// Clear Screen (Dune 2 sand color-ish?)
		sdl2.SetRenderDrawColor(dune_ctx.renderer, 194, 125, 60, 255)
		sdl2.RenderClear(dune_ctx.renderer)
		sdl2.RenderPresent(dune_ctx.renderer)
	}
}
