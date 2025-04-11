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
git clone github.com/Up05/toml_parser toml
```
into your project's subdirectory.

And then put `import "toml"` in your odin code.

The directory structure should look like:
```
your_project_folder
    toml_folder
        parser2.odin
        ...
    other_libraries
    source_code.odin
    ...
```

# Design/Idiom idea

Although, you can simply use `or_else` or just `val, ok := get(...`. I propose, that one could: 
  1. load a configuration at runtime, by using `parse_file`
  2. load their configuration at compile time by using `parse_data(#load(same_file))`
  3. first get a value from the runtime config by using `get` the, via `or_else`, fallback to the compile-time config and use `get_panic`, if the user-provided configuration has an error.

I would also then advise against using `get` for the compile-time version, since `get_panic` functions in a similar vein to a unit test (which I totally have in this project btw, just thought I'd mention, that I DO have that. I do!..)

# T\[hings\]I\[will never\]DO (a.k.a. tests that do not pass)

1. Technically, the parser is very loosey goosey, you can have double commas, you can have no commas, you can have sections with empty names and so on... But just don't, I guess.

2. Multiline strings 
```
_ = """ New line \

    test
```
should produce:  `{ _ = " New line test" }` I can't be arsed to fix this... It's not that difficult though, you just make another function after/before `cleanup_backslashes`.

3. Some tests fail because of how odin formats floats & non-printable characters, cba to fix that and it doesn't matter.
