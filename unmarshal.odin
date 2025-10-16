package toml

import "base:intrinsics"
import "base:runtime"
import "core:mem"
import "core:reflect"
import "core:strconv"
import "core:strings"
import "dates"

Unmarshal_Error :: enum {
	None,
	Invalid_Data,
	Invalid_Parameter,
	Non_Pointer_Parameter,
	Multiple_Use_Field,
	Out_Of_Memory,
	Unsupported_Type,
}

unmarshal_any :: proc(data: []byte, v: any, allocator := context.allocator) -> Unmarshal_Error {
	v := v
	if v == nil || v.id == nil {
		return .Invalid_Parameter
	}

	if v.data == nil {
		return .Invalid_Parameter
	}

	v = reflect.any_base(v)
	ti := type_info_of(v.id)
	if !reflect.is_pointer(ti) || ti.id == rawptr {
		return .Non_Pointer_Parameter
	}

	ti_named, ti_named_ok := ti.variant.(reflect.Type_Info_Named)
	filename: string
	if ti_named_ok do filename = ti_named.name

	table, parse_err := parse_data(data, filename, allocator)
	if parse_err.type != .None {
		return .Invalid_Data
	}

	v = any {
		data = (^rawptr)(v.data)^,
		id   = ti.variant.(reflect.Type_Info_Pointer).elem.id,
	}
	if err := unmarshal_table(table, v); err != nil {
		return err
	}
	return nil
}

unmarshal :: proc(data: []byte, ptr: ^$T, allocator := context.allocator) -> Unmarshal_Error {
	return unmarshal_any(data, ptr, allocator)
}

unmarshal_string :: proc(
	data: string,
	ptr: ^$T,
	allocator := context.allocator,
) -> Unmarshal_Error {
	return unmarshal_any(transmute([]byte)data, ptr, allocator)
}

@(private)
assign_int :: proc(val: any, i: $T) -> bool {
	v := reflect.any_core(val)
	switch &dst in v {
	case i8:
		dst = i8(i)
	case i16:
		dst = i16(i)
	case i16le:
		dst = i16le(i)
	case i16be:
		dst = i16be(i)
	case i32:
		dst = i32(i)
	case i32le:
		dst = i32le(i)
	case i32be:
		dst = i32be(i)
	case i64:
		dst = i64(i)
	case i64le:
		dst = i64le(i)
	case i64be:
		dst = i64be(i)
	case i128:
		dst = i128(i)
	case i128le:
		dst = i128le(i)
	case i128be:
		dst = i128be(i)
	case u8:
		dst = u8(i)
	case u16:
		dst = u16(i)
	case u16le:
		dst = u16le(i)
	case u16be:
		dst = u16be(i)
	case u32:
		dst = u32(i)
	case u32le:
		dst = u32le(i)
	case u32be:
		dst = u32be(i)
	case u64:
		dst = u64(i)
	case u64le:
		dst = u64le(i)
	case u64be:
		dst = u64be(i)
	case u128:
		dst = u128(i)
	case u128le:
		dst = u128le(i)
	case u128be:
		dst = u128be(i)
	case int:
		dst = int(i)
	case uint:
		dst = uint(i)
	case uintptr:
		dst = uintptr(i)
	case:
		is_bit_set_different_endian_to_platform :: proc(ti: ^runtime.Type_Info) -> bool {
			if ti == nil {
				return false
			}
			t := runtime.type_info_base(ti)
			#partial switch info in t.variant {
			case runtime.Type_Info_Integer:
				switch info.endianness {
				case .Platform:
					return false
				case .Little:
					return ODIN_ENDIAN != .Little
				case .Big:
					return ODIN_ENDIAN != .Big
				}
			}
			return false
		}

		ti := type_info_of(v.id)
		if info, ok := ti.variant.(runtime.Type_Info_Bit_Set); ok {
			do_byte_swap := is_bit_set_different_endian_to_platform(info.underlying)
			switch ti.size * 8 {
			case 0: // no-op.
			case 8:
				x := (^u8)(v.data)
				x^ = u8(i)
			case 16:
				x := (^u16)(v.data)
				x^ = do_byte_swap ? intrinsics.byte_swap(u16(i)) : u16(i)
			case 32:
				x := (^u32)(v.data)
				x^ = do_byte_swap ? intrinsics.byte_swap(u32(i)) : u32(i)
			case 64:
				x := (^u64)(v.data)
				x^ = do_byte_swap ? intrinsics.byte_swap(u64(i)) : u64(i)
			case:
				panic("unknown bit_size size")
			}
			return true
		}
		return false
	}
	return true
}

