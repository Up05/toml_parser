package toml

import "core:strconv"
import "core:fmt"
import "core:strings"
import rt "base:runtime"

import "dates"

Table :: map [string] Type
List  :: [dynamic] Type

Type :: union {
    ^Table,
    ^List,
    string,
    bool,
    i64,
    f64,
    dates.Date,
}

@private
IO :: struct {
    toks    : [] string,    // all token list
    curr    : int,          // the current token index
    err     : Error,        // current error
    root    : ^Table,       // the root/global table
    section : ^Table,       // TOML's `[section]` table
    this    : ^Table,       // TOML's local p.a.t.h or { table = {} } table
    reps    : int,          // for halting upon infinite loops
    aloc    : rt.Allocator, // probably useless, honestly...
}

@private // gets a token or an empty string.
peek :: proc(io: ^IO, o := 0) -> string {
    if io.curr + o >= len(io.toks) do return ""
    if io.reps >= 1000 { // <-- solution to the halting problem!
        if io.toks[io.curr + o] == "\n" {
            make_err(io, .Bad_New_Line,  "The parser is stuck on an out-of-place new line.")
        } else {
            io.err.type = .Parser_Is_Stuck
            b_printf(&io.err.more, "Token: '%s' at index: %d", io.toks[io.curr + o], io.curr + o)
        }
        return ""
    }
    io.reps += 1

    return io.toks[io.curr + o]
}


// skips by one or more tokens, the parser & validator CANNOT go back,
@private // since my solution to the halting problem may not work then.
skip :: proc(io: ^IO, o := 1) {
    assert(o >= 0)
    io.curr += o
    if o != 0 do io.reps = 0
}

@private // returns the current token and skips to the next token.
next :: proc(io: ^IO) -> string {
    defer skip(io)
    return peek(io)
}

parse :: proc(data: string, original_file: string, allocator := context.allocator) -> (tokens: ^Table, err: Error) {
    context.allocator = allocator

    // === TOKENIZER ===
    raw_tokens, t_err := tokenize(data, file = original_file)
    defer delete_dynamic_array(raw_tokens)
    if t_err.type != .None do return nil, t_err

    // === VALIDATOR ===
    v_err := validate(raw_tokens[:], original_file, allocator)
    if v_err.type != .None do return tokens, v_err

    // === TEMP DATA ===
    tokens = new(Table)

    io: IO = {
        toks = raw_tokens[:],
        err  = { line = 1, file = original_file },

        root    = tokens,
        this    = tokens,
        section = tokens,

        aloc = allocator,
    }

    // === MAIN WORK ===
    for peek(&io) != "" {
        if io.err.type != .None {
            return nil, io.err
        }

        if peek(&io) == "\n" {
            io.err.line += 1
            skip(&io)
            continue
        }

        parse_statement(&io)
        io.this = io.section
    }

    if io.err.type != .None {
        return nil, io.err
    }

    return
}

// ======================== STATEMENTS ========================

parse_statement :: proc(io: ^IO) {
    ok: bool

    ok = parse_section_list(io);  if ok do return
    ok = parse_section(io);       if ok do return
    ok = parse_assign(io);        if ok do return

    parse_expr(io) // skips orphaned expressions
}

// This function is for dotted.paths (stops at.the.NAME)
walk_down :: proc(io: ^IO, parent: ^Table) {

    // ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! !
    // ! This is intricate as fuck and I still don't         !
    // ! really get how it works.                            !
    // ! PLEASE RUN ALL TESTS IF YOU CHANGE THIS AT ALL.     !
    // ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! !

    if peek(io, 1) != "." do return

    name, err := unquote(next(io))
    io.err.type = err.type
    io.err.more = err.more
    if err.type != .None do return
    skip(io) // '.'

    do_not_free: bool
    defer if !do_not_free do delete_string(name)

    #partial switch value in parent[name] {
    case nil:
        io.this = new(Table)
        parent[name] = io.this
        do_not_free = true

    case ^Table:
        io.this = value

    case ^List:
        if len(value^) == 0 {
            io.this = new(Table)
            append(value, io.this)

        } else {
            table, is_table := value[len(value^) - 1].(^Table)
            if !is_table {
                make_err(io, .Key_Already_Exists, name)
                return
            }
            io.this = table
        }

    case:
        make_err(io, .Key_Already_Exists, name)
        return
    }

    walk_down(io, io.this)
}


