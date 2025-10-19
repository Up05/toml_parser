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
unmarshal_primitives_to_struct :: proc(t: ^testing.T) {
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
	testing.expect(t, toml.unmarshal_string(test_toml, &test, context.temp_allocator) == .None)
	defer free_all(context.temp_allocator)

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
unmarshal_primitives_to_map :: proc(t: ^testing.T) {
	test_toml := `
	integer = 22
	decimal = 12.4
	boolean = true
	string = "hello"
	date = 1111-02-03
	`


	test: map[string]toml.Type
	testing.expect(t, toml.unmarshal_string(test_toml, &test, context.temp_allocator) == .None)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, test["integer"], 22)
	testing.expect_value(t, test["decimal"], 12.4)
	testing.expect_value(t, test["boolean"], true)
	testing.expect_value(t, test["string"], "hello")

	expected_date := dates.Date {
		year         = 1111,
		month        = 2,
		day          = 3,
		is_date_only = true,
	}
	testing.expect_value(t, test["date"], expected_date)
}

@(test)
unmarshal_subtables_to_struct :: proc(t: ^testing.T) {
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
	testing.expect(t, toml.unmarshal_string(test_toml, &test, context.temp_allocator) == .None)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, test.table1.x, 1)
	testing.expect_value(t, test.table2.x, 2)
	testing.expect_value(t, test.table3.table4.x, 3)
}

@(test)
unmarshal_subtables_to_map :: proc(t: ^testing.T) {
	test_toml := `
	[table1]
	x = 123

	[table2]
	x = 345

	[table3.table4]
	x = 567
	`


	test: map[string]toml.Type
	testing.expect(t, toml.unmarshal_string(test_toml, &test, context.temp_allocator) == .None)
	defer free_all(context.temp_allocator)

	table1 := test["table1"].(^toml.Table)
	table1_x := table1["x"]

	table2 := test["table2"].(^toml.Table)
	table2_x := table2["x"]

	table3 := test["table3"].(^toml.Table)
	table4 := table3["table4"].(^toml.Table)
	table4_x := table4["x"]

	testing.expect_value(t, table1_x, 123)
	testing.expect_value(t, table2_x, 345)
	testing.expect_value(t, table4_x, 567)

}

@(test)
unmarshal_lists_to_struct :: proc(t: ^testing.T) {
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
	testing.expect(t, toml.unmarshal_string(test_toml, &test, context.temp_allocator) == .None)
	defer free_all(context.temp_allocator)

	expected_arr := []int{1, 2, 3, 4}

	for i in 0 ..< len(expected_arr) {
		testing.expect_value(t, test.enum_arr[cast(Test_Enum)i], expected_arr[i])
		testing.expect_value(t, test.slice[i], expected_arr[i])
		testing.expect_value(t, test.arr[i], expected_arr[i])
		testing.expect_value(t, test.dyn_arr[i], expected_arr[i])
	}
}

@(test)
unmarshal_lists_to_map :: proc(t: ^testing.T) {
	test_toml := `
	slice = [1, 2, 3, 4]
	arr = [1, 2, 3, 4]
	dyn_arr = [1, 2, 3, 4]
	enum_arr = [1, 2, 3, 4]
	`


	check_list :: proc(t: ^testing.T, list: []int) {
		expected_arr := []int{1, 2, 3, 4}
		for i in 0 ..< len(expected_arr) {
			testing.expect_value(t, list[i], expected_arr[i])
		}
	}

	defer free_all(context.temp_allocator)

	test_slice: map[string][]int
	testing.expect(
		t,
		toml.unmarshal_string(test_toml, &test_slice, context.temp_allocator) == .None,
	)

	test_arr: map[string][4]int
	testing.expect(t, toml.unmarshal_string(test_toml, &test_arr, context.temp_allocator) == .None)

	test_dynarr: map[string][dynamic]int
	testing.expect(
		t,
		toml.unmarshal_string(test_toml, &test_dynarr, context.temp_allocator) == .None,
	)

	Test_Enum :: enum {
		One,
		Two,
		Three,
		Four,
	}
	test_enumarr: map[string][Test_Enum]int
	testing.expect(
		t,
		toml.unmarshal_string(test_toml, &test_enumarr, context.temp_allocator) == .None,
	)
}

