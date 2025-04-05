package toml

/*

    This file is for testing. It should be ignored by library users.
 
    For contributors:
    I have (kind of) integrated these tests:
        https://github.com/toml-lang/toml-test

    To get them please download/build release 1.5.0:
        $ go install github.com/toml-lang/toml-test/cmd/toml-test@v1.5.0 

    For example: (Linux)
        $ export $GOBIN="/tmp"
        $ go install github.com/toml-lang/toml-test/cmd/toml-test@v1.5.0
        $ odin build . -out:toml_parser
        $ /tmp/toml-test ./toml_parser

    You may also run the `run-tests` shell script if you are on linux
    (TODO: add a powershell/python equivalent)

    Also, big thanks to tgolsson for suggesting this project

*/

import "core:fmt"
import "core:os"
import "core:encoding/json"
import "dates"

exit :: os.exit

@(private)
main :: proc() {
    data := make([] u8, 16 * 1024 * 1024)
    count, err_read := os.read(os.stdin, data)
    assert(err_read == nil)

    table, err := parse(string(data), "<stdin>")
    logln(err)
    if err.type != .None do os.exit(1) 
    json, _ := json.marshal(marshal(table))
    logln(string(json))
}

// Dunno what to really call this...
@(private="file")
TestingType :: struct {
    type: string,
    value: union {
        map [string] HelpMePlease,
        [] HelpMePlease,
        string,
        bool,
        i64,
        f64,
    }
}

@(private="file")
HelpMePlease :: union {
    TestingType,
    map [string] HelpMePlease,
    [] HelpMePlease
}

@(private="file")
marshal :: proc(input: Type) -> HelpMePlease {
    output: TestingType
    
    switch value in input {
    case nil: assert(false)
    case ^Table:
        out := make(map [string] HelpMePlease)
        for k, v in value do out[k] = marshal(v)
        return out

    case ^List:
        out := make([] HelpMePlease, len(value))
        for v, i in value do out[i] = marshal(v)
        return out

    case string: output = { type = "string",  value = value };
    case bool:   output = { type = "bool",    value = fmt.aprint(value) };
    case i64:    output = { type = "integer", value = fmt.aprint(value) };
    case f64:    output = { type = "float",   value = fmt.aprint(value) };

    case dates.Date: 
        result, err := dates.to_string(date = value, time_sep = 'T')
        if err != .NONE do os.exit(1) // I shouldn't do this like that...
        output.type = "datetime"
        output.value = result
    }

    return output
}
