#+private
package toml

import "core:encoding/json"
import "core:strings"
import "core:math"
import "core:fmt"
import "core:os"

import "dates"

main :: proc() {
    if any_of("-parse-example", ..os.args) {
        logln("=========== UNMARSHALING =============")
        unmarshal_example_toml()
        logln("=========== NORMAL PARSING =============")
        parse_example_toml()
        return
    }
    if any_of("-pack", ..os.args) {
        pack_source_files()
        return
    }

    run_integrated_test()
}

// packs .odin files into a single libtoml.odin (that still uses the dates library!)
// useful for Neovim's telescope users
// and people who don't want to litter their project...
pack_source_files :: proc() {
    alloc := make_arena(8 * 1024*1024) // 8 megabytes
    context.allocator = alloc
    defer free_all(alloc)

    files :: [?] string {
        "main.odin"         ,
        "toml.odin"         ,
        "unmarshal.odin"    ,

        "tokenizer.odin"    ,
        "validator.odin"    ,
        "parser.odin"       ,

        "misc.odin"         ,
    }

    output_file := "libtoml.odin"

    head   : strings.Builder // for package, imports and TOC
    body   : strings.Builder // for everything else (decls, ...)

    imports  :  map [string] struct{}
    contents := make([] string, len(files))
    lengths  := make([] int   , len(files))// lines per file (same order as files)

    for file, file_index in files {
        data, err := os.read_entire_file(file, alloc)
        fmt.assertf(err == nil, "Failed to pack the source files! Received error '%s' when reading '%s'", err, file)

        temp_text := string(data)
        line_count:  int
        
        for line in strings.split_lines_iterator(&temp_text) {

            if strings.starts_with(line, "package") || strings.starts_with(line, "#+") {
                continue
            }

            if strings.starts_with(strings.trim_left_space(line), "import ") {
                imports[line] = {}
                // valid odin code (as of 2026-05):
                //     import "core:os"
                //     import hmm1 "core:os"
                //     import hmm2 "core:os"
                continue
            }

            line_count += 1
        }

        contents[file_index] = string(data)
        lengths [file_index] = line_count
    }

    // ======================== HEAD ========================

    strings.write_string(&head, "package toml\n")
    strings.write_byte(&head, '\n')
    
    for import_stmt, _ in imports {
        strings.write_string(&head, import_stmt)
        strings.write_byte(&head, '\n')
    }                                             
    strings.write_byte(&head, '\n')
 
    toc_banner := "// ======================== TABLE OF CONTENTS ========================\n"
    strings.write_string(&head, toc_banner) // + 1
    toc_cursor := 8 + len(imports) + len(files)
    for file, file_index in files {
        padding := strings.repeat(".", max(len(toc_banner)-3 - 4 - len(file) - int(math.log10(f32(toc_cursor)) + 1), 4))
        fmt.sbprintfln(&head, "// %d. %s%s%d", file_index + 1, file, padding, toc_cursor)
        toc_cursor += lengths[file_index]
        toc_cursor += 6 // "\n\n === FILE NAME === \n\n"
    }
    strings.write_string(&head, "// ===================================================================\n")

    // ======================== BODY ========================

    for file, file_index in files {
        lhs_padding := strings.repeat("=", (max(42 - len(file), 1)) / 2)
        rhs_padding := strings.repeat("=", (max(43 - len(file), 0)) / 2)

        strings.write_string(&body, "\n\n// ================================================\n")
        fmt.sbprintf(&body, "// %s   %s   %s", lhs_padding, file, rhs_padding)
        strings.write_string(&body, "\n// ================================================\n\n")

        temp_text := string(contents[file_index])
        for line in strings.split_lines_iterator(&temp_text) {
            trimmed_line := strings.trim_left_space(line)

            if strings.starts_with(trimmed_line, "package ") || 
               strings.starts_with(trimmed_line, "import ")  ||
               strings.starts_with(trimmed_line, "#+") {
                continue
            }

            strings.write_string(&body, line)
            strings.write_byte(&body, '\n')
        }
    }

    // fmt.println(string(head.buf[:]))
    // fmt.println(string(body.buf[:]))
    strings.write_bytes(&head, body.buf[:])
    err := os.write_entire_file(output_file, head.buf[:])
    fmt.assertf(err == nil, "Failed to write to the output file -- %s with error %v", output_file, err)

}

unmarshal_example_toml :: proc() {
    value : struct {
        integer  : int,
        num      : f32,
        infinity : f64,
        mstr     : string `toml:"multiline_str"`,
        a : struct { b: string },
        c : struct { d: string },
        // rest of values in example.toml
        // are ignored by unmarshal_table
    }

    table, err1 := parse_file("example.toml")
    value_ptr := &value
    value_ptr_ptr := &value_ptr
    err2 := unmarshal_table(&value_ptr_ptr, table) // <-- btw, you should take 0 references of value, not 3.

    print_error(err1)
    assert(err2 == .None)

    logln(value)
}

parse_example_toml :: proc() {
    table, err := parse_file("example.toml")
    print_error(err)
    print_table(table)
}

// use ./run-tests.bash to run all tests at once
run_integrated_test :: proc() {

	data := make([]u8, 16 * 1024 * 1024)
	count, err_read := os.read(os.stdin, data)
	assert(err_read == nil || err_read == .EOF)

	table, err := parse(string(data[:count]), "<stdin>")

	if err.type != .None {print_error(err); os.exit(1)}

	idk, ok := marshal(table)
	if !ok do return

	json, _ := json.marshal(idk)
	logln(string(json))

	deep_delete(table)
    delete_error(&err)


    TypedValue :: struct {
        type:  string,
        value: union {
            map[string] UntypedValue,
            [] UntypedValue,
            string,
            bool,
            i64,
            f64,
        },
    }

    UntypedValue :: union {
        TypedValue,
        map[string] UntypedValue,
        [] UntypedValue,
    }

    marshal :: proc(input: Type) -> (result: UntypedValue, ok: bool) {
        output: TypedValue

        switch value in input {
        case nil:
            assert(false)
        case ^List:
            if value == nil do return result, false
            out := make([]UntypedValue, len(value))
            for v, i in value {out[i] = marshal(v) or_continue}
            return out, true

        case ^Table:
            if value == nil do return result, false
            out := make(map[string]UntypedValue)
            for k, v in value {out[k] = marshal(v) or_continue}
            return out, true

        case string:
            output = {
                type  = "string",
                value = value,
            }
        case bool:
            output = {
                type  = "bool",
                value = fmt.aprint(value),
            }
        case i64:
            output = {
                type  = "integer",
                value = fmt.aprint(value),
            }
        case f64:
            output = {
                type  = "float",
                value = fmt.aprint(value),
            }

        case dates.Date:
            result, err := dates.partial_date_to_string(date = value, time_sep = 'T')
            if err != .NONE do os.exit(1) // I shouldn't do this like that...

            date := value
            if date.is_time_only {
                output.type = "time-local"
            } else if date.is_date_only {
                output.type = "date-local"
            } else if date.is_date_local {
                output.type = "datetime-local"
            } else {
                output.type = "datetime"
            }
            output.value = result
        }

        return output, true
    }



}


