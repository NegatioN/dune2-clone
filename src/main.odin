package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
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

MINIMAP_SIZE  :: 128
MINIMAP_PAD   :: 10
MINIMAP_X     :: WINDOW_WIDTH - MINIMAP_SIZE - MINIMAP_PAD
MINIMAP_Y     :: WINDOW_HEIGHT - MINIMAP_SIZE - MINIMAP_PAD
MINIMAP_SCALE :: 2 // 1 tile = 2x2 pixels

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
	tile_id:  int,      // Index in the tileset texture (Column N)
	occupier: ^Entity,
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
	base_sprite_pos: IVec2, // Base coordinate in tileset (e.g. {7, 11} for Tank)
	
	// Animation
	state:       AnimState,
	frame_idx:   int,
	frame_timer: f32,
	anim_speed:  f32,      // Seconds per frame
	
	// Game Logic
	current_dir: Direction,
}

get_anim_info :: proc(state: AnimState) -> (row_offset: i32, num_frames: int) {
	// Simple offset from base position
	switch state {
	case .Idle:      return 0, 1
	case .Moving:    return 0, 1 // For now, reuse idle frame as we don't know moving frames layout
	case .Attacking: return 0, 1
	}
	return 0, 1
}

// Game Context
CTX :: struct {
	window:       ^sdl2.Window,
	renderer:     ^sdl2.Renderer,
	font:         ^ttf.Font,
	tileset:      ^sdl2.Texture,
	units_tex:    ^sdl2.Texture, // New texture for units
	
	// Game Logic
	selected_entity: ^Entity,
	
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
// ... (rest of init_sdl is same) ...

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

// --- Map Logic ---

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
			if x > 0 { // Only advance Y if we actually read a line
				y += 1
				x = 0
			}
			continue
		}
		
		if x >= MAP_WIDTH || y >= MAP_HEIGHT { continue }

		// '1' (49) -> Index 0
		// '2' (50) -> Index 1
		tile_idx := int(b) - 49
		if tile_idx < 0 { tile_idx = 0 }

		idx := y * MAP_WIDTH + x
		game_map[idx].tile_id = tile_idx
		
		// Set logical terrain type based on visual index (simplified mapping)
		if tile_idx == 0 { game_map[idx].terrain = .Sand }
		else { game_map[idx].terrain = .Rock }

		x += 1
	}
	log.info("Map loaded successfully.")
}

draw_map :: proc(ctx: ^CTX) {
	if ctx.tileset == nil { return }

	// Only draw visible tiles
	start_x := (-ctx.offset_x) / TILE_SIZE
	start_y := (-ctx.offset_y) / TILE_SIZE
	end_x   := start_x + (WINDOW_WIDTH / TILE_SIZE) + 1
	end_y   := start_y + (WINDOW_HEIGHT / TILE_SIZE) + 1

	// Clamp to map bounds
	start_x = math.clamp(start_x, 0, MAP_WIDTH)
	start_y = math.clamp(start_y, 0, MAP_HEIGHT)
	end_x   = math.clamp(end_x,   0, MAP_WIDTH)
	end_y   = math.clamp(end_y,   0, MAP_HEIGHT)

	SRC_SIZE    :: 32
	SRC_PADDING :: 0

	for y in start_y..<end_y {
		for x in start_x..<end_x {
			tile := &game_map[y * MAP_WIDTH + x]
			
			// Calculate Source Rect from Tile Index
			// Row 0, Column N
			src_x := i32(tile.tile_id) * (SRC_SIZE + SRC_PADDING)
			src_y := i32(0) // Specified as Row 0

			src := sdl2.Rect{
				x = src_x,
				y = src_y,
				w = SRC_SIZE,
				h = SRC_SIZE,
			}

			// Destination Rect (Screen Space)
			dst_x, dst_y := grid_to_screen(ctx, int(x), int(y))
			dst := sdl2.Rect{
				x = dst_x,
				y = dst_y,
				w = TILE_SIZE,
				h = TILE_SIZE,
			}

			sdl2.RenderCopy(ctx.renderer, ctx.tileset, &src, &dst)
		}
	}
}

// --- Entities ---

spawn_unit :: proc(ctx: ^CTX, x, y: int) {
	if x < 0 || x >= MAP_WIDTH || y < 0 || y >= MAP_HEIGHT { return }
	
	idx := y * MAP_WIDTH + x
	if game_map[idx].occupier != nil { return } // Tile occupied

	e := new(Entity)
	e.pos = Vec2{f32(x * TILE_SIZE), f32(y * TILE_SIZE)}
	e.target_pos = e.pos
	e.tex = ctx.tileset // Using the same texture
	e.base_sprite_pos = IVec2{11, 7} // Trying inverted coordinates to fit bounds
	e.state = .Idle
	e.frame_idx = 0
	e.anim_speed = 0.1
	e.current_dir = .Up
	
	game_map[idx].occupier = e
}

