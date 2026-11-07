//! Player representation for the long-term on-disk storage.

avatars: BoundedMultiArray(Avatar, Avatar.count_max),
weapons: BoundedMultiArray(Weapon.KeyValue, Weapon.count_max),
weapon_uid_counter: u32,
equipment: BoundedMultiArray(Equipment.KeyValue, Equipment.count_max),
equipment_uid_counter: u32,
// TODO: these 3 can be merged into a single struct so that they use a single buffer for save/load.
main_city: MainCity,
role: Role,
time: Time,

const Storage = @This();

const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;
const hasUniqueRepresentation = std.meta.hasUniqueRepresentation;

const yuzuha = @import("../yuzuha.zig");
const templates = yuzuha.templates;
const BoundedMultiArray = yuzuha.BoundedMultiArray;

comptime {
    if (builtin.target.cpu.arch.endian() != .little)
        @compileError("non-little-endian machines are not supported");
}

pub const Header = extern struct {
    file_version: u32,
    avatar_count: u32,
    weapon_count: u32,
    weapon_uid_counter: u32,
    equipment_count: u32,
    equipment_uid_counter: u32,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub const current_version: u32 = 10;
};

pub const Avatar = struct {
    id: Id,
    bits: Bits,
    weapon_uid_maybe: Weapon.Uid.Optional,
    dressed_equipment: [equipment_count]Equipment.Uid.Optional,

    pub const count_max = templates.AvatarBase.table.count;

    pub const equipment_count = 6;

    pub const Bits = packed struct(u32) {
        level_up: LevelUp,
        flags: Flags,
        mindscape: Mindscape,
        show_weapon_status: ShowWeapon.Status,
        _: u13 = 0,

        comptime {
            assert(hasUniqueRepresentation(@This()));
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

    pub const LevelUp = packed struct(u7) {
        pub const rank_min: u3 = 1;
        pub const rank_max: u3 = 6;

        rank: u3,
        up_times: u4,

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

    pub const Flags = packed struct(u1) {
        favorite: bool,
    };

    pub const Mindscape = packed struct(u9) {
        unlocked: u3,
        tab: Tab,

        pub const unlocked_max: u3 = 6;

        pub const Tab = packed struct(u6) {
            @"1": bool,
            @"2": bool,
            @"3": bool,
            @"4": bool,
            @"5": bool,
            @"6": bool,

            pub fn fromSwitches(switches: [unlocked_max]bool) ?Tab {
                for (switches[0..3], switches[3..6]) |a, b|
                    if (a and b) return null;

                var tab: Tab = undefined;
                inline for (
                    @typeInfo(Tab).@"struct".field_names,
                    switches,
                ) |switch_name, switch_value|
                    @field(tab, switch_name) = switch_value;

                return tab;
            }

            pub fn toSwitches(tab: Tab) [unlocked_max]bool {
                var switches: [unlocked_max]bool = undefined;

                inline for (
                    &switches,
                    @typeInfo(Tab).@"struct".field_names,
                ) |*switch_value, switch_name|
                    switch_value.* = @field(tab, switch_name);

                return switches;
            }

            pub fn highestSet(tab: Tab) u3 {
                const switch_names = @typeInfo(Tab).@"struct".field_names;
                comptime var i: u3 = 6;
                inline while (i > 0) : (i -= 1)
                    if (@field(tab, switch_names[i - 1])) return i;

                return 0;
            }
        };

        pub fn fromUnlockedAndSwitches(
            unlocked: u32,
            tab_switches: [unlocked_max]bool,
        ) ?Mindscape {
            if (unlocked > unlocked_max) return null;

            const tab = Tab.fromSwitches(tab_switches) orelse return null;
            if (tab.highestSet() > unlocked) return null;

            return .{ .unlocked = @intCast(unlocked), .tab = tab };
        }
    };

    pub const ShowWeapon = packed struct(u2) {
        unlock: bool,
        enable: bool,

        pub const Status = enum(u2) {
            locked = @backingInt(@as(
                ShowWeapon,
                .{ .unlock = false, .enable = false },
            )),
            unlocked_disabled = @backingInt(@as(
                ShowWeapon,
                .{ .unlock = true, .enable = false },
            )),
            unlocked_enabled = @backingInt(@as(
                ShowWeapon,
                .{ .unlock = true, .enable = true },
            )),

            pub fn fromBits(show_weapon: ShowWeapon) ?ShowWeapon.Status {
                return std.enums.fromInt(u2, @backingInt(show_weapon));
            }

            pub fn bits(status: ShowWeapon.Status) ShowWeapon {
                return @fromBackingInt(@backingInt(status));
            }
        };
    };
};

pub fn getOrAddAvatar(
    storage: *Storage,
    avatar: Avatar,
) error{NoSpaceLeft}!struct {
    found_existing: bool,
    index: u32,
} {
    if (storage.getAvatarIndexById(avatar.id)) |index|
        return .{ .found_existing = true, .index = index };

    try storage.avatars.append(avatar);
    const index = storage.avatars.count - 1;

    return .{ .found_existing = false, .index = index };
}

pub fn getAvatarIndexById(storage: *Storage, id: Avatar.Id) ?u32 {
    if (mem.findScalar(Avatar.Id, storage.avatars.items(.id), id)) |index_usize|
        return @intCast(index_usize);

    return null;
}

pub fn getAvatarIndexByWeaponUid(storage: *Storage, weapon_uid: Weapon.Uid) ?u32 {
    if (mem.findScalar(
        Weapon.Uid.Optional,
        storage.avatars.items(.weapon_uid_maybe),
        .wrap(weapon_uid),
    )) |index_usize|
        return @intCast(index_usize);

    return null;
}

pub fn getAvatarIndexByEquipmentUid(storage: *Storage, equipment_uid: Equipment.Uid) ?struct {
    avatar_index: u32,
    equipment_slot_index: u32,
} {
    if (mem.findScalar(
        Equipment.Uid.Optional,
        @ptrCast(storage.avatars.items(.dressed_equipment)),
        .wrap(equipment_uid),
    )) |equipment_index_usize| {
        const avatar_index_usize = @divFloor(equipment_index_usize, Avatar.equipment_count);
        const equipment_slot_index_usize = equipment_index_usize % Avatar.equipment_count;

        return .{
            .avatar_index = @intCast(avatar_index_usize),
            .equipment_slot_index = @intCast(equipment_slot_index_usize),
        };
    }

    return null;
}

pub const Weapon = packed struct(u64) {
    id: Id,
    refine: Refine,
    _: u24 = 0,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub const count_max: usize = 2_000;

    pub const KeyValue = struct {
        uid: Uid,
        weapon: Weapon,
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

        pub fn fromInt(uid_int: u32) Uid {
            assert(uid_int != 0);
            return @fromBackingInt(uid_int);
        }

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

    pub const Refine = enum(u8) {
        min = 1,
        max = 5,
        _,

        pub fn fromInt(refine_int: u32) ?Refine {
            if (refine_int > @backingInt(Refine.max)) return null;
            if (refine_int < @backingInt(Refine.min)) return null;

            return @fromBackingInt(@intCast(refine_int));
        }
    };
};

pub fn addWeapon(storage: *Storage, weapon: Weapon) error{NoSpaceLeft}!Weapon.Uid {
    storage.weapon_uid_counter += 1;
    const uid: Weapon.Uid = .fromInt(storage.weapon_uid_counter);

    storage.weapons.append(.{
        .uid = uid,
        .weapon = weapon,
    }) catch |err| switch (err) {
        error.NoSpaceLeft => |e| {
            storage.weapon_uid_counter -= 1;
            return e;
        },
    };
    return uid;
}

pub fn getWeaponIndexByUid(storage: *Storage, uid: Weapon.Uid) ?u32 {
    if (mem.findScalar(Weapon.Uid, storage.weapons.items(.uid), uid)) |index_usize|
        return @intCast(index_usize);

    return null;
}

pub const Equipment = extern struct {
    id: Id,
    main_property: Property,
    sub_properties: [Property.sub_count]Property.Optional,
    _: u16 = 0,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub const KeyValue = struct {
        uid: Uid,
        equipment: Equipment,
    };

    pub const count_max = 3_000;

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

        pub fn fromInt(uid_int: u32) Uid {
            assert(uid_int != 0);
            return @fromBackingInt(uid_int);
        }

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

            pub fn unwrapInt(uid_maybe: Optional) ?u32 {
                return switch (uid_maybe) {
                    .none => null,
                    else => |uid| @backingInt(uid),
                };
            }
        };
    };
};

pub fn getEquipmentIndexByUid(storage: *Storage, uid: Equipment.Uid) ?u32 {
    if (mem.findScalar(Equipment.Uid, storage.equipment.items(.uid), uid)) |index_usize|
        return @intCast(index_usize);

    return null;
}

pub fn addEquipment(storage: *Storage, equipment: Equipment) error{NoSpaceLeft}!Equipment.Uid {
    storage.equipment_uid_counter += 1;
    const uid: Equipment.Uid = .fromInt(storage.equipment_uid_counter);

    storage.equipment.append(.{
        .uid = uid,
        .equipment = equipment,
    }) catch |err| switch (err) {
        error.NoSpaceLeft => |e| {
            storage.weapon_uid_counter -= 1;
            return e;
        },
    };
    return uid;
}

pub const MainCity = extern struct {
    section: Section,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub const Section = enum(u32) {
        _,

        pub fn fromInt(section_int: u32) ?Section {
            if (templates.SectionConfig.table.getIndexByKey(section_int)) |index| {
                const display_name = templates.SectionConfig.table.items(.display_name)[index];
                if (display_name != .empty)
                    return @fromBackingInt(section_int);
            }

            return null;
        }
    };
};

pub const Role = extern struct {
    avatar: Storage.Role.Avatar,
    control_avatar: Storage.Role.Avatar,
    control_guise_avatar: Storage.Role.Guise,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub const Avatar = enum(u32) {
        wise = 2011,
        belle = 2021,

        pub fn fromInt(id_int: u32) ?Storage.Role.Avatar {
            return std.enums.fromInt(Storage.Role.Avatar, id_int);
        }
    };

    pub const Guise = enum(u32) {
        wise = 2011,
        belle = 2021,
        _,

        pub fn fromInt(id_int: u32) ?Guise {
            return switch (@as(Guise, @fromBackingInt(id_int))) {
                .wise, .belle => |main| main,
                _ => |custom| {
                    if (Storage.Avatar.Id.fromInt(id_int) == null)
                        return null;

                    return custom;
                },
            };
        }

        pub fn toAvatarId(guise: Guise) ?Storage.Avatar.Id {
            return switch (guise) {
                .wise, .belle => null,
                _ => |avatar| Storage.Avatar.Id.fromInt(@backingInt(avatar)).?,
            };
        }
    };
};

pub const Time = packed struct(u8) {
    day: Day,
    period: Period,
    _: u3 = 0,

    pub const Day = enum(u3) {
        sunday = 0,
        monday = 1,
        tuesday = 2,
        wednesday = 3,
        thursday = 4,
        friday = 5,
        saturday = 6,

        pub fn fromInt(day_unwrapped: u32) Day {
            return @fromBackingInt(@intCast(day_unwrapped % 7));
        }

        pub fn increment(day: Day) Day {
            return .fromInt(@backingInt(day) + 1);
        }
    };

    pub const Period = enum(u2) {
        morning = 0,
        afternoon = 1,
        evening = 2,
        night = 3,

        const variants_count: usize = 4;
        const minutes_per_hour: u16 = 60;

        pub const Change = struct {
            new_value: Period,
            day_advanced: bool,
        };

        pub fn increment(period: Period) Change {
            return switch (period) {
                .morning => .{ .new_value = .afternoon, .day_advanced = false },
                .afternoon => .{ .new_value = .evening, .day_advanced = false },
                .evening => .{ .new_value = .night, .day_advanced = false },
                .night => .{ .new_value = .morning, .day_advanced = true },
            };
        }

        pub fn fastForwardTo(from: Period, to: Period) Change {
            var day_advanced: bool = false;
            var new_value: Period = from;
            defer assert(new_value == to);

            var increments: u8 = 0;
            while (new_value != to) : (increments += 1) {
                assert(increments < variants_count);

                const incremented = new_value.increment();
                new_value = incremented.new_value;

                if (day_advanced) assert(!incremented.day_advanced); // day advanced 2 times?
                day_advanced = day_advanced or incremented.day_advanced;
            }

            return .{ .new_value = new_value, .day_advanced = day_advanced };
        }

        pub fn toMinutes(period: Period) u16 {
            const hour: u16 = switch (period) {
                .morning => 6,
                .afternoon => 12,
                .evening => 18,
                .night => 23,
            };

            return hour * minutes_per_hour;
        }
    };
};

pub fn initDefaults(storage: *Storage) void {
    storage.* = .{
        .avatars = .empty,
        .weapons = .empty,
        .weapon_uid_counter = 0,
        .equipment = .empty,
        .equipment_uid_counter = 0,
        .main_city = .{
            .section = MainCity.Section.fromInt(2).?,
        },
        .role = .{
            .avatar = .wise,
            .control_avatar = .wise,
            .control_guise_avatar = Role.Guise.fromInt(1411).?,
        },
        .time = .{
            .day = .friday,
            .period = .morning,
        },
    };

    const avatar_bits_maxed_out: Avatar.Bits = .{
        .level_up = comptime Avatar.LevelUp.fromRankAndLevel(6, 60).?,
        .flags = .{ .favorite = false },
        .mindscape = comptime Avatar.Mindscape.fromUnlockedAndSwitches(
            Avatar.Mindscape.unlocked_max,
            .{
                false, false, false,
                true,  true,  true,
            },
        ).?,
        .show_weapon_status = .locked,
    };

    for (templates.AvatarBase.table.items(.id)) |id_int| {
        const id = Avatar.Id.fromInt(id_int) orelse continue;

        // Workaround for Kafka locking the character menu,
        // to be removed once client-side bug is fixed.
        var avatar_bits = avatar_bits_maxed_out;
        avatar_bits.flags.favorite = id_int == 1411;

        const result = storage.getOrAddAvatar(.{
            .id = id,
            .bits = avatar_bits,
            .weapon_uid_maybe = .none,
            .dressed_equipment = @splat(.none),
        }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };

        assert(!result.found_existing);
    }

    for (templates.Weapon.table.items(.id)) |id_int| {
        const id = Weapon.Id.fromInt(id_int) orelse continue;

        _ = storage.addWeapon(.{ .id = id, .refine = .max }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
    }
}

const main_properties_per_slot: [6][]const Equipment.Property = .{
    &.{.{ .key = @fromBackingInt(11103), .base = 550, .add = 1 }},
    &.{.{ .key = @fromBackingInt(12103), .base = 79, .add = 1 }},
    &.{.{ .key = @fromBackingInt(13103), .base = 46, .add = 1 }},
    &.{
        .{ .key = @fromBackingInt(11102), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(12102), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(13102), .base = 1200, .add = 1 },
        .{ .key = @fromBackingInt(31203), .base = 23, .add = 1 },
        .{ .key = @fromBackingInt(21103), .base = 1200, .add = 1 },
        .{ .key = @fromBackingInt(20103), .base = 600, .add = 1 },
    },
    &.{
        .{ .key = @fromBackingInt(11102), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(12102), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(13102), .base = 1200, .add = 1 },
        .{ .key = @fromBackingInt(23103), .base = 600, .add = 1 },
        .{ .key = @fromBackingInt(31503), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(31603), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(31703), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(31803), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(31903), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(32303), .base = 750, .add = 1 },
    },
    &.{
        .{ .key = @fromBackingInt(11102), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(12102), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(13102), .base = 1200, .add = 1 },
        .{ .key = @fromBackingInt(31402), .base = 750, .add = 1 },
        .{ .key = @fromBackingInt(30502), .base = 1500, .add = 1 },
        .{ .key = @fromBackingInt(12202), .base = 450, .add = 1 },
    },
};

const rand_properties: [10]Equipment.Property = .{
    .{ .key = @fromBackingInt(11103), .base = 112, .add = 1 },
    .{ .key = @fromBackingInt(11102), .base = 300, .add = 1 },
    .{ .key = @fromBackingInt(12103), .base = 19, .add = 1 },
    .{ .key = @fromBackingInt(12102), .base = 300, .add = 1 },
    .{ .key = @fromBackingInt(13103), .base = 15, .add = 1 },
    .{ .key = @fromBackingInt(13102), .base = 480, .add = 1 },
    .{ .key = @fromBackingInt(23203), .base = 9, .add = 1 },
    .{ .key = @fromBackingInt(31203), .base = 9, .add = 1 },
    .{ .key = @fromBackingInt(21103), .base = 480, .add = 1 },
    .{ .key = @fromBackingInt(20103), .base = 240, .add = 1 },
};

/// TODO: move to a separate utility.
pub fn addRandomEquipment(
    storage: *Storage,
    rng: std.Random,
    comptime count: u32,
) error{NoSpaceLeft}!void {
    var slots_rand: [count]u8 = undefined;
    rng.bytes(&slots_rand);

    var suit_indices_rand: [count]u32 = undefined;
    rng.bytes(@ptrCast(&suit_indices_rand));

    var main_property_rands: [count]u8 = undefined;
    rng.bytes(&main_property_rands);

    var select_indices_rands: [count][4]u8 = undefined;
    rng.bytes(@ptrCast(&select_indices_rands));

    var property_add_rands: [count][3]u8 = undefined;
    rng.bytes(@ptrCast(&property_add_rands));

    for (
        &slots_rand,
        &suit_indices_rand,
        &main_property_rands,
        &select_indices_rands,
        &property_add_rands,
    ) |slot_rand, suit_index_rand, main_property_rand, select_indices_rand, property_add_rand| {
        const slot = (slot_rand % Avatar.equipment_count) + 1;
        const suit_index = suit_index_rand % templates.EquipmentSuit.table.count;
        const suit_id = templates.EquipmentSuit.table.items(.id)[suit_index];
        const equip_id = suit_id + 40 + slot;

        var rand_properties_buf = rand_properties;
        var property_selection: std.ArrayList(Equipment.Property) = .{
            .items = &rand_properties_buf,
            .capacity = rand_properties.len,
            .pointer_stability = .{},
        };

        const main_property_selection = main_properties_per_slot[slot - 1];
        const main_property = main_property_selection[main_property_rand % main_property_selection.len];

        for (property_selection.items, 0..) |rand_property, index| {
            if (rand_property.key == main_property.key) {
                _ = property_selection.swapRemove(index);
                break;
            }
        }

        var equipment: Equipment = .{
            .id = Equipment.Id.fromInt(equip_id).?,
            .main_property = main_property,
            .sub_properties = @splat(.none),
        };

        var rand_add_budget: u8 = 5;
        var rand_add: [equipment.sub_properties.len]u16 = @splat(0);
        for (rand_add[0 .. rand_add.len - 1], property_add_rand) |*add, rand| {
            if (rand_add_budget > 0) {
                add.* = rand % rand_add_budget;
                rand_add_budget -|= rand % rand_add_budget;
            }
        }
        rand_add[rand_add.len - 1] = rand_add_budget;

        for (
            &equipment.sub_properties,
            select_indices_rand,
            rand_add,
        ) |*sub_property, to_select_rand, add| {
            const to_select = to_select_rand % property_selection.items.len;
            defer _ = property_selection.swapRemove(to_select);

            sub_property.* = .wrap(property_selection.items[to_select]);
            sub_property.add += add;
        }

        _ = try storage.addEquipment(equipment);
    }
}

pub fn saveToFile(storage: *Storage, io: Io, dir: Io.Dir, sub_path: []const u8) !void {
    var vecs_buffer: [12][]const u8 = undefined;
    var vecs: std.ArrayList([]const u8) = .initBuffer(&vecs_buffer);

    const header: Header = .{
        .file_version = Header.current_version,
        .avatar_count = storage.avatars.count,
        .weapon_count = storage.weapons.count,
        .weapon_uid_counter = storage.weapon_uid_counter,
        .equipment_count = storage.equipment.count,
        .equipment_uid_counter = storage.equipment_uid_counter,
    };

    vecs.appendAssumeCapacity(@ptrCast(&header));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.bits)));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.id)));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.weapon_uid_maybe)));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.dressed_equipment)));
    vecs.appendAssumeCapacity(@ptrCast(storage.weapons.items(.weapon)));
    vecs.appendAssumeCapacity(@ptrCast(storage.weapons.items(.uid)));
    vecs.appendAssumeCapacity(@ptrCast(storage.equipment.items(.equipment)));
    vecs.appendAssumeCapacity(@ptrCast(storage.equipment.items(.uid)));
    vecs.appendAssumeCapacity(@ptrCast(&storage.main_city));
    vecs.appendAssumeCapacity(@ptrCast(&storage.role));
    vecs.appendAssumeCapacity(@ptrCast(&storage.time));

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
    storage: *Storage,
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

    var vecs_buffer: [11][]u8 = undefined;
    var vecs: std.ArrayList([]u8) = .initBuffer(&vecs_buffer);

    storage.avatars.count = header.avatar_count;
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.bits)));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.id)));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.weapon_uid_maybe)));
    vecs.appendAssumeCapacity(@ptrCast(storage.avatars.items(.dressed_equipment)));

    storage.weapons.count = header.weapon_count;
    storage.weapon_uid_counter = header.weapon_uid_counter;
    vecs.appendAssumeCapacity(@ptrCast(storage.weapons.items(.weapon)));
    vecs.appendAssumeCapacity(@ptrCast(storage.weapons.items(.uid)));

    storage.equipment.count = header.equipment_count;
    storage.equipment_uid_counter = header.equipment_uid_counter;
    vecs.appendAssumeCapacity(@ptrCast(storage.equipment.items(.equipment)));
    vecs.appendAssumeCapacity(@ptrCast(storage.equipment.items(.uid)));

    vecs.appendAssumeCapacity(@ptrCast(&storage.main_city));

    vecs.appendAssumeCapacity(@ptrCast(&storage.role));

    vecs.appendAssumeCapacity(@ptrCast(&storage.time));

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
