const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

fn usage(io: Io) noreturn {
    Io.File.stdout().writeStreamingAll(
        io,
        "usage: eldreda-convert-templatetb [input_dir] [output_dir]\n",
    ) catch {};
    process.exit(1);
}

const template_tb_dir_path = "TemplateTb";

pub fn main(init: process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    if (args.len != 3) usage(io);

    const inp_dir_path = args[1];
    const inp_dir = try Io.Dir.cwd().openDir(io, inp_dir_path, .{});
    defer inp_dir.close(io);

    const out_dir_path = args[2];
    const out_dir = try Io.Dir.cwd().openDir(io, out_dir_path, .{});
    defer out_dir.close(io);

    const gpa = init.gpa;
    try convertTemplateTbs(io, gpa, inp_dir, out_dir);
}

const template_tb_list: []const struct { []const u8, type } = &.{
    .{ "AvatarBaseTemplateTb", AvatarBaseTemplate },
    .{ "UnlockConfigTemplateTb", UnlockConfigTemplate },
    .{ "WeaponTemplateTb", WeaponTemplate },
};

const AvatarBaseTemplate = struct {
    id: u32,
    audio_event_replace_param: String,
    unlockable: bool,

    // TODO: bonus points for build/compile-fbs.zig
    const Fbs = struct {
        id: fbs.Int(u32),
        code_name: fbs.Discard,
        name: fbs.Discard,
        full_name: fbs.Discard,
        audio_event_replace_param: fbs.String,
        audio_bank: fbs.Discard,
        hit_types: fbs.Discard,
        element_types: fbs.Discard,
        unk_1: fbs.Discard,
        gender: fbs.Discard,
        camp: fbs.Discard,
        unk_2: fbs.Discard,
        unk_3: fbs.Discard,
        unk_4: fbs.Discard,
        unk_5: fbs.Discard,
        unk_6: fbs.Discard,
        unk_7: fbs.Discard,
        unk_8: fbs.Discard,
        unlockable: fbs.Bool,
    };
};

const UnlockConfigTemplate = struct {
    id: i32,

    const Fbs = struct {
        id: fbs.Int(i32),
    };
};

const WeaponTemplate = struct {
    id: u32,
    weapon_name: String,

    const Fbs = struct {
        id: fbs.Int(u32),
        weapon_name: fbs.String,
    };
};

fn TemplateTb(comptime Template: type) type {
    return struct { data: []const Template };
}

fn fieldsOrderedByAlignment(comptime T: type) bool {
    const field_types = @typeInfo(T).@"struct".field_types;
    comptime var prev_alignment = @alignOf(BackingType(field_types[0]));

    inline for (field_types[1..]) |FieldType| {
        const alignment = @alignOf(BackingType(FieldType));
        if (prev_alignment < alignment) return false;
        prev_alignment = alignment;
    }

    return true;
}

fn convertTemplateTbs(io: Io, gpa: Allocator, inp_dir: Io.Dir, out_dir: Io.Dir) !void {
    var arena_instance: std.heap.ArenaAllocator = .init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var out_write_buffer: [4096]u8 = undefined;

    inline for (template_tb_list) |template_tb_entry| {
        defer _ = arena_instance.reset(.retain_capacity);
        const file_name_stem, const Template = template_tb_entry;
        const file_name_bin = file_name_stem ++ ".bin";

        const inp_bytes = try inp_dir.readFileAlloc(io, file_name_bin, gpa, .unlimited);
        defer gpa.free(inp_bytes);

        const Root = struct { data: []const fbs.Table(Template.Fbs) };
        const parsed = try parseFlatbuffer(Root, arena, inp_bytes);

        const out_file = try out_dir.createFile(io, file_name_stem, .{});
        defer out_file.close(io);

        var out_file_writer = out_file.writer(io, &out_write_buffer);
        convertTemplateList(
            arena,
            Template,
            inp_bytes,
            parsed.data,
            &out_file_writer.interface,
        ) catch |err| switch (err) {
            error.WriteFailed => return out_file_writer.err.?,
            else => |e| return e,
        };
    }
}

const fbs = struct {
    pub fn Table(comptime S: type) type {
        return struct {
            base: usize,
            fields: Struct,

            pub const Struct = S;
        };
    }

    pub const Discard = struct {
        offset: u16,
    };

    pub fn Int(comptime T: type) type {
        return struct {
            offset: u16,

            pub fn read(int: @This(), buffer: []const u8, table_base: usize) T {
                if (int.offset == 0) return 0;
                const ptr = buffer[table_base + int.offset ..][0..@sizeOf(T)];
                return mem.readInt(T, ptr, .little);
            }
        };
    }

    pub const String = struct {
        offset: u16,

        pub fn read(string: *const fbs.String, buffer: []const u8, table_base: usize) []const u8 {
            if (string.offset == 0) return "";

            const payload_offset_ptr = buffer[table_base + string.offset ..][0..4];
            const payload_offset = mem.readInt(i32, payload_offset_ptr, .little);

            const payload =
                buffer[@intCast(@as(isize, @intCast(table_base + string.offset)) + payload_offset)..];
            const len = mem.readInt(u32, payload[0..4], .little);
            return payload[4..][0..len];
        }
    };

    pub const Bool = struct {
        offset: u16,

        pub fn read(@"bool": *const Bool, buffer: []const u8, table_base: usize) bool {
            if (@"bool".offset == 0) return false;
            return buffer[table_base + @"bool".offset] != 0;
        }
    };
};

