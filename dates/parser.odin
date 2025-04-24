package dates

import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

DateError :: enum {
    NONE,

    // Where parser REALIZED something is wrong!
    FAILED_AT_YEAR,
    FAILED_AT_MONTH,
    FAILED_AT_DAY,
    FAILED_AT_HOUR,
    FAILED_AT_MINUTE,
    FAILED_AT_SECOND,
    FAILED_AT_OFFSET_HOUR,
    FAILED_AT_OFFSET_MINUTE,
    YEAR_OUT_OF_BOUNDS,
    MONTH_OUT_OF_BOUNDS, // 01-12
    DAY_OUT_OF_BOUNDS,
    HOUR_OUT_OF_BOUNDS,
    MINUTE_OUT_OF_BOUNDS,
    SECOND_OUT_OF_BOUNDS,
    OFFSET_HOUR_OUT_OF_BOUNDS,
    OFFSET_MINUTE_OUT_OF_BOUNDS,
    FAILED_AT_TIME_SEPERATOR, // character seperating full-date & full-time isn't in variable "time_separators"
}

// may be overwritten. Set to empty array to accept any time seperator
time_separators: []string = {"t", "T", " "}
offset_separators: []string = {"z", "Z", "+", "-"}

Date :: struct {
    second:           f32,
    is_date_local:    bool,
    is_time_only :    bool,
    is_date_only :    bool,

    year, month, day: int,
    hour, minute:     int,
    offset_hour:      int,
    offset_minute:    int,
}

from_string :: proc(date: string) -> (out: Date, err: DateError) {
    date := date

    out.is_date_only = true
    out.is_time_only = true

    ok: bool

    // ##############################  D A T E  ##############################

    // Because there has to be a leading zero
    if date[4:5] == "-" {
        out.is_time_only = false
        out.year = parse_int2(date[0:4], .FAILED_AT_YEAR) or_return

        out.month = parse_int2(date[5:7], .FAILED_AT_MONTH) or_return
        if !between(out.month, 1, 12) do return out, .MONTH_OUT_OF_BOUNDS

        out.day = parse_int2(date[8:10], .FAILED_AT_DAY) or_return
        if !between(out.day, 1, days_in_month(out.year, out.month)) do return out, .DAY_OUT_OF_BOUNDS

        if len(date) > 10 {
            if !(len(time_separators) == 0 ||
                   slice.any_of(time_separators, date[10:11])) {
                return out, .FAILED_AT_TIME_SEPERATOR
            }

            date = date[11:]
        }
    }

    // ##############################  T I M E  ##############################

    if len(date) >= 8 && date[2] == ':' {
        out.is_date_only = false
        out.hour = parse_int2(date[0:2], .FAILED_AT_HOUR) or_return
        if !between(out.hour, 0, 23) do return out, .HOUR_OUT_OF_BOUNDS

        out.minute = parse_int2(date[3:5], .FAILED_AT_MINUTE) or_return
        if !between(out.minute, 0, 59) do return out, .MINUTE_OUT_OF_BOUNDS

        date = date[6:] // because of "-"
        offset, _ := strings.index_multi(date, offset_separators)

        out.second, ok = strconv.parse_f32(
            date[:offset if offset != -1 else len(date)],
        )
        if !ok do return out, .FAILED_AT_SECOND
        // seconds \in [00, 60], because of leap seconds 
        if !between(int(out.second), 0, 60) do return out, .SECOND_OUT_OF_BOUNDS

        if offset != -1 {
            date = date[offset:]
            // fine to have lowercase here, because it wouldn't have been detected otherwise
            if strings.to_lower(date[:1]) == "z" do return

            out.offset_hour = parse_int2(
                date[1:3],
                .FAILED_AT_OFFSET_HOUR,
            ) or_return
            if !between(out.offset_hour, 0, 23) do return out, .OFFSET_HOUR_OUT_OF_BOUNDS

            out.offset_minute = parse_int2(
                date[4:6],
                .FAILED_AT_OFFSET_MINUTE,
            ) or_return
            if !between(out.offset_minute, 0, 59) do return out, .OFFSET_MINUTE_OUT_OF_BOUNDS

            if date[:1] == "-" {
                out.offset_hour *= -1
                out.offset_minute *= -1
            }

        } else {
            out.is_date_local = true
        }
    }

    return
}

