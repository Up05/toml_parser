# TOML parser

A TOML 1.1.0 parser for the Odin programming language. 

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

  str  := get(string, section, "multiline_str") or_else "bad"
  date := get_date(section, "letsnot", "k", "l", "m", "n") or_else dates.Date {}
  list := get_panic(^List, section, "o", "p")
}
```

The library also supports unmarshalling using runtime reflection.  
Big thanks to RaphGL for making the entire unmarshaller.
```Odin
value : struct {
    integer  : int,
    num      : f32,
    infinity : f64,
    mstr     : string `toml:"multiline_str"`,
    a : struct { b: string },
    c : struct { d: string },
    // rest of values in example.toml
    // are ignored by unmarshal_table
}

table, err1 := parse_file("example.toml")
err2 := unmarshal_table(value, table)

print_error(err1)
assert(err2 == .None)

logln(value)
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
  1. load a configuration at runtime, by using `parse_file`;
  2. load their configuration at compile time by using `parse_data(#load(same_file), "filename.toml")`;
  3. query runtime config by using `get` then, fallback to the compile-time config (with `or_else`) and use `get_panic`.

# Function reference

```odin  
// Parses the specified toml file. Returns the root table & an error, which can then be nicely printed with `print_error`.
parse_file :: proc(filename: string, allocator := context.allocator) -> (section: ^Table, err: Error) 

// Parses the given data. Is meant to be used with `#load(file)`.
parse_data :: proc(data: []u8, original_filename := "untitled data", allocator := context.allocator) -> (section: ^Table, err: Error)  

// Parses the TOML in a string. Underlying function called by `parse_data` and `parse_file`.
parse :: proc(data: string, original_file: string, allocator := context.allocator) -> (tokens: ^Table, err: Error) 
```

```odin
// Unmarshal TOML text into the passed value.
// Usage: unmarshal_any(toml_text, &output_value) 
unmarshal :: proc(data: []byte, ptr: ^$T, allocator := context.allocator) -> Unmarshal_Error 

// Unmarshal parsed TOML into the passed value. (Allows TOML errors to be printed)
// Usage: unmarshal_any(output_value, parse_file("file") or_else nil) 
// NOTE: you do not need to pass the value by pointer here (because any automatically takes its reference)
unmarshal_table :: proc(v: any, table: ^Table) -> Unmarshal_Error
```

```odin
// Retrieves and type checks the value at path. **Careful, path is not specified by dots!**
// Works on any table.
get :: proc($T: typeid, section: ^Table, path: ..string) -> (val: T, ok: bool) // where T is in Type union

// Retrieves and type checks the value at path. **Careful, path is not specified by dots!**
// Works on any table. Crashes if not ok.
// 
// There are also `get_<type>` & `get_<type>_panic` functions for all possible types in the `Type` union.  
// Here are the variants: `{ table, list, string, bool, i64, f64, date }`
get_panic :: proc($T: typeid, section: ^Table, path: ..string) -> T // where T is in Type union
```

```odin
// Format's the error and returns it as well as whether it was fatal or not.
format_error :: proc(err: Error, allocator := context.temp_allocator) -> (message: string, fatal: bool) 

// Format's and prints the specified error to `stdout`. May use `format_error` to only get the error message.
print_error :: proc(err: Error) -> (fatal: bool)
```

```odin
// Can replaced by `fmt.print` and `fmt.printf("%#v\n", ...`.
print_table :: proc(section: ^Table, level := 0)
```

```odin
// Recursively frees parser's output
deep_delete :: proc(type: Type, allocator := context.allocator) -> (err: runtime.Allocator_Error)

// Simply, frees the error.  
// *Filename is not freed, because the parser only slices it.*
delete_error :: proc(err: ^Error)
```

# Files

Source files may be packed into a single `libtoml.odin` file.  
To do this:
```
odin build .
./toml_parser -pack
# ./libtoml.odin should have been generated
# all files other than libtoml.odin and dates/ can be removed.
```

```sh
main.odin       # an internal file for testing
toml.odin       # the main user-facing file
misc.odin       # a couple miscellaneous functions

tokenizer.odin  # rips text apart by space and special symbols (string -> [] string)
validator.odin  # checks whether given TOML is valid or not    ([] string -> Error?)
parser.odin     # parses tokens into the recursive Type union  ([] string -> Type)

tests/          # odin core:testing tests (currently, there is 1...)
dates/          # my small RFC3339 date parsing library
mod.pkg         # package info for the odin package website (can't find it right now...)
run-tests.bash  # can be used to run all integrated tests
```

# Testing

After making a change to parser or tokenizer, please run integrated tests via: 
```sh
./run-tests.bash
```

This library uses v2 tests from: github.com/toml-lang/toml-test (big thanks to arp242 and tgolsson here!)

There are also a couple odin tests, you can run with:
```sh
odin test .
odin test tests
```

*Some tests fail because of how odin formats floats & non-printable characters, cba to fix that and it doesn't matter.*



