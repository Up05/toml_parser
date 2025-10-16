package tests

import "core:slice"
import "core:testing"

import toml ".."
import "../dates"

@(test)
nil_guard_get :: proc(t: ^testing.T) {
	table: toml.Table

	_, found := toml.get_bool(&table, "enabled")
	testing.expectf(t, found == false, "should not crash on nullptr exception not found")
}

@(test)
unmarshal_primitives :: proc(t: ^testing.T) {
	test_toml := `
	integer = 22
	decimal = 12.4
	boolean = true
	string = "hello"
	date = 1111-02-03
	`


	Test :: struct {
		integer: int,
		decimal: f32,
		boolean: bool,
		str:     string `toml:"string"`,
		date:    dates.Date,
	}

	test: Test
	testing.expect(t, toml.unmarshal_string(test_toml, &test) == .None)

	testing.expect_value(t, test.integer, 22)
	testing.expect_value(t, test.decimal, 12.4)
	testing.expect_value(t, test.boolean, true)
	testing.expect_value(t, test.str, "hello")

	expected_date := dates.Date {
		year         = 1111,
		month        = 2,
		day          = 3,
		is_date_only = true,
	}
	testing.expect_value(t, test.date, expected_date)
}

@(test)
unmarshal_subtables :: proc(t: ^testing.T) {
	test_toml := `
	[table1]
	x = 1

	[table2]
	x = 2

	[table3.table4]
	x = 3
	`


	Test :: struct {
		table1: struct {
			x: int,
		},
		table2: struct {
			x: int,
		},
		table3: struct {
			table4: struct {
				x: int,
			},
		},
	}

	test: Test
	testing.expect(t, toml.unmarshal_string(test_toml, &test) == .None)

	testing.expect_value(t, test.table1.x, 1)
	testing.expect_value(t, test.table2.x, 2)
	testing.expect_value(t, test.table3.table4.x, 3)
}

@(test)
unmarshal_lists :: proc(t: ^testing.T) {
	test_toml := `
	slice = [1, 2, 3, 4]
	arr = [1, 2, 3, 4]
	dyn_arr = [1, 2, 3, 4]
	enum_arr = [1, 2, 3, 4]
	`


	Test_Enum :: enum {
		One,
		Two,
		Three,
		Four,
	}

	Test :: struct {
		slice:    []int,
		arr:      [4]int,
		dyn_arr:  [dynamic]int,
		enum_arr: [Test_Enum]int,
	}

	test: Test
	testing.expect(t, toml.unmarshal_string(test_toml, &test) == .None)

	expected_arr := []int{1, 2, 3, 4}

	for i in 0 ..< len(expected_arr) {
		testing.expect_value(t, test.enum_arr[cast(Test_Enum)i], expected_arr[i])
		testing.expect_value(t, test.slice[i], expected_arr[i])
		testing.expect_value(t, test.arr[i], expected_arr[i])
		testing.expect_value(t, test.dyn_arr[i], expected_arr[i])
	}
}

