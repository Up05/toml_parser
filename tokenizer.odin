package toml

tokenize :: proc(raw: string, file := "<unknown file>") -> (tokens: [dynamic] string, err: Error) {
    err = { .Missing_Quote, file, 1, "" }

    skip: int
    outer: for r, i in raw {
        this := raw[i:]

        switch { 
        case skip > 0: 
            skip -= 1

        case (r == '\r' && len(raw) > i + 1 && raw[i + 1] != '\n') || r == '\n':
            append(&tokens, "\n")
            err.line += 1

        case is_space(this[0]):
            // do nothing

        case is_special(this[0]):
            append(&tokens, this[:1])

        case r == '#':
            j, runes := find_newline(this)
            if j == -1 do return tokens, { .None, "", 0, "" }
            skip += runes

        case starts_with(this, "\"\"\""):
            j, runes := find(this, "\"\"\"", 3)
            if j == -1 { err.more = shorten_string(this, 16); return }
            j2, runes2 := go_further(this[j + 3:], '"')
            j += j2; runes += runes2
            append(&tokens, this[:j + 3])
            skip += runes + 2

        case starts_with(this, "'''"):
            j, runes := find(this, "'''", 3, false)
            if j == -1 { err.more = shorten_string(this, 16); return }
            j2, runes2 := go_further(this[j + 3:], '\'')
            j += j2; runes += runes2
            append(&tokens, this[:j + 3])
            skip += runes + 2
        
        case r == '"':
            j, runes := find(this, "\"", 1)
            if j == -1 { err.more = shorten_string(this, 16); return }
            append(&tokens, this[:j + 1])
            skip += runes

        case r == '\'':
            j, runes := find(this, "'", 1, false)
            if j == -1 { err.more = shorten_string(this, 16); return }
            append(&tokens, this[:j + 1])
            skip += runes

        case:
            key := leftover(this)
            if len(key) == 0 { err.more = shorten_string(this, 1); return }
            append(&tokens, key)
            skip += len(key) - 1
        }
    }

    return tokens, { .None, "", 0, "" }

}



@(private="file")
is_space :: proc(r: u8) -> bool {
    SPACE : [4] u8 = { ' ', '\r', '\n', '\t' }
    return r == SPACE[0] || r == SPACE[1] || r == SPACE[2] || r == SPACE[3]
    // Nudge nudge
} 

@(private="file")
is_special :: proc(r: u8) -> bool {
    SPECIAL : [8] u8 = { '=', ',',  '.',  '[', ']', '{', '}', 0 }
    return  r == SPECIAL[0] || r == SPECIAL[1] || r == SPECIAL[2] || r == SPECIAL[3] ||
            r == SPECIAL[4] || r == SPECIAL[5] || r == SPECIAL[6] || r == SPECIAL[7]
    // Shove shove
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

