const Player = @This();

const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;
const hasUniqueRepresentation = std.meta.hasUniqueRepresentation;

const eldreda = @import("eldreda.zig");
const templates = eldreda.templates;

pub const Zon = @import("Player/Zon.zig");

comptime {
    if (builtin.target.cpu.arch.endian() != .little)
        @compileError("non-little-endian machines are not supported");
}

avatars: Avatar.List,
weapons: Weapon.List,
equipment: Equipment.List,
main_city: MainCity,
role: Role,

pub const Header = extern struct {
    pub const current_version: u32 = 9;

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

    pub const List = struct {
        count: u32,
        bits_buffer: [count_max]Bits,
        ids_buffer: [count_max]Id,
        weapon_uids_buffer: [count_max]Weapon.Uid.Optional,
        dressed_equipment_buffer: [count_max][equipment_count]Equipment.Uid.Optional,

        pub const empty: List = .{
            .count = 0,
            .bits_buffer = undefined,
            .ids_buffer = undefined,
            .weapon_uids_buffer = undefined,
            .dressed_equipment_buffer = undefined,
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

        pub fn dressedEquipment(list: *List) [][equipment_count]Equipment.Uid.Optional {
            return list.dressed_equipment_buffer[0..list.count];
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

        pub fn getIndexByEquipmentUid(list: *List, equipment_uid: Equipment.Uid) ?struct {
            avatar_index: u32,
            equipment_slot_index: u32,
        } {
            if (mem.findScalar(
                Equipment.Uid.Optional,
                @ptrCast(list.dressedEquipment()),
                .wrap(equipment_uid),
            )) |equipment_index_usize| {
                const avatar_index_usize = @divFloor(equipment_index_usize, equipment_count);
                const equipment_slot_index_usize = equipment_index_usize % equipment_count;

                return .{
                    .avatar_index = @intCast(avatar_index_usize),
                    .equipment_slot_index = @intCast(equipment_slot_index_usize),
                };
            }

            return null;
        }

        pub fn at(list: *List, index: u32) Avatar {
            return .{
                .id = list.ids()[index],
                .bits = list.bits()[index],
                .weapon_uid_maybe = list.weaponUids()[index],
                .dressed_equipment = list.dressedEquipment()[index],
            };
        }

        pub fn get(list: *List, id_int: u32) ?struct { u32, Avatar } {
            const id = Id.fromInt(id_int) orelse return null;
            const index = list.getIndexById(id) orelse return null;

            return .{ index, list.at(index) };
        }

        pub fn getByWeaponUid(list: *List, weapon_uid: Weapon.Uid) ?struct { u32, Avatar } {
            const index = list.getIndexByWeaponUid(weapon_uid) orelse return null;
            return .{ index, list.at(index) };
        }

        pub fn getByEquipmentUid(list: *List, equipment_uid: Equipment.Uid) ?struct {
            equipment_slot_index: u32,
            avatar_index: u32,
            avatar: Avatar,
        } {
            const result = list.getIndexByEquipmentUid(equipment_uid) orelse return null;

            return .{
                .equipment_slot_index = result.equipment_slot_index,
                .avatar_index = result.avatar_index,
                .avatar = list.at(result.avatar_index),
            };
        }

        pub fn replaceAt(list: *List, index: u32, avatar: Avatar) void {
            assert(list.count > index);
            assert(list.ids()[index] == avatar.id); // avatar id is immutable

            list.bits()[index] = avatar.bits;
            list.weaponUids()[index] = avatar.weapon_uid_maybe;
            list.dressedEquipment()[index] = avatar.dressed_equipment;
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
            list.weapon_uids_buffer[index] = avatar.weapon_uid_maybe;
            list.dressed_equipment_buffer[index] = avatar.dressed_equipment;

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

pub const Weapon = struct {
    uid_maybe: Uid.Optional,
    bits: Bits,

    pub const count_max: usize = 2_000;

    pub const Bits = packed struct(u64) {
        id: Id,
        refine: Refine,
        _: u24 = 0,

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
    avatar: Player.Role.Avatar,
    control_avatar: Player.Role.Avatar,
    control_guise_avatar: Player.Role.Guise,

    comptime {
        assert(hasUniqueRepresentation(@This()));
    }

    pub const Avatar = enum(u32) {
        wise = 2011,
        belle = 2021,

        pub fn fromInt(id_int: u32) ?Player.Role.Avatar {
            return std.enums.fromInt(Player.Role.Avatar, id_int);
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
                    if (Player.Avatar.Id.fromInt(id_int) == null)
                        return null;

                    return custom;
                },
            };
        }

        pub fn toAvatarId(guise: Guise) ?Player.Avatar.Id {
            return switch (guise) {
                .wise, .belle => null,
                _ => |avatar| Player.Avatar.Id.fromInt(@backingInt(avatar)).?,
            };
        }
    };
};

pub fn initDefaults(player: *Player) void {
    player.* = .{
        .avatars = .empty,
        .weapons = .empty,
        .equipment = .empty,
        .main_city = .{
            .section = MainCity.Section.fromInt(2).?,
        },
        .role = .{
            .avatar = .wise,
            .control_avatar = .wise,
            .control_guise_avatar = Role.Guise.fromInt(1601).?,
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

        const result = player.avatars.getOrAdd(.{
            .id = id,
            .bits = avatar_bits_maxed_out,
            .weapon_uid_maybe = .none,
            .dressed_equipment = @splat(.none),
        }) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };

        assert(!result.found_existing);
    }

    for (templates.Weapon.table.items(.id)) |id_int| {
        const id = Weapon.Id.fromInt(id_int) orelse continue;

        _ = player.weapons.add(.{
            .uid_maybe = .none,
            .bits = .{ .id = id, .refine = .max },
        }) catch |err| switch (err) {
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
    player: *Player,
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
            .uid_maybe = .none,
            .bits = .{
                .id = Equipment.Id.fromInt(equip_id).?,
                .main_property = main_property,
                .sub_properties = @splat(.none),
            },
        };

        var rand_add_budget: u8 = 5;
        var rand_add: [equipment.bits.sub_properties.len]u16 = @splat(0);
        for (rand_add[0 .. rand_add.len - 1], property_add_rand) |*add, rand| {
            if (rand_add_budget > 0) {
                add.* = rand % rand_add_budget;
                rand_add_budget -|= rand % rand_add_budget;
            }
        }
        rand_add[rand_add.len - 1] = rand_add_budget;

        for (
            &equipment.bits.sub_properties,
            select_indices_rand,
            rand_add,
        ) |*sub_property, to_select_rand, add| {
            const to_select = to_select_rand % property_selection.items.len;
            defer _ = property_selection.swapRemove(to_select);

            sub_property.* = .wrap(property_selection.items[to_select]);
            sub_property.add += add;
        }

        _ = try player.equipment.add(equipment);
    }
}

pub fn saveToFile(player: *Player, io: Io, dir: Io.Dir, sub_path: []const u8) !void {
    var vecs_buffer: [11][]const u8 = undefined;
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
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.dressedEquipment()));
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.uids()));
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.uids()));
    vecs.appendAssumeCapacity(@ptrCast(&player.main_city));
    vecs.appendAssumeCapacity(@ptrCast(&player.role));

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

    var vecs_buffer: [10][]u8 = undefined;
    var vecs: std.ArrayList([]u8) = .initBuffer(&vecs_buffer);

    player.avatars.count = header.avatar_count;
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.ids()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.weaponUids()));
    vecs.appendAssumeCapacity(@ptrCast(player.avatars.dressedEquipment()));

    player.weapons.count = header.weapon_count;
    player.weapons.uid_counter = header.weapon_uid_counter;
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.weapons.uids()));

    player.equipment.count = header.equipment_count;
    player.equipment.uid_counter = header.equipment_uid_counter;
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.bits()));
    vecs.appendAssumeCapacity(@ptrCast(player.equipment.uids()));

    vecs.appendAssumeCapacity(@ptrCast(&player.main_city));

    vecs.appendAssumeCapacity(@ptrCast(&player.role));

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
