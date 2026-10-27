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
    string_arena: std.heap.ArenaAllocator.State,
    avatar_id_by_name: std.array_hash_map.String(Player.Avatar.Id),
    avatar_name_by_id: std.array_hash_map.Auto(Player.Avatar.Id, []const u8),
    weapon_id_by_name: std.array_hash_map.String(Player.Weapon.Id),
    weapon_name_by_id: std.array_hash_map.Auto(Player.Weapon.Id, []const u8),
    equipment_id_by_name_rarity_s: std.array_hash_map.String(u32),
    equipment_name_by_id_rarity_s: std.array_hash_map.Auto(u32, []const u8),

    pub fn init(gpa: Allocator, text_map: *const templates.Text.Map) Allocator.Error!NameMap {
        var arena_instance: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena_instance.deinit();
        const arena = arena_instance.allocator();

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

        var weapon_id_by_name: std.array_hash_map.String(Player.Weapon.Id) = .empty;
        defer weapon_id_by_name.deinit(gpa);
        var weapon_name_by_id: std.array_hash_map.Auto(Player.Weapon.Id, []const u8) = .empty;
        defer weapon_name_by_id.deinit(gpa);

        for (
            templates.Weapon.table.items(.id),
            templates.Weapon.table.items(.weapon_name),
        ) |id_int, weapon_name| {
            const id = Player.Weapon.Id.fromInt(id_int) orelse continue;

            const weapon_name_unformatted = templates.Weapon.table.getString(weapon_name);
            const weapon_name_slice = try arena.print("Item_{s}_Name", .{weapon_name_unformatted});
            const weapon_name_text = text_map.get(weapon_name_slice) orelse weapon_name_slice;

            try weapon_id_by_name.putNoClobber(gpa, weapon_name_text, id);
            try weapon_name_by_id.putNoClobber(gpa, id, weapon_name_text);
        }

        var equipment_id_by_name_rarity_s: std.array_hash_map.String(u32) = .empty;
        defer equipment_id_by_name_rarity_s.deinit(gpa);
        var equipment_name_by_id_rarity_s: std.array_hash_map.Auto(u32, []const u8) = .empty;
        defer equipment_name_by_id_rarity_s.deinit(gpa);

        for (templates.Equipment.table.items(.id)) |id_int| {
            const rarity: Equipment.Id.Rarity = @fromBackingInt((id_int / 10) % 10);
            if (rarity != .s) continue;

            const equipment_name_slice = try arena.print("Item_Equipment_{d}_name", .{id_int});
            const equipment_name_text = text_map.get(equipment_name_slice) orelse equipment_name_slice;

            try equipment_id_by_name_rarity_s.putNoClobber(gpa, equipment_name_text, id_int);
            try equipment_name_by_id_rarity_s.putNoClobber(gpa, id_int, equipment_name_text);
        }

        return .{
            .string_arena = arena_instance.state,
            .avatar_id_by_name = avatar_id_by_name.move(),
            .avatar_name_by_id = avatar_name_by_id.move(),
            .weapon_id_by_name = weapon_id_by_name.move(),
            .weapon_name_by_id = weapon_name_by_id.move(),
            .equipment_name_by_id_rarity_s = equipment_name_by_id_rarity_s.move(),
            .equipment_id_by_name_rarity_s = equipment_id_by_name_rarity_s.move(),
        };
    }

    pub fn deinit(name_map: *NameMap, gpa: Allocator) void {
        name_map.avatar_id_by_name.deinit(gpa);
        name_map.avatar_name_by_id.deinit(gpa);
        name_map.weapon_id_by_name.deinit(gpa);
        name_map.weapon_name_by_id.deinit(gpa);
        name_map.equipment_name_by_id_rarity_s.deinit(gpa);
        name_map.equipment_id_by_name_rarity_s.deinit(gpa);
        name_map.string_arena.promote(gpa).deinit();
    }

    pub fn getEquipmentIdByNameForRarity(
        name_map: *const NameMap,
        name: []const u8,
        rarity: Equipment.Id.Rarity,
    ) ?Player.Equipment.Id {
        const id_rarity_s = name_map.equipment_id_by_name_rarity_s.get(name) orelse return null;
        const slot = id_rarity_s % 10;
        const id_int = ((id_rarity_s / 100) * 100) +
            (@backingInt(rarity) * 10) +
            slot;

        return Player.Equipment.Id.fromInt(id_int);
    }

    pub fn getEquipmentNameAndRarityById(
        name_map: *const NameMap,
        id: Player.Equipment.Id,
    ) Equipment.Id {
        const id_int = @backingInt(id);
        const slot = id_int % 10;
        const id_rarity_s = ((id_int / 100) * 100) +
            (@backingInt(Equipment.Id.Rarity.s) * 10) +
            slot;

        const name = name_map.equipment_name_by_id_rarity_s.get(id_rarity_s).?;
        return .{ .name = name, .rarity = @fromBackingInt((id_int / 10) % 10) };
    }
};

