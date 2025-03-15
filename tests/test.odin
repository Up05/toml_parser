package tests

import "core:testing"

import toml ".."

@(test)
nil_guard_get :: proc(t: ^testing.T) {
	table: toml.Table

	_, found := toml.get_bool(&table, "enabled")
	testing.expectf(t, found == false, "should not crash on nullptr exception not found")
}
