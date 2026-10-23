const Player = @This();

const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;
const hasUniqueRepresentation = std.meta.hasUniqueRepresentation;

const eldreda = @import("eldreda.zig");
const templates = eldreda.templates;

comptime {
    if (builtin.target.cpu.arch.endian() != .little)
        @compileError("non-little-endian machines are not supported");
}

pub const Header = extern struct {
    pub const current_version: u32 = 1;

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    file_version: u32,
    avatar_count: u32,
};

pub const Avatar = extern struct {
    pub const count_max = templates.AvatarBase.table.count;

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    level_up: LevelUp,

    pub const List = struct {
        count: u32,
        data_buffer: [count_max]Avatar,
        keys_buffer: [count_max]Id,

        pub const empty: List = .{
            .count = 0,
            .data_buffer = undefined,
            .keys_buffer = undefined,
        };

        pub fn data(list: *List) []Avatar {
            return list.data_buffer[0..list.count];
        }

        pub fn keys(list: *List) []Id {
            return list.keys_buffer[0..list.count];
        }

        pub fn getIndexById(list: *List, id: Id) ?u32 {
            if (mem.findScalar(Id, list.keys(), id)) |index_usize|
                return @intCast(index_usize);

            return null;
        }

        pub const GetOrAddResult = struct {
            found_existing: bool,
            index: u32,
        };

        pub fn getOrAdd(
            list: *List,
            entry: struct { id: Id, data: Avatar },
        ) error{NoSpaceLeft}!GetOrAddResult {
            if (list.getIndexById(entry.id)) |index|
                return .{ .found_existing = true, .index = index };

            if (list.count == count_max) return error.NoSpaceLeft;
            errdefer comptime unreachable;

            defer list.count += 1;
            const index = list.count;

            list.keys_buffer[index] = entry.id;
            list.data_buffer[index] = entry.data;

            return .{ .found_existing = false, .index = index };
        }
    };

    pub const Id = enum(u32) {
        _,

        pub fn fromInt(int: u32) ?Id {
            if (templates.AvatarBase.table.getIndexByKey(int)) |template_index| {
                if (templates.AvatarBase.table.items(.unlockable)[template_index])
                    return @fromBackingInt(int);
            }

            return null;
        }
    };

    pub const LevelUp = packed struct(u8) {
        pub const rank_min: u3 = 1;
        pub const rank_max: u3 = 6;

        rank: u3,
        up_times: u4,
        _: u1 = 0,

        pub fn fromRankAndLevel(rank: u32, level: u32) ?LevelUp {
            if (rank < rank_min or rank > rank_max) return null;
            const rank_u3: u3 = @intCast(rank);

            if (level < minLevelForRank(rank_u3) or level > maxLevelForRank(rank_u3))
                return null;

            return .{
                .rank = rank_u3,
                .up_times = @intCast(level - minLevelForRank(rank_u3)),
            };
        }

        pub fn getLevel(level_up: LevelUp) u32 {
            const rank_base: u32 = minLevelForRank(level_up.rank);
            return rank_base + level_up.up_times;
        }

        pub fn getRank(level_up: LevelUp) u3 {
            return level_up.rank;
        }

        pub fn minLevelForRank(rank: u3) u32 {
            if (rank == rank_min) return 1;
            return maxLevelForRank(rank - 1);
        }

        pub fn maxLevelForRank(rank: u3) u32 {
            return @as(u32, rank) * 10;
        }
    };
};

avatars: Avatar.List,

pub fn initDefaults(player: *Player) void {
    player.* = .{
        .avatars = .empty,
    };

    const avatar_maxed_out: Avatar = .{
        .level_up = comptime Avatar.LevelUp.fromRankAndLevel(6, 60).?,
    };

    for (templates.AvatarBase.table.items(.id)) |id_int| {
        const id = Avatar.Id.fromInt(id_int) orelse continue;

        const result = player.avatars.getOrAdd(.{
            .id = id,
            .data = avatar_maxed_out,
        }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };

        assert(!result.found_existing);
    }
}

