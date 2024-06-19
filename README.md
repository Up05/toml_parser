# A TOML parser made for Odin

*Now we have parser2: electric boogaloo*

This should be more or less a fully spec-compliant odin parser (however, not writer/formatter).

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


```Odin
// example.odin

import "core:fmt"
import "toml"

main :: proc() {
  using toml
  
  section, err1 := parse_file("example.toml", context.temp_allocator)
  if print_error(err1) do return
  default, err2 := parse(#load("example.toml"), "xX example.toml Xx", context.temp_allocator)
  if print_error(err2) do return
  
  print_table(section)
  
  inf := get(f64, section, "infinity") or_else get_panic(f64, default, "infinity")
  num := get(i64, section, "num") or_else 5
  fmt.println(inf + f64(num)) // +Inf
  
  str := get(string, section, "multiline_str") or_else "bad"
  fmt.println(str) // \na\nb c ∰\n
  
  list := get_panic(^[dynamic] Type, section, "h", "i")
  date := get(dates.Date, list[0].(^Table), "k", "l", "m", "n") or_else dates.Date {}
  
  fmt.println(date)
  // Date{ year = 2024, month = 6, day = 7,
  //       hour = 20, minute = 0, second = 0.119999997,
  //       offset_hour = 2, offset_minute = 0 }
}
```
