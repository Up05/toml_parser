package toml

import "core:os"
import "core:strconv"
import "core:strings"
import "core:unicode/utf16"
import "core:unicode/utf8"

import "back"

assert_trace :: proc(expr: bool) {
    if !expr {
        logln("Runtime assertion failed:")
        trace := back.trace()
        lines, err := back.lines(trace.trace[3:trace.len - 2])
        assert(err == nil)
        back.print(lines)
        os.exit(1)
    }
}

// when literal is true, function JUST returns str
@(private)
cleanup_backslashes :: proc(str: string, literal := false) -> string {
    if literal do return str

    using strings
    b: Builder
    builder_init_len_cap(&b, 0, len(str))

    to_skip := 0

    last: rune
    for r, i in str {

        if to_skip > 0 {
            to_skip -= 1
            continue
        }
        if last == '\\' {

            split_bytes: [4]u8
            parsed_rune: rune

            switch r {
            case 'u':
                char_code, ok := strconv.parse_u64(str[i + 1:i + 5], 16)
                if !ok do errf("Tokenizer", "%s is an invalid unicode character, please use: \\uXXXX or \\UXXXXXXXX\n", str[i + 1:i + 5])
                utf16.decode_to_utf8(split_bytes[:], {u16(char_code)})
                parsed_rune, _ = utf8.decode_rune_in_bytes(split_bytes[:])
                write_rune(&b, parsed_rune)
                to_skip = 4

            case 'U':
                // this might work... I don't think, that my console/font supports the emojis and I can't be arsed to test it any further...
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
            }
        } else if r != '\\' do write_rune(&b, r)

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
    assert_trace(len(b) % 2 == 0)
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
    return a[qcount:len(a) - qcount]
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