to_string :: proc(
    date: Date,
    time_sep := ' ',
) -> (
    out: string,
    err: DateError,
) {
    date := date

    {
        using date
        if !between(year, 0, 9999) do return "", .YEAR_OUT_OF_BOUNDS
        if !between(month, 0, 12) do return "", .MONTH_OUT_OF_BOUNDS
        if !between(day, 0, days_in_month(year, month)) do return "", .DAY_OUT_OF_BOUNDS
        if !between(hour, 0, 23) do return "", .HOUR_OUT_OF_BOUNDS
        if !between(minute, 0, 59) do return "", .MINUTE_OUT_OF_BOUNDS
        if !between(int(second), 0, 60) do return "", .SECOND_OUT_OF_BOUNDS
        if !between(offset_hour, -23, 23) do return "", .OFFSET_HOUR_OUT_OF_BOUNDS
        if !between(offset_minute, -59, 59) do return "", .OFFSET_MINUTE_OUT_OF_BOUNDS
    }

    b: strings.Builder
    strings.builder_init_len_cap(&b, 0, 25)

    fmt.sbprintf(&b, "%04d-%02d-%02d", date.year, date.month, date.day)
    strings.write_rune(&b, time_sep)
    fmt.sbprintf(&b, "%02d:%02d:%02.0f", date.hour, date.minute, date.second)

    if date.offset_hour == 0 && date.offset_minute == 0 do strings.write_rune(&b, 'Z')
    else {
        if date.offset_minute != 0 && sign(date.offset_hour) != sign(date.offset_minute) {
            date.offset_hour += sign(date.offset_minute)
            date.offset_minute = 60 - abs(date.offset_minute) // sign doesn't matter, because later prints the abs of date.offset_minute
            fmt.printf("DATE PARSER WARNING: signs of your Date.offset_hour & Date.offset_minute do not match! " + "Given dates will be safely converted, but may be unexpected. " + "Go to line: %d in: %s to find out more.\n", #line - 5, #file)
        }

        if date.offset_hour < 0 do strings.write_rune(&b, '-')
        else do strings.write_rune(&b, '+')

        fmt.sbprintf(&b, "%02d:%02d", abs(date.offset_hour), abs(date.offset_minute))
    }

    return strings.to_string(b), .NONE
}

partial_date_to_string :: proc(date: Date, time_sep := ' ',) -> (out: string, err: DateError) {
    date := date
    {
        using date
        if !between(year, 0, 9999) do return "", .YEAR_OUT_OF_BOUNDS
        if !between(month, 0, 12) do return "", .MONTH_OUT_OF_BOUNDS
        if !between(day, 0, days_in_month(year, month)) do return "", .DAY_OUT_OF_BOUNDS
        if !between(hour, 0, 23) do return "", .HOUR_OUT_OF_BOUNDS
        if !between(minute, 0, 59) do return "", .MINUTE_OUT_OF_BOUNDS
        if !between(int(second), 0, 60) do return "", .SECOND_OUT_OF_BOUNDS
        if !between(offset_hour, -23, 23) do return "", .OFFSET_HOUR_OUT_OF_BOUNDS
        if !between(offset_minute, -59, 59) do return "", .OFFSET_MINUTE_OUT_OF_BOUNDS
    }

    b: strings.Builder
    strings.builder_init_len_cap(&b, 0, 25)

    if date.is_date_only {
        fmt.sbprintf(&b, "%04d-%02d-%02d", date.year, date.month, date.day)
        return strings.to_string(b), .NONE
    }
    if date.is_time_only {
        fmt.sbprintf(&b, "%02d:%02d:%02.0f", date.hour, date.minute, date.second)
        return strings.to_string(b), .NONE
    }

    fmt.sbprintf(&b, "%04d-%02d-%02d%c%02d:%02d:%02.0f",
        date.year, date.month, date.day, time_sep,
        date.hour, date.minute, date.second)

    if date.is_date_local do return strings.to_string(b), .NONE

    if date.offset_hour == 0 && date.offset_minute == 0 do strings.write_rune(&b, 'Z')
    else {
        if date.offset_minute != 0 && sign(date.offset_hour) != sign(date.offset_minute) {
            date.offset_hour += sign(date.offset_minute)
            date.offset_minute = 60 - abs(date.offset_minute) // sign doesn't matter, because later prints the abs of date.offset_minute
            fmt.printf("DATE PARSER WARNING: signs of your Date.offset_hour & Date.offset_minute do not match! " + "Given dates will be safely converted, but may be unexpected. " + "Go to line: %d in: %s to find out more.\n", #line - 5, #file)
        }

        if date.offset_hour < 0 do strings.write_rune(&b, '-')
        else do strings.write_rune(&b, '+')

        fmt.sbprintf(&b, "%02d:%02d", abs(date.offset_hour), abs(date.offset_minute))
    }

    return strings.to_string(b), .NONE
}


// I don't need to test for both the date & the time
is_date_lax :: proc(date: string) -> bool {
    is_date := true
    is_time := true

    if len(date) >= 10 {
        is_date &= are_all_numbers(date[0:4])
        is_date &= are_all_numbers(date[5:7])
        is_date &= are_all_numbers(date[8:10])
        is_date &= date[4] == '-' && date[7] == '-'
    } else do is_date = false

    if !is_date && len(date) >= 8 {
        is_time &= are_all_numbers(date[0:2])
        is_time &= are_all_numbers(date[3:5])
        is_time &= are_all_numbers(date[6:8])
        is_time &= date[2] == ':' && date[5] == ':'
    } else do is_time = false

    return is_date || is_time
}

@(private)
are_all_numbers :: proc(s: string) -> (out: bool) {
    out = true
    for r in s {
        if r < '0' || r > '9' do out = false
    }
    return
}

// odin doesn't have a sign_int???
@(private)
sign :: proc(#any_int a: int) -> int {
    return -1 if a < 0 else 1 if a > 0 else 0
}

// kind of a misnomer, but whatever.
@(private)
parse_int :: proc(num: string) -> (int, bool) {
    num, ok := strconv.parse_uint(num, 10)
    return int(num), ok
}

@(private)
parse_int2 :: proc(num: string, potential: DateError) -> (int, DateError) {
    num, ok := strconv.parse_uint(num, 10)
    return int(num), nil if ok else potential
}

@(private)
between :: proc(a, lo, hi: int) -> bool {
    return a >= lo && a <= hi
}


@(private)
days_in_month :: proc(year: int, month: int) -> int {
    if slice.any_of([]int{1, 3, 5, 7, 8, 10, 12}, month) do return 31
    if slice.any_of([]int{4, 6, 9, 11}, month) do return 30
    // just February left
    if leap_year(year) do return 29
    return 28
}

@(private)
leap_year :: proc(year: int) -> bool {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}
