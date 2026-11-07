storage: *Storage,
needs_save: bool,
sync: Sync,

const Player = @This();
const std = @import("std");

pub const Zon = @import("Player/Zon.zig");
pub const Storage = @import("Player/Storage.zig");

const yuzuha = @import("yuzuha.zig");
const gen = yuzuha.protobuf.gen;
const pack = yuzuha.protobuf.pack;

pub const Sync = struct {
    populated: bool,
    avatar_list: pack.AvatarInfoList,
    control_guise_avatar_changed: bool,

    pub const init: Sync = .{
        .populated = false,
        .avatar_list = .empty,
        .control_guise_avatar_changed = false,
    };
};

pub const Avatar = struct {
    id: u32,
    level: u32,
    rank: u32,
    unlocked_talent_num: u32,
    mindscape_tab: MindscapeTab,
    favorite: bool,
    weapon_show: WeaponShow,
    weapon_uid_maybe: ?u32,
    dressed_equipment: std.EnumMap(Equipment.Type, u32),

    pub const Iterator = struct {
        index: u32,
        player: *const Player,

        pub fn next(it: *Iterator) ?Avatar {
            if (it.player.storage.avatars.count == it.index) return null;
            defer it.index += 1;

            return it.player.avatarAtIndex(it.index);
        }
    };

    pub const WeaponShow = enum {
        locked,
        unlocked_show,
        unlocked_hidden,
    };

    pub const MindscapeTab = struct {
        switches: [switch_count]bool,

        const switch_count = 6;

        pub fn fromSlice(slice: []const bool) ?MindscapeTab {
            if (slice.len != switch_count) return null;

            const switches = slice[0..switch_count].*;
            for (switches[0..3], switches[3..6]) |a, b|
                if (a and b) return null;

            return .{ .switches = switches };
        }

        pub fn requiredUnlock(tab: *const MindscapeTab) u32 {
            var required_unlock: u32 = 6;
            while (required_unlock > 0 and !tab.switches[required_unlock - 1]) {
                required_unlock -= 1;
            }

            return required_unlock;
        }
    };
};

pub const Weapon = struct {
    id: u32,
    refine: u32,

    pub const KeyValue = struct {
        uid: u32,
        weapon: Weapon,

        pub const Iterator = struct {
            index: u32,
            player: *const Player,

            pub fn next(it: *Iterator) ?Weapon.KeyValue {
                if (it.player.storage.weapons.count == it.index) return null;
                defer it.index += 1;

                return it.player.weaponAtIndex(it.index);
            }
        };
    };
};

pub const Equipment = struct {
    id: u32,
    main_property: Property,
    sub_properties: [sub_property_count]?Property,

    pub const sub_property_count = 4;

    pub const Property = struct {
        key: u16,
        base: u16,
        add: u16,

        fn fromStorage(storage: *const Storage.Equipment.Property) Property {
            return .{
                .key = @backingInt(storage.key),
                .base = storage.base,
                .add = storage.add,
            };
        }

        fn fromStorageOptional(optional: *const Storage.Equipment.Property.Optional) ?Property {
            return if (optional.unwrap()) |storage| .fromStorage(&storage) else null;
        }
    };

    pub const Type = enum(u8) {
        @"1" = 1,
        @"2" = 2,
        @"3" = 3,
        @"4" = 4,
        @"5" = 5,
        @"6" = 6,
    };

    pub const KeyValue = struct {
        uid: u32,
        equipment: Equipment,

        pub const Iterator = struct {
            index: u32,
            player: *const Player,

            pub fn next(it: *Iterator) ?Equipment.KeyValue {
                if (it.player.storage.equipment.count == it.index) return null;
                defer it.index += 1;

                return it.player.equipmentAtIndex(it.index);
            }
        };
    };
};

pub const ControlGuiseAvatar = enum(u32) {
    wise = 2011,
    belle = 2021,
    _,

    pub fn requiresUnlock(guise: ControlGuiseAvatar) bool {
        return switch (guise) {
            .wise, .belle => false,
            _ => true,
        };
    }
};

