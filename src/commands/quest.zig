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

    var avatar_buffer: [Player.Avatar.count_max]protobuf.gen.AvatarInfo = undefined;
    var avatar_list: std.ArrayList(protobuf.gen.AvatarInfo) = .initBuffer(&avatar_buffer);

    for (
        session.player.avatars.keys(),
        session.player.avatars.data(),
    ) |id, data| {
        protobuf.pack.avatarInfo(
            avatar_list.addOneAssumeCapacity(),
            .{ .id = id, .data = data },
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
            .dungeon_package_info = .{ .avatar_list = avatar_list.items },
        },
    });

    return session.sink.respondMinimal(.StartTrainingQuestScRsp, .{ .retcode = 0 });
}

pub fn EndBattleCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EndBattleScRsp, &.{
        .fight_settle = .{},
    });
}
