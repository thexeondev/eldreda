const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn PlayerLoginCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.PlayerLoginScRsp, &.{});
}

pub fn GetSelfBasicInfoCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetSelfBasicInfoScRsp, &.{
        .self_basic_info = protobuf.pack.selfBasicInfo(&session.player.role),
    });
}

pub fn GetServerTimestampCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetServerTimestampScRsp, &.{
        .timestamp = @intCast(session.time.toMilliseconds()),
        .utc_offset = 3,
    });
}

pub fn KeepAliveNotify(_: *Session) !void {}

pub fn ModAvatarCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.ModAvatarCsReq.Decoded);

    const control_avatar = Player.Role.Avatar.fromInt(request.control_avatar_id) orelse
        return session.sink.respondMinimal(.ModAvatarScRsp, .{ .retcode = .RET_AVATAR_PARAM_ERROR });

    const control_guise_avatar = Player.Role.Guise.fromInt(request.control_guise_avatar_id) orelse
        return session.sink.respondMinimal(.ModAvatarScRsp, .{ .retcode = .RET_AVATAR_PARAM_ERROR });

    if (control_guise_avatar.toAvatarId()) |avatar_id| {
        if (session.player.avatars.getIndexById(avatar_id) == null)
            return session.sink.respondMinimal(
                .ModAvatarScRsp,
                .{ .retcode = .RET_AVATAR_PARAM_ERROR },
            );
    }

    session.playerModified();
    session.player.role.control_avatar = control_avatar;
    session.player.role.control_guise_avatar = control_guise_avatar;

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .self_basic_info = protobuf.pack.selfBasicInfo(&session.player.role),
    });

    return session.sink.respondMinimal(.ModAvatarScRsp, .{ .retcode = .RET_SUCC });
}