pub fn saveToFile(player: *Player, io: Io, dir: Io.Dir, sub_path: []const u8) !void {
    var vecs_buffer: [3][]const u8 = undefined;
    var vecs: std.ArrayList([]const u8) = .initBuffer(&vecs_buffer);

    const header: Header = .{
        .file_version = Header.current_version,
        .avatar_count = player.avatars.count,
    };

    vecs.appendAssumeCapacity(@ptrCast(&header));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.data()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.keys()));

    var af = try dir.createFileAtomic(io, sub_path, .{ .replace = true });
    defer af.deinit(io);

    var write_buffer: [1024]u8 = undefined;
    var file_writer = af.file.writer(io, &write_buffer);
    file_writer.interface.writeVecAll(vecs.items) catch return file_writer.err.?;
    file_writer.interface.flush() catch return file_writer.err.?;

    try af.replace(io);
}

pub const LoadDiagnostics = union(enum) {
    file_has_trailing_garbage: void,
    file_version_mismatch: struct { encountered: u32 },
    limit_exceeded: struct {
        name: []const u8,
        limit: u32,
        encountered: u32,
    },

    pub fn format(diag: *const LoadDiagnostics, writer: *Io.Writer) !void {
        switch (diag.*) {
            .file_has_trailing_garbage => return writer.writeAll(
                "save file is likely corrupted (trailing garbage encountered)",
            ),
            .file_version_mismatch => |version| return writer.print(
                "save file version mismatch, expected: {d}, got: {d}",
                .{
                    Header.current_version, version.encountered,
                },
            ),
            .limit_exceeded => |exceeded| return writer.print(
                "limit of {s} exceeded ({d}/{d})",
                .{ exceeded.name, exceeded.encountered, exceeded.limit },
            ),
        }
    }

    fn fail(
        ptr: *LoadDiagnostics,
        comptime cause: @EnumLiteral(),
        details: @FieldType(LoadDiagnostics, @tagName(cause)),
    ) error{CheckDiagnostics} {
        ptr.* = @unionInit(LoadDiagnostics, @tagName(cause), details);
        return error.CheckDiagnostics;
    }
};

pub const LoadFromFileOptions = struct {
    dir: Io.Dir,
    sub_path: []const u8,
    diagnostics: *LoadDiagnostics,
};

pub const LoadFromFileError = error{
    CheckDiagnostics,
} || Io.File.OpenError || Io.File.Reader.Error || Io.File.Reader.SizeError;

pub fn loadFromFile(player: *Player, io: Io, options: LoadFromFileOptions) !void {
    const file = try options.dir.openFile(io, options.sub_path, .{});
    defer file.close(io);

    var read_buffer: [1024]u8 = undefined;
    comptime assert(read_buffer.len >= @sizeOf(Header));

    var file_reader = file.reader(io, &read_buffer);
    const header = file_reader.interface.takeStruct(Header, .little) catch |err| switch (err) {
        error.EndOfStream => return error.EarlyEos,
        error.ReadFailed => return file_reader.err.?,
    };

    const diag = options.diagnostics;

    if (header.file_version != Header.current_version)
        return diag.fail(.file_version_mismatch, .{ .encountered = header.file_version });

    if (header.avatar_count > Avatar.count_max)
        return diag.fail(.limit_exceeded, .{
            .name = "avatars",
            .limit = Avatar.count_max,
            .encountered = header.avatar_count,
        });

    var vecs_buffer: [2][]u8 = undefined;
    var vecs: std.ArrayList([]u8) = .initBuffer(&vecs_buffer);

    player.avatars.count = header.avatar_count;
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.data()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.keys()));

    file_reader.interface.readVecAll(vecs.items) catch |err| switch (err) {
        error.EndOfStream => return error.EarlyEos,
        error.ReadFailed => return file_reader.err.?,
    };

    // `Io.File.Reader.atEnd` incorrectly returns `false`
    // because the "end" wasn't observed by any read functions,
    // since we're reading vectors of exact sizes.
    if (file_reader.pos < try file_reader.getSize())
        return diag.fail(.file_has_trailing_garbage, {});
}
