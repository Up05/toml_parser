package toml

import "dates" // I have since learned that odin has "core:time::rfc3339_to_components"
import "core:c/libc"

import "core:strconv"
import "core:strings"
import "core:reflect"

Table :: map[string]Type

Type :: union {
    ^Table,
    ^[dynamic]Type,
    string,
    bool,
    i64,
    f64,
    dates.Date,
}

parse :: proc(data: string, original_file: string, allocator := context.allocator) -> (tokens: ^Table, err: Error) {
    context.allocator = allocator
    raw_tokens := tokenize(data)
    // defer delete_dynamic_array(raw_tokens)
    err_v := validate(raw_tokens, original_file)
    if err_v.type != .None do return tokens, err_v

    tokens = new(Table)
    section := tokens

    err.file = original_file

    to_skip := 0
    for token, i in raw_tokens {
        if token == "\n" do err.line += 1

        if to_skip > 0 {
            to_skip -= 1
            continue
        }

        prev, next: string
        if i > 0 do prev = raw_tokens[i - 1]
        if i < len(raw_tokens) - 1 do next = raw_tokens[i + 1]

        switch {
        case starts_with(next, "="):
            key := token
            // key = key[get_quote_count(key):]
            // key = key[:len(key) - get_quote_count(key[len(key) - 1:])]
            key = unquote(key)

            // A little bit of back and forth, you know how it goes... 
            // Dotted.key.handler:
            use_temp_section := false
            temp_section := section
            path_start := 0
            if starts_with(prev, ".") {
                #reverse for key1, j in raw_tokens[:i - 1] {
                    if key1 == "\n" {
                        path_start = j + 1
                        break
                    }
                }
                use_temp_section = true
            }
            assert(i + 2 < len(raw_tokens))
            nextnext := raw_tokens[i + 2]

            if nextnext == "{" { // This is so trash & it repeats lower in the file
                                 // I just can't be arsed to fix this and use entype immediately 
                skip, err_table := handle_inline_table (
                    section, raw_tokens[path_start:]
                )
                to_skip += skip
                if err_table.type != .None {
                    err.type = err_table.type
                    err.more = err_table.more
                    return
                }
            } else {
                
                if use_temp_section {
                    for key2 in raw_tokens[path_start:i - 1] {
                        if key2 == "." do continue
                        dir := unquote(key2)
                        if dir not_in temp_section do temp_section[dir] = new(Table)
                        else if type_of(temp_section[dir]) != ^Table {
                            err.type = .Key_Already_Exists
                            err.more = dir
                            return
                        }
                        temp_section = temp_section[dir].(^Table)
                    }
                }
                val, skip, err_entype := entype(nextnext, raw_tokens[i + 3:], i_hate_this = true)
                if err_entype.type == .None {
                    if use_temp_section do temp_section^[key] = val
                    else do section^[key] = val
                } else {
                    err.type = err_entype.type
                    err.more = err_entype.more
                    return
                }
                to_skip += skip
            }

        case starts_with(token, "[") && starts_with(next, "["):
            assert(prev == "\n")
            assert(i + 3 < len(raw_tokens))
            nextnext := raw_tokens[i + 2]

            if raw_tokens[i + 3] == "." {
                section = tokens
                key: string
                for key1, j in raw_tokens[i + 2:] {
                    if starts_with(raw_tokens[i + j + 3], "]") {
                        key = key1
                        to_skip += 1
                        break
                    }
                    to_skip += 1
                    if key1 == "." do continue
                    walk_down_table(&section, unquote(key1))
                }
                if section[key] == nil do section[key] = new([dynamic] Type)
                arr_ptr := section[key].(^[dynamic]Type)
                append_elem(arr_ptr, new(Table))
                section = arr_ptr^[len(arr_ptr^) - 1].(^Table)
            } else {
                if tokens[nextnext] == nil {
                    tokens[nextnext] = new([dynamic]Type)
                }
                val := new(Table)
                append_elem(tokens[nextnext].(^[dynamic]Type), val)
                section = val
                to_skip += 1
            }

            to_skip += 4
        case starts_with(token, "["):
            assert(prev == "\n")
            assert(i + 2 < len(raw_tokens))

            if type_of(section[next]) == ^Table {
                err.type = .Key_Already_Exists
                err.more = next
                return
            } 

            if raw_tokens[i + 2] == "." {
                section = tokens
                for key1 in raw_tokens[i + 1:] {
                    if starts_with(key1, "]") do break
                    to_skip += 1
                    if key1 == "." do continue

                    walk_down_table(&section, unquote(key1))
                }
            } else {
                tokens[next] = new_clone(make_map(Table))
                section = tokens[next].(^Table)
                to_skip += 1
            }
            // append_elem(&inline_table_path, nextnext) // "inline table"
            to_skip += 2

        }

    }
    return
}

