package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
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
IVec2 :: [2]i32

Direction :: enum {
	None,
	Up,
	UpRight,
	Right,
	DownRight,
	Down,
	DownLeft,
	Left,
	UpLeft,
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

Player :: enum {
	Player1,
	Player2,
}

EntityType :: enum {
	Unit,
	Building,
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

// Generic Entity
Entity :: struct {
	// Identity
	player:      Player,
	type:        EntityType,

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
	path:        [dynamic]IVec2,

	// Combat
	hp:            int,
	max_hp:        int,
	damage:        int,
	attack_range:  f32,
	attack_timer:  f32,
	attack_speed:  f32, // Cooldown in seconds
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
	// Simple offset from base position
	switch state {
	case .Idle:      return 0, 1
	case .Moving:    return 0, 8
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
	selected_entities: [dynamic]^Entity,
	entities:          [dynamic]^Entity,
	projectiles:       [dynamic]Projectile,
	
	// Selection State
	is_dragging:       bool,
	is_targeting:      bool, // Attack Move / Targeting mode
	drag_start:        Vec2,
	current_mouse_pos: Vec2,
	
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

	sdl2.SetHint(sdl2.HINT_RENDER_SCALE_QUALITY, "nearest")

	ctx.window = sdl2.CreateWindow(WINDOW_TITLE,
		sdl2.WINDOWPOS_CENTERED, sdl2.WINDOWPOS_CENTERED,
		WINDOW_WIDTH, WINDOW_HEIGHT, sdl2.WINDOW_SHOWN | sdl2.WINDOW_FULLSCREEN_DESKTOP)
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
	
	// Set Logical Size for automatic upscaling
	sdl2.RenderSetLogicalSize(ctx.renderer, WINDOW_WIDTH, WINDOW_HEIGHT)

	return true
}

load_texture :: proc(ctx: ^CTX, path: string) -> ^sdl2.Texture {
	c_path := strings.clone_to_cstring(path, context.temp_allocator)
	tex := img.LoadTexture(ctx.renderer, c_path)
	if tex == nil {
		log.errorf("Failed to load texture %s: %s", path, sdl2.GetError())
	} else {
		sdl2.SetTextureBlendMode(tex, .BLEND)
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
	for e in ctx.entities {
		delete(e.path)
		free(e)
	}
	delete(ctx.selected_entities)
	delete(ctx.entities)
	delete(ctx.projectiles)
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
		game_map[idx].pos = {i32(x), i32(y)}
		
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
	end_x   := start_x + (WINDOW_WIDTH / TILE_SIZE) + 2
	end_y   := start_y + (WINDOW_HEIGHT / TILE_SIZE) + 2

	// Clamp to map bounds
	start_x = math.clamp(start_x, 0, MAP_WIDTH)
	start_y = math.clamp(start_y, 0, MAP_HEIGHT)
	end_x   = math.clamp(end_x,   0, MAP_WIDTH)
	end_y   = math.clamp(end_y,   0, MAP_HEIGHT)

	SRC_SIZE    :: 32
	for tile in game_map {
		//spirtesheet positions to render.
		src_x := i32(tile.tile_id) * SRC_SIZE
		src_y := i32(0) // Specified as Row 0

		src := sdl2.Rect{
			x = src_x,
			y = src_y,
			w = SRC_SIZE,
			h = SRC_SIZE,
		}

		// Destination Rect (Screen Space)
		dst_x, dst_y := grid_to_screen(ctx, tile.pos.x, tile.pos.y)
		dst := sdl2.Rect{
			x = dst_x,
			y = dst_y,
			w = TILE_SIZE,
			h = TILE_SIZE,
		}

		sdl2.RenderCopy(ctx.renderer, ctx.tileset, &src, &dst)
	}
}

// --- Entities ---
spawn_unit :: proc(ctx: ^CTX, x, y: int, player: Player) {
	if x < 0 || x >= MAP_WIDTH || y < 0 || y >= MAP_HEIGHT { return }
	
	idx := y * MAP_WIDTH + x
	if game_map[idx].occupier != nil { return } // Tile occupied

	e := new(Entity)
	e.player = player
	e.type = .Unit
	e.pos = Vec2{f32(x * TILE_SIZE), f32(y * TILE_SIZE)}
	e.target_pos = e.pos
	e.tex = ctx.units_tex // Use the dedicated units texture
	e.base_sprite_pos = IVec2{0, 0} // Reset base since we are using a dedicated sheet
	e.state = .Idle
	e.frame_idx = 0
	e.anim_speed = 0.1
	e.current_dir = .Up
	e.path = make([dynamic]IVec2)
	
	// Combat Stats
	e.hp = 100
	e.max_hp = 100
	e.damage = 10
	e.attack_range = 150.0
	e.attack_timer = 0.0
	e.attack_speed = 1.0 // 1 second cooldown
	
	game_map[idx].occupier = e
	append(&ctx.entities, e)
}

spawn_building :: proc(ctx: ^CTX, x, y: i32, player: Player) {
	if x < 0 || x >= MAP_WIDTH || y < 0 || y >= MAP_HEIGHT { return }
	
	idx := y * MAP_WIDTH + x
	if game_map[idx].occupier != nil { return }

	e := new(Entity)
	e.player = player
	e.type = .Building
	e.pos = Vec2{f32(x * TILE_SIZE), f32(y * TILE_SIZE)}
	e.target_pos = e.pos
	e.tex = ctx.tileset // Use tileset for buildings
	e.base_sprite_pos = IVec2{12, 0}
	e.state = .Idle
	e.frame_idx = 0
	e.anim_speed = 0.0
	e.current_dir = .None // Indicates static building
	e.path = make([dynamic]IVec2)
	
	e.hp = 500
	e.max_hp = 500
	e.damage = 0
	e.attack_range = 0
	
	game_map[idx].occupier = e
	append(&ctx.entities, e)
	log.info("Spawned Building at", x, y)
}

update_entity :: proc(ctx: ^CTX, e: ^Entity, dt: f32) {
	// Combat Logic
	if e.combat_target != nil {
		// Validate Target (Simple/Slow check)
		target_exists := false
		for unit in ctx.entities {
			if unit == e.combat_target {
				target_exists = true
				break
			}
		}
		
		if !target_exists {
			e.combat_target = nil
			e.state = .Idle
		} else {
			dist := linalg.distance(e.pos, e.combat_target.pos)
			if dist <= e.attack_range {
				// In Range - Attack
				e.state = .Attacking
				e.target_pos = e.pos // Stop moving
				
				// Face Target
				dir := e.combat_target.pos - e.pos
				// Reuse direction logic later? Or just set it here?
				// For now, let's just fire.
				
				e.attack_timer += dt
				if e.attack_timer >= e.attack_speed {
					e.attack_timer = 0
					
					// Spawn Projectile
					p_dir := linalg.normalize(e.combat_target.pos - e.pos)
					proj := Projectile{
						owner = e.player,
						pos = e.pos + {TILE_SIZE/2, TILE_SIZE/2},
						dir = p_dir,
						speed = 300.0,
						damage = e.damage,
						active = true,
						target = e.combat_target,
					}
					append(&ctx.projectiles, proj)
					log.info("Fired projectile")
				}
				return // Skip movement logic
			} else {
				// Move towards target
				e.target_pos = e.combat_target.pos
			}
		}
	}

	// Simple movement logic: Lerp towards target
	SPEED :: 100.0 // Pixels per second

	prev_grid_pos := world_to_grid(e.pos)
	dist := linalg.distance(e.pos, e.target_pos)
	if dist > 1.0 {
		e.state = .Moving
		dir := e.target_pos - e.pos
		dir = linalg.normalize(dir)
		
		// Update Direction (8-way)
		angle := math.atan2(dir.y, dir.x)
		deg := math.to_degrees(angle)
		if deg < 0 { deg += 360 }
		
		offset :: 22.5
		if deg >= 360 - offset || deg < offset { e.current_dir = .Right }
		else if deg < 45 + offset { e.current_dir = .DownRight }
		else if deg < 90 + offset { e.current_dir = .Down }
		else if deg < 135 + offset { e.current_dir = .DownLeft }
		else if deg < 180 + offset { e.current_dir = .Left }
		else if deg < 225 + offset { e.current_dir = .UpLeft }
		else if deg < 270 + offset { e.current_dir = .Up }
		else { e.current_dir = .UpRight }
		
		// Proposed movement
		move_vec := dir * SPEED * dt
		next_pos := e.pos + move_vec

		// Collision Detection (AABB)
		collided := false
		
		for other in ctx.entities {
			if other == e { continue } // Don't check against self
			
			if check_collision(next_pos, other.pos) {
				collided = true
				break
			}
		}

		if !collided {
			e.pos = next_pos
			
			// Update logic grid position (ownership)
			new_grid_pos := world_to_grid(e.pos)
			
			// If we crossed into a new tile
			if new_grid_pos != prev_grid_pos {
				// Bounds check
				if new_grid_pos.x >= 0 && new_grid_pos.x < MAP_WIDTH && 
				   new_grid_pos.y >= 0 && new_grid_pos.y < MAP_HEIGHT {
					   
					// Unconditionally clear the old tile to ensure no trails are left.
					old_idx := prev_grid_pos.y * MAP_WIDTH + prev_grid_pos.x
					game_map[old_idx].occupier = nil
					
					// Set new
					new_idx := new_grid_pos.y * MAP_WIDTH + new_grid_pos.x
					game_map[new_idx].occupier = e
				}
			}
		}
		
	} else {
		e.pos = e.target_pos
		if len(e.path) > 0 {
			ordered_remove(&e.path, 0)
			if len(e.path) > 0 {
				e.target_pos = Vec2{f32(e.path[0].x * TILE_SIZE), f32(e.path[0].y * TILE_SIZE)}
			} else {
				e.state = .Idle
			}
		} else {
			e.state = .Idle
		}
	}
	
	// Animation Tick
	e.frame_timer += dt
	if e.frame_timer >= e.anim_speed {
		e.frame_timer = 0
		_, num_frames := get_anim_info(e.state)
		e.frame_idx = (e.frame_idx + 1) % num_frames
	}
}

// --- Main Input Handling ---

handle_events :: proc(ctx: ^CTX) {
	e: sdl2.Event
	for sdl2.PollEvent(&e) {
		#partial switch e.type {
		case .QUIT:
			ctx.should_close = true
		case .KEYDOWN:
			if e.key.keysym.sym == .ESCAPE {
				if ctx.is_targeting {
					ctx.is_targeting = false
					log.info("Targeting Cancelled")
				} else {
					ctx.should_close = true
				}
			} else if e.key.keysym.sym == .A {
				if len(ctx.selected_entities) > 0 {
					ctx.is_targeting = true
					log.info("Targeting Mode ON")
				}
			} else if e.key.keysym.sym == .G {
				grid_pos := world_to_grid(ctx.current_mouse_pos)
				spawn_building(ctx, grid_pos.x, grid_pos.y, .Player1)
			}
		case .MOUSEBUTTONDOWN:
			world_pos := screen_to_world(ctx, e.button.x, e.button.y)
			
			if ctx.is_targeting {
				if e.button.button == sdl2.BUTTON_LEFT {
					target := get_entity_at(ctx, world_pos)
					if target != nil {
						issue_attack_order(ctx, target)
					} else {
						log.info("No target selected")
					}
					ctx.is_targeting = false
				} else if e.button.button == sdl2.BUTTON_RIGHT {
					ctx.is_targeting = false
					log.info("Targeting Cancelled")
				}
				return
			}

			if e.button.button == sdl2.BUTTON_LEFT {
				// Start Dragging
				ctx.is_dragging = true
				ctx.drag_start = world_pos
				clear(&ctx.selected_entities) // Clear previous selection
			} else if e.button.button == sdl2.BUTTON_RIGHT {
				grid_pos := world_to_grid(world_pos)
				handle_movement(ctx, grid_pos)
			}
		case .MOUSEBUTTONUP:
			if e.button.button == sdl2.BUTTON_LEFT && ctx.is_dragging {
				ctx.is_dragging = false
				world_pos := screen_to_world(ctx, e.button.x, e.button.y)
				handle_box_selection(ctx, ctx.drag_start, world_pos)
			}
		case .MOUSEMOTION:
			ctx.current_mouse_pos = screen_to_world(ctx, e.motion.x, e.motion.y)
		}
	}
}

handle_camera :: proc(ctx: ^CTX) {
	keys := sdl2.GetKeyboardState(nil)
	PAN_SPEED :: 8

	if keys[sdl2.Scancode.RIGHT] > 0 {
		ctx.offset_x -= PAN_SPEED
	}
	if keys[sdl2.Scancode.LEFT] > 0 {
		ctx.offset_x += PAN_SPEED
	}
	if keys[sdl2.Scancode.DOWN] > 0 {
		ctx.offset_y -= PAN_SPEED
	}
	if keys[sdl2.Scancode.UP] > 0 {
		ctx.offset_y += PAN_SPEED
	}

	// Clamp Camera
	min_offset_x := -(i32(MAP_WIDTH) * TILE_SIZE - WINDOW_WIDTH)
	min_offset_y := -(i32(MAP_HEIGHT) * TILE_SIZE - WINDOW_HEIGHT)

	ctx.offset_x = math.clamp(ctx.offset_x, min_offset_x, 0)
	ctx.offset_y = math.clamp(ctx.offset_y, min_offset_y, 0)
}

// --- Specific Input Handlers ---

get_entity_at :: proc(ctx: ^CTX, world_pos: Vec2) -> ^Entity {
	mouse_p := sdl2.Point{x = i32(world_pos.x), y = i32(world_pos.y)}
	for unit in ctx.entities {
		unit_rect := sdl2.Rect{
			x = i32(unit.pos.x),
			y = i32(unit.pos.y),
			w = TILE_SIZE,
			h = TILE_SIZE,
		}
		if sdl2.PointInRect(&mouse_p, &unit_rect) {
			return unit
		}
	}
	return nil
}

issue_attack_order :: proc(ctx: ^CTX, target: ^Entity) {
	count := 0
	for unit in ctx.selected_entities {
		if unit == target { continue }
		if unit.player == target.player { continue } // Prevent friendly fire
		unit.combat_target = target
		clear(&unit.path)
		// Reset target pos so it stops moving to previous location and focuses on target
		// Logic in update_entity will handle moving to range
		count += 1
	}
	if count > 0 {
		log.infof("Attack order issued by %d units against %v", count, target.player)
	}
}

handle_single_selection :: proc(ctx: ^CTX, world_pos: Vec2) {
	unit := get_entity_at(ctx, world_pos)
	if unit != nil {
		append(&ctx.selected_entities, unit)
		log.info("Selected Unit via Click")
	}
}

handle_box_selection :: proc(ctx: ^CTX, start, end: Vec2) {
	// Calculate Min/Max for AABB
	min_x := math.min(start.x, end.x)
	max_x := math.max(start.x, end.x)
	min_y := math.min(start.y, end.y)
	max_y := math.max(start.y, end.y)
	
	// For single click (or tiny drag), treat as point selection
	if max_x - min_x < 2 && max_y - min_y < 2 {
		handle_single_selection(ctx, start)
		return
	}

	for unit in ctx.entities {
		// Check if unit center is in box
		center := unit.pos + Vec2{f32(TILE_SIZE)/2, f32(TILE_SIZE)/2}
		
		if center.x >= min_x && center.x <= max_x &&
		   center.y >= min_y && center.y <= max_y {
			append(&ctx.selected_entities, unit)
			log.info("Selected Unit via Box")
		}
	}
}

handle_movement :: proc(ctx: ^CTX, grid_pos: IVec2) {
	count := 0
	for unit in ctx.selected_entities {
		if unit.type == .Building { continue }
		
		start_grid := world_to_grid(unit.pos)
		new_path := find_path(start_grid, grid_pos)
		if new_path != nil {
			delete(unit.path)
			unit.path = new_path
			unit.target_pos = Vec2{f32(unit.path[0].x * TILE_SIZE), f32(unit.path[0].y * TILE_SIZE)}
			unit.combat_target = nil
			unit.state = .Moving
			count += 1
		}
	}
	if count > 0 {
		log.info("Moving", count, "units to Grid", grid_pos)
	}
}

// --- Utilities ---

screen_to_world :: proc(ctx: ^CTX, screen_x, screen_y: i32) -> Vec2 {
	return Vec2{f32(screen_x - ctx.offset_x), f32(screen_y - ctx.offset_y)}
}

world_to_grid :: proc(world_pos: Vec2) -> IVec2 {
	return IVec2{i32(world_pos.x) / TILE_SIZE, i32(world_pos.y) / TILE_SIZE}
}

grid_to_screen :: proc(ctx: ^CTX, gx, gy: i32) -> (x, y: i32) {
	return ctx.offset_x + gx * TILE_SIZE, ctx.offset_y + gy * TILE_SIZE
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

check_collision :: proc(pos_a, pos_b: Vec2) -> bool {
	//TODO we need to pass entities, or hitboxes at some point ?
	SIZE :: f32(TILE_SIZE)
	// AABB Overlap Test
	return pos_a.x < pos_b.x + SIZE &&
	       pos_a.x + SIZE > pos_b.x &&
	       pos_a.y < pos_b.y + SIZE &&
	       pos_a.y + SIZE > pos_b.y
}

draw_entity :: proc(ctx: ^CTX, entity: ^Entity) {
	// 1. Calculate Destination Rect (Screen Space)
	screen_x := ctx.offset_x + i32(entity.pos.x)
	screen_y := ctx.offset_y + i32(entity.pos.y)

	dst := sdl2.Rect{x = screen_x, y = screen_y, w = TILE_SIZE, h = TILE_SIZE}
	
	// 2. Calculate Source Rect
	src_x, src_y: i32
	flip: sdl2.RendererFlip

	if entity.current_dir == .None {
		// Static entity / Building - use base_sprite_pos
		src_x = i32(entity.base_sprite_pos.x) * TILE_SIZE
		src_y = i32(entity.base_sprite_pos.y) * TILE_SIZE
		flip = .NONE
	} else {
		// Unit with directional animation
		row, f := get_direction_info(entity.current_dir)
		flip = f
		
		_, num_frames := get_anim_info(entity.state)
		frame := entity.frame_idx % num_frames
		
		src_x = i32(frame) * TILE_SIZE
		src_y = row * TILE_SIZE
	}
	
	src := sdl2.Rect{x = src_x, y = src_y, w = TILE_SIZE, h = TILE_SIZE}

	// 3. Draw
	sdl2.SetTextureColorMod(entity.tex, 255, 255, 255)
	
	// If texture is nil, we might want to draw a debug rect, but for now assuming valid texture
	if entity.tex != nil {
		sdl2.RenderCopyEx(ctx.renderer, entity.tex, &src, &dst, entity.rotation, nil, flip)
	}
	
	// Draw Player Indicator (Dot) TODO temporary
	dot_x := screen_x + 2
	dot_y := screen_y + 2
	dot_w := i32(4)
	dot_h := i32(4)
	dot := sdl2.Rect{x=dot_x, y=dot_y, w=dot_w, h=dot_h}
	
	r, g, b: u8
	switch entity.player {
	case .Player1: r, g, b = 0, 0, 255 // Blue
	case .Player2: r, g, b = 255, 0, 0 // Red
	}
	
	sdl2.SetRenderDrawColor(ctx.renderer, r, g, b, 255)
	sdl2.RenderFillRect(ctx.renderer, &dot)
	
	// DEBUG: Draw Red Box outline to verify position
	//sdl2.SetRenderDrawColor(ctx.renderer, 255, 0, 0, 255)
	//sdl2.RenderDrawRect(ctx.renderer, &dst)
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

update_projectiles :: proc(ctx: ^CTX, dt: f32) {
	for i := 0; i < len(ctx.projectiles); {
		p := &ctx.projectiles[i]
		
		// Homing Logic
		if p.target != nil {
			// Verify target exists
			exists := false
			for unit in ctx.entities {
				if unit == p.target {
					exists = true
					break
				}
			}
			
			if exists {
				// Update Direction to target center
				target_center := p.target.pos + {TILE_SIZE/2, TILE_SIZE/2}
				p.dir = linalg.normalize(target_center - p.pos)
			} else {
				p.target = nil // Stop homing if target lost
			}
		}
		
		// Move
		p.pos += p.dir * p.speed * dt
		
		// Check bounds (optional, remove if too far)
		// For now just check collision
		hit := false
		
		// Check collision with specific target only
		if p.target != nil {
			unit := p.target
			HIT_DIST :: 16.0
			
			// Verify target is still valid/alive (simple check if it's in our entities list would be safer, 
			// but for now we rely on the homing check logic which already sets p.target = nil if lost)
			
			if linalg.distance(p.pos, unit.pos + {TILE_SIZE/2, TILE_SIZE/2}) < HIT_DIST {
				// HIT!
				unit.hp -= p.damage
				log.infof("Unit hit! HP: %d/%d", unit.hp, unit.max_hp)
				
				if unit.hp <= 0 {
					// Kill Unit
					// Remove from grid
					grid_pos := world_to_grid(unit.pos)
					idx := grid_pos.y * MAP_WIDTH + grid_pos.x
					if idx >= 0 && idx < len(game_map) {
						if game_map[idx].occupier == unit {
							game_map[idx].occupier = nil
						}
					}
					
					// Find unit in entities list to remove
					for unit_idx := 0; unit_idx < len(ctx.entities); unit_idx += 1 {
						if ctx.entities[unit_idx] == unit {
							unordered_remove(&ctx.entities, unit_idx)
							break
						}
					}
					
					// Also remove from selected if active
					for s_i := 0; s_i < len(ctx.selected_entities); {
						if ctx.selected_entities[s_i] == unit {
							unordered_remove(&ctx.selected_entities, s_i)
						} else {
							s_i += 1
						}
					}
					
					delete(unit.path)
					free(unit)
				}
				hit = true
			}
		}
		
		if hit {
			// Remove projectile
			unordered_remove(&ctx.projectiles, i)
		} else {
			i += 1
		}
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
	dune_ctx.units_tex = load_texture(&dune_ctx, "assets/tank_32x32.png")
	
	// Init Map
	init_map(&dune_ctx)
	
	// Spawn Test Unit
	spawn_unit(&dune_ctx, 10, 10, .Player1)
	spawn_unit(&dune_ctx, 15, 10, .Player1)
	spawn_unit(&dune_ctx, 12, 10, .Player2)

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

		// Input Handling
		handle_events(&dune_ctx)
		handle_camera(&dune_ctx)

		// Clear Screen
		sdl2.SetRenderDrawColor(dune_ctx.renderer, 0, 0, 0, 255)
		sdl2.RenderClear(dune_ctx.renderer)
		
		draw_map(&dune_ctx)
		
		// 1. Update Entities (Logic)
		for e in dune_ctx.entities {
			update_entity(&dune_ctx, e, dt)
		}
		
		update_projectiles(&dune_ctx, dt)
		
		// 2. Draw Entities (Render)
		// Sort by Y for simple depth sorting
		slice.sort_by(dune_ctx.entities[:], proc(i, j: ^Entity) -> bool {
			return i.pos.y < j.pos.y
		})

		for e in dune_ctx.entities {
			draw_entity(&dune_ctx, e)
		}
		
		// Render Projectiles
		for p in dune_ctx.projectiles {
			rect := sdl2.Rect{
				x = dune_ctx.offset_x + i32(p.pos.x),
				y = dune_ctx.offset_y + i32(p.pos.y),
				w = 4,
				h = 4,
			}
			sdl2.SetRenderDrawColor(dune_ctx.renderer, 255, 255, 0, 255) // Yellow
			sdl2.RenderFillRect(dune_ctx.renderer, &rect)
		}
		
		// Draw Selection Indicators
		for e in dune_ctx.selected_entities {
			draw_selected_box(&dune_ctx, e)
		}

		if dune_ctx.is_dragging {
			draw_mouse_select_box(&dune_ctx)
		}

		draw_minimap(&dune_ctx)
		
		sdl2.RenderPresent(dune_ctx.renderer)
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
	// 1. Draw Background
	bg_rect := sdl2.Rect{
		x = MINIMAP_X,
		y = MINIMAP_Y,
		w = MINIMAP_SIZE,
		h = MINIMAP_SIZE,
	}
	sdl2.SetRenderDrawColor(ctx.renderer, 0, 0, 0, 255)
	sdl2.RenderFillRect(ctx.renderer, &bg_rect)
	
	// 2. Draw Terrain & Units
	for tile in game_map {
		// Color based on terrain or unit
		r, g, b: u8
		if tile.occupier != nil {
		// Color by player
			switch tile.occupier.player {
			case .Player1:  r, g, b = 0, 0, 255   // Blue
			case .Player2:  r, g, b = 255, 0, 0   // Red
			}
		} else {
			switch tile.terrain {
			case .Sand:  r, g, b = 194, 125, 60
			case .Rock:  r, g, b = 80, 80, 80
			case .Spice: r, g, b = 255, 140, 0
			}
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
