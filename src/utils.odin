package main

Vec2  :: [2]f32
IVec2 :: [2]i32

screen_to_world :: proc(ctx: ^CTX, sx, sy: i32) -> Vec2 {
	return Vec2{f32(sx - ctx.offset_x), f32(sy - ctx.offset_y)}
}

world_to_grid :: proc(wp: Vec2) -> IVec2 {
	return IVec2{i32(wp.x) / 32, i32(wp.y) / 32}
}

grid_to_screen :: proc(ctx: ^CTX, gx, gy: i32) -> (x, y: i32) {
	return ctx.offset_x + gx * 32, ctx.offset_y + gy * 32
}