fn avatarAtIndex(player: *const Player, index: u32) Avatar {
    const storage_avatar = player.storage.avatars.getPtr(index);

    return .{
        .id = @backingInt(storage_avatar.id.*),
        .level = storage_avatar.bits.level_up.getLevel(),
        .rank = storage_avatar.bits.level_up.getRank(),
        .unlocked_talent_num = storage_avatar.bits.mindscape.unlocked,
        .mindscape_tab = .{ .switches = storage_avatar.bits.mindscape.tab.toSwitches() },
        .favorite = storage_avatar.bits.flags.favorite,
        .weapon_show = switch (storage_avatar.bits.show_weapon_status) {
            .locked => .locked,
            .unlocked_disabled => .unlocked_show,
            .unlocked_enabled => .unlocked_hidden,
        },
        .weapon_uid_maybe = if (storage_avatar.weapon_uid_maybe.unwrap()) |uid|
            @backingInt(uid)
        else
            null,
        .dressed_equipment = .init(.{
            .@"1" = storage_avatar.dressed_equipment[0].unwrapInt(),
            .@"2" = storage_avatar.dressed_equipment[1].unwrapInt(),
            .@"3" = storage_avatar.dressed_equipment[2].unwrapInt(),
            .@"4" = storage_avatar.dressed_equipment[3].unwrapInt(),
            .@"5" = storage_avatar.dressed_equipment[4].unwrapInt(),
            .@"6" = storage_avatar.dressed_equipment[5].unwrapInt(),
        }),
    };
}

fn weaponAtIndex(player: *const Player, index: u32) Weapon.KeyValue {
    const storage_kv = player.storage.weapons.getPtr(index);

    return .{
        .uid = @backingInt(storage_kv.uid.*),
        .weapon = .{
            .id = @backingInt(storage_kv.weapon.id),
            .refine = @backingInt(storage_kv.weapon.refine),
        },
    };
}

fn equipmentAtIndex(player: *const Player, index: u32) Equipment.KeyValue {
    const storage_kv = player.storage.equipment.getPtr(index);

    var sub_properties: [4]?Equipment.Property = undefined;
    for (&sub_properties, &storage_kv.equipment.sub_properties) |*sp, *sp_storage|
        sp.* = .fromStorageOptional(sp_storage);

    return .{
        .uid = @backingInt(storage_kv.uid.*),
        .equipment = .{
            .id = @backingInt(storage_kv.equipment.id),
            .main_property = .fromStorage(&storage_kv.equipment.main_property),
            .sub_properties = sub_properties,
        },
    };
}

pub fn avatars(player: *const Player) Avatar.Iterator {
    return .{ .player = player, .index = 0 };
}

pub fn weapons(player: *const Player) Weapon.KeyValue.Iterator {
    return .{ .player = player, .index = 0 };
}

pub fn equipment(player: *const Player) Equipment.KeyValue.Iterator {
    return .{ .player = player, .index = 0 };
}

pub fn hasAvatarWithId(player: *const Player, id_int: u32) bool {
    const id = Storage.Avatar.Id.fromInt(id_int) orelse return false;
    return player.storage.getAvatarIndexById(id) != null;
}

pub fn getAvatarById(player: *const Player, id_int: u32) ?Avatar {
    const id = Storage.Avatar.Id.fromInt(id_int) orelse return null;
    const index = player.storage.getAvatarIndexById(id) orelse return null;
    return player.avatarAtIndex(index);
}

pub fn getAvatarWithWeaponUid(player: *const Player, uid_int: u32) ?Avatar {
    const uid: Storage.Weapon.Uid = .fromInt(uid_int);
    const index = player.storage.getAvatarIndexByWeaponUid(uid) orelse return null;
    return player.avatarAtIndex(index);
}

pub const AvatarWithEquipment = struct {
    equipment_type: Equipment.Type,
    avatar: Avatar,
};

