const std = @import("std");
const assert = std.debug.assert;

pub fn BoundedMultiArray(comptime Struct: type, comptime capacity: usize) type {
    const struct_info = @typeInfo(Struct).@"struct";

    return struct {
        count: usize,
        arrays: Arrays,

        const List = @This();

        pub const empty: List = .{
            .count = 0,
            .arrays = undefined,
        };

        pub const Arrays = Arrays: {
            var array_types: [struct_info.field_types.len]type = undefined;
            for (&array_types, struct_info.field_types) |*Array, Item|
                Array.* = [capacity]Item;

            break :Arrays @Struct(.auto, null, struct_info.field_names, &array_types, &@splat(.{}));
        };

        pub const Ptr = Ptr: {
            var ptr_field_types: [struct_info.field_types.len]type = undefined;

            @setEvalBranchQuota(ptr_field_types.len);
            for (&ptr_field_types, struct_info.field_types) |*PtrField, StructField|
                PtrField.* = *StructField;

            break :Ptr @Struct(
                .auto,
                null,
                struct_info.field_names,
                &ptr_field_types,
                &@splat(.{}),
            );
        };

        pub fn addOne(list: *List) Ptr {
            assert(capacity > list.count);
            const index = list.count;
            defer list.count += 1;

            return list.getPtr(index);
        }

        pub fn append(list: *List, item: Struct) void {
            const ptr = list.addOne();

            inline for (struct_info.field_names) |field_name|
                @field(ptr, field_name).* = @field(item, field_name);
        }

        pub fn getPtr(list: *List, index: usize) Ptr {
            var ptr: Ptr = undefined;

            @setEvalBranchQuota(struct_info.field_names.len);
            inline for (struct_info.field_names) |field_name|
                @field(ptr, field_name) = &@field(list.arrays, field_name)[index];

            return ptr;
        }

        pub const Field = std.meta.FieldEnum(Struct);

        pub fn items(
            list: *List,
            comptime field: Field,
        ) []@FieldType(Struct, @tagName(field)) {
            return @field(list.arrays, @tagName(field))[0..list.count];
        }
    };
}
