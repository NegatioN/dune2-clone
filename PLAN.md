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
- [x] Fog of War System (Explored vs Visible areas).
- [x] Entity System (Basic Units struct, Spawning).
- [ ] Resource System (Spice fields, Harvesting).

## 4. Units & Behaviors
- [x] Unit Selection (Single click, Box selection).
- [x] Unit Movement (Path-based movement).
- [x] Unit Collision Detection (Basic blocking).
- [x] Pathfinding (A*).
- [ ] Attack-Move Command ('A' + Click): Move toward destination, auto-engaging visible enemies.
- [x] Unit States (Idle, Move, Attack animation states).
- [x] Combat System (Range checks, Projectiles, Damage, Health).
- [ ] Optimization: Use 'inactive' state for dead units/projectiles instead of removing/allocating.

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

## Engine Development (Short-Term)
- [ ] Advanced UI Framework: Robust layout engine for HUD, command cards, and input routing.
- [ ] Resource & Economy Extensibility: Support for N-resources with varied gathering rules.
- [ ] Height & Line of Sight (2.5D): Elevation-based sight bonuses and terrain-masking fog.
- [ ] Scenario & Map Editor: Visual tool for painting terrain, placing entities, and defining triggers.

## Engine Development (Long-Term/Future)
- [ ] Deterministic Lockstep Networking: Syncing only inputs for low-bandwidth multiplayer.
- [ ] Scripting & Data Decoupling: Externalizing unit stats (JSON/TOML) and behavior (Lua).
- [ ] Robust Event & Message Bus: Decoupled system communication (e.g., UnitDiedEvent).
- [ ] Save/Load & Replay System: Full state serialization and input playback.

## Future Technical
- [ ] Local Pathfinding / Steering (RVO/ORCA) for smooth unit avoidance.
- [ ] Struct of Arrays for all game entities for quick looping in game logic.
- [ ] Arrays keep only identifiers and relevant fields of the entire Entity.
  - Example: If we want to loop over only living units (since we'll have dead units not be de-allocated, but respawned), there would be a struct with an id, and a boolean for living/dead.
