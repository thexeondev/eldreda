const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn EnterWorldCsReq(session: *Session) !void {
    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = protobuf.pack.sceneDataForHall(.{
            .main_city = &session.player.main_city,
            .role = &session.player.role,
            .time = &session.player.time,
        }),
    });

    return session.sink.respond(protobuf.gen.EnterWorldScRsp, &.{});
}

pub fn EnterSectionCompleteCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.EnterSectionCompleteScRsp, &.{});
}

pub fn LeaveCurSceneCsReq(session: *Session) !void {
    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = protobuf.pack.sceneDataForHall(.{
            .main_city = &session.player.main_city,
            .role = &session.player.role,
            .time = &session.player.time,
        }),
    });

    return session.sink.respondMinimal(.LeaveCurSceneScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EnterSectionCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EnterSectionCsReq.Decoded);
    const section = Player.MainCity.Section.fromInt(request.section_id) orelse
        return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = .RET_SCENE_NOT_FOUND });

    session.playerModified();
    session.player.main_city.section = section;

    try session.sink.notify(protobuf.gen.EnterSceneScNotify, &.{
        .scene = protobuf.pack.sceneDataForHall(.{
            .main_city = &session.player.main_city,
            .role = &session.player.role,
            .time = &session.player.time,
        }),
    });

    return session.sink.respondMinimal(.EnterSectionScRsp, .{ .retcode = .RET_SUCC });
}

pub fn ModMainCityTimeCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.ModMainCityTimeCsReq.Decoded);

    const period_tag = std.enums.fromInt(protobuf.gen.TimePeriodType, request.time_period) orelse
        return session.sink.respondMinimal(
            .ModMainCityTimeScRsp,
            .{ .retcode = .RET_INVALID_REQUEST_DATA },
        );

    const next_time_period_maybe: ?Player.Time.Period = switch (period_tag) {
        .TimePeriodType_MORNING => .morning,
        .TimePeriodType_AFTERNOON => .afternoon,
        .TimePeriodType_EVENING => .evening,
        .TimePeriodType_NIGHT => .night,

        .TimePeriodType_NOW,
        .TimePeriodType_TIME_PERIOD_TYPE_NONE,
        => null,
    };

    if (next_time_period_maybe) |next_time_period| {
        session.playerModified();

        const time_period_change = session.player.time.period.fastForwardTo(next_time_period);

        if (time_period_change.day_advanced)
            session.player.time.day = session.player.time.day.increment();

        session.player.time.period = time_period_change.new_value;
    }

    var refresh_notify = protobuf.pack.hall(protobuf.gen.HallRefreshScNotify, .{
        .main_city = &session.player.main_city,
        .role = &session.player.role,
        .time = &session.player.time,
    });
    refresh_notify.force_refresh = true;
    try session.sink.notify(protobuf.gen.HallRefreshScNotify, &refresh_notify);

    return session.sink.respondMinimal(.ModMainCityTimeScRsp, .{ .retcode = .RET_SUCC });
}
