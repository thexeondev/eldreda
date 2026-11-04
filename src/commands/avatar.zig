const std = @import("std");

const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;
const templates = yuzuha.templates;

pub fn GetAvatarDataCsReq(session: *Session) !void {
    var avatar_info_list: protobuf.pack.AvatarInfoList = .empty;
    var avatars = session.player.avatars();

    while (avatars.next()) |avatar|
        protobuf.pack.avatarInfo(avatar_info_list.addOneAssumeCapacity(), avatar);

    return session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
        .avatar_list = avatar_info_list.items(.avatar_info),
    });
}

pub fn AvatarFavoriteCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.AvatarFavoriteCsReq.Decoded);

    var avatar = session.player.getAvatarById(request.avatar_id) orelse
        return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = .RET_AVATAR_PARAM_ERROR });

    avatar.favorite = request.is_favorite;
    session.player.updateAvatar(avatar);

    try session.notify();
    return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = .RET_SUCC });
}

pub fn WeaponDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.WeaponDressCsReq.Decoded);

    if (!session.player.hasWeaponWithUid(request.weapon_uid))
        return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = .RET_ITEM_NOT_FOUND });

    var avatar_to_dress = session.player.getAvatarById(request.avatar_id) orelse
        return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = .RET_AVATAR_PARAM_ERROR });

    if (session.player.getAvatarWithWeaponUid(request.weapon_uid)) |previous_owner| {
        var avatar_to_undress = previous_owner;
        avatar_to_undress.weapon_uid_maybe = null;
        session.player.updateAvatar(avatar_to_undress);
    }

    avatar_to_dress.weapon_uid_maybe = request.weapon_uid;
    // TODO: update weapon_show
    session.player.updateAvatar(avatar_to_dress);

    try session.notify();
    return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn WeaponUnDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.WeaponUnDressCsReq.Decoded);

    var avatar_to_undress = session.player.getAvatarById(request.avatar_id) orelse
        return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = .RET_AVATAR_NO_WEAPON });

    avatar_to_undress.weapon_uid_maybe = null;
    session.player.updateAvatar(avatar_to_undress);

    try session.notify();
    return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EquipmentDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EquipmentDressCsReq.Decoded);

    const dress_equipment_type = std.enums.fromInt(Player.Equipment.Type, request.dress_index) orelse
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{
            .retcode = .RET_AVATAR_INVALID_DRESS_INDEX,
        });

    if (!session.player.hasEquipmentWithUid(request.equip_uid))
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{
            .retcode = .RET_ITEM_NOT_FOUND,
        });

    var avatar_to_dress = session.player.getAvatarById(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{
            .retcode = .RET_AVATAR_PARAM_ERROR,
        });

    if (session.player.getAvatarWithEquipmentUid(request.equip_uid)) |previous_owner| {
        var avatar_to_undress = previous_owner.avatar;
        avatar_to_undress.dressed_equipment.remove(previous_owner.equipment_type);
        session.player.updateAvatar(avatar_to_undress);
    }

    avatar_to_dress.dressed_equipment.put(dress_equipment_type, request.equip_uid);
    session.player.updateAvatar(avatar_to_dress);

    try session.notify();
    return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EquipmentUnDressCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.EquipmentUnDressCsReq.Decoded);

    var avatar_to_undress = session.player.getAvatarById(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{
            .retcode = .RET_AVATAR_PARAM_ERROR,
        });

    while (try request.undress_index_list.next()) |undress_index| {
        if (avatar_to_undress.dressed_equipment.count() == 0)
            return session.sink.respondMinimal(
                .EquipmentUnDressScRsp,
                .{ .retcode = .RET_AVATAR_INVALID_DRESS_INDEX },
            );

        const equipment_type = std.enums.fromInt(Player.Equipment.Type, undress_index) orelse
            return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{
                .retcode = .RET_AVATAR_INVALID_DRESS_INDEX,
            });

        if (avatar_to_undress.dressed_equipment.fetchRemove(equipment_type) == null)
            return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{
                .retcode = .RET_AVATAR_DRESS_INDEX_NOT_EQUIPPED,
            });
    }

    session.player.updateAvatar(avatar_to_undress);

    try session.notify();
    return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EquipmentSuitDressCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.EquipmentSuitDressCsReq.Decoded);

    var avatar_to_dress = session.player.getAvatarById(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{
            .retcode = .RET_AVATAR_PARAM_ERROR,
        });

    while (try request.param_list.next()) |dress_param| {
        const equipment_type = std.enums.fromInt(Player.Equipment.Type, dress_param.dress_index) orelse
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{
                .retcode = .RET_AVATAR_INVALID_DRESS_INDEX,
            });

        if (!session.player.hasEquipmentWithUid(dress_param.equip_uid))
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{
                .retcode = .RET_ITEM_NOT_FOUND,
            });

        if (avatar_to_dress.dressed_equipment.fetchPut(equipment_type, dress_param.equip_uid) != null)
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{
                .retcode = .RET_AVATAR_INVALID_DRESS_INDEX,
            });
    }

    session.player.updateAvatar(avatar_to_dress);

    try session.notify();
    return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = .RET_SUCC });
}
