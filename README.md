# TOML parser

A TOML parser for odin-lang. 

# Example

```Odin
import "toml"
import "toml/dates"

main :: proc() {
  using toml
  
  section, err1 := parse_file("toml/example.toml", context.temp_allocator)
  default, err2 := parse(#load("toml/example.toml"), "example.toml", context.temp_allocator)

  if print_error(err2) do return
  print_error(err1)

  print_table(section)
  
  inf := get_f64(section, "infinity") or_else get_f64_panic(default, "infinity")
  num := get(i64, section, "num") or_else 5

  str := get(string, section, "multiline_str") or_else "bad"

  date := get_date(section, "letsnot", "k", "l", "m", "n") or_else dates.Date {}
  
  list := get_panic(^List, section, "o", "p")

}
```

```TOML
# example.toml

integer = 5
num = 123.5
infinity = inf
# unicode chars need chcp 65001 & stuff
multiline_str = """
a
b c \u2230
"""
a.b = "dotted.tables"
c = { d = "inline tables" }
[e.f]
g = "useful tables"
[[h.i]]
j = "lists of tables"
k.l.m.n = 2024-06-07T20:00:00.12+02:00

[o]
p = [ 1, [ 2, 3 ], 4]
```
# Installation 

Simply,
```nix
cd your_project
git clone github.com/Up05/toml_parser toml
```  
And `import "toml"`

# Design/Idiom idea

Although, you can simply use `or_else` or just `val, ok := get(...`. I propose, that one could: 
  1. load a configuration at runtime, by using `parse_file`
  2. load their configuration at compile time by using `parse_data(#load(same_file), "filename.toml")`
  3. first get a value from the runtime config by using `get` then, if need be, (via `or_else`) fallback to the compile-time config and use `get_panic`.

# Function reference

## Errors
```odin
format_error :: proc(err: Error, allocator := context.temp_allocator) -> (message: string, fatal: bool) 
```
Format's the error and returns it as well as whether it was fatal or not.

```odin
print_error :: proc(err: Error) -> (fatal: bool)
```
Format's and prints the specified error to `stdout`. May use `format_error` to only get the error message.

## Parsing

```odin  
parse_file :: proc(filename: string, allocator := context.allocator) -> (section: ^Table, err: Error) 
```
Parses the specified toml file. Returns the root table & an error, which can then be nicely printed with `print_error`.

```odin  
parse_data :: proc(data: []u8, original_filename := "untitled data", allocator := context.allocator) -> (section: ^Table, err: Error)  
```
Parses the given data. Is meant to be used with `#load(file)`. 
 
```odin  
parse :: proc(data: string, original_file: string, allocator := context.allocator) -> (tokens: ^Table, err: Error) 
```
Parses the TOML in a string. Underlying function called by `parse_data` and `parse_file`.

## Getting the values

```odin
get :: proc($T: typeid, section: ^Table, path: ..string) -> (val: T, ok: bool) // where T is in Type union
```
Retrieves and type checks the value at path. **Careful, path is not specified by dots!**
Works on any table.

```odin
get_panic :: proc($T: typeid, section: ^Table, path: ..string) -> T // where T is in Type union
```
Retrieves and type checks the value at path. **Careful, path is not specified by dots!**
Works on any table. Crashes if not ok.

There are also `get_<type>` & `get_<type>_panic` functions for all possible types in the `Type` union.  
Here are the variants: `{ table, list, string, bool, i64, f64, date }`

## Printing

Generally replaced by `fmt.print` and `fmt.printf("%#v\n", ...`.
```odin
print_table :: proc(section: ^Table, level := 0)
```
A while back Odin used to hang when printing a map pointer.  
I'm pretty sure it does not anymore.

```odin
print_value :: proc(v: Type, level := 0) 
```

## Testing (internal)

```odin
@private
main :: proc()
```
This is here for `toml-test`. It takes in the TOML from `stdin`, parses it, marshal's it to JSON and prints the JSON to stdout. 
Unless there was an error, in which case the program does not print anything and only exits with exit code `1`. 

# TODO

1. Add a `destroy_table` function that recursivelly frees all memory allocated by the parser.

# TIDO (a.k.a. Things I will never DO)

1. Technically, the parser is very loosey goosey, you can have double commas, you can have no commas, you can have sections with empty names and so on... But just don't, I guess.

2. Multiline strings 
```
_ = """ New line \

    test
```
should produce:  `{ _ = " New line test" }` I can't be arsed to fix this... It's not that difficult though, you just make another function after/before `cleanup_backslashes`.

3. Some tests fail because of how odin formats floats & non-printable characters, cba to fix that and it doesn't matter.
