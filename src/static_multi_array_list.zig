const std = @import("std");
const assert = std.debug.assert;

pub fn StaticMultiArrayList(comptime Struct: type) type {
    const struct_info = @typeInfo(Struct).@"struct";

    return struct {
        const List = @This();

        const size_of_one = size_of_one: {
            var size: usize = 0;

            @setEvalBranchQuota(struct_info.field_types.len);
            for (struct_info.field_types) |FieldType|
                size += @sizeOf(FieldType);

            break :size_of_one size;
        };

        pub const alignment = highest_alignment: {
            @setEvalBranchQuota(struct_info.field_names.len);
            var prev_align = @alignOf(struct_info.field_types[0]);

            for (struct_info.field_types[1..]) |FieldType| {
                const next_align = @alignOf(FieldType);
                assert(prev_align >= next_align); // struct fields must be ordered by alignment.
                prev_align = next_align;
            }

            break :highest_alignment @alignOf(struct_info.field_types[0]);
        };

        count: usize,
        buffer: []align(alignment) u8,
        offsets: Slice,

        pub const Slice = Slice: {
            var slice_field_types: [struct_info.field_types.len]type = undefined;

            @setEvalBranchQuota(slice_field_types.len);
            for (&slice_field_types, struct_info.field_types) |*SliceField, StructField|
                SliceField.* = []StructField;

            break :Slice @Struct(
                .auto,
                null,
                struct_info.field_names,
                &slice_field_types,
                &@splat(.{}),
            );
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

        /// Inline function so that `bufferSizeFor` is known at comptime.
        pub inline fn bufferSizeFor(n: usize) usize {
            return size_of_one * n;
        }

        pub fn Buffer(comptime n: usize) type {
            return [bufferSizeFor(n)]u8;
        }

        pub fn init(buffer: []align(alignment) u8) List {
            const n = @divExact(buffer.len, size_of_one);

            var offsets: Slice = undefined;
            comptime var offset: usize = 0;

            @setEvalBranchQuota(struct_info.field_names.len);
            inline for (struct_info.field_names, struct_info.field_types) |field_name, FieldType| {
                @field(offsets, field_name) = @as(
                    [*]FieldType,
                    @ptrCast(@alignCast(buffer.ptr[offset * n ..])),
                )[0..n];

                offset += @sizeOf(FieldType);
            }

            return .{ .count = 0, .buffer = buffer, .offsets = offsets };
        }

        pub fn capacity(list: *const List) usize {
            return @divExact(list.buffer.len, size_of_one);
        }

        pub fn addOne(list: *List) Ptr {
            assert(list.capacity() > list.count);
            const index = list.count;
            defer list.count += 1;

            return list.getPtr(index);
        }

        pub fn append(list: *List, item: Struct) void {
            const ptr = list.addOne();

            inline for (struct_info.field_names) |field_name|
                @field(ptr, field_name).* = @field(item, field_name);
        }

        pub fn getPtr(list: *const List, index: usize) Ptr {
            var ptr: Ptr = undefined;

            @setEvalBranchQuota(struct_info.field_names.len);
            inline for (struct_info.field_names) |field_name|
                @field(ptr, field_name) = &@field(list.offsets, field_name)[index];

            return ptr;
        }

        pub const Field = std.meta.FieldEnum(Struct);

        pub fn items(
            list: *const List,
            comptime field: Field,
        ) []@FieldType(Struct, @tagName(field)) {
            return @field(list.offsets, @tagName(field))[0..list.count];
        }
    };
}