update_entity :: proc(e: ^Entity, dt: f32) {
	// Simple movement logic: Lerp towards target
	SPEED :: 100.0 // Pixels per second
	
	dist := linalg.distance(e.pos, e.target_pos)
	if dist > 1.0 {
		e.state = .Moving
		dir := e.target_pos - e.pos
		dir = linalg.normalize(dir)
		e.pos += dir * SPEED * dt
		
		// Update logic grid position (ownership) - Simplified
		// curr_grid := world_to_grid(e.pos)
	} else {
		e.pos = e.target_pos
		e.state = .Idle
	}
	
	// Animation Tick
	e.frame_timer += dt
	if e.frame_timer >= e.anim_speed {
		e.frame_timer = 0
		_, num_frames := get_anim_info(e.state)
		e.frame_idx = (e.frame_idx + 1) % num_frames
	}
}

// --- Utilities ---

screen_to_world :: proc(ctx: ^CTX, screen_x, screen_y: i32) -> Vec2 {
	return Vec2{f32(screen_x - ctx.offset_x), f32(screen_y - ctx.offset_y)}
}

world_to_grid :: proc(world_pos: Vec2) -> IVec2 {
	return IVec2{int(world_pos.x) / TILE_SIZE, int(world_pos.y) / TILE_SIZE}
}

grid_to_screen :: proc(ctx: ^CTX, gx, gy: int) -> (x, y: i32) {
	return ctx.offset_x + i32(gx) * TILE_SIZE, ctx.offset_y + i32(gy) * TILE_SIZE
}

draw_entity :: proc(ctx: ^CTX, entity: ^Entity) {
	// 1. Calculate Destination Rect (Screen Space)
	screen_x := ctx.offset_x + i32(entity.pos.x)
	screen_y := ctx.offset_y + i32(entity.pos.y)

	dst := sdl2.Rect{x = screen_x, y = screen_y, w = TILE_SIZE, h = TILE_SIZE}
	
	// 2. Calculate Source Rect (Animation Frame)
	row_offset, _ := get_anim_info(entity.state)
	
	// Base X + Animation Frame Offset
	src_x := i32(entity.base_sprite_pos.x) * TILE_SIZE + i32(entity.frame_idx) * TILE_SIZE
	
	// Base Y + Animation State Row Offset
	src_y := (i32(entity.base_sprite_pos.y) + row_offset) * TILE_SIZE
	
	src := sdl2.Rect{x = src_x, y = src_y, w = TILE_SIZE, h = TILE_SIZE}

	// 3. Draw
	sdl2.SetTextureColorMod(entity.tex, 255, 255, 255)
	
	// If texture is nil, we might want to draw a debug rect, but for now assuming valid texture
	if entity.tex != nil {
		sdl2.RenderCopyEx(ctx.renderer, entity.tex, &src, &dst, entity.rotation, nil, .NONE)
	}
	
	// DEBUG: Draw Red Box outline to verify position
	sdl2.SetRenderDrawColor(ctx.renderer, 255, 0, 0, 255)
	sdl2.RenderDrawRect(ctx.renderer, &dst)
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

	// Load Assets
	dune_ctx.tileset = load_texture(&dune_ctx, "assets/tileset2_32x32.png")
	if dune_ctx.tileset == nil { return }
	dune_ctx.units_tex = dune_ctx.tileset
	
	// Init Map
	init_map(&dune_ctx)
	
	// Spawn Test Unit
	spawn_unit(&dune_ctx, 10, 10)

	last_count := sdl2.GetPerformanceCounter()
	freq := sdl2.GetPerformanceFrequency()
	
	frame_counter := 0
	time_accumulator: f64 = 0

	for !dune_ctx.should_close {
		current_count := sdl2.GetPerformanceCounter()
		dt_raw := f64(current_count - last_count) / f64(freq)
		last_count = current_count
		dt := f32(dt_raw)
		
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
			case .MOUSEBUTTONDOWN:
				world_pos := screen_to_world(&dune_ctx, e.button.x, e.button.y)
				grid_pos := world_to_grid(world_pos)
				
				if e.button.button == sdl2.BUTTON_LEFT {
					// Selection Logic
					if grid_pos.x >= 0 && grid_pos.x < MAP_WIDTH && grid_pos.y >= 0 && grid_pos.y < MAP_HEIGHT {
						tile := &game_map[grid_pos.y * MAP_WIDTH + grid_pos.x]
						if tile.occupier != nil {
							dune_ctx.selected_entity = tile.occupier
							log.info("Selected Unit at", grid_pos)
						} else {
							dune_ctx.selected_entity = nil
						}
					}
				} else if e.button.button == sdl2.BUTTON_RIGHT {
					// Movement Logic
					if dune_ctx.selected_entity != nil {
						dune_ctx.selected_entity.target_pos = Vec2{f32(grid_pos.x * TILE_SIZE), f32(grid_pos.y * TILE_SIZE)}
					}
				}
			}
		}

		// Camera Panning (Arrow Keys)
		keys := sdl2.GetKeyboardState(nil)
		PAN_SPEED :: 8

		if keys[sdl2.Scancode.RIGHT] > 0 {
			dune_ctx.offset_x -= PAN_SPEED
		}
		if keys[sdl2.Scancode.LEFT] > 0 {
			dune_ctx.offset_x += PAN_SPEED
		}
		if keys[sdl2.Scancode.DOWN] > 0 {
			dune_ctx.offset_y -= PAN_SPEED
		}
		if keys[sdl2.Scancode.UP] > 0 {
			dune_ctx.offset_y += PAN_SPEED
		}

		// Clamp Camera
		min_offset_x := -(i32(MAP_WIDTH) * TILE_SIZE - WINDOW_WIDTH)
		min_offset_y := -(i32(MAP_HEIGHT) * TILE_SIZE - WINDOW_HEIGHT)

		dune_ctx.offset_x = math.clamp(dune_ctx.offset_x, min_offset_x, 0)
		dune_ctx.offset_y = math.clamp(dune_ctx.offset_y, min_offset_y, 0)

		// Clear Screen
		sdl2.SetRenderDrawColor(dune_ctx.renderer, 0, 0, 0, 255)
		sdl2.RenderClear(dune_ctx.renderer)
		
		draw_map(&dune_ctx)
		
		// Draw Entities
		for i in 0..<len(game_map) {
			if game_map[i].occupier != nil {
				e := game_map[i].occupier
				
				// Update & Draw
				update_entity(e, dt)
				draw_entity(&dune_ctx, e)
				
				// Selection Box
				if e == dune_ctx.selected_entity {
					sx := dune_ctx.offset_x + i32(e.pos.x)
					sy := dune_ctx.offset_y + i32(e.pos.y)
					
					// Draw slightly larger box
					r := sdl2.Rect{x=sx, y=sy, w=TILE_SIZE, h=TILE_SIZE}
					sdl2.SetRenderDrawColor(dune_ctx.renderer, 0, 255, 0, 255) // Green
					sdl2.RenderDrawRect(dune_ctx.renderer, &r)
				}
			}
		}
		
		draw_minimap(&dune_ctx)
		
		sdl2.RenderPresent(dune_ctx.renderer)
	}
}

