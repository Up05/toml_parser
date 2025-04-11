package toml

import "core:os"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:unicode/utf16"
import "core:unicode/utf8"

@private
find_newline :: proc(raw: string) -> (bytes: int, runes: int) {
    for r, i in raw {
        defer runes += 1
        if r == '\r' || r == '\n' do return i, runes
    }
    return -1, -1
}

@private
shorten_string :: proc(s: string, limit: int, or_newline := true) -> string {
    min :: proc(a, b: int) -> int {
        return a if a < b else b
    }

    newline, _ := find_newline(s) // add another line if you are using (..MAC OS 9) here... fuck it.
    if newline == -1 do newline = len(s)

    if limit < len(s) || newline < len(s) {
        return fmt.aprint(s[:min(limit, newline)], "...")
    }

    return s
}

// when literal is true, function JUST returns str
@private
cleanup_backslashes :: proc(str: string, literal := false) -> string {
    if literal do return str

    using strings
    b: Builder
    builder_init_len_cap(&b, 0, len(str))
    // defer builder_destroy(&b) don't need to, shouldn't even free the original str here

    to_skip := 0

    last: rune
    escaped: bool
    for r, i in str {

        if to_skip > 0 {
            to_skip -= 1
            continue
        }
        // if last == '\\' {
        if escaped {
            escaped = false

            split_bytes: [4]u8
            parsed_rune: rune

            switch r {
            case 'u':
                if len(str) < i + 5 {
                    // This'd happen in the parser, so it's fine, I guess...
                    g.err.type = .Bad_Value
                    g.err.more = fmt.aprint("'\\u' does most have hex 4 digits after it in string:", str)
                    return str
                }
                char_code, ok := strconv.parse_u64(str[i + 1:i + 5], 16)
                if !ok do errf("Tokenizer", "%s is an invalid unicode character, please use: \\uXXXX or \\UXXXXXXXX\n", str[i + 1:i + 5])
                utf16.decode_to_utf8(split_bytes[:], {u16(char_code)})
                parsed_rune, _ = utf8.decode_rune_in_bytes(split_bytes[:])
                write_rune(&b, parsed_rune)
                to_skip = 4

            case 'U':
                // this might work... I don't think, that my console/font supports the emojis and I can't be arsed to test it any further...
                if len(str) < i + 8 {
                    // This'd happen in the parser, so it's fine, I guess...
                    g.err.type = .Bad_Value
                    g.err.more = fmt.aprint("'\\U' does most have hex 8 digits after it in string:", str)
                    return str
                }
                char_code, ok := strconv.parse_u64(str[i + 1:i + 9], 16)
                if !ok do errf("Tokenizer", "%s is an invalid unicode character, please use: \\uXXXX or \\UXXXXXXXX\n", str[i + 1:i + 9])
                utf16.decode_to_utf8(
                    split_bytes[:],
                    {u16(char_code), u16(char_code >> 16)},
                ) // at least I don't discard the leftover 16 bytes ¯\_(ツ)_/¯
                parsed_rune, _ = utf8.decode_rune_in_bytes(split_bytes[:])
                write_rune(&b, parsed_rune)
                to_skip = 8

            case 'x':
                // this isn't in the spec?
                errln(
                    "Tokenizer",
                    "\\xXX is not in the spec, you can just use \\u00XX instead.",
                )
                to_skip = 2

            case 'n':
                write_byte(&b, '\n') // this is the most mappable thing ever, but who cares ¯\_(ツ)_/¯
            case 'r':
                write_byte(&b, '\r')
            case 't':
                write_byte(&b, '\t')
            case 'b':
                write_byte(&b, '\b')
            case '\\':
                write_byte(&b, '\\')
            case '"':
                write_byte(&b, '"')
            case '\'':
                write_byte(&b, '\'')

            }
        } else if r != '\\' {
            write_rune(&b, r)
        } else {
            escaped = true
        }

        last = r
    }
    return to_string(b)
}

// should be in misc.odin
@(private)
equal_any :: proc(a: rune, b: []rune) -> bool {
    for r in b do if a == r do return true
    return false
}

@(private)
between_any :: proc(a: rune, b: ..rune) -> bool {
    assert(len(b) % 2 == 0)
    for i := 0; i < len(b); i += 2 {
        if a >= b[i] && a <= b[i + 1] do return true
    }
    return false
}

@(private)
get_quote_count :: proc(a: string) -> int {
    s := len(a)
    if  s > 2 && 
        ((a[:3] == "\"\"\"" && a[s-3:] == "\"\"\"" ) ||
        (a[:3] == "'''" && a[s-3:] == "'''")) { return 3 }

    if  s > 0 && 
        ((a[:1] == "\"" && a[s-1:] == "\"") ||
        (a[:1] == "'" && a[s-1:] == "'")) { return 1 }

    return 0
}

@(private)
unquote :: proc(a: string, fluff: ..any) -> string {
    qcount := get_quote_count(a)
    unquoted := a[qcount:len(a) - qcount]
    if len(unquoted) > 0 && unquoted[0] == '\n' do unquoted = unquoted[1:]
    return cleanup_backslashes(unquoted, a[0] == '\'')
}

// clamp to zero
@(private)
cz :: proc(to_clamp: int) -> int {
    return 0 if to_clamp < 0 else to_clamp
}
@(private)
starts_with :: proc(a, b: string) -> bool {
    return len(a) >= len(b) && a[:len(b)] == b
}

@(private)
count_newlines :: proc(s: string) -> int {
    count: int
    for r, i in s {
        count += auto_cast r == '\r'
        count += auto_cast r == '\n'
        count -= auto_cast starts_with(s[i:], "\r\n")
    }
    return count
}

// case-insensitive compare
eq :: proc(a, b: string) -> bool {
    if len(a) != len(b) do return false
    #no_bounds_check for i in 0..<len(a) {
        r1 := a[i]
        r2 := b[i]

        A := r1 - 32*u8(r1 >= 'a' && r1 <= 'z')
        B := r2 - 32*u8(r2 >= 'a' && r2 <= 'z')
        if A != B do return false
    }
    return true
}


