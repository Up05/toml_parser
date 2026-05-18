package toml

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
    formatted: Builder,
}

// The filename is not freed, since it is only sliced
delete_error :: proc(err: ^Error) {
    if err.type != .None {
        b_destroy(&err.more)
    }
    if len(err.formatted.buf) > 0 {
        b_destroy(&err.formatted)
    }
}

// This may also be a warning!
print_error :: proc(err: Error, allocator := context.allocator) -> (fatal: bool) {
    err := err
    message: string
    message, fatal = format_error(&err, allocator)
    if message != "" {
        logf("[TOML ERROR] %s", message)
        delete(message, allocator)
    }
    return fatal
}

// The message is allocated and should be freed after use.
format_error :: proc(err: ^Error, allocator := context.allocator) -> (message: string, fatal: bool) {
    if err.type == .None do return "", false

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

    err.formatted.buf = make(type_of(err.formatted.buf), allocator)
    b_printf(&err.formatted, "%s:%d %s! %s\n", err.file, err.line + 1, descriptions[err.type], err.more.buf[:])

    return string(err.formatted.buf[:]), true
}

// Skips all consecutive new lines
// new lines should not be skipped everywhere
// that's why this is not inside of the peek() procedure.
skip_newline :: proc(io: ^IO) -> (ok: bool) { ok = peek(io) == "\n"; for peek(io) == "\n" { io.err.line += 1; skip(io) }; return }

validate :: proc(raw_tokens: [] string, file: string, allocator := context.allocator) -> Error {
    io: IO = {
        toks = raw_tokens,
        err  = { line = 1, file = file },
        aloc = allocator,
    }

    for peek(&io) != "" {
        if !validate_stmt(&io) {
            make_err(&io, .Unexpected_Token, "Unexpected token at the start of a statement: %s!", peek(&io))
        }
        if io.err.type != .None do break
    }

    err := io.err
    return err
}

// '||' operator has short-circuiting in Odin, so I use this to chain functions.
validate_stmt :: proc(io: ^IO) -> bool {
    return skip_newline(io) || (validate_array(io) || validate_table(io) || validate_assign(io)) &&
           !err_if_not(io, peek(io) == "" || peek(io) == "\n", .Missing_Newline, "Found a missing new line between statements!")
}

// array of tables: `[[item]]` at the start of lines
validate_array :: proc(io: ^IO) -> bool {
    if peek(io, 0) != "[" || peek(io, 1) != "[" do return false
    #no_bounds_check {
        if err_if_not(io, peek(io, 0)[1] == '[', .Missing_Bracket, "In section array both brackets must follow one another! '[[' not '[ ['") do return false
    }

    skip(io, 2) // '[' '['
    validate_path(io)

    #no_bounds_check {
        if peek(io, 0) == "]" && peek(io, 1) == "]" && err_if_not(io, peek(io, 0)[1] == ']', .Missing_Bracket, "In section array both brackets must follow one another! ']]' not '] ]'!") do return false
    }
    if err_if_not(io, next(io) == "]", .Missing_Bracket, "']' missing in section array declaration!") do return false
    if err_if_not(io, next(io) == "]", .Missing_Bracket, "']' missing in section array declaration!") do return false

    return true
}

// tables: `[object]` at the start of lines
validate_table :: proc(io: ^IO) -> bool {
    if peek(io, 0) != "[" do return false

    skip(io) // '['
    validate_path(io)
    return !err_if_not(io, next(io) == "]", .Missing_Bracket, "']' missing in section declaration!")
}

// key = value
validate_assign :: proc(io: ^IO) -> bool {
    if peek(io, 1) != "=" && peek(io, 1) != "." do return false

    if !validate_path(io) do return false
    if err_if_not(io, peek(io) == "=", .Expected_Equals, "Keys must be followed by '='! Instead got: %s!", peek(io)) do return false
    skip(io) // '='
    return validate_expr(io)
}

// there.are.dotted.paths.in.toml   each "directory" is supposed to be an object, last depends on the context.
// for example: in statement [[a.b]] a is a Table, b is a List of Table(s)
validate_path :: proc(io: ^IO) -> bool {//{{{
    validate_name :: proc(io: ^IO) -> bool {
        skip(io)
        return true
    }

    for peek(io, 1) == "." {
        if peek(io, 0) == "\n" || peek(io, 2) == "\n" {
            make_err(io, .Bad_New_Line, "paths.of.keys must be on the same line!")
            return false
        }

        if !validate_name(io) {
            make_err(io, .Bad_Name, "key in path cannot have this name: '%s'!", peek(io))
            return false
        }
        skip(io)
    }

    if !validate_name(io) {
        make_err(io, .Bad_Name, "key in path cannot have this name: '%s'!", peek(io))
        return false
    }

    return true
}//}}}