@(private)
assign_float :: proc(val: any, f: $T) -> bool {
	v := reflect.any_core(val)
	switch &dst in v {
	case f16:
		dst = f16(f)
	case f16le:
		dst = f16le(f)
	case f16be:
		dst = f16be(f)
	case f32:
		dst = f32(f)
	case f32le:
		dst = f32le(f)
	case f32be:
		dst = f32be(f)
	case f64:
		dst = f64(f)
	case f64le:
		dst = f64le(f)
	case f64be:
		dst = f64be(f)

	case complex32:
		dst = complex(f16(f), 0)
	case complex64:
		dst = complex(f32(f), 0)
	case complex128:
		dst = complex(f64(f), 0)

	case quaternion64:
		dst = quaternion(w = f16(f), x = 0, y = 0, z = 0)
	case quaternion128:
		dst = quaternion(w = f32(f), x = 0, y = 0, z = 0)
	case quaternion256:
		dst = quaternion(w = f64(f), x = 0, y = 0, z = 0)

	case:
		return false
	}
	return true
}

@(private)
assign_bool :: proc(val: any, b: bool) -> bool {
	v := reflect.any_core(val)
	switch &dst in v {
	case bool:
		dst = bool(b)
	case b8:
		dst = b8(b)
	case b16:
		dst = b16(b)
	case b32:
		dst = b32(b)
	case b64:
		dst = b64(b)
	case:
		return false
	}
	return true
}

@(private)
assign_date :: proc(val: any, date: dates.Date) -> bool {
	switch &v in val {
	case dates.Date:
		v = date
		return true
	}
	return false
}

@(private)
unmarshal_string_token :: proc(val: any, str: string, ti: ^reflect.Type_Info) -> bool {
	val := val
	switch &v in val {
	case string:
		v = str
		return true
	case cstring:
		if str == "" {
			cstr, cstr_err := strings.clone_to_cstring(str)
			if cstr_err != .None do return false
			v = cstr
		} else {
			// NOTE: This is valid because 'clone_string' appends a NUL terminator
			v = cstring(raw_data(str))
		}
		return true
	}

	#partial switch variant in ti.variant {
	case reflect.Type_Info_Enum:
		for name, i in variant.names {
			if name == str {
				assign_int(val, variant.values[i])
				return true
			}
		}
		return true

	case reflect.Type_Info_Integer:
		i := strconv.parse_i128(str) or_return
		if assign_int(val, i) {
			return true
		}
		if assign_float(val, i) {
			return true
		}

	case reflect.Type_Info_Float:
		f := strconv.parse_f64(str) or_return
		if assign_int(val, f) {
			return true
		}
		if assign_float(val, f) {
			return true
		}
	}

	return false
}

@(private)
unmarshal_value :: proc(dest: any, value: Type) -> (err: Unmarshal_Error) {
	dest := dest
	ti := reflect.type_info_base(type_info_of(dest.id))

	if u, ok := ti.variant.(reflect.Type_Info_Union); ok {
		// NOTE: If it's a union with only one variant, then treat it as that variant
		if len(u.variants) == 1 {
			variant := u.variants[0]
			dest.id = variant.id
			ti = reflect.type_info_base(variant)
			if !reflect.is_pointer_internally(variant) {
				tag := any {
					data = rawptr(uintptr(dest.data) + u.tag_offset),
					id   = u.tag_type.id,
				}
				assign_int(tag, 1)
			}
		} else if dest.id != Type {
			for variant, i in u.variants {
				variant_any := any {
					data = dest.data,
					id   = variant.id,
				}
				if err = unmarshal_value(variant_any, value); err == nil {
					raw_tag := i
					if !u.no_nil do raw_tag += 1
					tag := any {
						data = rawptr(uintptr(dest.data) + u.tag_offset),
						id   = u.tag_type.id,
					}
					assign_int(tag, raw_tag)
					return
				}
			}
			return .Unsupported_Type
		}
	}

	switch v in value {
	case ^List:
		unmarshal_list(dest, v) or_return

	case ^Table:
		unmarshal_table(v, dest) or_return

	case bool:
		if !assign_bool(dest, v) {
			return .Unsupported_Type
		}

	case dates.Date:
		if !assign_date(dest, v) {
			return .Unsupported_Type
		}

	case f64:
		if !assign_float(dest, v) {
			return .Unsupported_Type
		}

	case i64:
		if !assign_int(dest, v) {
			return .Unsupported_Type
		}

	case string:
		if !unmarshal_string_token(dest, v, ti) {
			return .Unsupported_Type
		}
	}

	return nil
}

@(private)
toml_name_from_tag_value :: proc(value: string) -> (toml_name, extra: string) {
	toml_name = value
	if comma_idx := strings.index_byte(toml_name, ','); comma_idx >= 0 {
		toml_name = toml_name[:comma_idx]
		extra = value[1 + comma_idx:]
	}
	return
}

