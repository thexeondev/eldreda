const eldreda = @import("../eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

const default_hall_scene: protobuf.gen.SceneData = .{
    .scene_type = 1,
    .hall_scene_data = .{
        .section_id = 1,
        .control_avatar_id = 2011,
        .control_guise_avatar_id = 1601,
        .day_of_week = 5,
        .scene_time_in_minutes = 360,
    },
};

pub fn EnterWorldCsReq(session: *Session) !void {
    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = default_hall_scene,
    });

    return session.sink.respond(protobuf.gen.EnterWorldScRsp, &.{});
}

pub fn EnterSectionCompleteCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EnterSectionCompleteScRsp, &.{});
}

pub fn LeaveCurSceneCsReq(session: *Session) !void {
    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = default_hall_scene,
    });

    return session.sink.respondMinimal(.LeaveCurSceneScRsp, .{ .retcode = 0 });
}

pub fn EnterSectionCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EnterSectionCsReq.Decoded);

    var scene = default_hall_scene;
    scene.hall_scene_data.?.section_id = request.section_id;

    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = scene,
    });

    return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = 0 });
}
