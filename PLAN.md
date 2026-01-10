# Dune II Clone Implementation Plan

## 1. Core Engine Setup
- [x] Initialize Window and Context (SDL2).
- [x] Implement Main Game Loop (Input, Update, Render).
- [x] Implement Time Management (Delta Time, Frame Limiting).
- [x] Input Handling System (Mouse selection, Keyboard shortcuts).

## 2. Rendering System
- [x] Asset Management (Load textures, spritesheets).
- [x] Sprite Rendering (Draw quads/sprites).
- [x] Tilemap Rendering (Render the game world grid).
- [x] Camera/Viewport Control (Scrolling).
- [ ] UI Rendering (Sidebar, Context buttons).
- [x] Minimap Rendering.

## 3. Game World & Logic
- [x] Map Data Structure (Grid-based, Terrain types).
- [ ] Fog of War System (Explored vs Visible areas).
- [x] Entity System (Basic Units struct, Spawning).
- [ ] Resource System (Spice fields, Harvesting).

## 4. Units & Behaviors
- [x] Unit Selection (Single click, Box selection).
- [x] Unit Movement (Basic direct movement).
- [ ] Pathfinding (A* or Flow Fields).
- [x] Unit States (Idle, Move, Attack animation states).
- [ ] Combat System (Range checks, Projectiles, Damage, Health).

## 5. Buildings & Construction
- [ ] Building Placement (Grid snapping, collision check).
- [ ] Construction Queue/Timers.
- [ ] Unit Production (Barracks, Factory logic).
- [ ] Structure Functionality (Refineries for credits, Radar for minimap).

## 6. Audio
- [ ] Sound Effects (Gunfire, Voices).
- [ ] Music System (Background tracks).

## 7. Polish
- [ ] Main Menu.
- [ ] Win/Loss Conditions.
- [ ] AI Opponent (Basic behavior).