@(private="file")
entype :: proc(
    token: string,
    raw_tokens: []string,
    level := 0,
    i_hate_this := false // Why are dotted/orphan and inline tables even a thing?..
) -> (
    value: Type,
    to_skip: int,
    err: Error,
) {
    switch {
    case get_quote_count(token) > 0:
        value = unquote(token)
        return 

    case starts_with(token, "true") || starts_with(token, "false"):
        value = starts_with(token, "true")
        return 

    case dates.is_date_lax(token):
        date: dates.Date
        err_date: dates.DateError
        
        dateb : strings.Builder
        strings.write_string(&dateb, token)
        skip := 0
        if dates.is_date_lax(raw_tokens[0]) {
            if !starts_with(raw_tokens[0], "T") do strings.write_rune(&dateb, ' ')
            strings.write_string(&dateb, raw_tokens[0])
            skip += 1
        } if raw_tokens[skip] == "." {
            strings.write_rune(&dateb, '.')
            skip += 1
            strings.write_string(&dateb, raw_tokens[skip])
            skip += 1
        }
        to_skip += skip + 1 // +1 for original date
        date, err_date = dates.from_string(strings.to_string(dateb))
        
        value = date
        if err_date != .NONE {
            err.type = .Bad_Date
            err.more = reflect.enum_string(err_date)
            return 
        }
        return 

    case starts_with(token, "["):
        nested_bracket_count: int = 0

        element_count: int
        for elem in raw_tokens {
            if starts_with(elem, "[") do nested_bracket_count += 1
            if starts_with(
                elem,
                "]",
            ) {if nested_bracket_count > 0 {nested_bracket_count -= 1} else do break}
            if starts_with(elem, "EOF") && nested_bracket_count > 0 {
                err.type = .Missing_Bracket
                return err
            }

            if nested_bracket_count <= 0 && elem != "," do element_count += 1
        }
        assert(nested_bracket_count == 0)
        arr := new([dynamic]Type)
        arr^ = make_dynamic_array_len_cap([dynamic]Type, 0, element_count)
        to_skip_nested: int
        for arr_token, j in raw_tokens {
            if to_skip_nested > 1 {
                to_skip_nested -= 1
                continue
            }

            if j == 0 || starts_with(raw_tokens[j - 1], ",") {
                val, skip, err_nested := entype(
                    arr_token,
                    raw_tokens[j + int(i_hate_this):],
                    level + 1,
                    i_hate_this
                )
                if err_nested.type != .None {
                    return value, 0, err_nested
                } else {
                    append_elem(arr, val)
                    to_skip_nested = skip
                }
            }
            else if starts_with(arr_token, "]") {
                value = arr
                return value, j + 1 + to_skip_nested, err // +1 is for the equals sign
            } else if starts_with(arr_token, "EOF") {
                err.type = .Missing_Bracket
                return
            }


        }
    case starts_with(token, "{"):
        
        section := new(Table)
        skip, err_table := handle_inline_table (
            section, raw_tokens[1:]
        )
        if err_table.type != .None {
            err.type = err_table.type
            err.more = err_table.more
            return
        }

        return section, skip + 1, err
    
    case len(raw_tokens) > 0 && raw_tokens[0] != "." && is_number(token): // int 
        num, ok := strconv.parse_i64(token)
        if ok {
            value = num
            to_skip += 1
            return 
        } else {
            err.type = .Bad_Integer
            err.more = token
            return
        }

    case:
        assert(len(raw_tokens) > 1, "Why the hell is a float's decimal char the penultimate character in your config!?")

        float_str := strings.concatenate( { token, ".", raw_tokens[1] } )
        dec, ok := parse_float(float_str)
        if ok {
            value = dec
            to_skip += 3
            return 
        } else {
            err.type = .Bad_Float
            err.more = float_str
            return
        }  
    }
    err.type = .Bad_Value
    return 
}

