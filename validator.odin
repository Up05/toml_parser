package toml

import "base:runtime"
import "core:fmt"

ErrorType :: enum {
    None,

    Bad_Date,
    Bad_File,
    Bad_Float,
    Bad_Integer,
    Bad_Name,
    Bad_New_Line,
    Bad_Unicode_Char,
    Bad_Value,

    Missing_Bracket,
    Missing_Comma,
    Missing_Key,
    Missing_Newline,
    Missing_Quote,
    Missing_Value,

    Double_Comma,
    Expected_Equals,
    Key_Already_Exists,
    Parser_Is_Stuck,
    Unexpected_Token,
}

Error :: struct {
    type: ErrorType,
    line: int,    
    file: string,
    more: Builder,
}

// The filename is not freed, since it is only sliced 
delete_error :: proc(err: ^Error) {
    if err.type != .None do b_destroy(&err.more)
}

// This may also be a warning!
print_error :: proc(err: Error, allocator := context.allocator) -> (fatal: bool) {
    message: string
    message, fatal = format_error(err)
    if message != "" {
        logf("[TOML ERROR] %s", message) 
        delete(message, allocator)
    }
    return fatal
}

// The message is allocated and should be freed after use.
format_error :: proc(err: Error, allocator := context.allocator) -> (message: string, fatal: bool) {
    descriptions : [ErrorType] string = {
        .None               = "",
        .Bad_Date           = "Failed to parse a date",
        .Bad_File           = "Toml parser could not read the given file",
        .Bad_Float          = "Failed to parse a floating-point number (may be invalid value)",
        .Bad_Integer        = "Failed to parse an interger",
        .Bad_Name           = "Bad key/table name found before, use quotes, or only 'A-Za-z0-9_-'",
        .Bad_New_Line       = "New line is out of place",
        .Bad_Unicode_Char   = "Found an invalid unicode character in string",
        .Bad_Value          = "Bad value found after '='",
        .Double_Comma       = "Lists must have exactly 1 comma after each element (except trailing commas are optional)",
        .Expected_Equals    = "Expected '=' after assignment of a key",
        .Key_Already_Exists = "That key/section already exists",
        .Missing_Bracket    = "A bracket is missing (one of: '[', '{', '}', ']')",
        .Missing_Comma      = "A comma is missing",
        .Missing_Key        = "Expected key before '='",
        .Missing_Newline    = "A new line is missing between two key-value pairs",
        .Missing_Quote      = "Missing a quote",
        .Missing_Value      = "Expected a value after '='",
        .Parser_Is_Stuck    = "Parser has halted due to being in an infinite loop",
        .Unexpected_Token   = "Found a token that should not be there",
    }

    return fmt.aprintf("%s:%d %s! %s\n", err.file, err.line + 1, descriptions[err.type], err.more.buf[:]), true
}

// Skips all consecutive new lines
// new lines should not be skipped everywhere
// that's why this is not inside of the peek() procedure.
skip_newline :: proc() -> (ok: bool) { ok = peek() == "\n"; for peek() == "\n" { g.err.line += 1; skip() }; return }

validate :: proc(raw_tokens: [] string, file: string, allocator := context.allocator) -> Error {

    initial_data: GlobalData = {
        toks = raw_tokens,
        err  = { line = 1, file = file },
        aloc = allocator,
    }

    snapshot := g
    g = &initial_data
    defer g = snapshot

    for peek() != "" {
        if !validate_stmt() {
            make_err(.Unexpected_Token, "Could not validate the (assumed to be) statement: %s", peek())
        }
        if g.err.type != .None do break
    }

    err := g.err
    return err
}

// '||' operator has short-circuiting in Odin, so I use this to chain functions.
validate_stmt :: proc() -> bool {
    return skip_newline()   ||   (validate_array() || validate_table() || validate_assign())   &&    

           !err_if_not(peek() == "" || peek() == "\n", .Missing_Newline, "Found a missing new line between statements.") 
}

