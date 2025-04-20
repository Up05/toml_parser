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
GlobalData :: struct {
    toks    : [] string, // all token list
    curr    : int,       // the current token index
    err     : Error,     // current error
    root    : ^Table,    // the root/global table
    section : ^Table,    // TOML's `[section]` table
    this    : ^Table,    // TOML's local p.a.t.h or { table = {} } table
    reps    : int,       // for halting upon infinite loops
    aloc    : rt.Allocator // probably useless, honestly...
}

@private // is only allocated when parse() and validate() are working.
g: ^GlobalData 


@private // gets a token or an empty string.
peek :: proc(o := 0) -> string {
    if g.curr + o >= len(g.toks) do return ""
    if g.reps >= 1000 { // <-- solution to the halting problem!
        if g.toks[g.curr + o] == "\n" {
            make_err(.Bad_New_Line,  "The parser is stuck on an out-of-place new line.")
        } else {
            g.err.type = .Parser_Is_Stuck
            b_printf(&g.err.more, "Token: '%s' at index: %d", g.toks[g.curr + o], g.curr + o)
        }
        return ""
    }
    g.reps += 1

    return g.toks[g.curr + o]
}


// skips by one or more tokens, the parser & validator CANNOT go back, 
@private // since my solution to the halting problem may not work then.
skip :: proc(o := 1) {
    assert(o >= 0)
    g.curr += o
    if o != 0 do g.reps = 0
}             

@private // returns the current token and skips to the next token.
next :: proc() -> string {
    defer skip()
    return peek()
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

    initial_data: GlobalData = {
        toks = raw_tokens[:],
        err  = { line = 1, file = original_file }, 

        root    = tokens,
        this    = tokens,
        section = tokens,

        aloc = allocator,
    }

    g = &initial_data
    defer g = nil

    // === MAIN WORK ===
    for peek() != "" {
        if g.err.type != .None {
            return nil, g.err
        }
        
        if peek() == "\n" {
            g.err.line += 1
            skip()
            continue
        }

        parse_statement() 
        g.this = g.section
    }
    
    if g.err.type != .None {
        return nil, g.err
    }
        
    return
}

// ==================== STATEMENTS ====================  

parse_statement :: proc() {
    ok: bool

    ok = parse_section_list();  if ok do return
    ok = parse_section();       if ok do return
    ok = parse_assign();        if ok do return

    parse_expr() // skips orphaned expressions
}

// This function is for dotted.paths (stops at.the.NAME)
walk_down :: proc(parent: ^Table) {

    // ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! !
    // ! This is intricate as fuck and I still don't         !
    // ! really get how it works.                            !
    // ! PLEASE RUN ALL TESTS IF YOU CHANGE THIS AT ALL.     !
    // ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! ! !

    if peek(1) != "." do return 

    name, err := unquote(next())
    g.err.type = err.type
    g.err.more = err.more
    if err.type != .None do return
    skip() // '.'
    
    do_not_free: bool
    defer if !do_not_free do delete_string(name)

    #partial switch value in parent[name] {
    case nil: 
        g.this = new(Table); 
        parent[name] = g.this; 
        do_not_free = true

    case ^Table:
        g.this = value

    case ^List:
        if len(value^) == 0 {
            g.this = new(Table)
            append(value, g.this)

        } else {
            table, is_table := value[len(value^) - 1].(^Table)
            if !is_table {
                make_err(.Key_Already_Exists, name)
                return
            }
            g.this = table
        }

    case:
        make_err(.Key_Already_Exists, name)
        return
    }

    walk_down(g.this)
}


parse_section_list :: proc() -> bool {
    if peek(0) != "[" || peek(1) != "[" do return false
    skip(2) // '[' '['

    g.this = g.root
    g.section = g.root   
    walk_down(g.root) 

    name, err := unquote(next()) // take care with ordering of this btw
    g.err.type = err.type
    g.err.more = err.more
    if err.type != .None do return true

    list   : ^List
    result := new(Table)

    if name not_in g.this {
        list = new(List)
        g.this[name] = list

    } else if !is_list(g.this[name]) {
        make_err(.Key_Already_Exists, name)
    } else {
        list = g.this[name].(^List)
    }

    append(list, result) 

    skip(2) // ']' ']'
    g.section = result
    return true
}

// put() is only used in parse_section, so it's specialized
// general version: commit 8910187045028ce13df3214e04ace6071ea89158
put :: proc(parent: ^Table, key: string, value: ^Table) {

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
        make_err(.Key_Already_Exists, key)
    }
}

parse_section :: proc() -> bool {
    if peek() != "[" do return false
    skip() // '['
    
    g.this = g.root
    g.section = g.root   
    walk_down(g.root)

    name, err := unquote(next()) // take care with ordering of this btw
    g.err.type = err.type
    g.err.more = err.more
    if err.type != .None do return true

    result := new(Table)

    put(g.this, name, result)

    skip() // ']'
    g.this = result
    g.section = g.this
    return true
}