@(private="file")
is_number :: proc(str: string) -> bool {
    digits := 0 
    for r in str {
        if r >= '0' && r <= '9' do digits += 1
    }
    return len(str) - digits < 3
}

// I regret raw_tokens = raw_tokens[...:]...
@(private="file")
handle_inline_table :: proc(section: ^Table, raw_tokens: [] string, level := 0) -> (to_skip: int, err: Error) {
    raw_tokens := raw_tokens
    key: string
    first_element := true
    // # Loops thru each comma-seperated value in the table 
    for len(raw_tokens) > -1 && raw_tokens[0] == "," || first_element {
        temp_section: ^Table
        temp_section = section 
        first_element = false
        
        if raw_tokens[0] == "," || raw_tokens[0] == "{" { 
            raw_tokens = raw_tokens[1:] // i hate this...
            to_skip += 1
        }
        // # Deals with dotted.keys & grabs the key
        if raw_tokens[1] == "." {
            for key1, i in raw_tokens {
                to_skip += 1
                if raw_tokens[i + 1] == "=" {
                    to_skip += 1
                    key = raw_tokens[i]
                    raw_tokens = raw_tokens[i + 2:]
                    break
                }
                if key1 == "." do continue
                err = walk_down_table(&temp_section, unquote(key1))
                if err.type != .None do return
            }
        // # Grabs the key
        } else {
            to_skip += 2
            key = raw_tokens[0]
            raw_tokens = raw_tokens[2:]
        }

        skip: int
        // # Handles tables, technically redundant, since entype() already does that...
        if starts_with(raw_tokens[0], "{") {
            err = walk_down_table(&temp_section, unquote(key))
            if err.type != .None do return

            skip, err = handle_inline_table(temp_section, raw_tokens[1:], level + 1)
            if err.type != .None do return

            skip += 1
            raw_tokens = raw_tokens[skip:]
            to_skip += skip
        // Handles normal values (not tables)
        } else {
            val: Type;
            val, skip, err = entype(raw_tokens[0], raw_tokens[1:])
            if err.type != .None do return

            temp_section[key] = val
            raw_tokens = raw_tokens[skip:]
            to_skip += skip
        }
        if raw_tokens[0] == "}" do to_skip += 1
        if raw_tokens[0] != "," do return
    }
    return
}

walk_down_table :: proc(section: ^^Table, name: string) -> (err: Error) {
    #partial switch t in section^^[name] {
        case ^Table: // do nothing
        case nil: section^^[name] = new(Table)
        case:
            err.type = .Key_Already_Exists
            err.more = name
            return
    }
    section^ = section^^[name].(^Table)
    return
}

parse_float :: proc(s: string) -> (f64, bool) {
    if starts_with(s, "inf") || starts_with(s[1:], "inf") {
        if starts_with(s[:1], "-") do return -libc.HUGE_VAL, true
        else do return libc.HUGE_VAL, true
    } else if starts_with(s, "nan") || starts_with(s[1:], "nan") {
        errln("Tokenizer", "Just no... (Why are you using nan in TOML???)")
    }

    num, ok := strconv.parse_f64(s)
    if ok do return num, true
    return num, false
}