// array of tables: `[[item]]` at the start of lines
validate_array :: proc() -> bool {
    if peek(0) != "[" || peek(1) != "[" do return false
    #no_bounds_check {
        if err_if_not(peek(0)[1] == '[', .Missing_Bracket, "In section array both brackets must follow one another! '[[' not '[ ['") do return false
    }
    
    skip(2) // '[' '['
    validate_path()

    #no_bounds_check {
        if peek(0) == "]" && peek(1) == "]" && err_if_not(peek(0)[1] == ']', .Missing_Bracket, "In section array both brackets must follow one another! ']]' not '] ]'") do return false
    }
    if err_if_not(next() == "]", .Missing_Bracket, "']' missing in section array declaration") do return false   
    if err_if_not(next() == "]", .Missing_Bracket, "']' missing in section array declaration") do return false  

    return true
}

// tables: `[object]` at the start of lines
validate_table :: proc() -> bool {
    if peek(0) != "[" do return false
    
    skip() // '['
    validate_path()
    return !err_if_not(next() == "]", .Missing_Bracket, "']' missing in section declaration")   
}

// key = value
validate_assign :: proc() -> bool {
    if peek(1) != "=" && peek(1) != "." do return false

    if !validate_path() do return false
    if err_if_not(peek() == "=", .Expected_Equals, "Keys must be followed by '=' and then the value! Instead got: %s", peek()) do return false
    skip() // '='
    return validate_expr()
}

// there.are.dotted.paths.in.toml   each "directory" is supposed to be an object, last depends on the context.
// for example: in statement [[a.b]] a is a Table, b is a List of Table(s)
validate_path :: proc() -> bool {//{{{
    validate_name :: proc() -> bool {
        skip()
        return true
    }

    for peek(1) == "." {
        if peek(0) == "\n" || peek(2) == "\n" {
            make_err(.Bad_New_Line, "paths.of.keys must be on the same line")
            return false
        }

        if !validate_name() {
            make_err(.Bad_Name, "key in path cannot have this name: '%s'", peek())
            return false
        }
        skip()
    }

    if !validate_name() {
        make_err(.Bad_Name, "key in path cannot have this name: '%s'", peek())
        return false
    }
    
    return true
}//}}}

// Order matters. There can be expressions without statements (See: last line of validate_assign()).
validate_expr :: proc() -> bool {
    return validate_string()       || 
           validate_bool()         || 
           validate_date()         || 
           validate_inline_list()  || 
           validate_inline_table() ||
           validate_number() 
}

validate_string :: proc() -> bool {//{{{
    validate_quotes :: proc() -> bool {
        PATTERNS := [] string { "\"\"\"", "'''", "\"", "\'", }
        for p in PATTERNS {
            if starts_with(peek(), p) {
                if err_if_not(ends_with(peek(), p), .Missing_Quote, "string '%s' is missing one or more quotes", peek()) do return false
            }
        }
        skip()
        return true
    }

    if len(peek()) == 0 do return false
    if r := peek()[0]; !any_of(r, '"', '\'') do return false 

    return validate_quotes() 
    // this should be done in the tokenizer & cleanup_backslashes() (it isn't):  || validate_escapes() || validate_codepoints()
}//}}}

validate_bool :: proc() -> bool {  //{{{
    if eq(peek(), "yes") do make_err(.Bad_Value, "'Yes' is not a valid expression in TOML, please use 'true'!")
    if eq(peek(), "no")  do make_err(.Bad_Value, "'No' is not a valid expression in TOML, please use 'false'!")

    // eq is case-insensitive compare, while '==' operator is case-sensitive
    if !eq(peek(), "false") && !eq(peek(), "true") do return false
    
    defer skip()
    return !err_if_not(peek() == "false" || peek() == "true", .Bad_Value, "booleans must be lowercase")
}//}}}

