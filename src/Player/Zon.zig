//! This is a user-facing format and it's designed for convenience rather than efficiency.

const Zon = @This();

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const templates = eldreda.templates;

avatars: []Avatar,
weapons_undressed: []Weapon,
equipment_undressed: []Equipment,

pub const NameMap = struct {
    avatar_id_by_name: std.array_hash_map.String(Player.Avatar.Id),
    avatar_name_by_id: std.array_hash_map.Auto(Player.Avatar.Id, []const u8),

    pub fn init(gpa: Allocator, text_map: *const templates.Text.Map) Allocator.Error!NameMap {
        var avatar_id_by_name: std.array_hash_map.String(Player.Avatar.Id) = .empty;
        defer avatar_id_by_name.deinit(gpa);

        var avatar_name_by_id: std.array_hash_map.Auto(Player.Avatar.Id, []const u8) = .empty;
        defer avatar_name_by_id.deinit(gpa);

        for (
            templates.AvatarBase.table.items(.id),
            templates.AvatarBase.table.items(.code_name),
        ) |id_int, code_name| {
            const id = Player.Avatar.Id.fromInt(id_int) orelse continue;

            const code_name_slice = templates.AvatarBase.table.getString(code_name);
            const code_name_text = text_map.get(code_name_slice) orelse code_name_slice;

            try avatar_id_by_name.putNoClobber(gpa, code_name_text, id);
            try avatar_name_by_id.putNoClobber(gpa, id, code_name_text);
        }

        return .{
            .avatar_id_by_name = avatar_id_by_name.move(),
            .avatar_name_by_id = avatar_name_by_id.move(),
        };
    }

    pub fn deinit(name_map: *NameMap, gpa: Allocator) void {
        name_map.avatar_id_by_name.deinit(gpa);
        name_map.avatar_name_by_id.deinit(gpa);
    }
};

pub const Avatar = struct {
    name: []const u8,
    level: u32,
    rank: u32,
    favorite: bool,
    weapon: ?Weapon,
    equipment: EquipmentSlots,

    pub const EquipmentSlots = struct {
        @"1": ?Equipment,
        @"2": ?Equipment,
        @"3": ?Equipment,
        @"4": ?Equipment,
        @"5": ?Equipment,
        @"6": ?Equipment,
    };
};

pub const Weapon = struct {
    id: u32,

    fn init(data: Player.Weapon) Weapon {
        return .{ .id = @backingInt(data.bits.id) };
    }

    fn pack(weapon: Weapon, diag: *PackDiagnostics) PackError!Player.Weapon {
        return .{
            .uid_maybe = .none,
            .bits = .{
                .id = Player.Weapon.Id.fromInt(weapon.id) orelse return diag.fail(
                    .id_invalid,
                    .{ .kind = "weapon", .id = weapon.id },
                ),
            },
        };
    }
};

pub const Equipment = struct {
    id: u32,
    main_property: Property,
    sub_properties: SubProperties,

    pub const SubProperties = struct {
        @"1": ?Property,
        @"2": ?Property,
        @"3": ?Property,
        @"4": ?Property,
    };

    pub const Property = struct {
        key: u16,
        base: u16,
        add: u16,

        fn init(data: Player.Equipment.Property) Property {
            return .{
                .key = @backingInt(data.key),
                .base = data.base,
                .add = data.add,
            };
        }

        fn pack(property: Property, diag: *PackDiagnostics) PackError!Player.Equipment.Property {
            _ = diag;
            return .{
                .key = @fromBackingInt(property.key),
                .base = property.base,
                .add = property.add,
            };
        }
    };

    fn init(data: Player.Equipment) Equipment {
        return .{
            .id = @backingInt(data.bits.id),
            .main_property = .init(data.bits.main_property),
            .sub_properties = .{
                .@"1" = if (data.bits.sub_properties[0].unwrap()) |p| .init(p) else null,
                .@"2" = if (data.bits.sub_properties[1].unwrap()) |p| .init(p) else null,
                .@"3" = if (data.bits.sub_properties[2].unwrap()) |p| .init(p) else null,
                .@"4" = if (data.bits.sub_properties[3].unwrap()) |p| .init(p) else null,
            },
        };
    }

    fn pack(equipment: Equipment, diag: *PackDiagnostics) PackError!Player.Equipment {
        return .{
            .uid_maybe = .none,
            .bits = .{
                .id = Player.Equipment.Id.fromInt(equipment.id) orelse return diag.fail(
                    .id_invalid,
                    .{ .kind = "equipment", .id = equipment.id },
                ),
                .main_property = try equipment.main_property.pack(diag),
                .sub_properties = sub_properties: {
                    const sub_properties_count = Player.Equipment.Property.sub_count;
                    var sub_properties: [sub_properties_count]Player.Equipment.Property.Optional =
                        undefined;

                    inline for (
                        &sub_properties,
                        @typeInfo(SubProperties).@"struct".field_names,
                    ) |*sub_property_maybe, property_name| {
                        if (@field(equipment.sub_properties, property_name)) |property| {
                            sub_property_maybe.* = .wrap(try property.pack(diag));
                        } else {
                            sub_property_maybe.* = .none;
                        }
                    }

                    break :sub_properties sub_properties;
                },
            },
        };
    }
};

