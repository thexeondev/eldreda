const eldreda = @import("../eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const templates = eldreda.templates;

pub fn VideoGetInfoCsReq(session: *Session) !void {
    // TODO
    try session.sink.respond(protobuf.gen.VideoGetInfoScRsp, &.{});
}

pub fn GetMiscDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetMiscDataScRsp, &.{
        .data = .{
            .unlock = .{
                .unlocked_list = templates.UnlockConfig.table.items(.id),
            },
            .teleport = .{
                .unlocked_list = templates.TeleportConfig.table.items(.id),
            },
            .post_girl = .{
                .show_post_girl_id_list = &.{3510060},
                .post_girl_item_list = &.{.{ .id = 3510060 }},
            },
            .business_card = .{},
            .player_accessory = .{ .control_guise_avatar_id = 1601 },
        },
    });
}
