# A TOML parser for Odin

*Now with parser2: electric boogaloo*

This should be more or less a fully spec-compliant odin parser (however, not writer/formatter).

# Example

```Odin
// example.odin

import "core:fmt"
import "toml"
import "toml/dates"

main :: proc() {
  using toml
  
  section, err1 := parse_file("toml/example.toml", context.temp_allocator)
  if print_error(err1) do return
  default, err2 := parse(#load("toml/example.toml"), "xX example.toml Xx", context.temp_allocator)
  if print_error(err2) do return

  // Currently(2024-06-XX), Odin hangs when printing certain maps.
  print_table(section)
  
  // You may use either suffixed functions
  inf := get_f64(section, "infinity") or_else get_f64_panic(default, "infinity")
  // Or the underlying parapoly function
  num := get(i64, section, "num") or_else 5
  fmt.println(inf + f64(num)) // +Inf

  str := get(string, section, "multiline_str") or_else "bad"
  fmt.println(str) // \na\nb c ∰\n

  date := get_date(section, "letsnot", "k", "l", "m", "n") or_else dates.Date {}
  
  fmt.println(date)
  // Date{ year = 2024, month = 6, day = 7,
  //       hour = 20, minute = 0, second = 0.119999997,
  //       offset_hour = 2, offset_minute = 0 }
  
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
# Design/Idiom idea

Although, you can simply use `or_else` or just `val, ok := get(...`. I propose, that one could: 
  1. load a configuration at runtime, by using `parse_file`
  2. load their configuration at compile time by using `parse_data(#load(same_file))`
  3. first get a value from the runtime config by using `get` the, via `or_else`, fallback to the compile-time config and use `get_panic`, if the user-provided configuration has an error.

I would also then advise against using `get` for the compile-time version, since `get_panic` functions in a similar vein to a unit test (which I totally have in this project btw, just thought I'd mention, that I DO have that. I do!..)

# Todo

- Cleanup asserts, unify them & get proper messages for them
- Make an error for badly read file, currently it kind of sucks...
- Maybe, have `print_tokens()` & `print_file_data()` ¯\\\_(ツ)\_/¯
