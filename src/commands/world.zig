const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn EnterWorldCsReq(session: *Session) !void {
    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = protobuf.pack.sceneDataForHall(session.player.main_city),
    });

    return session.sink.respond(protobuf.gen.EnterWorldScRsp, &.{});
}

pub fn EnterSectionCompleteCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EnterSectionCompleteScRsp, &.{});
}

pub fn LeaveCurSceneCsReq(session: *Session) !void {
    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = protobuf.pack.sceneDataForHall(session.player.main_city),
    });

    return session.sink.respondMinimal(.LeaveCurSceneScRsp, .{ .retcode = 0 });
}

pub fn EnterSectionCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EnterSectionCsReq.Decoded);
    const section = Player.MainCity.Section.fromInt(request.section_id) orelse
        return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = 1 });

    session.playerModified();
    session.player.main_city.section = section;

    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = protobuf.pack.sceneDataForHall(session.player.main_city),
    });

    return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = 0 });
}
