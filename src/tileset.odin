package game

import "core:os"
import "core:encoding/json"
import "core:fmt"
import rl "vendor:raylib"
import "core:math"

Layer :: struct {
    data: []i32,
    height:i32,
    id:i32,
    name:string,
    opacity:i32,
    type:string,
    visible:bool,
    width:i32,
    x:i32,
    y:i32
}

TileMap :: struct {
    width: i32,
    height: i32,
    tilewidth: i32,
    tileheight: i32,
    layers: [1]Layer
}

load_tileset :: proc(file_path: string) -> TileMap {
    if file, ok := os.read_entire_file(file_path, allocator = context.temp_allocator); ok {
        fmt.println("gere")
        tile_map := TileMap{}
        json.unmarshal(file, &tile_map, allocator = context.temp_allocator)
        return tile_map
    }
    return TileMap{}
}


draw_tilemap :: proc(tile_map: ^TileMap, texture : rl.Texture) {
    tile_size := tile_map.tilewidth
	tileset_columns := i32(texture.width) / tile_size
	for y in 0 ..< tile_map.height {
		for x in 0 ..< tile_map.width {
			tile_id := tile_map.layers[0].data[y * tile_map.width + x]
			if tile_id > 0 {
				tile_id -= 1
				source := rl.Rectangle {
					f32((tile_id % tileset_columns) * tile_size),
					f32((tile_id / tileset_columns) * tile_size),
					f32(tile_size),
					f32(tile_size),
				}
				dest := rl.Rectangle {
					f32(x * tile_size),
					f32(y * tile_size),
					f32(tile_size),
					f32(tile_size),
				}
				rl.DrawTexturePro(texture, source, dest, rl.Vector2{}, 0, rl.WHITE)
			}
		}
	}
}