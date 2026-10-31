const std = @import("std");
const ArrayList = std.ArrayList;

const eldreda = @import("../eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const templates = eldreda.templates;

pub fn GetAreaMapDataCsReq(session: *Session) !void {
    var groups_buffer: [templates.UrbanAreaMapGroup.table.count]protobuf.gen.AreaGroupInfo =
        undefined;
    var groups: ArrayList(protobuf.gen.AreaGroupInfo) = .initBuffer(&groups_buffer);

    for (templates.UrbanAreaMapGroup.table.items(.id)) |id| {
        groups.appendAssumeCapacity(.{
            .group_id = id,
            .area_progress = 99,
            .is_unlocked = true,
        });
    }

    var streets_buffer: [templates.UrbanAreaMap.table.count]protobuf.gen.AreaStreetInfo =
        undefined;
    var streets: ArrayList(protobuf.gen.AreaStreetInfo) = .initBuffer(&streets_buffer);

    for (templates.UrbanAreaMap.table.items(.id)) |id| {
        streets.appendAssumeCapacity(.{
            .area_id = id,
            .area_progress = 99,
            .is_unlocked = true,
            .is_area_pop_show = true,
            .is_urban_area_show = true,
            .is_3d_area_show = true,
        });
    }

    try session.sink.respond(protobuf.gen.GetAreaMapDataScRsp, &.{ .data = .{
        .group = groups.items,
        .street = streets.items,
    } });
}

pub fn GetNewAreaPortalListCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetNewAreaPortalListScRsp, &.{});
}

pub fn GetFloorActiveGroupListCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.GetFloorActiveGroupListScRsp, &.{});
}
