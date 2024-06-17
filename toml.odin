package toml

import "core:os"
import "base:intrinsics"

// Parses the file. You can use print_error(err) for error messages.
parse_file :: proc(filename: string, allocator := context.allocator) -> (section: ^Table, err: Error) {
    context.allocator = allocator
    blob, ok_file_read := os.read_entire_file_from_filename(filename)
    if !ok_file_read do errf("Couldn't read file at path: \"%s\"\n", filename)

    section, err = parse(string(blob), filename, allocator)
    delete_slice(blob)
    return
}

// This is made to be used with default, err := #load(filename). original_filename is only used for errors.
parse_data :: proc(data: []u8, original_filename := "untitled data", allocator := context.allocator) -> (section: ^Table, err: Error) {
    return parse(string(data), original_filename, allocator)
}

// Retrieves and type checks the value at path. The last element of path is the actual key.
//section may be any Table.
get :: proc($T: typeid, section: ^Table, path: ..string) -> (val: T, ok: bool)
    where intrinsics.type_is_variant_of(Type, T) 
{
    assert(len(path) > 0, "You must specify at least one path str in toml.fetch()!")
    section := section
    for dir in path[:len(path) - 1] {
        if dir in section {
            section, ok = section[dir].(^Table)
            if !ok do return val, false
        } else do return val, false
    }
    last := path[len(path) - 1]
    if last in section do return section[last].(T)
    else do return val, false
}

// Also retrieves and typechecks the value at path, but if something goes wrong, it crashes the program.
get_panic :: proc($T: typeid, section: ^Table, path: ..string) -> T
    where intrinsics.type_is_variant_of(Type, T)
{
    assert(len(path) > 0, "You must specify at least one path str in toml.fetch_panic()!")
    section := section
    for dir in path[:len(path) - 1] {
        assert_trace(dir in section)
        section = section[dir].(^Table)
    }
    last := path[len(path) - 1]
    assert_trace(last in section)
    return section[last].(T)
}

// Currently(2024-06-17), Odin hangs if you simply fmt.print Table
print_table :: proc(section: ^Table, level := 0){
    log("{ ")
    for k, v in section {
        log(k, "= ") 
        print_value(v, level)
    }
    log("}, ")
    if level == 0 do logln()
}

@(private="file")
print_value :: proc(v: Type, level := 0){
    #partial switch t in v {
    case ^Table:
        print_table(t, level + 1)
    case ^[dynamic] Type:
        log("[ ")
        for e in t do print_value(e, level)
        log("] ")
    case string:
        logf("%q, ", v)
    case:
        log(v, ", ", sep = "")
    }
}