// Order matters. There can be expressions without statements (See: last line of validate_assign()).
validate_expr :: proc(io: ^IO) -> bool {
    return validate_string(io)       ||
           validate_bool(io)         ||
           validate_date(io)         ||
           validate_inline_list(io)  ||
           validate_inline_table(io) ||
           validate_number(io)
}

validate_string :: proc(io: ^IO) -> bool {//{{{
    validate_quotes :: proc(io: ^IO) -> bool {
        PATTERNS := [] string { "\"\"\"", "'''", "\"", "\'", }
        for p in PATTERNS {
            if starts_with(peek(io), p) {
                if err_if_not(io, ends_with(peek(io), p), .Missing_Quote, "string '%s' is missing one or more quotes!", peek(io)) do return false
            }
        }
        skip(io)
        return true
    }

    if len(peek(io)) == 0 do return false
    if r := peek(io)[0]; !any_of(r, '"', '\'') do return false

    return validate_quotes(io)
}//}}}

validate_bool :: proc(io: ^IO) -> bool {  //{{{
    if eq(peek(io), "yes") do make_err(io, .Bad_Value, "'Yes' is not a valid expression in TOML, please use 'true'!")
    if eq(peek(io), "no")  do make_err(io, .Bad_Value, "'No' is not a valid expression in TOML, please use 'false'!")

    // eq is case-insensitive compare, while '==' operator is case-sensitive
    if !eq(peek(io), "false") && !eq(peek(io), "true") do return false

    defer skip(io)
    return !err_if_not(io, peek(io) == "false" || peek(io) == "true", .Bad_Value, "Booleans must be lowercase!")
}//}}}

