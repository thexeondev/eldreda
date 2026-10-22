const eldreda = @import("../eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn GetWeaponDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetWeaponDataScRsp, &.{});
}

pub fn GetEquipDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetEquipDataScRsp, &.{});
}

pub fn GetItemDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetItemDataScRsp, &.{});
}

pub fn GetWishlistDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetWishlistDataScRsp, &.{});
}