fn parseFlatbuffer(comptime Root: type, arena: Allocator, bytes: []const u8) Allocator.Error!Root {
    const root_offset: u31 = @intCast(mem.readInt(i32, bytes[0..4], .little));
    const root_vtable_offset = root_offset - mem.readInt(i32, bytes[root_offset..][0..4], .little);
    comptime assert(@typeInfo(Root).@"struct".field_names.len == 1); // TODO

    const first_field_offset = mem.readInt(
        u16,
        bytes[@intCast(root_vtable_offset + 2)..][0..2],
        .little,
    );

    const Slice = @typeInfo(Root).@"struct".field_types[0];
    const Item = @typeInfo(Slice).pointer.child;
    const Struct = Item.Struct;

    const item_count_offset: usize = @intCast(root_offset + first_field_offset);
    const item_count = mem.readInt(u32, bytes[item_count_offset..][0..4], .little);
    const items_base = item_count_offset + @sizeOf(u32);

    const items_slice = try arena.alloc(Item, item_count);
    for (items_slice, 0..) |*item, item_index| {
        const item_slot = items_base + item_index * @sizeOf(u32);
        const item_offset = mem.readInt(u32, bytes[item_slot..][0..4], .little);

        item.base = item_slot + item_offset;

        const vtable_sub_ptr = bytes[item_slot + item_offset ..][0..4];
        const item_vtable_sub = mem.readInt(i32, vtable_sub_ptr, .little);
        const item_vtable_base =
            bytes[@intCast(@as(isize, @intCast(item_slot + item_offset)) - item_vtable_sub)..];

        const item_vtable_size = mem.readInt(u16, item_vtable_base[0..2], .little);

        inline for (@typeInfo(Struct).@"struct".field_names, 0..) |field_name, field_index| {
            const offset_pos = 4 + field_index * @sizeOf(u16);

            if (offset_pos > item_vtable_size) {
                @field(item.fields, field_name) = .{ .offset = 0 };
            } else {
                const field_offset =
                    mem.readInt(u16, item_vtable_base[offset_pos..][0..2], .little);

                @field(item.fields, field_name) = .{ .offset = field_offset };
            }
        }
    }

    return .{ .data = items_slice };
}

const String = enum(u32) {
    empty = std.math.maxInt(u32),
    _,

    const Table = struct {
        interned: std.array_hash_map.String(String),
        bytes: std.ArrayList(u8),

        pub const init: Table = .{
            .interned = .empty,
            .bytes = .empty,
        };

        pub fn put(
            table: *String.Table,
            gpa: Allocator,
            slice: []const u8,
        ) Allocator.Error!String {
            if (slice.len == 0) return .empty;

            if (table.interned.get(slice)) |string| {
                assert(string != .empty);
                return string;
            }

            try table.bytes.ensureUnusedCapacity(gpa, slice.len + 1);
            try table.interned.ensureUnusedCapacity(gpa, 1);
            errdefer comptime unreachable;

            const string: String = @fromBackingInt(@intCast(table.bytes.items.len));
            assert(string != .empty); // overflow

            table.bytes.appendSliceAssumeCapacity(slice);
            table.bytes.appendAssumeCapacity(0);
            table.interned.putAssumeCapacity(slice, string);
            return string;
        }
    };
};

fn BackingType(comptime T: type) type {
    return switch (T) {
        []const u8 => String,
        else => T,
    };
}

/// The output is the following:
/// HEADER: item count (u32), `Offsets` (an u32 for each field)
/// PAYLOAD: struct-of-arrays, []const u8 are indices into `STRING_TABLE`
/// STRING_TABLE: zero-terminated-strings
fn convertTemplateList(
    arena: Allocator,
    comptime Template: type,
    buffer_fbs: []const u8,
    list_fbs: []const fbs.Table(Template.Fbs),
    output: *Io.Writer,
) !void {
    comptime assert(fieldsOrderedByAlignment(Template));

    const field_types = @typeInfo(Template).@"struct".field_types;
    const field_names = @typeInfo(Template).@"struct".field_names;
    const Offsets = @Struct(.@"extern", null, field_names, &@splat(u32), &@splat(.{}));
    const item_count: u32 = @intCast(list_fbs.len);

    var offsets: Offsets = undefined;

    var position: u32 = 0;
    inline for (field_types, field_names) |FieldType, field_name| {
        @field(offsets, field_name) = position;
        position += @sizeOf(BackingType(FieldType)) * item_count;
    }

    var string_table: String.Table = .init;
    const struct_of_arrays = try arena.alloc([]const u8, field_names.len);

    inline for (field_types, field_names, struct_of_arrays) |FieldType, field_name, *array| {
        const field_values = try arena.alloc(BackingType(FieldType), item_count);

        for (list_fbs, field_values) |template_fbs, *field_value| {
            const value_fbs =
                @field(template_fbs.fields, field_name).read(buffer_fbs, template_fbs.base);

            field_value.* = switch (FieldType) {
                String => try string_table.put(arena, value_fbs),
                else => value_fbs,
            };
        }

        array.* = @ptrCast(field_values);
    }

    const first_field_alignment = @alignOf(BackingType(field_types[0]));
    const post_header = @sizeOf(u32) + @sizeOf(Offsets);
    const post_header_aligned = mem.alignForward(usize, post_header, first_field_alignment);
    const post_header_padding = post_header_aligned - post_header;

    try output.writeAll(@ptrCast(&item_count)); // item count
    try output.writeAll(@ptrCast(&offsets));
    try output.splatByteAll(0, post_header_padding);
    try output.writeVecAll(struct_of_arrays);
    try output.writeAll(string_table.bytes.items);
    try output.flush();
}