pub const Avatar = struct {
    name: []const u8,
    level: u32,
    rank: u32,
    favorite: bool,
    unlocked_mindscape: u32,
    mindscape_tab_state: [Player.Avatar.Mindscape.unlocked_max]bool,
    show_weapon_status: ShowWeaponStatus,
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

    pub const ShowWeaponStatus = enum {
        locked,
        unlocked_disabled,
        unlocked_enabled,
    };
};

pub const Weapon = struct {
    name: []const u8,
    refine: u32,

    fn init(data: Player.Weapon, name_map: *const NameMap) Weapon {
        return .{
            .name = name_map.weapon_name_by_id.get(data.bits.id).?,
            .refine = @backingInt(data.bits.refine),
        };
    }

    fn pack(
        weapon: Weapon,
        name_map: *const NameMap,
        diag: *PackDiagnostics,
    ) PackError!Player.Weapon {
        return .{
            .uid_maybe = .none,
            .bits = .{
                .id = name_map.weapon_id_by_name.get(weapon.name) orelse return diag.fail(
                    .name_invalid,
                    .{ .kind = "weapon", .name = weapon.name },
                ),
                .refine = Player.Weapon.Refine.fromInt(weapon.refine) orelse return diag.fail(
                    .weapon_refine_invalid,
                    .{ .name = weapon.name, .encountered = weapon.refine },
                ),
            },
        };
    }
};

