const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const templates = eldreda.templates;

pub fn GetAvatarDataCsReq(session: *Session) !void {
    var avatars_buffer: [Player.Avatar.count_max]protobuf.gen.AvatarInfo = undefined;
    var avatar_list: std.ArrayList(protobuf.gen.AvatarInfo) = .initBuffer(&avatars_buffer);

    for (
        session.player.avatars.keys(),
        session.player.avatars.data(),
    ) |id, data| {
        protobuf.pack.avatarInfo(
            avatar_list.addOneAssumeCapacity(),
            .{ .id = id, .data = data },
        );
    }

    try session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
        .avatar_list = avatar_list.items,
    });
}
