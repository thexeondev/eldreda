const std = @import("std");

const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;

pub fn EnterWorldCsReq(session: *Session) !void {
    session.player.enterMainCity();
    try session.notify();
    return session.sink.respond(protobuf.gen.EnterWorldScRsp, &.{});
}

pub fn EnterSectionCompleteCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EnterSectionCompleteScRsp, &.{});
}

pub fn LeaveCurSceneCsReq(session: *Session) !void {
    session.player.enterMainCity();
    try session.notify();
    return session.sink.respondMinimal(.LeaveCurSceneScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EnterSectionCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EnterSectionCsReq.Decoded);
    const section = Player.MainCitySection.fromInt(request.section_id) orelse
        return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = .RET_SCENE_NOT_FOUND });

    session.player.updateMainCitySection(section);

    try session.notify();
    return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = .RET_SUCC });
}

pub fn ModMainCityTimeCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.ModMainCityTimeCsReq.Decoded);

    const period_tag = std.enums.fromInt(protobuf.gen.TimePeriodType, request.time_period) orelse
        return session.sink.respondMinimal(
            .ModMainCityTimeScRsp,
            .{ .retcode = .RET_INVALID_REQUEST_DATA },
        );

    const next_time_period_maybe: ?Player.TimePeriod = switch (period_tag) {
        .TimePeriodType_MORNING => .morning,
        .TimePeriodType_AFTERNOON => .afternoon,
        .TimePeriodType_EVENING => .evening,
        .TimePeriodType_NIGHT => .night,

        .TimePeriodType_NOW,
        .TimePeriodType_TIME_PERIOD_TYPE_NONE,
        => null,
    };

    if (next_time_period_maybe) |next_time_period| {
        const time_period_change = session.player.storage.time.period.fastForwardTo(next_time_period);
        session.player.updateTimePeriod(time_period_change);
    }

    try session.notify();
    return session.sink.respondMinimal(.ModMainCityTimeScRsp, .{ .retcode = .RET_SUCC });
}
