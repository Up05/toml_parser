package toml

import "dates" // I have since learned that odin has "core:time::rfc3339_to_components"
import "core:c/libc"

import "core:strconv"
import "core:strings"
import "core:reflect"

Table :: map[string]Type
List  :: [dynamic] Type // This was added later, so there's code that doesn't use it, that might aswell.

Type :: union {
    ^Table,
    ^List,
    string,
    bool,
    i64,
    f64,
    dates.Date,
}

parse :: proc (
    data: string, original_file: string, allocator := context.allocator
) -> (tokens: ^Table, err: Error) { 
    context.allocator = allocator

    raw_tokens := tokenize(data)
    defer delete_dynamic_array(raw_tokens)

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
        prev := raw_tokens[i - 1] if i > 0 else ""
        next := raw_tokens[i + 1] if i + 1 < len(raw_tokens) else ""

        switch {
        case token == "EOF": return
        case token == "[" && next == "[":
            section = tokens

            key_index, skip, err_w := walk_down_to(&section, raw_tokens[i + 2:], "]", true)
            if err_w.type != .None {
                err.type = err_w.type
                err.more = err_w.more
                return
            }

            to_skip += skip + 3 // +3 for next == "[" and the 2 * ']'
            key := strings.clone(unquote(raw_tokens[i + 2 + key_index]))

            list, ok := section[key].(^List)
            if !ok {
                list = new(List)
                section[key] = list
            }
            append(list, new(Table))
            section = list^[len(list^) - 1].(^Table)

        case token == "[":
            section = tokens

            key_index, skip, err_w := walk_down_to(&section, raw_tokens[i + 1:], "]")
            if err_w.type != .None {
                err.type = err_w.type
                err.more = err_w.more
                return
            }

            to_skip += skip + 1 // +1 for the ']'
            key := raw_tokens[i + 1 + key_index]

            walk_table(&section, key)

        case token != "\n":
            skip, e := put(section, raw_tokens[i:])
            if e.type != .None {
                err.type = e.type
                err.more = e.more
                return
            }
            to_skip += skip

        case:
        }
    }
    return 
}
@private
entype :: proc(tokens: [] string) -> (value: Type, to_skip: int, err: Error) {
    first := tokens[0]

    switch {
    case get_quote_count(first) > 0:
        value = unquote(first)
        to_skip += 1
        return
    case starts_with(first, "true") || starts_with(first, "false"):
        value = starts_with(first, "true")
        to_skip += 1
        return 
    case is_integer(tokens):
        num, ok := strconv.parse_i64(tokens[0])
        if !ok {
            err.type = .Bad_Integer
            err.more = tokens[0]
            return
        }
        value = num
        to_skip += 1
        return
    case is_float(tokens):
        num, ok, skip := parse_float(tokens)
        if !ok {
            err.type = .Bad_Float
            err.more = strings.concatenate(tokens[:3])
            return
        }
        value = num
        to_skip += skip
        return
    case dates.is_date_lax(first):
        return parse_date(tokens)
    case tokens[0] == "[":
        return parse_list(tokens)
    case tokens[0] == "{":
        return parse_inline_table(tokens)
    case:
        err.type = .Bad_Value
        err.more = tokens[0]
        return
    }
    return
}

@private
parse_date :: proc(tokens: [] string) -> (date: dates.Date, to_skip: int, err: Error) {
    using strings
    b : Builder

    write_string(&b, tokens[0])

    if dates.is_date_lax(tokens[1]) {
        to_skip += 1
        write_rune(&b, ' ')
        write_string(&b, tokens[to_skip])
    }

    if tokens[to_skip + 1] == "." {
        to_skip += 1
        write_string(&b, tokens[to_skip])
        to_skip += 1
        write_string(&b, tokens[to_skip])
        to_skip += 1
    }
    
    to_skip += 1 // to make it 1-based, not 0-based

    err_date : dates.DateError
    date, err_date = dates.from_string(to_string(b))
    if err_date != .NONE {
        err.type = .Bad_Date
        err.more = reflect.enum_string(err_date)
    }

    return
}

@private
parse_list :: proc(tokens: [] string) -> (list: ^List, to_skip: int, err: Error) {
    assertf(tokens[0] == "[", "Tried to parse a list i.e.: '[...]', but got '%s' as first token!", tokens[0])
    
    back :: proc(arr: [dynamic] ^List) -> ^List {
        return arr[len(arr) - 1]
    }

    stack : [dynamic] ^List
    
    skip := 0
    for e, i in tokens {

        if skip > 0 {
            skip -= 1
            continue
        }

        switch e {
        case "\n": err.line += 1
        case ",": // ---
        case "[": append_elem(&stack, new(List))
        case "]": 
            list = pop(&stack)
            if len(stack) == 0 {
                to_skip = i + 1
                return
            }
            append_elem(back(stack), list)
        case "EOF": 
            err.type = .Missing_Bracket; 
            err.more = "Missing closing bracket"
            return
        case:
            val, s, e := entype(tokens[i:])
            skip = s - 1
            
            if e.type != .None {
                e.line += err.line
                return list, to_skip, e
            }
            to_skip += s
            append_elem(back(stack), val)
            continue//: for loop
        }

    }
    return

}

