package toml

import "core:strconv"
import "core:fmt"
import "core:strings"

import "dates"

Table :: map[string]Type
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

@(private="file")
g: struct {
    toks : [] string,
    curr : int,
    err  : Error,
    root : ^Table,
    section: ^Table,
    this : ^Table,
}

peek :: proc(o := 0) -> string {
    if g.curr + o >= len(g.toks) do return ""
    return g.toks[g.curr + o]
}

skip :: proc(o := 1) {
    g.curr += o
}

next :: proc() -> string {
    defer skip()
    return peek()
}

parse :: proc(data: string, original_file: string, allocator := context.allocator
    ) -> (tokens: ^Table, err: Error) { 
    
    context.allocator = allocator

    raw_tokens, tokenizer_err := tokenize(data, file = original_file)
    defer delete_dynamic_array(raw_tokens)
    if tokenizer_err.type != .None do return nil, tokenizer_err
    
    {
        err := validate(raw_tokens, original_file)
        if err.type != .None do return tokens, err
    }           

    g = {
        toks = raw_tokens[:],
        curr = 0,
        err  = { file = original_file }, 
        root = new(Table),
        section = nil,
        this = nil,
    }
    g.section = g.root
    g.this    = g.root

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
        // logf("%s, ", peek())
    }
    
    return
}

// ==================== STATEMENTS ====================  

parse_statement :: proc() {
    ok: bool

    ok = parse_section_list(); if ok do return
    ok = parse_section(); if ok do return
    
    ok = parse_assign(); 
    if !ok do parse_expr()
}

parse_path :: proc() -> (root_key: string, root: ^Table, last: ^Table, ok: bool) {//{{{
    parse_path_inner :: proc(parent: ^Table) -> (table: ^Table, ok: bool) {
        if peek(1) != "." do return
        ok = true

        key := unquote(next()); skip(1) // '.'
        table = new(Table)

        parent[key] = table
        ctable, cok := parse_path_inner(table)
        if cok do return ctable, true

        return 
    }

    if peek(1) != "." do return
    
    root_key = unquote(next()); skip()
    root = new(Table)

    ctable, cok := parse_path_inner(root)
    if cok do return root_key, root, ctable, true 
    return root_key, root, root, true
}//}}}

walk_down :: proc(parent: ^Table) {//{{{
    if peek(1) != "." do return 
    
    name := unquote(next())
    skip() // '.'
    
    #partial switch value in parent[name] {
    case nil: 
        g.this = new(Table)
        parent[name] = g.this
    case ^Table:
        ok: bool
        g.this, ok = parent[name].(^Table)
        if !ok { g.this = new(Table); parent[name] = g.this}

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
}//}}}


parse_section_list :: proc() -> bool {//{{{
    if peek(0) != "[" || peek(1) != "[" do return false
    skip(2) // '[' '['

    g.this = g.root
    g.section = g.root   
    walk_down(g.root) // TODO maybe (g.this = parent) in wlak-down_

    name   := unquote(next()) // take care with ordering of this btw
    list   : ^List
    result := new(Table)

    if name not_in g.this {
        list = new(List)
        g.this[name] = list
    } else if  _, is_list := g.this[name].(^List); !is_list {
        g.err.type = .Key_Already_Exists
        g.err.more = name // should be the whole line here, honestly
    } else {
        list = g.this[name].(^List)
    }
    append(list, result) 

    skip(2) // ']' ']'
    g.section = result
    return true
}//}}}


put :: proc(parent: ^Table, key: string, value: Type) {//{{{
    if key not_in parent {
        parent[key] = value
        return
    }

    #partial switch A in parent[key] {
    case ^Table:
        #partial switch B in value {
        case ^Table:
            for k, v in B { A[k] = v }
            delete_map(B^)
            B^ = A^
        case: 
            A[key] = value
        }
    case ^List:
        append(A, value)
    case: 
        g.err.type = .Key_Already_Exists
        g.err.more = key
    }
}//}}}


parse_section :: proc() -> bool {
    if peek() != "[" do return false
    skip() // '['
    
    g.this = g.root
    g.section = g.root   
    walk_down(g.root)

    name  := unquote(next()) // take care with ordering of this btw
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

    key   := unquote(peek()); skip(2);
    value := parse_expr()

    g.this[key] = value
    return true
}

// ==================== EXPRESSIONS ====================  


parse_expr :: proc() -> (result: Type) {
    ok: bool
    result, ok = parse_string(); if ok do return result
    result, ok = parse_bool();   if ok do return result
    result, ok = parse_date();   if ok do return result
    result, ok = parse_float();  if ok do return result
    result, ok = parse_int();    if ok do return result
    result, ok = parse_list();   if ok do return result
    result, ok = parse_table();  if ok do return result

    return result
}

parse_string :: proc() -> (result: string, ok: bool) {
    if len(peek()) == 0 || (peek()[0] != '"' && peek()[0] != '\'') do return 
    return unquote(next()), true
}

parse_bool :: proc() -> (result: bool, ok: bool) {
    defer skip(+1)
    if peek() == "true"  do return true, true
    if peek() == "false" do return false, true
    skip(-1)
    return false, false
}

parse_float :: proc() -> (result: f64, ok: bool) {
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
    } else if strings.contains(peek(), "e") || strings.contains(peek(), "E") {
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
    }

    builder_destroy(&full)
    return

}

parse_list :: proc() -> (result: ^List, ok: bool) { 
    if peek() != "[" do return
    skip() // '['
    ok = true
    
    result = new(List)

    for peek() != "]" && peek() != "" {

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
    for peek() != "}" && peek() != "" {
        
        if peek() == "," { skip(); continue }
        if peek() == "\n" { g.err.line += 1; skip(); continue }

        g.this, g.section = result, result
        parse_assign()
    }
     g.this, g.section = temp_this, temp_section

    skip() // '}'
    return
}
