validate_date :: proc(io: ^IO) -> (ok: bool) {  //{{{
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
        if len(str) == 5 {
            return str[0] >= '0' && str[0] <= '9' &&
                str[1] >= '0' && str[1] <= '9' &&
                str[2] == ':' &&
                str[3] >= '0' && str[3] <= '9' &&
                str[4] >= '0' && str[4] <= '9'
        }
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

    validate_time :: proc(io: ^IO, str: string) -> bool {
        if err_if_not(io, is_proper_time(str), .Bad_Date, "The date: '%s' is not valid, please use rfc 3339 (e.io.: 1234-12-12, or 60:45:30+02:00)!", peek(io)) do return false

        offset := str[8:] if len(str) > 8 else ""

        // because of dotted.keys, 'start' '.' 'end' are different tokens.
        if peek(io, 1) == "." {
            for r, i in peek(io, 2) {
                if r == '-' || r == '+' {
                    offset = peek(io, 2)[i:]
                    break
                }
                if err_if_not(io, is_digit(r, 10) || r == 'Z' || r == 'z', .Bad_Date, "Bad millisecond count in the date!") do return false
            }
            skip(io, 2)
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
    if len(peek(io)) > 4 && peek(io)[4] == '-' {
        err_if_not(io, is_proper_date(peek(io)), .Bad_Date, "The date: '%s' is not valid, please use rfc 3339 (e.io.: 1234-12-12, or 60:45:30+02:00)!", peek(io))

        // time can be seperated either by { 't', 'T' or ' ' }, ' ' is split by tokenizer
        if len(peek(io)) > 11 && (peek(io)[10] == 'T' || peek(io)[10] == 't') {
            if !validate_time(io, peek(io)[11:]) do return false
        }
        next(io)
        ok = true
    }

    // Time can be either without date or split from it by whitespace.
    // This handles both scenarios
    if len(peek(io)) > 2 && peek(io)[2] == ':' {
        validate_time(io, peek(io))
        next(io)
        ok = true
    }

    return ok
}//}}}

// Good luck!
validate_number :: proc(io: ^IO) -> bool {//{{{
    at :: proc(s: string, i: int) -> rune { for r, j in s do if i == j do return r; return 0 }

    number := peek(io)
    if at(number, 0) == '+' || at(number, 0) == '-' do number = number[1:]

    if eq(number, "nan") || eq(number, "inf") {
        err_if_not(io, number == "nan" || number == "inf", .Bad_Float, 
            "NaN and Inf must be fully lowercase in TOML: `nan` and `inf`! (I don't know why). Your's is: '%s'!", peek(io))
        skip(io)
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
    validate_underscores :: proc(io: ^IO, r: rune, p: rune, is_last: bool) -> bool {
        if r != '_' do return true
        switch {
        case p == '_' : make_err(io, .Bad_Integer, "Double underscore mid number!")
        case p == 0   : make_err(io, .Bad_Integer, "Underscore cannot be the first character in a number!")
        case is_last  : make_err(io, .Bad_Integer, "Underscore cannot be the last character in a number!")
        case: return true
        }
        return false
    }

    // I split the number into three parts:  main.fractionEexponent or mainEexponent
    main, fraction, exponent: string

    {
        exp1, exp2: string
        main, exp1 = split_by(number, "eE")
        if peek(io, 1) == "." {
            fraction, exp2 = split_by(peek(io, 2), "eE")

            if exp1 != "" && exp2 != "" {
                make_err(io, .Bad_Float, "A number cannot have 2 exponent parts! '1e5.7e6' is invalid!")
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
        case  0 : // nothing
        case: make_err(io, .Bad_Integer, "A number cannot start with '0'. Please use '0o1234' for octal!")
        }
    }

    prev: rune

    prev = 0
    for r, i in main {
        if prev == 0 && !is_digit(r, base) do return false
        if err_if_not(io, is_digit(r, base) || r == '_', .Bad_Integer, "Unexpected character: '%v' in number!", r) do return false
        if !validate_underscores(io, r, prev, i == len(main) - 1) do return false
        prev = r
    }

    prev = 0
    for r, i in fraction {
        if prev == 0 && !is_digit(r, base) do return false
        if err_if_not(io, is_digit(r, base) || r == '_', .Bad_Integer, "Unexpected character: '%v' in decimal part of number!", r) do return false
        if !validate_underscores(io, r, prev, i == len(fraction) - 1) do return false
        prev = r
    }

    prev = 0
    for r, i in exponent {
        if prev == 0 && !is_digit(r, base) do return false
        if err_if_not(io, is_digit(r, base) || r == '_', .Bad_Integer, "Unexpected character: '%v' in exponent part of number!", r) do return false
        if !validate_underscores(io, r, prev, i == len(exponent) - 1) do return false
        prev = r
    }

    skip(io)
    if fraction != "" do skip(io, 2)
    return true
}//}}}

validate_inline_list :: proc(io: ^IO) -> bool { //{{{
    if peek(io) != "[" do return false
    skip(io) // '['

    for {
        skip_newline(io)
        if peek(io) == "]" do break

        if err_if_not(io, validate_expr(io), .Unexpected_Token, "Unexpected token in inline list!") do return false

        skip_newline(io)
        if peek(io) == "]" do break

        if err_if_not(io, peek(io) == ",", .Missing_Comma, "Missing comma or ']' in list!") do return false
        skip(io) // ','
        skip_newline(io)
        if peek(io) == "," {
            make_err(io, .Double_Comma, "double comma found in an inline list!")
            return false
        }
    }

    return !err_if_not(io, next(io) == "]", .Missing_Bracket, "']' missing in inline array declaration!")
}//}}}

validate_inline_table :: proc(io: ^IO) -> bool { //{{{
    if peek(io) != "{" do return false
    skip(io) // '{'

    for {
        skip_newline(io)
        if peek(io) == "}" do break

        if err_if_not(io, validate_assign(io), .Unexpected_Token, "Unexpected token in inline table!") do return false

        skip_newline(io)
        if peek(io) == "}" do break

        if err_if_not(io, peek(io) == ",", .Missing_Comma, "Missing comma or '}' in table!") do return false
        skip(io) // ','
        skip_newline(io)
        if peek(io) == "," {
            make_err(io, .Double_Comma, "double comma found in an inline list!")
            return false
        }
    }

    return !err_if_not(io, next(io) == "}", .Missing_Bracket, "'}' missing in inline table declaration!")
}//}}}

make_err :: proc(io: ^IO, type: ErrorType, more_fmt: string, more_args: ..any) {
    io.err.type = type
    context.allocator = io.aloc
    if len(io.err.more.buf) > 0 do return // b_reset(&io.err.more) 
    b_printf(&io.err.more, more_fmt, ..more_args)
}

err_if_not :: proc(io: ^IO, cond: bool, type: ErrorType, more_fmt: string, more_args: ..any) -> bool {
    if !cond do make_err(io, type, more_fmt, ..more_args)
    return !cond
}

