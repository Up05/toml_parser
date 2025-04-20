package toml

tokenize :: proc(raw: string, file := "<unknown file>") -> (tokens: [dynamic] string, err: Error) {
    err = { file = file, line = 1 }

    skip: int
    outer: for r, i in raw {
        this := raw[i:]

        switch { // by the way, do NOT use the 'fallthrough' keyword
        case !is_bare_rune_valid(r):
            set_err(&err, .Bad_Unicode_Char, "'%v'", r)
            return

        case r == '\r' && len(raw) > i + 1 && raw[i + 1] != '\n':
            set_err(&err, .Bad_Unicode_Char, "carriage returns must be followed by new lines in TOML!")
            return

        case skip > 0: 
            skip -= 1

        case r == '\n':
            append(&tokens, "\n")
            err.line += 1

        case starts_with(raw[i:], "\r\n"):
            append(&tokens, "\n")
            err.line += 1

        case is_space(this[0]):
            // do nothing

        case is_special(this[0]):
            append(&tokens, this[:1])

        case r == '#':
            j, runes := find_newline(this)
            if j == -1 do return tokens, { }
            skip += runes - 1

        case starts_with(this, "\"\"\""):
            j, runes := find(this, "\"\"\"", 3)
            if j == -1 do return tokens, set_err(&err, .Missing_Quote, shorten_string(this, 16))
            j2, runes2 := go_further(this[j + 3:], '"')
            j += j2; runes += runes2
            append(&tokens, this[:j + 3])
            skip += runes + 2

        case starts_with(this, "'''"):
            j, runes := find(this, "'''", 3, false)
            if j == -1 do return tokens, set_err(&err, .Missing_Quote, shorten_string(this, 16))
            j2, runes2 := go_further(this[j + 3:], '\'')
            j += j2; runes += runes2
            append(&tokens, this[:j + 3])
            skip += runes + 2
        
        case r == '"':
            j, runes := find(this, "\"", 1)
            if j == -1 do return tokens, set_err(&err, .Missing_Quote, shorten_string(this, 16))
            append(&tokens, this[:j + 1])
            skip += runes

        case r == '\'':
            j, runes := find(this, "'", 1, false)
            if j == -1 do return tokens, set_err(&err, .Missing_Quote, shorten_string(this, 16))
            append(&tokens, this[:j + 1])
            skip += runes

        case:
            key := leftover(this)
            if len(key) == 0 do return tokens, set_err(&err, .None, shorten_string(this, 1))
            append(&tokens, key)
            skip += len(key) - 1
        }
    }

    return tokens, err

}

@(private="file")
leftover :: proc(raw: string) -> string {
    for _, i in raw {
        if is_space(raw[i]) || is_special(raw[i]) || raw[i] == '#' {
            return raw[:i]
        }
    }
    return ""
}

@(private="file")
find :: proc(a: string, b: string, skip := 0, escape := true) -> (bytes: int, runes: int) {
    escaped: bool
    for r, i in a[skip:] {
        defer runes += 1
        if escaped do escaped = false
        else if escape && r == '\\' do escaped = true
        else if starts_with(a[i + skip:], b) do return i + skip, runes + skip 
    }    // "+ skip" here is bad, it would be best to count runes up until "skip"
    return -1, -1
}

@(private="file")
go_further :: proc(a: string, r1: rune) -> (bytes: int, runes: int) {
    for r2, i in a {
        if r1 != r2 do return i, runes
        bytes  = i
        runes += 1
    }
    return 
}

@(private="file")
set_err :: proc(err: ^Error, type: ErrorType, more_fmt: string, more_args: ..any) -> Error {
    err.type = type
    b_printf(&err.more, more_fmt, ..more_args)
    return err^
}
