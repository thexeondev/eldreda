const std = @import("std");
const mem = std.mem;

pub const AvatarBase = struct {
    pub const Table = TemplateTb(AvatarBase, "AvatarBaseTemplateTb", .id);
    pub const table: Table = .init();

    id: u32,
    audio_event_replace_param: String,
    unlockable: bool,
};

pub const UnlockConfig = struct {
    pub const Table = TemplateTb(UnlockConfig, "UnlockConfigTemplateTb", .id);
    pub const table: Table = .init();

    id: i32,
};

pub const String = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

fn TemplateTb(
    comptime Template: type,
    comptime file_name: []const u8,
    comptime key_field: @EnumLiteral(),
) type {
    const struct_info = @typeInfo(Template).@"struct";
    const field_names = struct_info.field_names;

    return struct {
        const Tb = @This();

        const bytes align(@alignOf(u32)) = @embedFile(file_name).*;

        const Arrays = Arrays: {
            var field_types: [struct_info.field_names.len]type = undefined;
            for (struct_info.field_types, &field_types) |Item, *Slice|
                Slice.* = []const Item;

            break :Arrays @Struct(
                .auto,
                null,
                struct_info.field_names,
                &field_types,
                &@splat(.{}),
            );
        };

        const Offsets = @Struct(
            .@"extern",
            null,
            field_names,
            &@splat(u32),
            &@splat(.{}),
        );

        const data_start = arrays_base: {
            const first_field_alignment = @alignOf(struct_info.field_types[0]);
            const post_header = @sizeOf(u32) + @sizeOf(Offsets);
            break :arrays_base mem.alignForward(usize, post_header, first_field_alignment);
        };

        count: u32,
        arrays: Arrays,
        string_table: []const u8,
        /// Biased towards cheap linear search.
        index_by_key: std.array_hash_map.Custom(void, void, void, false),

        pub const Field = std.meta.FieldEnum(Template);

        fn init() Tb {
            const item_count = @as(*const u32, @ptrCast(bytes[0..4])).*;
            const offsets: *const Offsets = @ptrCast(bytes[4..][0..@sizeOf(Offsets)]);
            const first_field_alignment = @alignOf(struct_info.field_types[0]);

            const string_table_offset =
                @field(offsets, field_names[field_names.len - 1]) +
                (@sizeOf(@FieldType(Template, field_names[field_names.len - 1])) * item_count);

            const data: []align(first_field_alignment) const u8 = @alignCast(bytes[data_start..]);
            var arrays: Arrays = undefined;

            inline for (field_names, struct_info.field_types) |field_name, FieldType| {
                const offset = @field(offsets, field_name);
                @field(arrays, field_name) =
                    @as([*]const FieldType, @ptrCast(data.ptr[offset..]))[0..item_count];
            }

            return .{
                .count = item_count,
                .arrays = arrays,
                .string_table = data[string_table_offset..],
                .index_by_key = .{ .entries = .{
                    .bytes = undefined,
                    .len = item_count,
                    .capacity = item_count,
                } },
            };
        }

        const Key = @FieldType(Template, @tagName(key_field));

        pub fn getIndexByKey(tb: *const Tb, key: Key) ?u32 {
            const Adapter = struct {
                keys: []const Key,

                pub fn eql(context: @This(), a: Key, b_void: void, b_map_index: usize) bool {
                    _ = b_void;
                    return a == context.keys[b_map_index];
                }

                pub fn hash(context: @This(), a: Key) u32 {
                    _ = context;
                    return @bitCast(a);
                }
            };

            const adapter: Adapter = .{ .keys = tb.items(key_field) };
            if (tb.index_by_key.getIndexAdapted(key, adapter)) |index_usize|
                return @intCast(index_usize);

            return null;
        }

        pub fn items(tb: *const Tb, comptime which: Field) @FieldType(Arrays, @tagName(which)) {
            return @field(tb.arrays, @tagName(which));
        }

        pub fn getString(tb: *const Tb, string: String) [:0]const u8 {
            switch (string) {
                .empty => return "",
                _ => {
                    const start = @backingInt(string);
                    const ptr: [*:0]const u8 = @ptrCast(tb.string_table[start..].ptr);
                    return mem.span(ptr);
                },
            }
        }
    };
}