pub fn init(arena: Allocator, name_map: *const NameMap, player: *Player) Allocator.Error!Zon {
    const avatars = try arena.alloc(Avatar, player.avatars.count);

    for (
        avatars,
        player.avatars.bits(),
        player.avatars.ids(),
        player.avatars.weaponUids(),
        player.avatars.dressedEquipment(),
    ) |*avatar_zon, bits, id, weapon_uid_maybe, dressed_equipment| {
        const weapon_maybe: ?Weapon = if (weapon_uid_maybe.unwrap()) |weapon_uid| weapon: {
            const weapon_index = player.weapons.getIndexByUid(weapon_uid).?;
            break :weapon .init(.{
                .uid_maybe = .wrap(weapon_uid),
                .bits = player.weapons.bits()[weapon_index],
            });
        } else null;

        var equipment: Avatar.EquipmentSlots = undefined;
        inline for (
            @typeInfo(Avatar.EquipmentSlots).@"struct".field_names,
            dressed_equipment,
        ) |slot_name, equipment_uid_maybe| {
            if (equipment_uid_maybe.unwrap()) |equipment_uid| {
                const equipment_index = player.equipment.getIndexByUid(equipment_uid).?;
                @field(equipment, slot_name) = .init(.{
                    .uid_maybe = .wrap(equipment_uid),
                    .bits = player.equipment.bits()[equipment_index],
                });
            } else {
                @field(equipment, slot_name) = null;
            }
        }

        avatar_zon.* = .{
            .name = name_map.avatar_name_by_id.get(id).?,
            .level = bits.level_up.getLevel(),
            .rank = bits.level_up.getRank(),
            .favorite = bits.flags.favorite,
            .weapon = weapon_maybe,
            .equipment = equipment,
        };
    }

    var weapons: std.ArrayList(Weapon) = try .initCapacity(arena, player.weapons.count);
    for (player.weapons.uids(), player.weapons.bits()) |weapon_uid, bits| {
        if (player.avatars.getByWeaponUid(weapon_uid) != null)
            continue;

        weapons.appendAssumeCapacity(.init(.{
            .uid_maybe = .wrap(weapon_uid),
            .bits = bits,
        }));
    }

    var equipment: std.ArrayList(Equipment) = try .initCapacity(arena, player.equipment.count);
    for (player.equipment.uids(), player.equipment.bits()) |equipment_uid, bits| {
        if (player.avatars.getByEquipmentUid(equipment_uid) != null)
            continue;

        equipment.appendAssumeCapacity(.init(.{
            .uid_maybe = .wrap(equipment_uid),
            .bits = bits,
        }));
    }

    return .{
        .avatars = avatars,
        .weapons_undressed = weapons.items,
        .equipment_undressed = equipment.items,
    };
}

