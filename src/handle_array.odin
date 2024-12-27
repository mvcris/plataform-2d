/*
Handle-based array. Used for many things in the game, such as entities. It is great when you need
to permanently store a reference to an array element without storing a pointer to that element.

Storing pointers is scary because:
1. If the array grows then pointer may die (can be fixed by using fixed arrays / pre-allocated
   arrays that cannot grow).
2. If one part of the game destroys something you have a pointer to then you don't know if that
   object is dead / has been replaced already.

Handle-based arrays fix this by having a Handle with an index and a generation. The index tells us
where in the array the thing is and the generation says if the thing at that index is still the same
thing as when we go hold of the handle.

See https://gist.github.com/karl-zylinski/a5c6acd551473f90b872f46a2fa58deb for an updated version
with some additional info.

Also see this article: https://floooh.github.io/2018/06/17/handles-vs-pointers.html
*/

package game

import "core:mem"
import "core:fmt"

_ :: fmt

Handle :: struct {
	idx: u32,
	gen: u32,

	// This is a hack I guess. I use this for serializing the entity ID and resolving entity references
	// after level load.
	id: UID,
}

HandleNone :: Handle {}

HandleArray :: struct($T: typeid, $HT: typeid) {
	items: [dynamic]T,
	unused_items: [dynamic]u32,
	allocator: mem.Allocator,
}

ha_delete :: proc(ha: HandleArray($T, $HT), loc := #caller_location) {
	items := ha.items
	items.allocator = ha.allocator
	delete(items, loc)
	delete(ha.unused_items, loc)
}

HandleArraySize :: 1024

ha_add :: proc(ha: ^HandleArray($T, $HT), v: T) -> HT {
	if ha.items == nil {
		ha.allocator = context.allocator
		ha.items = make([dynamic]T, 0, HandleArraySize)
		ha.items.allocator = mem.panic_allocator()
		ha.unused_items = make([dynamic]u32)
	}

	v := v

	if len(ha.unused_items) > 0 {
		reuse_idx := pop(&ha.unused_items)
		reused := &ha.items[reuse_idx]
		h := reused.handle
		reused^ = v
		reused.handle.idx = u32(reuse_idx)
		reused.handle.gen = h.gen + 1
		reused.handle.id = v.id != 0 ? v.id : new_uid()
		return reused.handle
	}

	if len(ha.items) == 0 {
		// Dummy item at idx zero
		append(&ha.items, T{})
	}

	assert(len(ha.items) < HandleArraySize, "Ran out of handles!")
	v.handle.idx = u32(len(ha.items))
	v.handle.gen = 1
	v.handle.id = v.id != 0 ? v.id : new_uid()
	append(&ha.items, v)
	return v.handle
}

ha_get :: proc(ha: HandleArray($T, $HT), h: HT) -> (T, bool) {
	if h.idx == 0 {
		return {}, false
	}

	if int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		return ha.items[h.idx], true
	}

	return {}, false
}

ha_get_ptr :: proc(ha: HandleArray($T, $HT), h: HT) -> ^T {
	if h.idx == 0 {
		return nil
	}

	if int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		return &ha.items[h.idx]
	}

	return nil
}

ha_remove :: proc(ha: ^HandleArray($T, $HT), h: HT) {
	if h.idx == 0 {
		return
	}

	if int(h.idx) < len(ha.items) && ha.items[h.idx].handle == h {
		append(&ha.unused_items, h.idx)
		ha.items[h.idx].handle.idx = 0
		ha.items[h.idx].handle.gen += 1
	}
}

ha_valid :: proc(ha: HandleArray($T, $HT), h: HT) -> bool {
	return ha_get_ptr(ha, h) != nil
}

HandleArrayIter :: struct($T: typeid, $HT: typeid) {
	ha: HandleArray(T, HT),
	index: int,
}

ha_make_iter :: proc(ha: HandleArray($T, $HT)) -> HandleArrayIter(T, HT) {
	return HandleArrayIter(T, HT) { ha = ha }
}

ha_iter :: proc(it: ^HandleArrayIter($T, $HT)) -> (val: T, h: HT, cond: bool) {
	cond = it.index < len(it.ha.items)

	for ; cond; cond = it.index < len(it.ha.items) {
		if it.ha.items[it.index].handle.idx == 0 {
			it.index += 1
			continue
		}

		val = it.ha.items[it.index]
		h = val.handle
		it.index += 1
		break
	}

	return
}

ha_iter_ptr :: proc(it: ^HandleArrayIter($T, $HT)) -> (val: ^T, h: HT, cond: bool) {
	cond = it.index < len(it.ha.items)

	for ; cond; cond = it.index < len(it.ha.items) {
		if it.ha.items[it.index].handle.idx == 0 {
			it.index += 1
			continue
		}

		val = &it.ha.items[it.index]
		h = val.handle
		it.index += 1
		break
	}

	return
}