parse_section_list :: proc(io: ^IO) -> bool {
    if peek(io, 0) != "[" || peek(io, 1) != "[" do return false
    skip(io, 2) // '[' '['

    io.this = io.root
    io.section = io.root
    walk_down(io, io.root)

    name, err := unquote(next(io)) // take care with ordering of this btw
    io.err.type = err.type
    io.err.more = err.more
    if err.type != .None do return true

    list   : ^List
    result := new(Table)

    if name not_in io.this {
        list = new(List)
        io.this[name] = list

    } else if !is_list(io.this[name]) {
        make_err(io, .Key_Already_Exists, name)
    } else {
        list = io.this[name].(^List)
        delete_string(name)
    }

    append(list, result)

    skip(io, 2) // ']' ']'
    io.section = result
    return true
}

// put() is only used in parse_section, so it's specialized
// general version: commit 8910187045028ce13df3214e04ace6071ea89158
put :: proc(io: ^IO, parent: ^Table, key: string, value: ^Table) {

    // I simply admit that I do not understand how tables work...
    // fuck this shit! [[a.b]]\n [a] is somehow valid..?
    // I do not know what the hell is even that...
    // The valid tests pass. That is what matters...

    #partial switch existing in parent[key] {
    case ^Table:
        for k, v in value { existing[k] = v }
        delete_map(value^)
        value^ = existing^
    case ^List:
        append(existing, value)

    case nil:
        parent[key] = value

    case:
        make_err(io, .Key_Already_Exists, key)
    }
}

parse_section :: proc(io: ^IO) -> bool {
    if peek(io) != "[" do return false
    skip(io) // '['

    io.this = io.root
    io.section = io.root
    walk_down(io, io.root)

    name, err := unquote(next(io)) // take care with ordering of this btw
    io.err.type = err.type
    io.err.more = err.more
    if err.type != .None do return true

    result := new(Table)

    put(io, io.this, name, result)

    skip(io) // ']'
    io.this = result
    io.section = io.this
    return true
}

parse_assign :: proc(io: ^IO)  -> bool {
    if peek(io, 1) != "=" && peek(io, 1) != "." do return false

    walk_down(io, io.this)

    key, err := unquote(peek(io))
    io.err.type = err.type
    io.err.more = err.more
    if err.type != .None do return true

    if any_of(u8('\n'), ..transmute([] u8)peek(io)) {
        make_err(io, .Bad_Name, "Keys cannot have raw new lines in them")
        return true
    }

    skip(io, 2)
    value := parse_expr(io)

    if key in io.this {
        make_err(io, .Key_Already_Exists, key)
    }

    io.this[key] = value
    return true
}

// ======================== EXPRESSIONS ========================


parse_expr :: proc(io: ^IO) -> (result: Type) {
    ok: bool
    result, ok = parse_string(io); if ok do return
    result, ok = parse_bool(io);   if ok do return
    result, ok = parse_date(io);   if ok do return
    result, ok = parse_float(io);  if ok do return
    result, ok = parse_int(io);    if ok do return
    result, ok = parse_list(io);   if ok do return
    result, ok = parse_table(io);  if ok do return
    return
}

parse_string :: proc(io: ^IO) -> (result: string, ok: bool) {
    if len(peek(io)) == 0 do return
    if r := peek(io)[0]; !any_of(r, '"', '\'') do return
    str, err := unquote(next(io))
    io.err.type = err.type
    io.err.more = err.more
    return str, true
}

