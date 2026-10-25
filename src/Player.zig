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

avatars: Avatar.List,
weapons: Weapon.List,
equipment: Equipment.List,

pub const Header = extern struct {
    pub const current_version: u32 = 4;

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    file_version: u32,
    avatar_count: u32,
    weapon_count: u32,
    weapon_uid_counter: u32,
    equipment_count: u32,
    equipment_uid_counter: u32,
};

pub const Avatar = struct {
    id: Id,
    bits: Bits,
    weapon_uid_maybe: Weapon.Uid.Optional,

    pub const count_max = templates.AvatarBase.table.count;

    pub const Bits = extern struct {
        level_up: LevelUp,
        flags: Flags,

        comptime {
            assert(hasUniqueRepresentation(@This()));
        }
    };

    pub const List = struct {
        count: u32,
        bits_buffer: [count_max]Bits,
        ids_buffer: [count_max]Id,
        weapon_uids_buffer: [count_max]Weapon.Uid.Optional,

        pub const empty: List = .{
            .count = 0,
            .bits_buffer = undefined,
            .ids_buffer = undefined,
            .weapon_uids_buffer = undefined,
        };

        pub fn bits(list: *List) []Bits {
            return list.bits_buffer[0..list.count];
        }

        pub fn ids(list: *List) []Id {
            return list.ids_buffer[0..list.count];
        }

        pub fn weaponUids(list: *List) []Weapon.Uid.Optional {
            return list.weapon_uids_buffer[0..list.count];
        }

        pub fn getIndexById(list: *List, id: Id) ?u32 {
            if (mem.findScalar(Id, list.ids(), id)) |index_usize|
                return @intCast(index_usize);

            return null;
        }

        pub fn getIndexByWeaponUid(list: *List, weapon_uid: Weapon.Uid) ?u32 {
            if (mem.findScalar(Weapon.Uid.Optional, list.weaponUids(), .wrap(weapon_uid))) |index_usize|
                return @intCast(index_usize);

            return null;
        }

        pub fn get(list: *List, id_int: u32) ?struct { u32, Avatar } {
            const id = Id.fromInt(id_int) orelse return null;
            const index = list.getIndexById(id) orelse return null;

            return .{ index, .{
                .id = id,
                .bits = list.bits()[index],
                .weapon_uid_maybe = list.weaponUids()[index],
            } };
        }

        pub fn getByWeaponUid(list: *List, weapon_uid: Weapon.Uid) ?struct { u32, Avatar } {
            const index = list.getIndexByWeaponUid(weapon_uid) orelse return null;

            return .{ index, .{
                .id = list.ids()[index],
                .bits = list.bits()[index],
                .weapon_uid_maybe = .wrap(weapon_uid),
            } };
        }

        pub fn replaceAt(list: *List, index: u32, avatar: Avatar) void {
            assert(list.count > index);
            assert(list.ids()[index] == avatar.id); // avatar id is immutable

            list.bits()[index] = avatar.bits;
            list.weaponUids()[index] = avatar.weapon_uid_maybe;
        }

        pub const GetOrAddResult = struct {
            found_existing: bool,
            index: u32,
        };

        pub fn getOrAdd(
            list: *List,
            avatar: Avatar,
        ) error{NoSpaceLeft}!GetOrAddResult {
            if (list.getIndexById(avatar.id)) |index|
                return .{ .found_existing = true, .index = index };

            if (list.count == count_max) return error.NoSpaceLeft;
            errdefer comptime unreachable;

            defer list.count += 1;
            const index = list.count;

            list.ids_buffer[index] = avatar.id;
            list.bits_buffer[index] = avatar.bits;

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

    pub const Flags = packed struct(u8) {
        favorite: bool,
        _: u7 = 0,
    };
};

pub const Weapon = struct {
    uid_maybe: Uid.Optional,
    bits: Bits,

    pub const count_max: usize = 2_000;

    pub const Bits = extern struct {
        id: Id,

        comptime {
            assert(hasUniqueRepresentation(@This()));
        }
    };

    pub const List = struct {
        count: u32,
        uid_counter: u32,
        bits_buffer: [count_max]Bits,
        uids_buffer: [count_max]Uid,

        pub const empty: List = .{
            .count = 0,
            .uid_counter = 0,
            .bits_buffer = undefined,
            .uids_buffer = undefined,
        };

        pub fn uids(list: *List) []Uid {
            return list.uids_buffer[0..list.count];
        }

        pub fn bits(list: *List) []Bits {
            return list.bits_buffer[0..list.count];
        }

        pub fn add(list: *List, weapon: Weapon) error{NoSpaceLeft}!Uid {
            assert(weapon.uid_maybe == .none); // uid is not known before `add`

            if (list.count == count_max) return error.NoSpaceLeft;
            errdefer comptime unreachable;

            const index = list.count;
            defer list.count += 1;

            list.uid_counter += 1;
            const uid: Uid = @fromBackingInt(list.uid_counter);

            list.uids_buffer[index] = uid;
            list.bits_buffer[index] = weapon.bits;

            return uid;
        }

        pub fn getIndexByUid(list: *List, uid: Uid) ?u32 {
            if (mem.findScalar(Uid, list.uids(), uid)) |index_usize|
                return @intCast(index_usize);

            return null;
        }
    };

    pub const Id = enum(u32) {
        _,

        pub fn fromInt(id_int: u32) ?Id {
            if (templates.Weapon.table.getIndexByKey(id_int)) |_|
                return @fromBackingInt(id_int);

            return null;
        }
    };

    pub const Uid = enum(u32) {
        _,

        pub const Optional = enum(u32) {
            none = 0,
            _,

            pub fn wrap(uid: Uid) Optional {
                return @fromBackingInt(@backingInt(uid));
            }

            pub fn unwrap(uid_maybe: Optional) ?Uid {
                return switch (uid_maybe) {
                    .none => null,
                    else => |uid| @fromBackingInt(@backingInt(uid)),
                };
            }
        };
    };
};

pub const Equipment = struct {
    uid_maybe: Uid.Optional,
    bits: Bits,

    pub const count_max = 3_000;

    pub const Bits = extern struct {
        id: Id,
        main_property: Property,
        sub_properties: [Property.sub_count]Property.Optional,
        _: u16 = 0,

        comptime {
            assert(hasUniqueRepresentation(@This()));
        }
    };

    pub const Property = extern struct {
        key: Key,
        base: u16,
        add: u16,

        comptime {
            assert(hasUniqueRepresentation(@This()));
        }

        pub const sub_count = 4;

        pub const Key = enum(u16) {
            _,

            pub const Optional = enum(u16) {
                none = 0,
                _,

                pub fn wrap(key: Key) Key.Optional {
                    assert(@backingInt(key) != @backingInt(Key.Optional.none));
                    return @fromBackingInt(@backingInt(key));
                }

                pub fn unwrap(key_maybe: Key.Optional) ?Key {
                    return switch (key_maybe) {
                        .none => null,
                        _ => |key| @fromBackingInt(@backingInt(key)),
                    };
                }
            };
        };

        pub const Optional = extern struct {
            key_maybe: Key.Optional,
            /// If `key_maybe` is `none`, this is `undefined`.
            base: u16,
            /// If `key_maybe` is `none`, this is `undefined`.
            add: u16,

            comptime {
                assert(hasUniqueRepresentation(@This()));
                assert(@sizeOf(Optional) == @sizeOf(Property));
            }

            pub const none: Optional = .{
                .key_maybe = .none,
                .base = 0,
                .add = 0,
            };

            pub fn wrap(property: Property) Optional {
                return .{
                    .key_maybe = .wrap(property.key),
                    .base = property.base,
                    .add = property.add,
                };
            }

            pub fn unwrap(property_maybe: Optional) ?Property {
                if (property_maybe.key_maybe.unwrap()) |key|
                    return .{
                        .key = key,
                        .base = property_maybe.base,
                        .add = property_maybe.add,
                    };

                return null;
            }
        };
    };

    pub const Id = enum(u32) {
        _,

        pub fn fromInt(id_int: u32) ?Id {
            if (templates.Equipment.table.getIndexByKey(id_int)) |_|
                return @fromBackingInt(id_int);

            return null;
        }
    };

    pub const Uid = enum(u32) {
        _,

        pub const Optional = enum(u32) {
            none = 0,
            _,

            pub fn wrap(uid: Uid) Optional {
                return @fromBackingInt(@backingInt(uid));
            }

            pub fn unwrap(uid_maybe: Optional) ?Uid {
                return switch (uid_maybe) {
                    .none => null,
                    else => |uid| @fromBackingInt(@backingInt(uid)),
                };
            }
        };
    };

    pub const List = struct {
        count: u32,
        uid_counter: u32,
        bits_buffer: [count_max]Equipment.Bits,
        uids_buffer: [count_max]Equipment.Uid,

        pub const empty: List = .{
            .count = 0,
            .uid_counter = 0,
            .bits_buffer = undefined,
            .uids_buffer = undefined,
        };

        pub fn uids(list: *List) []Equipment.Uid {
            return list.uids_buffer[0..list.count];
        }

        pub fn bits(list: *List) []Equipment.Bits {
            return list.bits_buffer[0..list.count];
        }

        pub fn getIndexByUid(list: *List, uid: Equipment.Uid) ?u32 {
            if (mem.findScalar(Uid, list.uids(), uid)) |index_usize|
                return @intCast(index_usize);

            return null;
        }

        pub fn add(list: *List, equipment: Equipment) error{NoSpaceLeft}!Equipment.Uid {
            assert(equipment.uid_maybe == .none); // uid is not known before `add`

            if (list.count == count_max) return error.NoSpaceLeft;
            errdefer comptime unreachable;

            const index = list.count;
            defer list.count += 1;

            list.uid_counter += 1;
            const uid: Uid = @fromBackingInt(list.uid_counter);

            list.uids_buffer[index] = uid;
            list.bits_buffer[index] = equipment.bits;

            return uid;
        }
    };
};

pub fn initDefaults(player: *Player) void {
    player.* = .{
        .avatars = .empty,
        .weapons = .empty,
        .equipment = .empty,
    };

    const avatar_bits_maxed_out: Avatar.Bits = .{
        .level_up = comptime Avatar.LevelUp.fromRankAndLevel(6, 60).?,
        .flags = .{ .favorite = false },
    };

    for (templates.AvatarBase.table.items(.id)) |id_int| {
        const id = Avatar.Id.fromInt(id_int) orelse continue;

        const result = player.avatars.getOrAdd(.{
            .id = id,
            .bits = avatar_bits_maxed_out,
            .weapon_uid_maybe = .none,
        }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };

        assert(!result.found_existing);
    }

    for (templates.Weapon.table.items(.id)) |id_int| {
        const id = Weapon.Id.fromInt(id_int) orelse continue;

        _ = player.weapons.add(.{
            .uid_maybe = .none,
            .bits = .{ .id = id },
        }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
    }

    for (templates.Equipment.table.items(.id)) |id_int| {
        const id = Equipment.Id.fromInt(id_int) orelse continue;

        _ = player.equipment.add(.{
            .uid_maybe = .none,
            .bits = .{
                .id = id,
                .main_property = .{ .key = @fromBackingInt(11103), .base = 550, .add = 0 },
                .sub_properties = @splat(.none),
            },
        }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
    }
}

pub fn saveToFile(player: *Player, io: Io, dir: Io.Dir, sub_path: []const u8) !void {
    var vecs_buffer: [8][]const u8 = undefined;
    var vecs: std.ArrayList([]const u8) = .initBuffer(&vecs_buffer);

    const header: Header = .{
        .file_version = Header.current_version,
        .avatar_count = player.avatars.count,
        .weapon_count = player.weapons.count,
        .weapon_uid_counter = player.weapons.uid_counter,
        .equipment_count = player.equipment.count,
        .equipment_uid_counter = player.equipment.uid_counter,
    };

    vecs.appendAssumeCapacity(@ptrCast(&header));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.ids()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.weaponUids()));
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.uids()));
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.uids()));

    var af = try dir.createFileAtomic(io, sub_path, .{ .replace = true });
    defer af.deinit(io);

    var write_buffer: [1024]u8 = undefined;
    var file_writer = af.file.writer(io, &write_buffer);
    file_writer.interface.writeVecAll(vecs.items) catch return file_writer.err.?;
    file_writer.interface.flush() catch return file_writer.err.?;

    try af.replace(io);
}