validate_date :: proc() -> (ok: bool) {  //{{{
    is_proper_date :: proc(str: string) -> bool {
        // I hope, LLVM can do something with this...
        return len(str) > 9 &&
            str[0] >= '0' && str[0] <= '9' &&
            str[1] >= '0' && str[1] <= '9' &&
            str[2] >= '0' && str[2] <= '9' &&
            str[3] >= '0' && str[3] <= '9' &&
            str[4] == '-' &&      
            str[5] >= '0' && str[5] <= '9' &&
            str[6] >= '0' && str[6] <= '9' &&
            str[7] == '-' &&      
            str[8] >= '0' && str[8] <= '9' &&
            str[9] >= '0' && str[9] <= '9'
    }

    is_proper_time :: proc(str: string) -> bool {
        return len(str) > 7 &&
            str[0] >= '0' && str[0] <= '9' &&
            str[1] >= '0' && str[1] <= '9' &&
            str[2] == ':' &&      
            str[3] >= '0' && str[3] <= '9' &&
            str[4] >= '0' && str[4] <= '9' &&
            str[5] == ':' &&      
            str[6] >= '0' && str[6] <= '9' &&
            str[7] >= '0' && str[7] <= '9'
    }

    validate_time :: proc(str: string) -> bool {
        if err_if_not(is_proper_time(str), .Bad_Date, "The date: '%s' is not valid, please use rfc 3339 (e.g.: 1234-12-12, or 60:45:30+02:00)", peek()) do return false
        
        offset := str[8:] if len(str) > 8 else ""

        // because of dotted.keys, 'start' '.' 'end' are different tokens.
        if peek(1) == "." {
            for r, i in peek(2) {
                if r == '-' || r == '+' {
                    offset = peek(2)[i:]
                    break
                }
                if err_if_not(is_digit(r, 10) || r == 'Z' || r == 'z', .Bad_Date, "Bad millisecond count in the date.") do return false
            }
            skip(2)
        } 
        
        if offset == "" do return true

        if offset[0] == '+' || offset[0] == '-' {
            s := offset[1:]
            return len(str) > 4 &&
                s[0] >= '0' && s[0] <= '9' &&
                s[1] >= '0' && s[1] <= '9' &&
                s[2] == ':' &&
                s[3] >= '0' && s[3] <= '9' &&
                s[4] >= '0' && s[4] <= '9'
        } 
        return true // 'Z' and 'z' are unnecessary in TOML 
    }
     
    // Dates will necessarily have - as their 5th symbol: "0123-00-00"
    if len(peek()) > 4 && peek()[4] == '-' {
        err_if_not(is_proper_date(peek()), .Bad_Date, "The date: '%s' is not valid, please use rfc 3339 (e.g.: 1234-12-12, or 60:45:30+02:00)", peek())
        
        // time can be seperated either by { 't', 'T' or ' ' }, ' ' is split by tokenizer
        if len(peek()) > 11 && (peek()[10] == 'T' || peek()[10] == 't') {
            if !validate_time(peek()[11:]) do return false
        }
        next()
        ok = true
    }
    
    // Time can be either without date or split from it by whitespace. 
    // This handles both scenarios
    if len(peek()) > 2 && peek()[2] == ':' {
        validate_time(peek())
        next()
        ok = true
    }

    return ok
}//}}}