parse_bool :: proc(io: ^IO) -> (result: bool, ok: bool) {
    if peek(io) == "true"  { skip(io); return true, true }
    if peek(io) == "false" { skip(io); return false, true }
    return false, false
}

parse_float :: proc(io: ^IO) -> (result: f64, ok: bool) {

    has_e_but_not_x :: proc(s: string) -> bool {
        if len(s) > 2       { if any_of(s[1], 'x', 'X') do return false }
        #reverse for r in s { if any_of(r,    'e', 'E') do return true }
        return false
    }

    Infinity : f64 = 0h7FF0_0000_0000_0000 // or: 1.0e5000 (but not 1e5000)
    NaN      : f64 = 0h7FF0_0000_0000_0001 // or: transmute(f64) ( transmute(i64) Infinity | 1 )

    if len(peek(io)) == 4 {
        if peek(io)[0] == '-' { if peek(io)[1:] == "inf" { skip(io); return -Infinity, true } }
        if peek(io)[0] == '+' { if peek(io)[1:] == "inf" { skip(io); return +Infinity, true } }
        if peek(io)[1:] == "nan" { skip(io); return NaN, true }
    }

    if peek(io) == "nan" { skip(io); return NaN, true }
    if peek(io) == "inf" { skip(io); return Infinity, true }

    if peek(io, 1) == "." {
        number := fmt.aprint(peek(io), ".", peek(io, 2), sep = "")
        cleaned, has_alloc := strings.remove_all(number, "_")
        defer if has_alloc do delete(cleaned)
        defer delete(number)
        skip(io, 3)
        return strconv.parse_f64(cleaned)

    } else if has_e_but_not_x(peek(io)) {
        cleaned, has_alloc := strings.remove_all(next(io), "_")
        defer if has_alloc do delete(cleaned)
        return strconv.parse_f64(cleaned)
    }

    // it's an int then
    return
}

parse_int :: proc(io: ^IO) -> (result: i64, ok: bool) {
    result, ok = strconv.parse_i64(peek(io))
    if ok do skip(io)
    return
}

parse_date :: proc(io: ^IO) -> (result: dates.Date, ok: bool) {
    if !dates.is_date_lax(peek(io, 0)) do return
    ok = true

    full: strings.Builder
    strings.write_string(&full, next(io))

    // is date, time or both?
    if dates.is_date_lax(peek(io)) {
        strings.write_rune(&full, ' ')
        strings.write_string(&full, next(io))
    }

    if peek(io) == "." {
        strings.write_byte(&full, '.'); skip(io)
        strings.write_string(&full, next(io))
    }

    err: dates.DateError
    result, err = dates.from_string(strings.to_string(full))
    if err != .NONE {
        make_err(io, .Bad_Date, "Received error: %v by parsing: '%s' as date\n", err, strings.to_string(full))
        return
    }

    strings.builder_destroy(&full)
    return

}

parse_list :: proc(io: ^IO) -> (result: ^List, ok: bool) {
    if peek(io) != "[" do return
    skip(io) // '['
    ok = true

    result = new(List)

    for !any_of(peek(io), "]", "") {

        if peek(io) == "," { skip(io); continue }
        if peek(io) == "\n" { io.err.line += 1; skip(io); continue }

        element := parse_expr(io)
        append(result, element)
    }

    skip(io) // ']'
    return
}

parse_table :: proc(io: ^IO) -> (result: ^Table, ok: bool) {
    if peek(io) != "{" do return
    skip(io) // '{'
    ok = true

    result = new(Table)

    temp_this, temp_section := io.this, io.section
    for !any_of(peek(io), "}", "") {

        if peek(io) == "," { skip(io); continue }
        if peek(io) == "\n" { io.err.line += 1; skip(io); continue }

        io.this, io.section = result, result
        parse_assign(io)
    }
    io.this, io.section = temp_this, temp_section

    skip(io) // '}'
    return
}