pub fn getAvatarWithEquipmentUid(player: *const Player, uid_int: u32) ?AvatarWithEquipment {
    const uid: Storage.Equipment.Uid = .fromInt(uid_int);
    const result = player.storage.getAvatarIndexByEquipmentUid(uid) orelse return null;

    return .{
        .equipment_type = @fromBackingInt(@intCast(result.equipment_slot_index + 1)),
        .avatar = player.avatarAtIndex(result.avatar_index),
    };
}

pub fn updateAvatar(player: *Player, avatar: Avatar) void {
    const avatar_index = player.storage.getAvatarIndexById(@fromBackingInt(avatar.id)).?;
    player.updateAvatarAtIndex(avatar_index, avatar);
    player.appendAvatarToSync(avatar);
}

pub fn hasWeaponWithUid(player: *Player, uid_int: u32) bool {
    const uid: Storage.Weapon.Uid = @fromBackingInt(uid_int);
    return player.storage.getWeaponIndexByUid(uid) != null;
}

pub fn hasEquipmentWithUid(player: *Player, uid_int: u32) bool {
    const uid: Storage.Equipment.Uid = @fromBackingInt(uid_int);
    return player.storage.getEquipmentIndexByUid(uid) != null;
}

fn updateAvatarAtIndex(player: *Player, avatar_index: u32, avatar: Avatar) void {
    player.needs_save = true;

    const storage_avatar = player.storage.avatars.getPtr(avatar_index);
    storage_avatar.bits.* = .{
        .level_up = Storage.Avatar.LevelUp.fromRankAndLevel(avatar.rank, avatar.level).?,
        .flags = .{ .favorite = avatar.favorite },
        .mindscape = .{
            .unlocked = @intCast(avatar.unlocked_talent_num),
            .tab = Storage.Avatar.Mindscape.Tab.fromSwitches(avatar.mindscape_tab.switches).?,
        },
        .show_weapon_status = switch (avatar.weapon_show) {
            .locked => .locked,
            .unlocked_show => .unlocked_enabled,
            .unlocked_hidden => .unlocked_disabled,
        },
    };

    storage_avatar.weapon_uid_maybe.* =
        if (avatar.weapon_uid_maybe) |uid| .wrap(.fromInt(uid)) else .none;

    const dressed_equipment_storage = storage_avatar.dressed_equipment;
    for (std.enums.values(Equipment.Type)) |equipment_type| {
        const equipment_index = @backingInt(equipment_type) - 1;

        if (avatar.dressed_equipment.get(equipment_type)) |uid| {
            dressed_equipment_storage[equipment_index] = .wrap(.fromInt(uid));
        } else {
            dressed_equipment_storage[equipment_index] = .none;
        }
    }
}

pub fn updateControlGuiseAvatar(player: *Player, guise: ControlGuiseAvatar) void {
    player.needs_save = true;
    player.storage.role.control_guise_avatar = @fromBackingInt(@backingInt(guise));

    player.sync.populated = true;
    player.sync.control_guise_avatar_changed = true;
}

fn appendAvatarToSync(player: *Player, avatar: Avatar) void {
    player.sync.populated = true;
    pack.avatarInfo(player.sync.avatar_list.addOneAssumeCapacity(), avatar);
}

pub fn buildPlayerSyncScNotify(player: *Player) ?gen.PlayerSyncScNotify {
    if (!player.sync.populated) return null;

    var notify: gen.PlayerSyncScNotify = .{ .misc = .{} };
    notify.avatar = .{ .avatar_list = player.sync.avatar_list.items(.avatar_info) };

    const self_basic_info_needs_sync = player.sync.control_guise_avatar_changed;
    if (self_basic_info_needs_sync) {
        notify.self_basic_info = pack.selfBasicInfo(&player.storage.role);
    }

    const accessory_data_needs_sync = player.sync.control_guise_avatar_changed;
    if (accessory_data_needs_sync) {
        notify.misc.?.player_accessory = .{
            .control_guise_avatar_id = @backingInt(player.storage.role.control_guise_avatar),
        };
    }

    return notify;
}
