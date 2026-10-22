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
};

const AvatarBaseTemplate = struct {
    id: u32,
    audio_event_replace_param: []const u8,
};

const UnlockConfigTemplate = struct {
    id: i32,
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

    var inp_read_buffer: [4096]u8 = undefined;
    var out_write_buffer: [4096]u8 = undefined;

    inline for (template_tb_list) |template_tb_entry| {
        defer _ = arena_instance.reset(.retain_capacity);
        const file_name_stem, const Template = template_tb_entry;
        const file_name_json = file_name_stem ++ ".json";

        const inp_file = try inp_dir.openFile(io, file_name_json, .{});
        defer inp_file.close(io);
        var inp_file_reader = inp_file.reader(io, &inp_read_buffer);

        var json_reader: std.json.Reader = .init(arena, &inp_file_reader.interface);

        const parsed = try std.json.parseFromTokenSourceLeaky(
            TemplateTb(Template),
            arena,
            &json_reader,
            .{
                .ignore_unknown_fields = true,
            },
        );

        const out_file = try out_dir.createFile(io, file_name_stem, .{});
        defer out_file.close(io);

        var out_file_writer = out_file.writer(io, &out_write_buffer);
        convertTemplateList(
            arena,
            Template,
            parsed.data,
            &out_file_writer.interface,
        ) catch |err| switch (err) {
            error.WriteFailed => return out_file_writer.err.?,
            else => |e| return e,
        };
    }
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
    list: []const Template,
    output: *Io.Writer,
) !void {
    comptime assert(fieldsOrderedByAlignment(Template));

    const field_types = @typeInfo(Template).@"struct".field_types;
    const field_names = @typeInfo(Template).@"struct".field_names;
    const Offsets = @Struct(.@"extern", null, field_names, &@splat(u32), &@splat(.{}));
    const item_count: u32 = @intCast(list.len);

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
        for (list, field_values) |template, *field_value| {
            const value_json = @field(template, field_name);
            field_value.* = switch (FieldType) {
                []const u8 => try string_table.put(arena, value_json),
                else => value_json,
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