pub const LoadDiagnostics = union(enum) {
    /// `error.FileNotFound` and `error.Canceled` are unreachable
    /// and are instead propagated.
    filesystem: FileSystemError,
    file_has_trailing_garbage: void,
    file_version_mismatch: struct { encountered: u32 },
    limit_exceeded: struct {
        name: []const u8,
        limit: u32,
        encountered: u32,
    },

    pub const FileSystemError = Io.File.OpenError ||
        Io.File.Reader.Error ||
        Io.File.Reader.SizeError ||
        error{EarlyEos};

    pub fn format(diag: *const LoadDiagnostics, writer: *Io.Writer) !void {
        switch (diag.*) {
            .filesystem => |err| return writer.print(
                "filesystem failure: {t}",
                .{err},
            ),
            .file_has_trailing_garbage => return writer.writeAll(
                "save file is likely corrupted (trailing garbage encountered)",
            ),
            .file_version_mismatch => |version| return writer.print(
                "save file version mismatch, expected: {d}, got: {d}",
                .{ Header.current_version, version.encountered },
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
        comptime assert(cause != .filesystem); // use `fileSystem` instead

        ptr.* = @unionInit(LoadDiagnostics, @tagName(cause), details);
        return error.CheckDiagnostics;
    }

    fn fileSystem(
        ptr: *LoadDiagnostics,
        err: FileSystemError,
    ) LoadFromFileError {
        switch (err) {
            // cancelation must be propagated rather than logged.
            error.Canceled => |e| return e,
            error.FileNotFound => |e| return e,
            else => |e| {
                ptr.* = .{ .filesystem = e };
                return error.CheckDiagnostics;
            },
        }
    }
};

pub const LoadFromFileOptions = struct {
    dir: Io.Dir,
    sub_path: []const u8,
    diagnostics: *LoadDiagnostics,
};

pub const LoadFromFileError = error{
    FileNotFound,
    CheckDiagnostics,
} || Io.Cancelable;

pub fn loadFromFile(
    player: *Player,
    io: Io,
    options: LoadFromFileOptions,
) LoadFromFileError!void {
    const diag = options.diagnostics;

    const file = options.dir.openFile(io, options.sub_path, .{}) catch |err|
        return diag.fileSystem(err);
    defer file.close(io);

    var read_buffer: [1024]u8 = undefined;
    comptime assert(read_buffer.len >= @sizeOf(Header));

    var file_reader = file.reader(io, &read_buffer);
    const header = file_reader.interface.takeStruct(Header, .little) catch |err| switch (err) {
        error.EndOfStream => return diag.fileSystem(error.EarlyEos),
        error.ReadFailed => return diag.fileSystem(file_reader.err.?),
    };

    if (header.file_version != Header.current_version)
        return diag.fail(.file_version_mismatch, .{ .encountered = header.file_version });

    if (header.avatar_count > Avatar.count_max)
        return diag.fail(.limit_exceeded, .{
            .name = "avatars",
            .limit = Avatar.count_max,
            .encountered = header.avatar_count,
        });

    if (header.weapon_count > Weapon.count_max)
        return diag.fail(.limit_exceeded, .{
            .name = "weapons",
            .limit = Weapon.count_max,
            .encountered = header.weapon_count,
        });

    if (header.equipment_count > Equipment.count_max)
        return diag.fail(.limit_exceeded, .{
            .name = "equipment",
            .limit = Equipment.count_max,
            .encountered = header.equipment_count,
        });

    var vecs_buffer: [7][]u8 = undefined;
    var vecs: std.ArrayList([]u8) = .initBuffer(&vecs_buffer);

    player.avatars.count = header.avatar_count;
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.ids()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.weaponUids()));

    player.weapons.count = header.weapon_count;
    player.weapons.uid_counter = header.weapon_uid_counter;
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.uids()));

    player.equipment.count = header.equipment_count;
    player.equipment.uid_counter = header.equipment_uid_counter;
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.uids()));

    file_reader.interface.readVecAll(vecs.items) catch |err| switch (err) {
        error.EndOfStream => return diag.fileSystem(error.EarlyEos),
        error.ReadFailed => return diag.fileSystem(file_reader.err.?),
    };

    // `Io.File.Reader.atEnd` incorrectly returns `false`
    // because the "end" wasn't observed by any read functions,
    // since we're reading vectors of exact sizes.
    const file_size = file_reader.getSize() catch |err| return diag.fileSystem(err);
    if (file_reader.pos < file_size) return diag.fail(.file_has_trailing_garbage, {});
}
