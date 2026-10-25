const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn GetQuestDataCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.GetQuestDataCsReq.Decoded);

    try session.sink.respond(protobuf.gen.GetQuestDataScRsp, &.{
        .quest_type = request.quest_type,
        .quest_data = .{},
    });
}

pub fn GetHollowDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetHollowDataScRsp, &.{
        .hollow_data = .{},
    });
}

pub fn GetArchiveDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetArchiveDataScRsp, &.{
        .archive_data = .{},
    });
}

pub fn StartTrainingQuestCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.StartTrainingQuestCsReq.Decoded);

    var avatar_id_buffer: [3]u32 = undefined;
    var avatar_id_list: std.ArrayList(u32) = .initBuffer(&avatar_id_buffer);

    while (try request.avatar_id_list.next()) |avatar_id|
        avatar_id_list.appendBounded(avatar_id) catch
            return session.sink.respondMinimal(.StartTrainingQuestScRsp, .{ .retcode = 1 });

    if (avatar_id_list.items.len == 0)
        return session.sink.respondMinimal(.StartTrainingQuestScRsp, .{ .retcode = 1 });

    const buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(Player.Avatar.count_max);
    var buffer: [buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) = undefined;
    var avatar_list: protobuf.pack.AvatarInfoList = .init(&buffer);

    for (
        session.player.avatars.ids(),
        session.player.avatars.bits(),
        session.player.avatars.weaponUids(),
        session.player.avatars.dressedEquipment(),
    ) |id, bits, weapon_uid_maybe, dressed_equipment| {
        protobuf.pack.avatarInfo(
            avatar_list.addOne(),
            .{
                .id = id,
                .bits = bits,
                .weapon_uid_maybe = weapon_uid_maybe,
                .dressed_equipment = dressed_equipment,
            },
        );
    }

    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = .{
            .scene_type = 3,
            .scene_id = 19800014,
            .play_type = 290,
            .fight_scene_data = .{ .scene_reward = .{}, .scene_perform = .{} },
        },
        .dungeon = .{
            .quest_id = request.quest_id,
            .dungeon_package_info = .{ .avatar_list = avatar_list.items(.avatar_info) },
        },
    });

    return session.sink.respondMinimal(.StartTrainingQuestScRsp, .{ .retcode = 0 });
}

pub fn EndBattleCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EndBattleScRsp, &.{
        .fight_settle = .{},
    });
}
