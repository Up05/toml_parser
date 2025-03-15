package toml

import "base:runtime"
import "core:fmt"
import "core:strings"

ErrorType :: enum {
    // TOKENIZER ERRORS:
    // VALIDATOR ERRORS:
    None,
    Missing_Key,
    Bad_Name,
    Missing_Value,
    Bad_Value,
    Missing_Bracket,
    Missing_Curly_Bracket,
    Mismatched_Brackets,
    Unexpected_Equals_In_Array,
    // PARSER ERRORS:
    Key_Already_Exists,
    Bad_Date,
    Bad_Integer,
    Bad_Float,
    Missing_Newline
}

Error :: struct {
    type: ErrorType,
    file: string,
    line: int,
    more: string // I am such a poet!
}

// This may also be a warning!
print_error :: proc(err: Error) -> (fatal: bool) {
    message: string
    message, fatal = format_error(err)
    if message != "" {
        logf("[ERROR] %s", message) // Lines are not 0-indexed (to my knowledge)
        delete(message, context.temp_allocator)
    }
    return fatal
}

format_error :: proc(
    err: Error,
    allocator := context.temp_allocator,
) -> (
    message: string,
    fatal: bool,
) {
    switch err.type {
    case .None:
        return "", false
    case .Missing_Key:
        message = fmt_err(err, "Expected the name of a key before '='", allocator)
    case .Bad_Name:
        message = fmt_err(
            err,
            "Bad key/table name found before, please eiter use quotes, or stick to 'A-Za-z0-9_-'",
            allocator,
        )
    case .Missing_Value:
        message = fmt_err(err, "Expected a value after '='", allocator)
    case .Bad_Value:
        message = fmt_err(err, "Bad value found after '='", allocator)
    case .Mismatched_Brackets:
        message = fmt_err(err, "Mismatched brackets found, e.g.: [{{]}}", allocator)
    case .Missing_Bracket:
        message = fmt_err(err, "Too few/too many brackets found", allocator)
    case .Missing_Curly_Bracket:
        message = fmt_err(err, "Too few/too many curly brackets found", allocator)
    case .Unexpected_Equals_In_Array:
        message = fmt_err(err, "Unexpected equals in an array found", allocator)
    case .Key_Already_Exists:
        message = fmt_err(err, "That key/section already exists", allocator)
    case .Bad_Date:
        message = fmt_err(err, "Failed to parse a date", allocator)
    case .Bad_Integer:
        message = fmt_err(err, "Failed to parse an interger", allocator)
    case .Bad_Float:
        message = fmt_err(
            err,
            "Failed to parse a floating-point number (may be invalid value)",
            allocator,
        )
    case .Missing_Newline:
        message = fmt_err(err, "A new line is missing between two key-value pairs", allocator)
    }

    return message, true
}

@(private = "file")
fmt_err :: proc(err: Error, message: string, allocator: runtime.Allocator) -> string {
    return fmt.aprintf("%s:%d %s! %s\n", err.file, err.line + 1, message, err.more)
}

validate :: proc(raw_tokens: [dynamic]string, filename: string) -> (err: Error) {
    err.file = filename

    to_skip := 0
    for token, i in raw_tokens {
        s := len(raw_tokens) // (s)ize

        if token == "\n" do err.line += 1 // "\n" is a specially processed token btw
        inner_lines := 0

        if to_skip > 0 {
            to_skip -= 1
            continue
        }
        
        prev :=     raw_tokens[i - 1] if i > 0 else ""
        next :=     raw_tokens[i + 1] if i < s - 1 else ""

        switch token {
        case "=":

            // # Key name validation
            err.type = .Missing_Key
            if i < 1 do return
            if prev == "\n" do return
            err.type = .None
            if get_quote_count(prev) == 0 {
                for r in prev {
                    if !between_any(r, 'A', 'Z', 'a', 'z', '0', '9') && r != '_' && r != '-' {
                        err.more = prev
                        err.type = .Bad_Name
                        return
                    }
                }
            }

            // # Value validation
            err.type = .Missing_Value
            if i > s - 2 do return // last element is EOF
            if next == "\n" do return
            err.type = .None
            to_skip += 1
            

            // # Array & table validation
            back :: proc(array: ^[dynamic] rune) -> rune {
                return array^[len(array^) - 1] if len(array^) > 0 else 0
            }

            perens: [dynamic] rune // I could use u8 or enum or bool, but whatever...
            for t in raw_tokens[i+1:]{
                if t == "\n" do inner_lines += 1

                switch t {
                case "[": append(&perens, '[')
                case "]": 
                    if back(&perens) == '[' do pop(&perens)
                    else {
                        err.type = .Mismatched_Brackets
                        err.line += inner_lines
                        err.more = "Expected ']', got '}'"
                        return
                    }
                case "{": append(&perens, '{')
                case "}": 
                    if back(&perens) == '{' do pop(&perens)
                    else {
                        err.type = .Mismatched_Brackets
                        err.line += inner_lines
                        err.more = "Expected '}', got ']'"
                        return
                    }
                }
                
                if back(&perens) == '[' && t == "=" {
                    err.type = .Unexpected_Equals_In_Array
                    err.line += inner_lines
                    return
                } 
                if len(perens) == 0 do break
                to_skip += 1
            }
            if back(&perens) == '[' {
                err.type = .Missing_Bracket
                return
            } else if back(&perens) == '{' {
                err.type = .Missing_Curly_Bracket
                return
            }
        case "[":
            
            if i > s - 2 {
                err.type = .Missing_Bracket
                return
            }

            list_of_tables := next == "["
            to_skip += int(list_of_tables)

            for t, j in raw_tokens[i + 1 + int(list_of_tables):] {
                inner_lines += 1
                if t == "." do continue
                nextt := i + 1 + int(list_of_tables)
                if  list_of_tables && t == "]" && raw_tokens[nextt + j] == "]" do break
                if !list_of_tables && t == "]" do break
                
                if get_quote_count(t) == 0 {
                    for r in t {
                        if !between_any(r, 'A', 'Z', 'a', 'z', '0', '9') && r != '_' && r != '-' {
                            err.type = .Bad_Name
                            err.line += inner_lines
                            err.more = t
                            return
                        }
                    }
                }

                to_skip += 1
            }
        }
    }
    return
}
