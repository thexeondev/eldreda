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
    const buffer_size = protobuf.pack.EquipInfoList.bufferSizeFor(Player.Equipment.count_max);
    var buffer: [buffer_size]u8 align(protobuf.pack.EquipInfoList.alignment) = undefined;
    var equip_list: protobuf.pack.EquipInfoList = .init(&buffer);

    for (
        session.player.equipment.uids(),
        session.player.equipment.bits(),
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
