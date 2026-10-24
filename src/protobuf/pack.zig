const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const gen = eldreda.protobuf.gen;

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

pub fn avatarInfo(out: *gen.AvatarInfo, avatar: Player.Avatar) void {
    out.* = .{
        .id = @backingInt(avatar.id),
        .level = avatar.bits.level_up.getLevel(),
        .rank = avatar.bits.level_up.getRank(),
        .is_favorite = avatar.bits.flags.favorite,
        .cur_weapon_uid = @backingInt(avatar.weapon_uid_maybe),
        .unlocked_talent_num = 6,
        .mindscape_tab_state = &.{ false, false, false, true, true, true },
        .skill_type_level = &skills,
    };
}

pub fn weaponInfo(out: *gen.WeaponInfo, weapon: Player.Weapon) void {
    out.* = .{
        .uid = @backingInt(weapon.uid_maybe.unwrap().?),
        .id = @backingInt(weapon.bits.id),
        .level = 60,
        .star = 5,
        .refine_level = 1,
    };
}
