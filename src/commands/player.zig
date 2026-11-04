const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;

pub fn PlayerLoginCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.PlayerLoginScRsp, &.{});
}

pub fn GetSelfBasicInfoCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetSelfBasicInfoScRsp, &.{
        .self_basic_info = protobuf.pack.selfBasicInfo(&session.player.storage.role),
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
    const control_guise_avatar: Player.ControlGuiseAvatar = @fromBackingInt(request.control_guise_avatar_id);

    if (control_guise_avatar.requiresUnlock()) {
        if (!session.player.hasAvatarWithId(request.control_guise_avatar_id))
            return session.sink.respondMinimal(
                .ModAvatarScRsp,
                .{ .retcode = .RET_AVATAR_PARAM_ERROR },
            );
    }

    session.player.updateControlGuiseAvatar(control_guise_avatar);

    try session.notify();
    return session.sink.respondMinimal(.ModAvatarScRsp, .{ .retcode = .RET_SUCC });
}