// --- Minimap ---

draw_minimap :: proc(ctx: ^CTX) {
	// 1. Draw Background
	bg_rect := sdl2.Rect{
		x = MINIMAP_X,
		y = MINIMAP_Y,
		w = MINIMAP_SIZE,
		h = MINIMAP_SIZE,
	}
	sdl2.SetRenderDrawColor(ctx.renderer, 0, 0, 0, 255)
	sdl2.RenderFillRect(ctx.renderer, &bg_rect)
	
	// 2. Draw Terrain & Units (Simplified)
	// For loop over map data could go here.
	// Since we don't initialize the map with data yet, this will just be black.
	// But let's verify bounds: 64 tiles * 2 scale = 128 pixels. Perfect fit.
	
	for y in 0..<MAP_HEIGHT {
		for x in 0..<MAP_WIDTH {
			tile := game_map[y * MAP_WIDTH + x]
			
			// Color based on terrain or unit
			r, g, b: u8
			if tile.occupier != nil {
				r, g, b = 0, 0, 255 // Blue for units
			} else {
				switch tile.terrain {
				case .Sand:  r, g, b = 194, 125, 60
				case .Rock:  r, g, b = 80, 80, 80
				case .Spice: r, g, b = 255, 140, 0
				}
			}
			
			sdl2.SetRenderDrawColor(ctx.renderer, r, g, b, 255)
			pixel_rect := sdl2.Rect{
				x = MINIMAP_X + i32(x) * MINIMAP_SCALE,
				y = MINIMAP_Y + i32(y) * MINIMAP_SCALE,
				w = MINIMAP_SCALE,
				h = MINIMAP_SCALE,
			}
			sdl2.RenderFillRect(ctx.renderer, &pixel_rect)
		}
	}
	
	// 3. Draw Viewport Rect
	// Camera offset is typically negative (moving right means offset becomes negative).
	// Viewport X on Map (Tiles) = (-offset_x) / TILE_SIZE
	
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
	
	sdl2.SetRenderDrawColor(ctx.renderer, 255, 255, 255, 255) // White box
	sdl2.RenderDrawRect(ctx.renderer, &view_rect)
}