pub const PackDiagnostics = union(enum) {
    limit_exceeded: struct {
        name: []const u8,
        limit: usize,
    },
    id_invalid: struct {
        kind: []const u8,
        id: u32,
    },
    name_invalid: struct {
        kind: []const u8,
        name: []const u8,
    },
    avatar_duplicated: struct {
        avatar_name: []const u8,
    },
    avatar_level_up_invalid: struct {
        avatar_name: []const u8,
        rank: u32,
        level: u32,
    },

    pub fn format(diag: *const PackDiagnostics, writer: *Io.Writer) Io.Writer.Error!void {
        switch (diag.*) {
            .limit_exceeded => |details| return writer.print(
                "too many {s} encountered, the limit is {d}",
                .{ details.name, details.limit },
            ),
            .id_invalid => |details| return writer.print(
                "invalid {s} id: {d}",
                .{ details.kind, details.id },
            ),
            .name_invalid => |details| return writer.print(
                "invalid {s} name: {q}",
                .{ details.kind, details.name },
            ),
            .avatar_duplicated => |details| return writer.print(
                "duplicated avatar {q}",
                .{details.avatar_name},
            ),
            .avatar_level_up_invalid => |details| return writer.print(
                "avatar {q} has an invalid rank and level combination ({d}, {d})",
                .{ details.avatar_name, details.rank, details.level },
            ),
        }
    }

    fn fail(
        diag: *PackDiagnostics,
        comptime cause: @EnumLiteral(),
        details: @FieldType(PackDiagnostics, @tagName(cause)),
    ) PackError {
        diag.* = @unionInit(PackDiagnostics, @tagName(cause), details);
        return error.CheckDiagnostics;
    }
};

pub const PackError = error{CheckDiagnostics};

pub fn pack(
    zon: *const Player.Zon,
    name_map: *const NameMap,
    diag: *PackDiagnostics,
) PackError!Player {
    var player: Player = .{
        .avatars = .empty,
        .weapons = .empty,
        .equipment = .empty,
    };

    for (zon.avatars) |avatar_zon| {
        const weapon_uid_maybe: Player.Weapon.Uid.Optional = if (avatar_zon.weapon) |weapon_zon| add: {
            const weapon = try weapon_zon.pack(diag);
            const weapon_uid = player.weapons.add(weapon) catch |err| switch (err) {
                error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                    .name = "weapons",
                    .limit = Player.Weapon.count_max,
                }),
            };

            break :add .wrap(weapon_uid);
        } else .none;

        var dressed_equipment: [Player.Avatar.equipment_count]Player.Equipment.Uid.Optional =
            undefined;

        inline for (
            &dressed_equipment,
            @typeInfo(Avatar.EquipmentSlots).@"struct".field_names,
        ) |*equipment_uid_maybe, slot_name| {
            if (@field(avatar_zon.equipment, slot_name)) |equipment_zon| {
                const equipment = try equipment_zon.pack(diag);
                equipment_uid_maybe.* =
                    .wrap(player.equipment.add(equipment) catch |err| switch (err) {
                        error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                            .name = "equipment",
                            .limit = Player.Equipment.count_max,
                        }),
                    });
            } else {
                equipment_uid_maybe.* = .none;
            }
        }

        const avatar: Player.Avatar = .{
            .id = name_map.avatar_id_by_name.get(avatar_zon.name) orelse return diag.fail(
                .name_invalid,
                .{ .kind = "avatar", .name = avatar_zon.name },
            ),
            .bits = .{
                .level_up = Player.Avatar.LevelUp.fromRankAndLevel(
                    avatar_zon.rank,
                    avatar_zon.level,
                ) orelse return diag.fail(.avatar_level_up_invalid, .{
                    .avatar_name = avatar_zon.name,
                    .rank = avatar_zon.rank,
                    .level = avatar_zon.level,
                }),
                .flags = .{ .favorite = avatar_zon.favorite },
            },
            .weapon_uid_maybe = weapon_uid_maybe,
            .dressed_equipment = dressed_equipment,
        };

        const result = player.avatars.getOrAdd(avatar) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "avatars",
                .limit = Player.Avatar.count_max,
            }),
        };

        if (result.found_existing) return diag.fail(.avatar_duplicated, .{
            .avatar_name = avatar_zon.name,
        });
    }

    for (zon.weapons_undressed) |weapon_zon| {
        const weapon = try weapon_zon.pack(diag);
        _ = player.weapons.add(weapon) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "weapons",
                .limit = Player.Weapon.count_max,
            }),
        };
    }

    for (zon.equipment_undressed) |equipment_zon| {
        const equipment = try equipment_zon.pack(diag);
        _ = player.equipment.add(equipment) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "equipment",
                .limit = Player.Equipment.count_max,
            }),
        };
    }

    return player;
}
