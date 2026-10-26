const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

fn usage(io: Io) noreturn {
    Io.File.stdout().writeStreamingAll(
        io,
        "usage: eldreda-convert-textmap [input_file_path]\n",
    ) catch {};
    process.exit(1);
}

const textmap_includes: []const struct {
    prefix: []const u8,
    suffix: []const u8,
} = &.{
    .{ .prefix = "Avatar_Female_Size", .suffix = "_En" },
    .{ .prefix = "Avatar_Male_Size", .suffix = "_En" },
};

pub fn main(init: process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const io = init.io;
    if (args.len != 2) usage(io);

    const input_file_path = args[1];
    const content = try Io.Dir.cwd().readFileAlloc(io, input_file_path, gpa, .unlimited);
    defer gpa.free(content);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);

    const Root = struct { data: []const fbs.Table(Entry.Fbs) };
    const parsed = try parseFlatbuffer(Root, arena, content);

    convertTemplateList(
        gpa,
        Entry,
        content,
        parsed.data,
        &stdout_writer.interface,
    ) catch |err| switch (err) {
        error.WriteFailed => return stdout_writer.err.?,
        else => |e| return e,
    };

    stdout_writer.interface.flush() catch |err| switch (err) {
        error.WriteFailed => return stdout_writer.err.?,
    };
}

const Entry = struct {
    key: String,
    value: String,

    const Fbs = struct {
        key: fbs.String,
        value: fbs.String,
    };
};

const fbs = struct {
    pub fn Table(comptime S: type) type {
        return struct {
            base: usize,
            fields: Struct,

            pub const Struct = S;
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
};

fn parseFlatbuffer(comptime Root: type, arena: Allocator, bytes: []const u8) Allocator.Error!Root {
    const root_offset: u31 = @intCast(mem.readInt(i32, bytes[0..4], .little));
    const root_vtable_offset = root_offset - mem.readInt(i32, bytes[root_offset..][0..4], .little);
    comptime assert(@typeInfo(Root).@"struct".field_names.len == 1);

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

        fn deinit(table: *String.Table, gpa: Allocator) void {
            table.interned.deinit(gpa);
            table.bytes.deinit(gpa);
        }

        fn put(
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
    gpa: Allocator,
    comptime Template: type,
    buffer_fbs: []const u8,
    list_fbs: []const fbs.Table(Template.Fbs),
    output: *Io.Writer,
) !void {
    const field_types = @typeInfo(Template).@"struct".field_types;
    const field_names = @typeInfo(Template).@"struct".field_names;
    const Offsets = @Struct(.@"extern", null, field_names, &@splat(u32), &@splat(.{}));

    var string_table: String.Table = .init;
    defer string_table.deinit(gpa);

    var entries: std.MultiArrayList(struct {
        key: String,
        value: String,
    }) = try .initCapacity(gpa, list_fbs.len);
    defer entries.deinit(gpa);

    for (list_fbs) |entry_fbs| {
        const key_slice = entry_fbs.fields.key.read(buffer_fbs, entry_fbs.base);

        for (textmap_includes) |include| {
            if (mem.startsWith(u8, key_slice, include.prefix) and
                mem.endsWith(u8, key_slice, include.suffix))
                break;
        } else continue;

        const value_slice = entry_fbs.fields.value.read(buffer_fbs, entry_fbs.base);

        const key = try string_table.put(gpa, key_slice);
        const value = try string_table.put(gpa, value_slice);

        entries.appendAssumeCapacity(.{
            .key = key,
            .value = value,
        });
    }

    const first_field_alignment = @alignOf(BackingType(field_types[0]));
    const post_header = @sizeOf(u32) + @sizeOf(Offsets);
    const post_header_aligned = mem.alignForward(usize, post_header, first_field_alignment);
    const post_header_padding = post_header_aligned - post_header;

    const offsets: Offsets = .{
        .key = 0,
        .value = @intCast(entries.len * @sizeOf(String)),
    };

    const item_count: u32 = @intCast(entries.len);
    try output.writeAll(@ptrCast(&item_count)); // item count
    try output.writeAll(@ptrCast(&offsets));
    try output.splatByteAll(0, post_header_padding);

    var vec: [2][]const u8 = .{
        @ptrCast(entries.items(.key)),
        @ptrCast(entries.items(.value)),
    };

    try output.writeVecAll(&vec);
    try output.writeAll(string_table.bytes.items);
    try output.flush();
}
