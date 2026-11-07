const std = @import("std");

const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;

pub fn GetWeaponDataCsReq(session: *Session) !void {
    var weapon_buffer: [Player.Storage.Weapon.count_max]protobuf.gen.WeaponInfo = undefined;
    var weapon_list: std.ArrayList(protobuf.gen.WeaponInfo) = .initBuffer(&weapon_buffer);
    var weapons = session.player.weapons();

    while (weapons.next()) |weapon_kv| {
        protobuf.pack.weaponInfo(
            weapon_list.addOneAssumeCapacity(),
            weapon_kv,
        );
    }

    return session.sink.respond(protobuf.gen.GetWeaponDataScRsp, &.{
        .weapon_list = weapon_list.items,
    });
}

pub fn GetEquipDataCsReq(session: *Session) !void {
    var equip_list: protobuf.pack.EquipInfoList = .empty;
    var equipment = session.player.equipment();

    while (equipment.next()) |equipment_kv| {
        protobuf.pack.equipInfo(
            equip_list.addOneAssumeCapacity(),
            equipment_kv,
        );
    }

    return session.sink.respond(protobuf.gen.GetEquipDataScRsp, &.{
        .equip_list = equip_list.items(.equip_info),
    });
}

pub fn GetItemDataCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.GetItemDataScRsp, &.{});
}

pub fn GetWishlistDataCsReq(session: *Session) !void {
    return session.sink.respond(protobuf.gen.GetWishlistDataScRsp, &.{});
}