parse_assign :: proc()  -> bool {
    if peek(1) != "=" && peek(1) != "." do return false

    walk_down(g.this)

    key, err := unquote(peek())
    g.err.type = err.type
    g.err.more = err.more
    if err.type != .None do return true
    
    if any_of(u8('\n'), ..transmute([] u8)peek()) {
        make_err(.Bad_Name, "Keys cannot have raw new lines in them")
        return true
    }

    skip(2);
    value := parse_expr()
    
    if key in g.this {
        make_err(.Key_Already_Exists, key)
    }

    g.this[key] = value
    return true
}

// ==================== EXPRESSIONS ====================  


parse_expr :: proc() -> (result: Type) {
    ok: bool
    result, ok = parse_string(); if ok do return
    result, ok = parse_bool();   if ok do return
    result, ok = parse_date();   if ok do return
    result, ok = parse_float();  if ok do return
    result, ok = parse_int();    if ok do return
    result, ok = parse_list();   if ok do return
    result, ok = parse_table();  if ok do return
    return
}

parse_string :: proc() -> (result: string, ok: bool) {
    if len(peek()) == 0 do return
    if r := peek()[0]; !any_of(r, '"', '\'') do return 
    str, err := unquote(next())
    g.err.type = err.type
    g.err.more = err.more
    return str, true
}

parse_bool :: proc() -> (result: bool, ok: bool) {
    if peek() == "true"  { skip(); return true, true }
    if peek() == "false" { skip(); return false, true }
    return false, false
}

parse_float :: proc() -> (result: f64, ok: bool) {

    has_e_but_not_x :: proc(s: string) -> bool {
        if len(s) > 2       { if any_of(s[1], 'x', 'X') do return false }
        #reverse for r in s { if any_of(r,    'e', 'E') do return true }
        return false
    }

    Infinity : f64 = 1e5000
    NaN := transmute(f64) ( transmute(i64) Infinity | 1 ) 

    if len(peek()) == 4 {
        if peek()[0] == '-' { if peek()[1:] == "inf" { skip(); return -Infinity, true } }
        if peek()[0] == '+' { if peek()[1:] == "inf" { skip(); return +Infinity, true } }
        if peek()[1:] == "nan" { skip(); return NaN, true }
    }

    if peek() == "nan" { skip(); return NaN, true }
    if peek() == "inf" { skip(); return Infinity, true }

    if peek(1) == "." {
        number := fmt.aprint(peek(), ".", peek(2), sep = "")
        cleaned, has_alloc := strings.remove_all(number, "_")
        defer if has_alloc do delete(cleaned)
        defer delete(number)
        skip(3)
        return strconv.parse_f64(cleaned)

    } else if has_e_but_not_x(peek()) {
        cleaned, has_alloc := strings.remove_all(next(), "_")
        defer if has_alloc do delete(cleaned)
        return strconv.parse_f64(cleaned)
    }

    // it's an int then
    return 
}

parse_int :: proc() -> (result: i64, ok: bool) { 
    result, ok = strconv.parse_i64(peek())
    if ok do skip()
    return
}

parse_date :: proc() -> (result: dates.Date, ok: bool) { 
    using strings
    if !dates.is_date_lax(peek(0)) do return
    ok = true

    full: Builder
    write_string(&full, next())
    
    // is date, time or both?
    if dates.is_date_lax(peek()) {
        write_rune(&full, ' ')
        write_string(&full, next())
    }

    if peek() == "." {
        write_byte(&full, '.'); skip()
        write_string(&full, next())
    }

    err: dates.DateError
    result, err = dates.from_string(to_string(full))
    if err != .NONE {
        make_err(.Bad_Date, "Received error: %v by parsing: '%s' as date\n", err, to_string(full))
        return
    }

    builder_destroy(&full)
    return

}

parse_list :: proc() -> (result: ^List, ok: bool) { 
    if peek() != "[" do return
    skip() // '['
    ok = true
    
    result = new(List)

    for !any_of(peek(), "]", "") {

        if peek() == "," { skip(); continue }
        if peek() == "\n" { g.err.line += 1; skip(); continue }
        
        element := parse_expr()
        append(result, element) 
    }
    
    skip() // ']'
    return
}   

parse_table :: proc() -> (result: ^Table, ok: bool) { 
    if peek() != "{" do return
    skip() // '{'
    ok = true

    result = new(Table)

    temp_this, temp_section := g.this, g.section
    for !any_of(peek(), "}", "") {
        
        if peek() == "," { skip(); continue }
        if peek() == "\n" { g.err.line += 1; skip(); continue }

        g.this, g.section = result, result
        parse_assign()
    }
    g.this, g.section = temp_this, temp_section

    skip() // '}'
    return
}

@(private="file")
make_err :: proc(type: ErrorType, more_fmt: string, more_args: ..any) {
    g.err.type = type
    context.allocator = g.aloc
    b_reset(&g.err.more)
    b_printf(&g.err.more, more_fmt, ..more_args)
}

@(private="file")
err_if_not :: proc(cond: bool, type: ErrorType, more_fmt: string, more_args: ..any) -> bool {
    if !cond do make_err(type, more_fmt, ..more_args)
    return !cond
}
