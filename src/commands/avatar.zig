const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const templates = eldreda.templates;

pub fn GetAvatarDataCsReq(session: *Session) !void {
    var avatars_buffer: [templates.AvatarBase.table.count]protobuf.gen.AvatarInfo = undefined;
    var avatar_list: std.ArrayList(protobuf.gen.AvatarInfo) = .initBuffer(&avatars_buffer);

    for (templates.AvatarBase.table.items(.id)) |id| {
        if (id % 10 != 1 or id >= 2_000) continue;
        protobuf.pack.avatarInfo(avatar_list.addOneAssumeCapacity(), id);
    }

    try session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
        .avatar_list = avatar_list.items,
    });
}
