const std = @import("std");

const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;

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
            return session.sink.respondMinimal(
                .StartTrainingQuestScRsp,
                .{ .retcode = .RET_AVATAR_PARAM_ERROR },
            );

    if (avatar_id_list.items.len == 0)
        return session.sink.respondMinimal(
            .StartTrainingQuestScRsp,
            .{ .retcode = .RET_AVATAR_PARAM_ERROR },
        );

    var avatar_info_list: protobuf.pack.AvatarInfoList = .empty;
    var avatars = session.player.avatars();
    while (avatars.next()) |avatar|
        protobuf.pack.avatarInfo(avatar_info_list.addOne(), avatar);

    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = .{
            .scene_type = 3,
            .scene_id = 19800014,
            .play_type = 290,
            .fight_scene_data = .{ .scene_reward = .{}, .scene_perform = .{} },
        },
        .dungeon = .{
            .quest_id = request.quest_id,
            .dungeon_package_info = .{ .avatar_list = avatar_info_list.items(.avatar_info) },
        },
    });

    return session.sink.respondMinimal(.StartTrainingQuestScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EndBattleCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EndBattleScRsp, &.{
        .fight_settle = .{},
    });
}
