package toml

import "core:reflect"

Unmarshal_Error :: enum {
	Invalid_Data,
	Invalid_Parameter,
	Non_Pointer_Parameter,
	Multiple_Use_Field,
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

	v = any{
		data = (^rawptr)(v.data)^,
		id = ti.variant.(reflect.Type_Info_Pointer).elem.id
	}
	if err := unmarshal_table(table, v); err != nil {
		return err
	}
	return nil
}

unmarshal :: proc(data: []byte, ptr: ^$T, allocator := context.allocator) -> Unmarshal_Error {
	return unmarshal_any(data, ptr, allocator)	
}

unmarshal_string :: proc(data: string, ptr: ^$T, allocator := context.allocator) -> Unmarshal_Error {
	return unmarshal_any(transmute([]byte)data, ptr, allocator)
}

unmarshal_table :: proc(table: ^Table, v: any) -> Unmarshal_Error {
	v := v
	ti := reflect.type_info_base(type_info_of(v.id))

	#partial switch t in ti.variant {
		case reflect.Type_Info_Struct:
			// TODO
		case reflect.Type_Info_Map:
			// TODO
		case:
			return .Unsupported_Type
	}

	return nil
}
