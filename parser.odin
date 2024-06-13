package main

import dates "RFC_3339_date_parser"
import "core:c/libc"

import "core:fmt" // I have since learned that odin has "core:time::rfc3339_to_components"
import "core:strconv"
import "core:strings"

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

parse :: proc() {

    raw_tokens := tokenize("test.toml")

    tokens := make_map(Table)
    section := &tokens
    // section: ^Table = new(Table)
    // tokens["bigtest"] = section
    inline_table_path: [dynamic]string // this won't work, because I would need to reset it after inline + ! don't forget to close in task manager...

    to_skip := 0
    for token, i in raw_tokens {

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
            if starts_with(prev, ".") do logln("TODO dots") //

            assert(i + 2 < len(raw_tokens))
            nextnext := raw_tokens[i + 2]

            if false && starts_with(nextnext, "{") {
                if key in section {     // type_of(section[key]) != ^Table 
                    section^[key] = new_clone(make_map(Table))
                    section = section[key].(^Table)
                }

                append_elem(&inline_table_path, key)
                to_skip += 2
                break
            }
            val, skip, ok := entype(nextnext, raw_tokens[i + 3:])
            if ok do section^[key] = val
            // logln(inline_table_path, ":", key, "=", val)
            to_skip += skip

        case starts_with(next, "[") && starts_with(raw_tokens[i + 2], "["):
            assert(token == "\n")
            assert(i + 3 < len(raw_tokens))
            nextnextnext := raw_tokens[i + 3]

            if tokens[nextnextnext] == nil {
                tokens[nextnextnext] = new([dynamic]Type)
            }

            val := new(Table)
            append_elem(tokens[nextnextnext].(^[dynamic]Type), val)
            section = val

            to_skip += 5
        case starts_with(next, "["):
            assert(token == "\n")
            assert(i + 2 < len(raw_tokens))
            nextnext := raw_tokens[i + 2]

            // if type_of(section[nextnext]) == ^Table do errf("PARSER", "TODO. Please use [[ for list of tables")
            tokens[nextnext] = new_clone(make_map(Table))

            section = tokens[nextnext].(^Table)
            // append_elem(&inline_table_path, nextnext) // "inline table"
            to_skip += 3

        case starts_with(next, "}"):
            if len(inline_table_path) == 0 do break
            pop(&inline_table_path) // this has to go all the way from left to rightmost "directory"/object
            section = &tokens
            for dir in inline_table_path {
                section = section[dir].(^Table)
            }
            to_skip += 1

        }

    }
    logln()
    logln(":( -", tokens)
    // logln(tokens["table"].(^Table)["b"])
    // fmt.println(tokens["table"])

    // 1) a) Memory access violation when I dereference the pointer
    //    b) after transmuting a pointer to an ^int, the ptr looks fine 
    // 2) fmt.println just freezes, when I give it ANY of the maps in the union
    // 3) accessing the value that is inside the map works perfectly...

    // logln("arr:", tokens["test3"].(^Table)["yep"])
    // logln(tokens["test3"].(^[dynamic]Type)[0].(^Table)["b"])
    // for k, v in tokens.(^Table)^ {
    //     logln("key:", k)
    //     logf("val: %s", v)
    // }
    // logln(tokens)
}
// expects a slice of the raw_tokens array [token_index:]
entype :: proc(
    token: string,
    raw_tokens: []string,
    level := 0,
) -> (
    value: Type,
    to_skip: int,
    ok: bool,
) {
    switch {
    case get_quote_count(token) > 0:
        value = unquote(token)
        return value, to_skip, true

    case starts_with(token, "true") || starts_with(token, "false"):
        value = starts_with(token, "true")
        return value, to_skip, true

    case dates.is_date_lax(token):
        date: dates.Date
        err: dates.DateError

        if dates.is_date_lax(raw_tokens[1]) {
            concated, _ := strings.concatenate({token, " ", raw_tokens[1]})
            date, err = dates.from_string(concated)
            to_skip += 1
        } else {
            date, err = dates.from_string(token)
        }
        to_skip += 1
        if err != nil do errf("PARSER", "Failed to parse date \"%v\"", err)

        value = date
        return value, to_skip, true

    case starts_with(token, "["):
        nested_bracket_count: int

        element_count: int
        for elem, j in raw_tokens {
            if starts_with(elem, "[") do nested_bracket_count += 1
            if starts_with(
                elem,
                "]",
            ) {if nested_bracket_count > 0 {nested_bracket_count -= 1} else do break}
            if starts_with(elem, "EOF") && nested_bracket_count > 0 do errln("PARSER", "Found unmatched '['")

            if nested_bracket_count <= 0 && elem != "," do element_count += 1
        }
        assert(nested_bracket_count == 0)
        arr := new([dynamic]Type)
        arr^ = make_dynamic_array_len_cap([dynamic]Type, 0, element_count)
        to_skip_nested: int
        for arr_token, j in raw_tokens {
            if to_skip_nested > 0 {
                to_skip_nested -= 1
                continue
            }

            if j == 0 || starts_with(raw_tokens[j - 1], ",") {
                val, skip, ok := entype(
                    arr_token,
                    raw_tokens[j + (1 if starts_with(arr_token, "[") else 0):],
                    level + 1,
                )
                if ok {
                    append_elem(arr, val)
                    to_skip_nested = skip
                }
            }

            if starts_with(arr_token, "]") {
                value = arr
                return value, j + 1 + to_skip_nested, true // +1 is for the equals sign
            } else if starts_with(arr_token, "EOF") do logln("BAD BAD BAD no matching closing bracket!")


        }
    case starts_with(token, "{"):
        return nil, 0, false // this isn't handled here!

    case:
        // int & float
        token := token
        is_space_last_char :=
            strings.index_any(token[len(token) - 1:], SEPERATOR_SYMBOLS) != -1
        if is_space_last_char do token = token[:len(token) - 1]

        num, ok1 := strconv.parse_i64(token)
        if ok1 {
            value = num
            return value, to_skip, true
        }
        dec, ok2 := parse_float(token)
        if ok2 {
            value = dec
            return value, to_skip, true
        }
    }
    return nil, to_skip, false
}

parse_float :: proc(s: string) -> (f64, bool) {
    if starts_with(s, "inf") || starts_with(s[1:], "inf") {
        if starts_with(s[:1], "-") do return -libc.HUGE_VAL, true
        else do return libc.HUGE_VAL, true
    } else if starts_with(s, "nan") || starts_with(s[1:], "nan") {
        errln("Tokenizer", "Just no... (Why are you using nan in toml???)")
    }

    num, ok := strconv.parse_f64(s)
    if ok do return num, true
    return num, false
}
