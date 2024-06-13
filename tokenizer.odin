package main

import "core:c"
import "core:os"
import "core:slice"
import "core:strings"
import "core:unicode/utf8"

SEPERATOR_SYMBOLS :: " \r\n\t"
SPECIAL_SYMBOLS :: "=.,[]{}" // special symbols

tokenize :: proc(file: string) -> [dynamic]string {
    blob, ok_file_read := os.read_entire_file_from_filename(file)
    if !ok_file_read do errf("Couldn't read file at path: \"%s\"\n", file)

    tokens: [dynamic]string
    it := string(blob) // iterator

    // * _.M A I N  L O O P._
    for len(it) > 0 {

        // i1 -- start of whitespace, i2 -- end of continuous whitespace
        i1, i2 := find_last_connected(it, {' ', '\r', '\n', '\t'})
        i0 := strings.index_any(it, SPECIAL_SYMBOLS) // start of any special symbols/operators

        if i1 == -1 {
            append_elem(&tokens, it)
            break
        }

        found_quotes: bool
        it, found_quotes = handle_quotes(&tokens, it)
        if found_quotes do continue


        if i0 > 0 && i0 < i1 {     // for symbols immediately after key name/other strings e.g.: '=', '{' or '.'
            rune_before_symbol, size_of_rune := utf8.decode_rune_in_string(
                it[i0 - 1:],
            ) // both numbers and symbols here will only be ascii, so who cares, I guess...
            // if rune_before_symbol < '0' || rune_before_symbol > '9' { // TODO: WHY?
            append_elem(&tokens, it[:i0])
            it = it[i0:]
            continue
            // }
        }
        found_symbol: bool // for symbols, seperated by space from other non-symbols
        it, found_symbol = handle_special_symbols(&tokens, it)
        if found_symbol do continue

        // ############################################################

        append_elem(&tokens, it[:i1])
        if strings.contains_any(it[i1:i2], "\r\n") do append_elem(&tokens, "\n") // for comments
        it = it[i2:]
    }

    // ############################################################

    append(&tokens, "EOF")

    // ############################################################

    #reverse for tok, i in tokens {
        if tok == "" do ordered_remove(&tokens, i)
    }

    // ############################################################

    for tok, index in tokens {
        switch tok {
        case "#":
            for t2, j in tokens[index + 1:] {
                if t2 == "\n" || t2 == "EOF" {
                    // comment := strings.concatenate(tokens[index:index + j + 1])
                    // logln("comment: ", comment) I don't save spaces/tabs & so on, soooo + this'll, probably, only be a reader anyways
                    remove_range(&tokens, index, index + j + 1)
                    break
                }
            }
        case "'''", "\"\"\"":
            // TODO: should this be here???
            errf("Tokenizer", "%s is unpaired!", tok)
        }
    }

    // for debugging!
    for token in tokens {
        if token == "\n" do logln()
        else do logf("%s\t", token)
    }
    logln()


    return tokens
}

handle_special_symbols :: proc(
    out: ^[dynamic]string,
    it: string,
) -> (
    slice: string,
    found: bool,
) {
    if strings.contains_rune(SPECIAL_SYMBOLS, utf8.rune_at(it[:1], 0)) {
        append_elem(out, it[:1])
        return it[1:], true
    }
    return it, false
}

handle_quotes :: proc(
    out: ^[dynamic]string,
    it: string,
) -> (
    slice: string,
    found: bool,
) {
    q1: string // start of pair of quotes
    q2: int //   end of pair of quotes
    is_literal: bool // 'literal' <---> "basic" 

    if len(it) > 2 && (it[:3] == "'''" || it[:3] == "\"\"\"") {
        q1 = it[:3]
        is_literal = q1 == "'''"
        q2 = index_all(it[3:], q1, !is_literal, true) + 3

        assert(q2 > 0, "Pairing of: ''' or \"\"\" was not found") // this just doesn't work ever :(
        append_elem(out, cleanup_backslashes(it[:q2 + 3], is_literal))
        return it[q2 + 3:], true
    }

    if it[:1] == "'" || it[:1] == "\"" {
        q1 = it[:1]
        is_literal = q1 == "'"
        q2 = index_all(it[1:], q1, !is_literal) + 1
        nl := strings.index_any(it[1:], "\r\n") + 1
        // why is the nl <= 0 instead of nl < 0? Well... ¯\_(ツ)_/¯
        assert(
            nl <= 0 || nl > q2,
            "Found a quote without a pair! (Use ''' or \"\"\" for multiline quotes or \\ to escape a quote)",
        )
        append_elem(out, cleanup_backslashes(it[:q2 + 1], is_literal))
        return it[q2 + 1:], true
    }

    return it, false
}


// ascii*: string[i] == r when i in [start, end)
find_last_connected :: proc(str: string, r: []rune) -> (start, end: int) {
    was_equal := false
    for ch, i in str {
        if !was_equal && equal_any(ch, r) {
            was_equal = true
            start = i
        } else if was_equal && !equal_any(ch, r) {
            return start, i
        }
    }
    return -1, -1
}

// If not found, returns c.INT32_MIN! So you can just check if result < 0.  
// Technically, multi_line is for whether to get last(true) or first(false) of multiple connected quotation marks: """ """"" --> ""
index_all :: proc(
    str: string,
    a: string,
    check_escape := false,
    multi_line := false,
) -> int {
    escaped := false
    was_equal := false
    for r, i in str {
        if i + len(a) > len(str) do return i if was_equal else int(c.INT32_MIN)
        if !escaped && str[i:i + len(a)] == a {
            if multi_line do was_equal = true
            else do return i
        } else if was_equal && str[i:i + len(a)] != a do return i - 1

        if check_escape {
            if !escaped && r == '\\' do escaped = true
            else do escaped = false
        }
    }
    return int(c.INT32_MIN)
}
// This should be specific enough to where it doesn't need to be in misc. Misc should, technically, have as little as possible.

