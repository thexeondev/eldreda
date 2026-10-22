const std = @import("std");

const eldreda = @import("../eldreda.zig");
const protobuf = eldreda.protobuf;
const gen = protobuf.gen;

const Skill = enum(u8) {
    common_attack = 0,
    special_attack = 1,
    evade = 2,
    cooperate_skill = 3,
    unique_skill = 4,
    core_skill = 5,
    assist_skill = 6,
};

const skills: [@typeInfo(Skill).@"enum".field_names.len]protobuf.gen.AvatarSkillLevel = skills: {
    const skill_types = std.enums.values(Skill);
    var array: [skill_types.len]protobuf.gen.AvatarSkillLevel = undefined;

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

pub fn avatarInfo(out: *gen.AvatarInfo, id: u32) void {
    out.* = .{
        .id = id,
        .level = 60,
        .rank = 6,
        .unlocked_talent_num = 6,
        .mindscape_tab_state = &.{ false, false, false, true, true, true },
        .skill_type_level = &skills,
    };
}
