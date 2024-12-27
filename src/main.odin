package game

import rl "vendor:raylib"
import "core:fmt"
import "core:math/rand"
import "core:math"
import core_hash "core:hash"
import "core:encoding/json"
import "core:os"
Hash :: distinct u64

hash :: proc(s: string) -> Hash {
	return Hash(core_hash.murmur64a(transmute([]byte)(s)))
}

PIXEL_WINDOW_HEIGHT :: 360

EntityHandle :: distinct Handle

EntityHandleNone :: EntityHandle(HandleNone)

Shake :: struct {
    duration: f32,
    magnitude: f32,
    timer: f32,
}

start_shake :: proc(shake: ^Shake, duration: f32, magnitude: f32) {
    shake.duration = duration;
    shake.magnitude = magnitude;
    shake.timer = duration;
}

update_shake :: proc(shake: ^Shake, camera: ^rl.Camera2D) {
    if shake.timer > 0 {
        shake.timer -= rl.GetFrameTime();
        offset_x := (f32(rl.GetRandomValue(-100, 100)) * shake.magnitude);
        offset_y := (f32(rl.GetRandomValue(-100, 100)) * shake.magnitude);
        camera.offset.x += offset_x;
        camera.offset.y += offset_y;
    }
}

Animation :: struct {
    current_frame: i32,
    frames: i32,
    frame_speed: f32,
    frame: f32
}

Teste :: struct {
    entities: EntityHandle,
    hello: string,
}

PlayerState :: enum {
    idle,
    run,
}

Player :: struct {
    position: rl.Vector2,
    speed: rl.Vector2,
    texture: rl.Texture2D,
    animation: Animation,
    anim_state: PlayerState
}

EditorTab :: enum {
    tiles,
    tiles_colliders,
    entities
}

Edtior :: struct {
    tab: EditorTab,
    selected_tile: i32,
    selected_tile_collider: rl.Rectangle,
    selected_tile_collider_idx: int,
    creating_colider: bool,
    new_collider_recs: [2]rl.Rectangle
}

Tile :: struct {
    id: i32,
    pos: rl.Vector2,
}

World :: struct {
    tiles: [dynamic]Tile,
    colliders: [dynamic]rl.Rectangle
}

jump_height :: 170
jump_time_to_peak :: 0.6
jump_time_to_descent :: 0.5
Collider :: rl.Rectangle

UID :: distinct u128

new_uid :: proc() -> UID {
	return UID(rand.uint128())
}

merge_rectangles :: proc(r1: rl.Rectangle, r2: rl.Rectangle) -> rl.Rectangle {
    min_x := math.min(r1.x, r2.x);                      
    min_y := math.min(r1.y, r2.y);                      
    max_x := math.max(r1.x + r1.width, r2.x + r2.width);  
    max_y := math.max(r1.y + r1.height, r2.y + r2.height);
    return rl.Rectangle{min_x, min_y, max_x - min_x, max_y - min_y};
}

string_to_uid :: proc(s: string) -> UID {
	return UID(transmute(u128)([2]u64 { u64(hash(s)), u64(hash("from_string")) }))
}

