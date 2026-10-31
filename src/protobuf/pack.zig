const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const gen = eldreda.protobuf.gen;
const StaticMultiArrayList = eldreda.StaticMultiArrayList;

const Skill = enum(u8) {
    common_attack = 0,
    special_attack = 1,
    evade = 2,
    cooperate_skill = 3,
    unique_skill = 4,
    core_skill = 5,
    assist_skill = 6,
};

const skills: [@typeInfo(Skill).@"enum".field_names.len]gen.AvatarSkillLevel = skills: {
    const skill_types = std.enums.values(Skill);
    var array: [skill_types.len]gen.AvatarSkillLevel = undefined;

    for (&array, skill_types) |*skill_level, skill_type|
        skill_level.* = .{
            .skill_type = @backingInt(skill_type),
            .level = switch (skill_type) {
                .core_skill => 7,
                else => 12,
            },
        };

    break :skills array;
};

pub const AvatarInfoList = StaticMultiArrayList(struct {
    avatar_info: gen.AvatarInfo,
    dressed_equip_buffer: [Player.Avatar.equipment_count]gen.DressedEquip,
    mindscape_tab_state: [Player.Avatar.Mindscape.unlocked_max]bool,
});

pub fn avatarInfo(out: AvatarInfoList.Ptr, avatar: Player.Avatar) void {
    var dressed_equip: std.ArrayList(gen.DressedEquip) = .initBuffer(out.dressed_equip_buffer);

    for (avatar.dressed_equipment, 1..) |equipment_uid_maybe, slot_index| {
        const equipment_uid = equipment_uid_maybe.unwrap() orelse continue;

        dressed_equip.appendAssumeCapacity(.{
            .index = @intCast(slot_index),
            .equip_uid = @backingInt(equipment_uid),
        });
    }

    out.mindscape_tab_state.* = avatar.bits.mindscape.tab.toSwitches();

    out.avatar_info.* = .{
        .id = @backingInt(avatar.id),
        .level = avatar.bits.level_up.getLevel(),
        .rank = avatar.bits.level_up.getRank(),
        .is_favorite = avatar.bits.flags.favorite,
        .cur_weapon_uid = @backingInt(avatar.weapon_uid_maybe),
        .unlocked_talent_num = avatar.bits.mindscape.unlocked,
        .mindscape_tab_state = out.mindscape_tab_state,
        .skill_type_level = &skills,
        .passive_skill_level = 6,
        .dressed_equip_list = dressed_equip.items,
        .show_weapon_type = switch (avatar.bits.show_weapon_status) {
            .locked => .LOCKED,
            .unlocked_enabled => .SHOW,
            .unlocked_disabled => .HIDE,
        },
    };
}

pub fn weaponInfo(out: *gen.WeaponInfo, weapon: Player.Weapon) void {
    out.* = .{
        .uid = @backingInt(weapon.uid_maybe.unwrap().?),
        .id = @backingInt(weapon.bits.id),
        .level = 60,
        .star = 5,
        .refine_level = @backingInt(weapon.bits.refine),
    };
}

pub const EquipInfoList = StaticMultiArrayList(struct {
    equip_info: gen.EquipInfo,
    main_property: gen.EquipProperty,
    sub_properties_buffer: [Player.Equipment.Property.sub_count]gen.EquipProperty,
});

pub fn equipInfo(out: EquipInfoList.Ptr, equipment: Player.Equipment) void {
    out.main_property.* = .{
        .key = @backingInt(equipment.bits.main_property.key),
        .base_value = equipment.bits.main_property.base,
        .add_value = equipment.bits.main_property.add,
    };

    var sub_property_list: std.ArrayList(gen.EquipProperty) =
        .initBuffer(out.sub_properties_buffer);

    for (equipment.bits.sub_properties) |property_maybe| {
        const property = property_maybe.unwrap() orelse continue;
        sub_property_list.appendAssumeCapacity(.{
            .key = @backingInt(property.key),
            .base_value = property.base,
            .add_value = property.add,
        });
    }

    out.equip_info.* = .{
        .uid = @backingInt(equipment.uid_maybe.unwrap().?),
        .id = @backingInt(equipment.bits.id),
        .level = 15,
        .star = 5,
        .propertys = out.main_property[0..1],
        .sub_propertys = sub_property_list.items,
    };
}

pub fn sceneDataForHall(options: struct {
    main_city: *const Player.MainCity,
    role: *const Player.Role,
}) gen.SceneData {
    return .{
        .scene_type = 1, // hall
        .hall_scene_data = .{
            .section_id = @backingInt(options.main_city.section),
            .control_avatar_id = @backingInt(options.role.control_avatar),
            .control_guise_avatar_id = @backingInt(options.role.control_guise_avatar),
            .day_of_week = 5, // TODO: Player.Time
            .scene_time_in_minutes = 360, // TODO: Player.Time
        },
    };
}

pub fn selfBasicInfo(role: *const Player.Role) gen.SelfBasicInfo {
    return .{
        .nick_name = "xeondev",
        .level = 1,
        .name_change_times = 1,
        .avatar_id = @backingInt(role.avatar),
        .control_avatar_id = @backingInt(role.control_avatar),
        .control_guise_avatar_id = @backingInt(role.control_guise_avatar),
    };
}
