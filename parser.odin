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
    aloc    : rt.Allocator
}

@private // 8 bytes vs ~128 bytes
g: ^GlobalData

@private
peek :: proc(o := 0, caller := #caller_location) -> string {
    // logln(caller)
    if g.curr + o >= len(g.toks) do return ""
    if g.reps >= 1000 {
        if g.toks[g.curr + o] == "\n" {
            g.err.type = .Bad_New_Line
            g.err.more = "The parser is stuck on an out-of-place new line."
        } else {
            g.err.type = .Parser_Is_Stuck
            g.err.more = fmt.aprintf("Token: '%s' at index: %d", g.toks[g.curr + o], g.curr + o)
        }
        return ""
    }
    g.reps += 1

    return g.toks[g.curr + o]
}

@private
skip :: proc(o := 1, caller := #caller_location) {
    assert(o >= 0)
    g.curr += o
    if o != 0 do g.reps = 0
}             

@private
next :: proc() -> string {
    defer skip()
    return peek()
}

parse :: proc(data: string, original_file: string, allocator := context.allocator) -> (tokens: ^Table, err: Error) { 
    
    {
        g = new(GlobalData); defer free(g)
        g^ = {
            toks = { }, // set right after tokenizer
            curr = 0,
            err  = { line = 1, file = original_file }, 
            root = new(Table),
            section = nil,
            this = nil,
            aloc = allocator,
        }

        g.section = g.root
        g.this    = g.root
    }

    context.allocator = allocator

    raw_tokens, tokenizer_err := tokenize(data, file = original_file)
    g.toks = raw_tokens[:]
    defer delete_dynamic_array(raw_tokens)
    if tokenizer_err.type != .None do return nil, tokenizer_err
    
    {
        err := validate_new(raw_tokens[:], original_file, allocator)
        if err.type != .None do return tokens, err
    }

    tokens = g.root
    
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

walk_down :: proc(parent: ^Table) {
    if peek(1) != "." do return 

    name, err := unquote(next())
    g.err.type = err.type
    g.err.more = err.more
    if err.type != .None do return
    skip() // '.'
    
    #partial switch value in parent[name] {
    case nil: 
        g.this = new(Table); 
        parent[name] = g.this; 

    case ^Table:
        g.this = value

    case ^List:
        if len(value^) == 0 {
            g.this = new(Table)
            append(value, g.this)

        } else {
            table, is_table := value[len(value^) - 1].(^Table)
            if !is_table {
                g.err.type = .Key_Already_Exists
                g.err.more = name
                return
            }
            g.this = table
        }

    case:
        g.err.type = .Key_Already_Exists
        g.err.more = name
        return
    }

    walk_down(g.this)
}


parse_section_list :: proc() -> bool {
    if peek(0) != "[" || peek(1) != "[" do return false
    skip(2) // '[' '['

    g.this = g.root
    g.section = g.root   
    walk_down(g.root) // TODO maybe (g.this = parent) in wlak-down_

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
        g.err.type = .Key_Already_Exists
        g.err.more = name // should be the whole line here, honestly

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
    // I simply ... that I do not understand how toml tables work.
    // fuck this shit. [[a.b]]\n [a] is somehow valid.
    // I do not know what the hell is even that.
    // The valid tests passs. That is what matters.
    // ...

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
        g.err.type = .Key_Already_Exists
        g.err.more = key
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
        g.err.type = .Bad_Name
        g.err.more = "Keys cannot have raw new lines in them"
        return true
    }

    skip(2);
    value := parse_expr()
    
    if key in g.this {
        g.err.type = .Key_Already_Exists
        g.err.more = key
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
        if peek()[0] == '-' { if eq(peek()[1:], "inf") { skip(); return -Infinity, true } }
        if peek()[0] == '+' { if eq(peek()[1:], "inf") { skip(); return +Infinity, true } }
        if eq(peek()[1:], "nan") { skip(); return NaN, true }
    }

    if eq(peek(), "nan") { skip(); return NaN, true }
    if eq(peek(), "inf") { skip(); return Infinity, true }

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
    
    if dates.is_date_lax(peek()) {
        write_rune(&full, ' ')
        write_string(&full, next())
    }

    if peek(0) == "." {
        write_string(&full, next())
        write_string(&full, next())
    }

    err: dates.DateError
    result, err = dates.from_string(to_string(full))
    if err != .NONE {
        g.err.type = .Bad_Date
        g.err.more = fmt.aprintf("Received error: %v by parsing: '%s' as date\n", err, to_string(full))
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