@(private)
unmarshal_list :: proc(dest: any, list: ^List) -> Unmarshal_Error {
	assign_list :: proc(
		base: rawptr,
		elem_ti: ^reflect.Type_Info,
		list: ^List,
	) -> Unmarshal_Error {
		for i in 0 ..< len(list) {
			elem_ptr := rawptr(uintptr(base) + uintptr(i) * uintptr(elem_ti.size))
			elem := any {
				data = elem_ptr,
				id   = elem_ti.id,
			}

			unmarshal_value(elem, list[i]) or_return
		}

		return .None
	}

	ti := reflect.type_info_base(type_info_of(dest.id))

	#partial switch t in ti.variant {
	case reflect.Type_Info_Slice:
		raw := cast(^mem.Raw_Slice)dest.data
		data, data_ok := mem.alloc_bytes(t.elem.size * len(list), t.elem.align, list.allocator)
		if data_ok != .None {
			return .Out_Of_Memory
		}
		raw.data = raw_data(data)
		raw.len = len(list)

		return assign_list(raw.data, t.elem, list)

	case reflect.Type_Info_Dynamic_Array:
		raw := cast(^mem.Raw_Dynamic_Array)dest.data
		data, data_ok := mem.alloc_bytes(t.elem.size * len(list), t.elem.align, list.allocator)
		if data_ok != .None {
			return .Out_Of_Memory
		}
		raw.data = raw_data(data)
		raw.len = len(list)
		raw.allocator = context.allocator
		return assign_list(raw.data, t.elem, list)

	case reflect.Type_Info_Array:
		// NOTE(bill): Allow lengths which are less than the dst array
		if len(list) > t.count {
			return .Unsupported_Type
		}
		return assign_list(dest.data, t.elem, list)

	case reflect.Type_Info_Enumerated_Array:
		// NOTE(bill): Allow lengths which are less than the dst array
		if len(list) > t.count {
			return .Unsupported_Type
		}
		return assign_list(dest.data, t.elem, list)

	case reflect.Type_Info_Complex:
		// NOTE(bill): Allow lengths which are less than the dst array
		if len(list) > 2 {
			return .Unsupported_Type
		}

		switch ti.id {
		case complex32:
			return assign_list(dest.data, type_info_of(f16), list)
		case complex64:
			return assign_list(dest.data, type_info_of(f32), list)
		case complex128:
			return assign_list(dest.data, type_info_of(f64), list)
		}


	}

	return .Unsupported_Type
}

unmarshal_table :: proc(table: ^Table, v: any) -> Unmarshal_Error {
	v := v
	ti := reflect.type_info_base(type_info_of(v.id))

	#partial switch t in ti.variant {
	case reflect.Type_Info_Struct:
		if .raw_union in t.flags {
			return .Unsupported_Type
		}

		fields := reflect.struct_fields_zipped(ti.id)
		for key, value in table {
			use_field_idx := -1

			for field, field_idx in fields {
				tag_value := reflect.struct_tag_get(field.tag, "toml")
				toml_name, _ := toml_name_from_tag_value(tag_value)
				if key == toml_name {
					use_field_idx = field_idx
					break
				}
			}

			if use_field_idx < 0 {
				for field, field_idx in fields {
					tag_value := reflect.struct_tag_get(field.tag, "toml")
					toml_name, _ := toml_name_from_tag_value(tag_value)
					if toml_name == "" && key == field.name {
						use_field_idx = field_idx
						break
					}
				}
			}


			check_children_using_fields :: proc(
				key: string,
				parent: typeid,
			) -> (
				offset: uintptr,
				type: ^reflect.Type_Info,
				found: bool,
			) {
				for field in reflect.struct_fields_zipped(parent) {
					if field.is_using && field.name == "_" {
						offset, type, found = check_children_using_fields(key, field.type.id)
						if found {
							offset += field.offset
							return
						}
					}

					tag_value := reflect.struct_tag_get(field.tag, "toml")
					toml_name, _ := toml_name_from_tag_value(tag_value)
					if (toml_name == "" && field.name == key) || toml_name == key {
						offset = field.offset
						type = field.type
						found = true
						return
					}
				}
				return
			}

			offset: uintptr
			type: ^reflect.Type_Info
			field_found := use_field_idx >= 0

			if field_found {
				offset = fields[use_field_idx].offset
				type = fields[use_field_idx].type
			} else {
				offset, type, field_found = check_children_using_fields(key, ti.id)
			}

			if field_found {
				field_ptr := rawptr(uintptr(v.data) + offset)
				field := any {
					data = field_ptr,
					id   = type.id,
				}
				unmarshal_value(field, table[key])
			}
		}

	case reflect.Type_Info_Map:
	// TODO
	case:
		return .Unsupported_Type
	}

	return nil
}