@private
parse_inline_table :: proc(tokens: [] string) -> (section: ^Table, to_skip: int, err: Error) {
    assertf(tokens[0] == "{", "Tried to parse inline table, i.e.: '{...}', but got '%s' as first token...", tokens[0])
    tokens := tokens[1:]; to_skip += 1 
    section = new(Table)

    skip : int
    for e, i in tokens {
        
        if skip > 0 {
            skip -= 1
            continue
        }

        switch e {
        case "\n": err.line += 1
        case ",":
        case "}": to_skip += 1; return 
        case "EOF":
            err.type = .Missing_Curly_Bracket
            err.more = "Missing closing curly bracket"
            return
        case:
            e: Error
            skip, e = put(section, tokens[i:])
            if e.type != .None {
                e.line += err.line
                return section, to_skip, e;
            }

            to_skip += skip
            skip -= 1 // This is because the current value is already key (tokens[0])
            // gets "continued" automatically

        }

        to_skip += 1

    }
    return

}

@private
put :: proc(table: ^Table, tokens: [] string) -> (to_skip: int, err: Error) {
    tokens := tokens
    table := table

    key_index, skip_w, err_w := walk_down_to(&table, tokens, "=")
    if err_w.type != .None do return to_skip, err_w
    tokens = tokens[key_index:]
    to_skip += skip_w
    
    to_skip += 1 // This is necessary for '='
    assertf(tokens[1] == "=", "When parsing assignment, i.e.: 'a = 5', expected '=' but got '%s'!", tokens[1])

    val, skip, err_entype := entype(tokens[2:])
    if err_entype.type != .None {
        err_entype.line += err.line
        return 0, err_entype
    }

    to_skip += skip
    s, _ := strings.clone(unquote(tokens[0])) // huh, sure & I cba to find out whether unquote copies too...
    #partial switch t in table^[tokens[0]] {
    case nil: table^[s] = val
    case: 
        err.type = .Key_Already_Exists
        err.more = tokens[0]
        return
    }

    
    return
}

@private
walk_down_to :: proc(section: ^^Table, tokens: [] string, stop: string, listify := false) -> 
    (key_index: int, to_skip: int, err: Error) {


    if tokens[1] != "." do return 0, 1, err

    for t, i in tokens {
        to_skip += 1

        // random bug fix
        if i + 1 >= len(tokens) || tokens[i + 1] == stop {
            return i, to_skip, err
        } 

        if t == "." do continue
        err = walk_table(section, strings.clone(unquote(t)), listify)
        if err.type != .None do return
    }

    return
}

@private // I should clean this up...
back_list :: proc(list: [dynamic] Type) -> Type {
    return list[len(list) - 1]
}

// Beauty is in the eye of the beholder
@private
walk_table :: proc(section: ^^Table, name: string, listify := false) -> Error {
    name := strings.clone(name)
    #partial switch t in section^^[name] {
    case ^Table:
    case ^List: section^ = back_list(t^).(^Table); return { }
    case nil:   
        if listify { 
            section^^[name] = new(List)
            append_elem(section^^[name].(^List), new(Table)) 
            section^ = back_list(section^^[name].(^List)^).(^Table)
            return { }
        } else do section^^[name] = new(Table);
    case:       
        return { type = .Key_Already_Exists, more = name }
    }
    section^ = section^^[name].(^Table)
    return {}
}

@private
is_integer :: proc(tokens: [] string) -> bool {
    if tokens[1] == "." do return false

    for r in tokens[0] {
        if r != '+' && r != '-' && (r < '0' || r > '9') do return false
        break // Some may call this... "Stupid." I call this: "I'm too lazy to jump to the begining of the file"
    }

    for d in tokens[0] do if d < '0' || d > '9' do return false

    return true
}

@private
is_float :: proc(tokens: [] string) -> bool {
    using strings
    if  contains(to_lower(tokens[0]), "inf") || 
        contains(to_lower(tokens[0]), "nan") { return true }
    
    _, ok := strconv.parse_f64(tokens[0])
    return ok
}

@private
parse_float :: proc(tokens: [] string) -> (num: f64, ok: bool, to_skip: int) {
    using strings
    if contains(to_lower(tokens[0]), "inf") {
        return -libc.HUGE_VAL if tokens[0][:1] == "-" else libc.HUGE_VAL, true, 1
    }
    assert(!contains(to_lower(tokens[0]), "nan"), "No.  (No NaN)")
    
    b : Builder
    write_string(&b, tokens[0])
    to_skip += 1

    if tokens[1] == "." {
        write_string(&b, tokens[1])
        write_string(&b, tokens[2])
        to_skip += 2
    }

    return strconv.parse_f64(to_string(b)), to_skip
}
