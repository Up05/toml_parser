package toml

import "core:fmt"
import "core:os"
import "core:strings"
import "core:slice"

log     :: fmt.print
logf    :: fmt.printf
logln   :: fmt.println

warn    :: fmt.print
warnf   :: fmt.printf
warnln  :: fmt.println

assertf :: fmt.assertf

errf :: proc(section: string, format: string, args: ..any, _flush := true) {
    fmt.eprintf(fmt = strings.concatenate({ "[", strings.to_upper(section), " ERROR] ", format }), args = args, flush = _flush)
    os.exit(1)
}

errln :: proc(section: string, args: ..any, _sep := " ", _flush := true) {
    fmt.eprintln(strings.concatenate({ "[", strings.to_upper(section), " ERROR]" }), args, sep = _sep, flush = _flush)
    os.exit(1)
}