// Good luck!
validate_number :: proc() -> bool {//{{{
    at :: proc(s: string, i: int) -> rune { for r, j in s do if i == j do return r; return 0 }
    
    number := peek()
    if at(number, 0) == '+' || at(number, 0) == '-' do number = number[1:] 

    if eq(number, "nan") || eq(number, "inf") {
        err_if_not(number == "nan" || number == "inf", .Bad_Float, "NaN and Inf must be fully lowercase in TOML: `nan` and `inf`! (I don't know why). Your's is: '%s'", peek())
        skip()
        return true
    }
    
    split_by :: proc(a: string, b: string) -> (string, string) {
        for r1, i in a {
            for r2 in b {
               if r1 == r2 do return a[:i], a[i + 1:]
            }
        }
        return a, ""
    }
    
    // underscores must be between 2 digits
    validate_underscores :: proc(r: rune, p: rune, is_last: bool) -> bool {
        if r != '_' do return true
        switch {
        case p == '_' : make_err(.Bad_Integer, "Double underscore mid number")
        case p == 0   : make_err(.Bad_Integer, "Underscore cannot be the first character in a number")
        case is_last  : make_err(.Bad_Integer, "Underscore cannot be the last character in a number")
        case: return true
        }
        return false
    }
    
    // I split the number into three parts:  main.fractionEexponent or mainEexponent 
    main, fraction, exponent: string
    
    {
        exp1, exp2: string
        main, exp1 = split_by(number, "eE")
        if peek(1) == "." {
            fraction, exp2 = split_by(peek(2), "eE")

            if exp1 != "" && exp2 != "" {
                make_err(.Bad_Float, "A number cannot have 2 exponent parts! '1e5.7e6' is invalid")
                return false
            }
        }
        exponent = exp1 if exp1 != "" else exp2
        if at(exponent, 0) == '-' || at(exponent, 0) == '+' do exponent = exponent[1:] 
    }
    
    // If a number starts with zero it must be followed by 'x', 'o', 'b' ir nothing
    base := 10
    if at(main, 0) == '0' {
        switch at(main, 1) {
        case 'x': base = 16; main = main[2:]
        case 'o': base =  8; main = main[2:]
        case 'b': base =  2; main = main[2:]
        case  0 : ;
        case: make_err(.Bad_Integer, "A number cannot start with '0'. Please use '0o1234' for octal")
        }
    }

    prev: rune

    prev = 0 
    for r, i in main {
        if prev == 0 && !is_digit(r, base) do return false
        if err_if_not(is_digit(r, base) || r == '_', .Bad_Integer, "Unexpected character: '%v' in number", r) do return false
        if !validate_underscores(r, prev, i == len(main) - 1) do return false
        prev = r
    }

    prev = 0
    for r, i in fraction {
        if prev == 0 && !is_digit(r, base) do return false
        if err_if_not(is_digit(r, base) || r == '_', .Bad_Integer, "Unexpected character: '%v' in decimal part of number ", r) do return false
        if !validate_underscores(r, prev, i == len(fraction) - 1) do return false
        prev = r
    }
    
    prev = 0
    for r, i in exponent {
        if prev == 0 && !is_digit(r, base) do return false
        if err_if_not(is_digit(r, base) || r == '_', .Bad_Integer, "Unexpected character: '%v' in exponent part of number", r) do return false
        if !validate_underscores(r, prev, i == len(exponent) - 1) do return false
        prev = r
    }
    
    skip()
    if fraction != "" do skip(2)
    return true
}//}}}

validate_inline_list :: proc() -> bool { //{{{
    if peek() != "[" do return false
    skip() // '['

    last_was_comma: bool
    for {

        skip_newline()
        if peek() == "]" do break

        if !validate_expr() do return false

        skip_newline()
        if peek() == "]" do break

        if err_if_not(peek() == ",", .Missing_Comma, "Comma is missing between elements") do return false
        skip() // ','
        skip_newline()
        if peek() == "," {
            make_err(.Double_Comma, "double comma found in an inline list.")
            return false
        }
        
    }
    
    return !err_if_not(next() == "]", .Missing_Bracket, "']' missing in inline array declaration")
}//}}}

validate_inline_table :: proc() -> bool { //{{{
    if peek() != "{" do return false
    skip() // '{'
    
    for {
        skip_newline()
        if peek() == "}" do break

        if !validate_assign() do return false

        skip_newline()
        if peek() == "}" do break
        
        if err_if_not(peek() == ",", .Missing_Comma, "Comma is missing between elements") do return false
        skip() // ','  // you can have trailing commas in my inline tables, why not?
        skip_newline()
        if peek() == "," {
            make_err(.Double_Comma, "double comma found in an inline list.")
            return false
        }
    }

    return !err_if_not(next() == "}", .Missing_Bracket, "'}' missing in inline table declaration")
}//}}}

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
