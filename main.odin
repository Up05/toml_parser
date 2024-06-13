package main

import "core:os"
import "core:strconv"

import dates "RFC_3339_date_parser"

import "back"
// get_defaults_from_file(contents: string) // so you can just #load
// I shouldn't just crash the program on error...
// Line & space trimming in multiline strings that have a backslash on the end of the line doesn't exist.
// Line & (maybe column) number for errors
main :: proc() {

    when false {
        track: back.Tracking_Allocator
        back.tracking_allocator_init(&track, context.allocator)
        defer back.tracking_allocator_destroy(&track)

        context.allocator = back.tracking_allocator(&track)
        defer back.tracking_allocator_print_results(&track)

        context.assertion_failure_proc = back.assertion_failure_proc
        back.register_segfault_handler()
    }

    // date_ := 
    // logln( dates.from_string("1996-02-29") )
    // logln(date, dates.to_string(date, ' '))    
    // logln(dates.is_date_lax("1996-02-29"))
    // logln(dates.is_date_lax("16:39:57"))
    // assert(false)


    parse()

}
