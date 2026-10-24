const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

pub fn GetWeaponDataCsReq(session: *Session) !void {
    var weapon_buffer: [Player.Weapon.count_max]protobuf.gen.WeaponInfo = undefined;
    var weapon_list: std.ArrayList(protobuf.gen.WeaponInfo) = .initBuffer(&weapon_buffer);

    for (
        session.player.weapons.uids(),
        session.player.weapons.bits(),
    ) |uid, bits| {
        protobuf.pack.weaponInfo(
            weapon_list.addOneAssumeCapacity(),
            .{ .uid_maybe = .wrap(uid), .bits = bits },
        );
    }

    return session.sink.respond(protobuf.gen.GetWeaponDataScRsp, &.{
        .weapon_list = weapon_list.items,
    });
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
