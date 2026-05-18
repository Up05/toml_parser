#+private
package toml

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "dates"

import "core:testing"

main :: proc() {
    if any_of("-parse-example", ..os.args) {
        parse_example_toml()
    }

    run_integrated_test()
}

@test
memory_test :: proc(t: ^testing.T) {
    data := `x = """"""�`

    table, err := parse(string(data), "<f>")

    if any_of("--print-errors", ..os.args) && err.type != .None { logln(err); print_error(err) }
    if err.type != .None do os.exit(1)

    logln(deep_delete(table))
    delete_error(&err)
}

parse_example_toml :: proc() {
    table, err := parse_file("example.toml")
    print_error(err)
    print_table(table)
}

run_integrated_test :: proc() {

	data := make([]u8, 16 * 1024 * 1024)
	count, err_read := os.read(os.stdin, data)
	assert(err_read == nil || err_read == .EOF)

	table, err := parse(string(data[:count]), "<stdin>")

	if err.type != .None {print_error(err); os.exit(1)}

	idk, ok := marshal(table)
	if !ok do return

	json, _ := json.marshal(idk)
	logln(string(json))

	deep_delete(table)
    delete_error(&err)


    // ================================================

    TypedValue :: struct {
        type:  string,
        value: union {
            map[string] UntypedValue,
            [] UntypedValue,
            string,
            bool,
            i64,
            f64,
        },
    }

    UntypedValue :: union {
        TypedValue,
        map[string] UntypedValue,
        [] UntypedValue,
    }

    marshal :: proc(input: Type) -> (result: UntypedValue, ok: bool) {
        output: TypedValue

        switch value in input {
        case nil:
            assert(false)
        case ^List:
            if value == nil do return result, false
            out := make([]UntypedValue, len(value))
            for v, i in value {out[i] = marshal(v) or_continue}
            return out, true

        case ^Table:
            if value == nil do return result, false
            out := make(map[string]UntypedValue)
            for k, v in value {out[k] = marshal(v) or_continue}
            return out, true

        case string:
            output = {
                type  = "string",
                value = value,
            }
        case bool:
            output = {
                type  = "bool",
                value = fmt.aprint(value),
            }
        case i64:
            output = {
                type  = "integer",
                value = fmt.aprint(value),
            }
        case f64:
            output = {
                type  = "float",
                value = fmt.aprint(value),
            }

        case dates.Date:
            result, err := dates.partial_date_to_string(date = value, time_sep = 'T')
            if err != .NONE do os.exit(1) // I shouldn't do this like that...

            date := value
            if date.is_time_only {
                output.type = "time-local"
            } else if date.is_date_only {
                output.type = "date-local"
            } else if date.is_date_local {
                output.type = "datetime-local"
            } else {
                output.type = "datetime"
            }
            output.value = result
        }

        return output, true
    }



}


