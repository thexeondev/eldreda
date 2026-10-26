//! This is a user-facing format and it's designed for convenience rather than efficiency.

const Zon = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;

avatars: []Avatar,
weapons_undressed: []Weapon,
equipment_undressed: []Equipment,

pub const Avatar = struct {
    id: u32,
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
};

pub const Equipment = struct {
    id: u32,
    main_property: Property,
    sub_properties: struct {
        @"1": ?Property,
        @"2": ?Property,
        @"3": ?Property,
        @"4": ?Property,
    },

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
};

pub fn init(arena: Allocator, player: *Player) Allocator.Error!Zon {
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
            .id = @backingInt(id),
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
