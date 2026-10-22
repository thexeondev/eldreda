const eldreda = @import("../eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn PlayerLoginCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.PlayerLoginScRsp, &.{});
}

pub fn GetSelfBasicInfoCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetSelfBasicInfoScRsp, &.{
        .self_basic_info = .{
            .nick_name = "xeondev",
            .level = 1,
            .name_change_times = 1,
            .avatar_id = 2011,
            .control_avatar_id = 2011,
            .control_guise_avatar_id = 1601,
        },
    });
}

pub fn GetServerTimestampCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetServerTimestampScRsp, &.{
        .timestamp = @intCast(session.time.toMilliseconds()),
        .utc_offset = 3,
    });
}

pub fn KeepAliveNotify(_: *Session) !void {}
