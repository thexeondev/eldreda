const yuzuha = @import("../yuzuha.zig");
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;
const templates = yuzuha.templates;

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
                .show_post_girl_id_list = &.{3510037},
                .post_girl_item_list = &.{.{ .id = 3510037 }},
            },
            .business_card = .{},
            .player_accessory = .{
                .control_guise_avatar_id = @backingInt(session.player.role.control_guise_avatar),
            },
        },
    });
}