pub const Equipment = struct {
    id: Id,
    main_property: MainProperty,
    sub_properties: SubProperties,

    pub const Id = struct {
        name: []const u8,
        rarity: Rarity,

        pub const Rarity = enum(u32) {
            s = 4,
            a = 3,
            b = 2,
        };
    };

    pub const SubProperties = struct {
        @"1": ?SubProperty,
        @"2": ?SubProperty,
        @"3": ?SubProperty,
        @"4": ?SubProperty,
    };

    pub const MainProperty = struct {
        key: []const u8,

        fn init(data: Player.Equipment.Property) MainProperty {
            const key: Key = @fromBackingInt(@backingInt(data.key));

            return .{ .key = Key.names.get(key) };
        }

        fn pack(
            main_property: MainProperty,
            diag: *PackDiagnostics,
        ) PackError!Player.Equipment.Property {
            const key = Key.by_name.get(main_property.key) orelse return diag.fail(
                .name_invalid,
                .{ .kind = "main property key", .name = main_property.key },
            );

            return .{
                .key = @fromBackingInt(@backingInt(key)),
                .base = base_by_key.get(key) orelse return diag.fail(
                    .name_invalid,
                    .{ .kind = "main property key", .name = main_property.key },
                ),
                .add = 1,
            };
        }

        const base_by_key: std.EnumMap(Key, u16) = .init(.{
            .HpMax = 550,
            .HpMax_Ratio = 750,
            .Atk = 79,
            .Atk_Ratio = 750,
            .Def = 46,
            .Def_Ratio = 1200,
            .PenRatio = 600,
            .ElementAbnormalPower = 750,
            .ElementMystery = 23,
            .CritDmg = 1200,
            .Crit = 600,
            .SpRecover = 1500,
            .BreakStun = 450,
            .AddedDamageRatioElec = 750,
            .AddedDamageRatioEther = 750,
            .AddedDamageRatioFire = 750,
            .AddedDamageRatioIce = 750,
            .AddedDamageRatioPhysics = 750,
            .AddedDamageRatioWind = 750,
        });
    };

    pub const SubProperty = struct {
        key: []const u8,
        @"+": u16,

        fn init(data: Player.Equipment.Property) SubProperty {
            const key: Key = @fromBackingInt(@backingInt(data.key));

            return .{
                .key = Key.names.get(key),
                .@"+" = data.add - 1,
            };
        }

        fn pack(
            sub_property: SubProperty,
            diag: *PackDiagnostics,
        ) PackError!Player.Equipment.Property {
            const key = Key.by_name.get(sub_property.key) orelse return diag.fail(
                .name_invalid,
                .{ .kind = "sub property key", .name = sub_property.key },
            );

            return .{
                .key = @fromBackingInt(@backingInt(key)),
                .base = base_by_key.get(key) orelse return diag.fail(
                    .name_invalid,
                    .{ .kind = "sub property key", .name = sub_property.key },
                ),
                .add = sub_property.@"+" + 1,
            };
        }

        const base_by_key: std.EnumMap(Key, u16) = .init(.{
            .HpMax = 112,
            .HpMax_Ratio = 300,
            .Atk = 19,
            .Atk_Ratio = 300,
            .Def = 15,
            .Def_Ratio = 480,
            .PenDelta = 9,
            .ElementMystery = 9,
            .CritDmg = 480,
            .Crit = 240,
        });
    };

    pub const Key = enum(u16) {
        HpMax = 11103,
        HpMax_Ratio = 11102,
        Atk = 12103,
        Atk_Ratio = 12102,
        Def = 13103,
        Def_Ratio = 13102,
        PenDelta = 23203,
        PenRatio = 23103,
        ElementAbnormalPower = 31402,
        ElementMystery = 31203,
        CritDmg = 21103,
        Crit = 20103,
        SpRecover = 30502,
        BreakStun = 12202,
        AddedDamageRatioElec = 31803,
        AddedDamageRatioEther = 31903,
        AddedDamageRatioFire = 31603,
        AddedDamageRatioIce = 31703,
        AddedDamageRatioPhysics = 31503,
        AddedDamageRatioWind = 32303,

        pub const by_name: std.StaticStringMap(Key) = .initComptime(&.{
            .{ "HP", .HpMax },
            .{ "Percent HP", .HpMax_Ratio },
            .{ "ATK", .Atk },
            .{ "Percent ATK", .Atk_Ratio },
            .{ "DEF", .Def },
            .{ "Percent DEF", .Def_Ratio },
            .{ "PEN", .PenDelta },
            .{ "PEN Ratio", .PenRatio },
            .{ "Anomaly Mastery", .ElementAbnormalPower },
            .{ "Anomaly Proficiency", .ElementMystery },
            .{ "CRIT DMG", .CritDmg },
            .{ "CRIT Rate", .Crit },
            .{ "Energy Regen", .SpRecover },
            .{ "Impact", .BreakStun },
            .{ "Electric DMG Bonus", .AddedDamageRatioElec },
            .{ "Ether DMG Bonus", .AddedDamageRatioEther },
            .{ "Fire DMG Bonus", .AddedDamageRatioFire },
            .{ "Ice DMG Bonus", .AddedDamageRatioIce },
            .{ "Physical DMG Bonus", .AddedDamageRatioPhysics },
            .{ "Wind DMG Bonus", .AddedDamageRatioWind },
        });

        pub const names: std.EnumArray(Key, []const u8) = .init(.{
            .HpMax = "HP",
            .HpMax_Ratio = "Percent HP",
            .Atk = "ATK",
            .Atk_Ratio = "Percent ATK",
            .Def = "DEF",
            .Def_Ratio = "Percent DEF",
            .PenDelta = "PEN",
            .PenRatio = "PEN Ratio",
            .ElementAbnormalPower = "Anomaly Mastery",
            .ElementMystery = "Anomaly Proficiency",
            .CritDmg = "CRIT DMG",
            .Crit = "CRIT Rate",
            .SpRecover = "Energy Regen",
            .BreakStun = "Impact",
            .AddedDamageRatioElec = "Electric DMG Bonus",
            .AddedDamageRatioEther = "Ether DMG Bonus",
            .AddedDamageRatioFire = "Fire DMG Bonus",
            .AddedDamageRatioIce = "Ice DMG Bonus",
            .AddedDamageRatioPhysics = "Physical DMG Bonus",
            .AddedDamageRatioWind = "Wind DMG Bonus",
        });
    };

    fn init(data: Player.Equipment, name_map: *const NameMap) Equipment {
        return .{
            .id = name_map.getEquipmentNameAndRarityById(data.bits.id),
            .main_property = .init(data.bits.main_property),
            .sub_properties = .{
                .@"1" = if (data.bits.sub_properties[0].unwrap()) |p| .init(p) else null,
                .@"2" = if (data.bits.sub_properties[1].unwrap()) |p| .init(p) else null,
                .@"3" = if (data.bits.sub_properties[2].unwrap()) |p| .init(p) else null,
                .@"4" = if (data.bits.sub_properties[3].unwrap()) |p| .init(p) else null,
            },
        };
    }

    fn pack(
        equipment: Equipment,
        name_map: *const NameMap,
        diag: *PackDiagnostics,
    ) PackError!Player.Equipment {
        return .{
            .uid_maybe = .none,
            .bits = .{
                .id = name_map.getEquipmentIdByNameForRarity(
                    equipment.id.name,
                    equipment.id.rarity,
                ) orelse return diag.fail(
                    .equipment_invalid,
                    .{ .name = equipment.id.name, .rarity = equipment.id.rarity },
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
            }, name_map);
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
                }, name_map);
            } else {
                @field(equipment, slot_name) = null;
            }
        }

        avatar_zon.* = .{
            .name = name_map.avatar_name_by_id.get(id).?,
            .level = bits.level_up.getLevel(),
            .rank = bits.level_up.getRank(),
            .favorite = bits.flags.favorite,
            .unlocked_mindscape = bits.mindscape.unlocked,
            .mindscape_tab_state = bits.mindscape.tab.toSwitches(),
            .show_weapon_status = switch (bits.show_weapon_status) {
                .locked => .locked,
                .unlocked_disabled => .unlocked_disabled,
                .unlocked_enabled => .unlocked_enabled,
            },
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
        }, name_map));
    }

    var equipment: std.ArrayList(Equipment) = try .initCapacity(arena, player.equipment.count);
    for (player.equipment.uids(), player.equipment.bits()) |equipment_uid, bits| {
        if (player.avatars.getByEquipmentUid(equipment_uid) != null)
            continue;

        equipment.appendAssumeCapacity(.init(.{
            .uid_maybe = .wrap(equipment_uid),
            .bits = bits,
        }, name_map));
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
    name_invalid: struct {
        kind: []const u8,
        name: []const u8,
    },
    equipment_invalid: struct {
        rarity: Equipment.Id.Rarity,
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
    avatar_mindscape_invalid: struct {
        avatar_name: []const u8,
        unlocked: u32,
        tab_state: [Player.Avatar.Mindscape.unlocked_max]bool,
    },
    weapon_refine_invalid: struct {
        name: []const u8,
        encountered: u32,
    },

    pub fn format(diag: *const PackDiagnostics, writer: *Io.Writer) Io.Writer.Error!void {
        switch (diag.*) {
            .limit_exceeded => |details| return writer.print(
                "too many {s} encountered, the limit is {d}",
                .{ details.name, details.limit },
            ),
            .name_invalid => |details| return writer.print(
                "invalid {s} name: {q}",
                .{ details.kind, details.name },
            ),
            .equipment_invalid => |details| return writer.print(
                "invalid equipment name {q} and rarity {t}",
                .{ details.name, details.rarity },
            ),
            .avatar_duplicated => |details| return writer.print(
                "duplicated avatar {q}",
                .{details.avatar_name},
            ),
            .avatar_level_up_invalid => |details| return writer.print(
                "avatar {q} has an invalid rank and level combination ({d}, {d})",
                .{ details.avatar_name, details.rank, details.level },
            ),
            .avatar_mindscape_invalid => |details| return writer.print(
                "avatar {q} has an invalid mindscape unlock and tab combination ({d}, {any})",
                .{ details.avatar_name, details.unlocked, details.tab_state },
            ),
            .weapon_refine_invalid => |details| return writer.print(
                "weapon {q} has an invalid refine value ({d}, expected {d}-{d})",
                .{
                    details.name,             details.encountered,
                    Player.Weapon.Refine.min, Player.Weapon.Refine.max,
                },
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
            const weapon = try weapon_zon.pack(name_map, diag);
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
                const equipment = try equipment_zon.pack(name_map, diag);
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
                .mindscape = Player.Avatar.Mindscape.fromUnlockedAndSwitches(
                    avatar_zon.unlocked_mindscape,
                    avatar_zon.mindscape_tab_state,
                ) orelse return diag.fail(
                    .avatar_mindscape_invalid,
                    .{
                        .avatar_name = avatar_zon.name,
                        .unlocked = avatar_zon.unlocked_mindscape,
                        .tab_state = avatar_zon.mindscape_tab_state,
                    },
                ),
                .show_weapon_status = switch (avatar_zon.show_weapon_status) {
                    .locked => .locked,
                    .unlocked_disabled => .unlocked_disabled,
                    .unlocked_enabled => .unlocked_enabled,
                },
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
        const weapon = try weapon_zon.pack(name_map, diag);
        _ = player.weapons.add(weapon) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "weapons",
                .limit = Player.Weapon.count_max,
            }),
        };
    }

    for (zon.equipment_undressed) |equipment_zon| {
        const equipment = try equipment_zon.pack(name_map, diag);
        _ = player.equipment.add(equipment) catch |err| switch (err) {
            error.NoSpaceLeft => return diag.fail(.limit_exceeded, .{
                .name = "equipment",
                .limit = Player.Equipment.count_max,
            }),
        };
    }

    return player;
}
