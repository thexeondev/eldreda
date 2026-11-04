const std = @import("std");

const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;

pub fn GetWeaponDataCsReq(session: *Session) !void {
    var weapon_buffer: [Player.Storage.Weapon.count_max]protobuf.gen.WeaponInfo = undefined;
    var weapon_list: std.ArrayList(protobuf.gen.WeaponInfo) = .initBuffer(&weapon_buffer);

    for (
        session.player.storage.weapons.uids(),
        session.player.storage.weapons.bits(),
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
    var equip_list: protobuf.pack.EquipInfoList = .empty;

    for (
        session.player.storage.equipment.uids(),
        session.player.storage.equipment.bits(),
    ) |uid, bits| {
        protobuf.pack.equipInfo(
            equip_list.addOne(),
            .{ .uid_maybe = .wrap(uid), .bits = bits },
        );
    }

    try session.sink.respond(protobuf.gen.GetEquipDataScRsp, &.{
        .equip_list = equip_list.items(.equip_info),
    });
}

pub fn GetItemDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetItemDataScRsp, &.{});
}

pub fn GetWishlistDataCsReq(session: *Session) !void {
    try session.sink.respond(protobuf.gen.GetWishlistDataScRsp, &.{});
}