main :: proc() {
    rl.InitWindow(1280, 720, "Platform 2D")
    rl.SetWindowState({.WINDOW_RESIZABLE})
    rl.SetTargetFPS(60)
    player_sprite_idle := rl.LoadTexture("./assets/player/idle.png")
    player_sprite_run := rl.LoadTexture("./assets/player/run.png")
    animation := Animation{current_frame = 0, frame_speed= 0.05, frames = 11, frame = 0 }
    player := Player{{0,0}, 60, player_sprite_idle, animation, .run}
    tile_texture := rl.LoadTexture("./assets/tilemaps/terrain.png")
    teste := load_tileset("./assets/tilemaps/map.json")
    is_on_ground := false
    jump_delay: f32 = 0.1
    jump_velocity : f32 = ((2.0 * jump_height) / jump_time_to_peak) * -1.0
    jump_gravity : f32 = ((-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)) * -1.0
    fall_gravity : f32 = ((-2.0 * jump_height) / (jump_time_to_descent * jump_time_to_descent)) * -1.0
    editor := false
    jumping := false
    offset := rl.Vector2{0,0}
    editor_zoom: f32 = 1
    editor_g := Edtior{selected_tile = -1}
    world := World{}
    dash_time:f32 = 0.3
    dash_speed := 200
    dash_current_time:f32 = 0
    in_dash := false
    shake := Shake{2, 1.5, 0.1}
    scrollPos := 0.0
    if world_tiles, ok := os.read_entire_file("./assets/tiles.json", allocator = context.allocator); ok {
        tiles := make([dynamic]Tile, 0)
        json.unmarshal(world_tiles, &tiles, allocator = context.temp_allocator)
        world.tiles = tiles
    }
    if colliders, ok := os.read_entire_file("./assets/colliders.json", allocator = context.allocator); ok {
        colliders_w := make([dynamic]Collider, 0)
        json.unmarshal(colliders, &colliders_w, allocator = context.temp_allocator)
        world.colliders = colliders_w
    }
    for !rl.WindowShouldClose() {
        window_height := f32(rl.GetScreenHeight())
        window_width := f32(rl.GetScreenWidth())

        
        zoom := window_height / PIXEL_WINDOW_HEIGHT
        tilemap_pixel_height := f32(teste.height * teste.tileheight)
        viewport_height := window_height / zoom
        fixed_camera_y := min(
            max(player.position.y, viewport_height/2),
            tilemap_pixel_height - viewport_height/2
        )

        camera := rl.Camera2D{
            zoom = zoom,
            offset = {window_width / 2, window_height / 2},
            target = {player.position.x, fixed_camera_y},
        }
        
        if rl.IsKeyDown(.A) {
            player.speed.x = -100
            player_sprite_run.width = player_sprite_run.width
        } else if rl.IsKeyDown(.D) {
            player.speed.x = 100
            player_sprite_run.width = player_sprite_run.width
        } else {
            player.speed.x = 0
        }
        if editor {
            if rl.IsKeyDown(.D) {
               offset.x += 15
            } else if rl.IsKeyDown(.A) {
                offset.x -= 15
            }
            camera.target = {0,0}
            camera.offset = offset
            camera.zoom = 1
        }
        if editor {
            player.speed.x = 0
            player.speed.y = 0
        }
        gravity_force: f32
        if player.speed.y  < 0 {
            gravity_force = jump_gravity
        } else {
            gravity_force = fall_gravity
        }

        if rl.IsKeyPressed(.E) {
            editor = !editor
        }
        if rl.IsKeyUp(.SPACE) && jumping {
            gravity_force = fall_gravity
        }
        if is_on_ground && rl.IsKeyDown(.SPACE) && jump_delay >= 0.15{
            player.speed.y -= 450
            jumping = true
            jump_delay = 0
        }

        if rl.IsKeyPressed(.R) {
            player.position = rl.Vector2{0,0}
            player.speed = {0,0}
        }

        if !editor {
            player.speed.y += gravity_force * rl.GetFrameTime()
        }

        if player.speed.x == 0 {
            player.animation.frames = 11
            player.anim_state = .idle
        } else {
            player.animation.frames = 12
            player.anim_state = .run
        }
        
        is_on_ground = false


        if !in_dash && rl.IsKeyPressed(.LEFT_SHIFT) {
            dash_current_time = 0
            in_dash = true
        }

        if in_dash {
            player.speed.y = 0
            player.speed.x = 800
            dash_current_time += rl.GetFrameTime()
            if dash_current_time >= dash_time {
                in_dash = false

            }   
        }
        //y collision
        {
            player.position.y += player.speed.y * rl.GetFrameTime()
            for collider in world.colliders {
                overlap := rl.GetCollisionRec({player.position.x + 10, player.position.y + 10, 15, 20}, collider)

                if overlap.height != 0 {
                    sign: f32 = (player.position.y + 32 /2) < (collider.y + collider.height /2) ? -1 : 1
                    player.position.y += overlap.height * sign
                    player.speed.y = 0
                    is_on_ground = true
                }
            }
        }
        //x collision
        {
            player.position.x += player.speed.x * rl.GetFrameTime()
            for collider in world.colliders {
                overlap := rl.GetCollisionRec({player.position.x + 10, player.position.y + 10, 15, 20}, collider)

                if overlap.width != 0 {
                    sign: f32 = (player.position.x + 32 /2) < (collider.x + collider.width /2) ? -1 : 1
                    player.position.x += overlap.width * sign
                    player.speed.x = 0
                }
            }
        }
        if is_on_ground {
            jump_delay += rl.GetFrameTime()
        }

        if rl.IsKeyPressed(.G) {
            start_shake(&shake, 1.5, 0.01);
        }
        update_shake(&shake, &camera);

        rl.BeginDrawing()
        rl.BeginMode2D(camera)
        rl.ClearBackground(rl.SKYBLUE)
        switch player.anim_state {
            case .idle:
                player.texture = player_sprite_idle
            case .run:
                player.texture = player_sprite_run
        }
        player.animation.frame += rl.GetFrameTime()
        if player.animation.frame >= player.animation.frame_speed {
            player.animation.frame = 0
            player.animation.current_frame +=1
            if player.animation.current_frame >= player.animation.frames {
                player.animation.current_frame = 0
            }
        }
        frame_width := f32(player.texture.width) / f32(player.animation.frames)
        source := rl.Rectangle{frame_width * f32(player.animation.current_frame), 0, frame_width, f32(player.texture.height)}
        dest := rl.Rectangle{player.position.x, player.position.y, 32, 32}
        for tile in world.tiles {
            tile_size: i32 = 16
            width := math.floor(f32(tile_texture.width) / f32(tile_size))
            height := math.floor(f32(tile_texture.height) / f32(tile_size))
            x := (tile.id % i32(width)) * tile_size
            y := (tile.id / i32(width)) * tile_size
            source := rl.Rectangle{f32(x), f32(y), 16, 16}
            dest := rl.Rectangle{tile.pos.x, tile.pos.y, 16, 16}
            rl.DrawTexturePro(tile_texture, source, dest, {0,0}, 0, rl.WHITE)

        }
        rl.DrawTexturePro(player.texture, source, dest, {0, 0}, 0, rl.WHITE)
        //rl.DrawRectangleRec({player.position.x + 10, player.position.y + 12, 15,20}, rl.RED)
        
        if editor {
            for collider in world.colliders{
            rl.DrawRectangleRec(collider, {255,0,0,90})
            }
            if editor_g.tab == .tiles_colliders {
                if rl.IsMouseButtonDown(.LEFT) {
                    mouse_pos := rl.GetMousePosition()
                    for collider, i in world.colliders  {
                        if rl.CheckCollisionRecs({mouse_pos.x, mouse_pos.y, 5, 5}, collider) && !editor_g.creating_colider {
                            editor_g.selected_tile_collider = collider
                            editor_g.selected_tile_collider_idx = i
                            editor_g.new_collider_recs[0] = collider
                            editor_g.creating_colider = true
                        }
                    }
                }
                
            }
        }
        

        if editor_g.creating_colider {
            mouse_pos := rl.GetMousePosition()
            world_pos := rl.GetScreenToWorld2D(mouse_pos, camera)
                x := math.floor((world_pos.x  / 16)) * 16
                y := math.floor((world_pos.y / 16)) * 16
                rl.DrawRectangle(i32(x), i32(y), 16, 16, {255, 0, 0, 150})
                rl.DrawRectangleRec(editor_g.new_collider_recs[0], {0,115,255, 100})
            gui_box := rl.Rectangle{f32(window_width) - 456, 15, 200, 150}
            if mouse_pos.x <= window_width - 256 && !rl.CheckCollisionRecs({mouse_pos.x, mouse_pos.y, 16, 16}, gui_box) {
                if rl.IsMouseButtonDown(.LEFT) {
                    new_rect := rl.Rectangle{x, y, 16, 16};
                    if editor_g.new_collider_recs[0].width == 0 {
                        editor_g.new_collider_recs[0] = new_rect;
                    } else if editor_g.new_collider_recs[1].width == 0 {
                        editor_g.new_collider_recs[1] = new_rect;
                    } else {
                        editor_g.new_collider_recs[0] = merge_rectangles(editor_g.new_collider_recs[0], editor_g.new_collider_recs[1]);
                        editor_g.new_collider_recs[1] = new_rect;
                    }
                }
            }
            
        }
        rl.EndMode2D()
        if editor {
            rl.DrawRectangleV({window_width - 256, 0}, {256, 1600}, rl.GRAY)
            indicatorY := 90 + i32(scrollPos * f64(window_height) / f64(1600))
            rl.DrawRectangle(i32(window_width-15), indicatorY, 15, 15, rl.DARKGRAY)
            scrollPos += f64(rl.GetMouseWheelMove()) * 5
            if scrollPos < 0 {
                scrollPos = 0
            }
            if scrollPos > f64(1600-window_height) {
                scrollPos = f64(1600 - window_height)
            }
            if rl.GuiButton({0,0,60,20}, "Tiles") {
                editor_g.tab = .tiles
            }
            if rl.GuiButton({60,0,60,20}, "Tiles Collider") {
                editor_g.tab = .tiles_colliders
            }
            if rl.GuiButton({120,0,60,20}, "Entities") {
                editor_g.tab = .entities
            }

            mouse_pos := rl.GetMousePosition()
            if rl.IsMouseButtonPressed(.LEFT) {
                #partial switch editor_g.tab {
                    case .tiles:
                        width := tile_texture.width
                        height := tile_texture.height
                        tile_size: i32 = 16
                        for y in 0 ..< height {
                            for x in 0 ..< width / tile_size {
                                if rl.CheckCollisionPointRec(mouse_pos, {f32((x * tile_size) + i32(window_width) - 256), f32(y * tile_size + 35), f32(tile_size), f32(tile_size)}) {
                                    editor_g.selected_tile = y * (width / tile_size) + x
                                }
                            }
                        }
                }
            }
            switch editor_g.tab {
                case .tiles:
                    tile_size: i32 = 16
                    width := math.floor(f32(tile_texture.width) / f32(tile_size))
                    height := math.floor(f32(tile_texture.height) / f32(tile_size))
                    rl.DrawText("Tiles", i32(window_width) - 256, 15, 20, rl.WHITE)
                    rl.DrawTextureEx(tile_texture, {window_width - 256,35}, 0, 1, rl.WHITE)

                    offset := i32(window_width - 256)
                    for x in 0..< width {
                        for y in 0..< height {
                           rl.DrawRectangleLines((i32(x) * 16) + offset, (i32(y) *16) + 35, 16, 16, rl.BLACK) 
                        }
                    }
                    if editor_g.selected_tile != -1 {
                        x := (editor_g.selected_tile % i32(width)) * tile_size
                        y := (editor_g.selected_tile / i32(width)) * tile_size
                        source := rl.Rectangle{f32(x), f32(y), 16, 16}
                        mouse_position := rl.GetMousePosition()
                        world_position := rl.GetScreenToWorld2D(mouse_position, camera)
                        x_grid: f32 = (math.floor(world_position.x / 16) * 16)
                        y_grid: f32 = (math.floor(world_position.y / 16) * 16)
                        dest := rl.Rectangle{x_grid + camera.offset.x, y_grid, 16, 16}
                        rl.DrawTexturePro(tile_texture, source, dest, {0,0}, 0, rl.WHITE)
                    }
                    if rl.IsMouseButtonPressed(.LEFT) && editor_g.selected_tile != -1 {
                        tile_size: i32 = 16
                        width := math.floor(f32(tile_texture.width) / f32(tile_size))
                        height := math.floor(f32(tile_texture.height) / f32(tile_size))
                        x := (editor_g.selected_tile % i32(width)) * tile_size
                        y := (editor_g.selected_tile / i32(width)) * tile_size
                        mouse_position := rl.GetMousePosition()
                        if mouse_position.x <= f32(rl.GetScreenWidth() - 256) {
                            world_position := rl.GetScreenToWorld2D(mouse_pos, camera)
                            x_grid: f32 = math.round(math.floor((world_position.x / 16)) * 16)
                            y_grid: f32 = math.round(math.floor((world_position.y / 16)) * 16)
                            for tile, idx in &world.tiles {
                                if x_grid == tile.pos.x && y_grid == tile.pos.y {
                                    ordered_remove(&world.tiles, idx)
                                }
                            }
                            for collider, idx in world.colliders {
                                if x_grid == collider.x && y_grid == collider.y {
                                    ordered_remove(&world.colliders, idx)
                                }
                            }
                            append(&world.tiles, Tile{id = editor_g.selected_tile, pos = {x_grid, y_grid}})
                        }
                        
                    }
                case .tiles_colliders:
                    rl.DrawText("Tiles Collider", i32(window_width) - 256, 15, 20, rl.WHITE)
                    if rl.GuiButton({f32(window_width) - 256, 50, 150, 25}, "Create Collider") {
                        editor_g.creating_colider = true
                        editor_g.selected_tile_collider_idx = -1
                    }
                    if editor_g.creating_colider {
                        tile_collider_editor_box := rl.GuiWindowBox({f32(window_width) - 456, 15, 200, 150}, fmt.ctprintf("Collider: %v", editor_g.selected_tile_collider_idx))
                        if tile_collider_editor_box == 1 {
                            editor_g.creating_colider = false
                            editor_g.new_collider_recs[0] = rl.Rectangle{}
                            editor_g.new_collider_recs[1] = rl.Rectangle{}
                            editor_g.selected_tile_collider_idx = -1
                        }
                        rl.DrawTextEx(rl.GetFontDefault(),  fmt.ctprintf("X:%v", editor_g.new_collider_recs[0].x), {f32(window_width) - 450, 40}, 20, 1, rl.BLACK)
                        rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("Y:%v", editor_g.new_collider_recs[0].y), {f32(window_width) - 450, 60}, 20, 1, rl.BLACK)
                        rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("W:%v", editor_g.new_collider_recs[0].width), {f32(window_width) - 450, 80}, 20, 1, rl.BLACK)
                        rl.DrawTextEx(rl.GetFontDefault(), fmt.ctprintf("H:%v", editor_g.new_collider_recs[0].height), {f32(window_width) - 450, 100}, 20, 1, rl.BLACK)
                        fmt.println(editor_g.selected_tile_collider_idx)
                        if rl.GuiButton({f32(window_width) - 450, 120, 80, 25}, "Save") {
                            if editor_g.selected_tile_collider_idx != -1 {
                                world.colliders[editor_g.selected_tile_collider_idx] = editor_g.new_collider_recs[0]
                            } else {
                                append(&world.colliders, editor_g.new_collider_recs[0])
                            }
                            editor_g.creating_colider = false
                            editor_g.new_collider_recs[0] = rl.Rectangle{}
                            editor_g.new_collider_recs[1] = rl.Rectangle{}
                            editor_g.selected_tile_collider_idx = -1
                        }
                        if rl.GuiButton({f32(window_width) - 350, 120, 80, 25}, "Delete") {
                            ordered_remove(&world.colliders, editor_g.selected_tile_collider_idx)
                            editor_g.creating_colider = false
                            editor_g.new_collider_recs[0] = rl.Rectangle{}
                            editor_g.new_collider_recs[1] = rl.Rectangle{}
                            if scrollPos >= 90{
                                scrollPos -= 90
                            }
                        }
                    }
                    
                    for collider, i in &world.colliders {
                        y_pos := f32(50 + (i * 50) - int(scrollPos))
                        if 90 + y_pos >= 100 {
                            if rl.GuiLabelButton({f32(window_width) - 256, 90 + y_pos, 150, 30}, fmt.ctprintf("Collider %v", i)) {
                                editor_g.selected_tile_collider = collider
                                editor_g.new_collider_recs[0] = collider
                                editor_g.creating_colider = true
                                editor_g.selected_tile_collider_idx = i
                            }
                        }
                    }
                    
                case .entities:
                    rl.DrawText("Entities", i32(window_width) - 256, 15, 20, rl.WHITE)
            }
        }
        rl.EndDrawing()
    }
    if json_tiles, err := json.marshal(world.tiles, allocator = context.temp_allocator); err == nil {
        os.write_entire_file("./assets/tiles.json", json_tiles)
    } 
    if colliders, err := json.marshal(world.colliders, allocator = context.temp_allocator); err == nil {
        os.write_entire_file("./assets/colliders.json", colliders)
    }
    rl.CloseWindow()
    
}