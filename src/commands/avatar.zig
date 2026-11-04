const std = @import("std");

const yuzuha = @import("../yuzuha.zig");
const Player = yuzuha.Player;
const Session = yuzuha.Session;
const protobuf = yuzuha.protobuf;
const templates = yuzuha.templates;

pub fn GetAvatarDataCsReq(session: *Session) !void {
    var avatar_list: protobuf.pack.AvatarInfoList = .empty;

    for (
        session.player.storage.avatars.ids(),
        session.player.storage.avatars.bits(),
        session.player.storage.avatars.weaponUids(),
        session.player.storage.avatars.dressedEquipment(),
    ) |id, bits, weapon_uid_maybe, dressed_equipment| {
        protobuf.pack.avatarInfo(
            avatar_list.addOne(),
            .{
                .id = id,
                .bits = bits,
                .weapon_uid_maybe = weapon_uid_maybe,
                .dressed_equipment = dressed_equipment,
            },
        );
    }

    return session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
        .avatar_list = avatar_list.items(.avatar_info),
    });
}

pub fn AvatarFavoriteCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.AvatarFavoriteCsReq.Decoded);
    const index, var avatar = session.player.storage.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(
            .AvatarFavoriteScRsp,
            .{ .retcode = .RET_AVATAR_PARAM_ERROR },
        );

    if (avatar.bits.flags.favorite != request.is_favorite) {
        avatar.bits.flags.favorite = true;

        session.playerModified();
        session.player.storage.avatars.replaceAt(index, avatar);

        var avatar_list: protobuf.pack.AvatarInfoList = .empty;
        protobuf.pack.avatarInfo(avatar_list.addOne(), avatar);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
        });
    }

    return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = .RET_SUCC });
}

pub fn WeaponDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.WeaponDressCsReq.Decoded);
    const weapon_uid: Player.Storage.Weapon.Uid = @fromBackingInt(request.weapon_uid);

    const weapon_index = session.player.storage.weapons.getIndexByUid(weapon_uid) orelse
        return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = .RET_ITEM_NOT_FOUND });

    const weapon_id = session.player.storage.weapons.bits()[weapon_index].id;

    const avatar_to_dress_index, var avatar_to_dress =
        session.player.storage.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = .RET_AVATAR_PARAM_ERROR });

    session.playerModified();

    var avatar_sync: protobuf.pack.AvatarInfoList = .empty;

    if (session.player.storage.avatars.getByWeaponUid(weapon_uid)) |previous_owner| {
        const avatar_to_undress_index, var avatar_to_undress = previous_owner;
        avatar_to_undress.weapon_uid_maybe = .none;
        session.player.storage.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);

        protobuf.pack.avatarInfo(
            avatar_sync.addOne(),
            avatar_to_undress,
        );
    }

    avatar_to_dress.weapon_uid_maybe = .wrap(weapon_uid);

    switch (avatar_to_dress.bits.show_weapon_status) {
        .locked => {
            const template_index = templates.Weapon.table.getIndexByKey(@backingInt(weapon_id)).?;
            const weapon_avatar_id = templates.Weapon.table.items(.avatar_id)[template_index];

            if (@backingInt(avatar_to_dress.id) == weapon_avatar_id)
                avatar_to_dress.bits.show_weapon_status = .unlocked_enabled;
        },
        .unlocked_disabled, .unlocked_enabled => {},
    }

    session.player.storage.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);

    protobuf.pack.avatarInfo(
        avatar_sync.addOne(),
        avatar_to_dress,
    );

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_sync.items(.avatar_info) },
    });

    return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn WeaponUnDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.WeaponUnDressCsReq.Decoded);

    const avatar_to_undress_index, var avatar_to_undress =
        session.player.storage.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = .RET_AVATAR_NO_WEAPON });

    session.playerModified();

    avatar_to_undress.weapon_uid_maybe = .none;
    session.player.storage.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);

    var avatar_list: protobuf.pack.AvatarInfoList = .empty;

    protobuf.pack.avatarInfo(avatar_list.addOne(), avatar_to_undress);

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
    });

    return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EquipmentDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EquipmentDressCsReq.Decoded);
    const equipment_uid: Player.Storage.Equipment.Uid = @fromBackingInt(request.equip_uid);

    if (request.dress_index < 1 or request.dress_index > Player.Storage.Avatar.equipment_count)
        return session.sink.respondMinimal(
            .EquipmentDressScRsp,
            .{ .retcode = .RET_AVATAR_INVALID_DRESS_INDEX },
        );

    const dress_index = request.dress_index - 1;

    if (session.player.storage.equipment.getIndexByUid(equipment_uid) == null)
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = .RET_ITEM_NOT_FOUND });

    const avatar_to_dress_index, var avatar_to_dress =
        session.player.storage.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = .RET_AVATAR_PARAM_ERROR });

    var avatar_sync: protobuf.pack.AvatarInfoList = .empty;

    if (session.player.storage.avatars.getByEquipmentUid(equipment_uid)) |previous_owner| {
        if (previous_owner.avatar_index == avatar_to_dress_index)
            return session.sink.respondMinimal(
                .EquipmentDressScRsp,
                .{ .retcode = .RET_AVATAR_PARAM_ERROR },
            );

        var avatar_to_undress = previous_owner.avatar;
        avatar_to_undress.dressed_equipment[previous_owner.equipment_slot_index] = .none;
        session.player.storage.avatars.replaceAt(previous_owner.avatar_index, avatar_to_undress);

        protobuf.pack.avatarInfo(avatar_sync.addOne(), avatar_to_undress);
    }

    session.playerModified();

    avatar_to_dress.dressed_equipment[dress_index] = .wrap(equipment_uid);
    session.player.storage.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);
    protobuf.pack.avatarInfo(avatar_sync.addOne(), avatar_to_dress);

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_sync.items(.avatar_info) },
    });

    return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EquipmentUnDressCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.EquipmentUnDressCsReq.Decoded);

    const avatar_to_undress_index, var avatar_to_undress =
        session.player.storage.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(
            .EquipmentUnDressScRsp,
            .{ .retcode = .RET_AVATAR_PARAM_ERROR },
        );

    var undressed_count: usize = 0;
    while (try request.undress_index_list.next()) |undress_index_plus_one| {
        defer undressed_count += 1;

        if (undressed_count == Player.Storage.Avatar.equipment_count)
            return session.sink.respondMinimal(
                .EquipmentUnDressScRsp,
                .{ .retcode = .RET_AVATAR_INVALID_DRESS_INDEX },
            );

        if (undress_index_plus_one < 1 or undress_index_plus_one > Player.Storage.Avatar.equipment_count)
            return session.sink.respondMinimal(
                .EquipmentUnDressScRsp,
                .{ .retcode = .RET_AVATAR_INVALID_DRESS_INDEX },
            );

        const undress_index = undress_index_plus_one - 1;

        if (avatar_to_undress.dressed_equipment[undress_index] == .none)
            return session.sink.respondMinimal(
                .EquipmentUnDressScRsp,
                .{ .retcode = .RET_AVATAR_DRESS_INDEX_NOT_EQUIPPED },
            );

        avatar_to_undress.dressed_equipment[undress_index] = .none;
    }

    if (undressed_count != 0) {
        session.player.storage.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);
        session.playerModified();

        var avatar_list: protobuf.pack.AvatarInfoList = .empty;
        protobuf.pack.avatarInfo(avatar_list.addOne(), avatar_to_undress);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
        });
    }

    return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{ .retcode = .RET_SUCC });
}

pub fn EquipmentSuitDressCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.EquipmentSuitDressCsReq.Decoded);

    const avatar_to_dress_index, var avatar_to_dress =
        session.player.storage.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(
            .EquipmentSuitDressScRsp,
            .{ .retcode = .RET_AVATAR_PARAM_ERROR },
        );

    var dressed_count: usize = 0;
    while (try request.param_list.next()) |dress_param| {
        defer dressed_count += 1;

        if (dressed_count == Player.Storage.Avatar.equipment_count)
            return session.sink.respondMinimal(
                .EquipmentSuitDressScRsp,
                .{ .retcode = .RET_AVATAR_INVALID_DRESS_INDEX },
            );

        if (dress_param.dress_index < 1 or dress_param.dress_index > Player.Storage.Avatar.equipment_count)
            return session.sink.respondMinimal(
                .EquipmentSuitDressScRsp,
                .{ .retcode = .RET_AVATAR_INVALID_DRESS_INDEX },
            );
        const dress_index = dress_param.dress_index - 1;

        const equipment_uid: Player.Storage.Equipment.Uid = @fromBackingInt(dress_param.equip_uid);
        if (session.player.storage.equipment.getIndexByUid(equipment_uid) == null)
            return session.sink.respondMinimal(
                .EquipmentSuitDressScRsp,
                .{ .retcode = .RET_ITEM_NOT_FOUND },
            );

        if (session.player.storage.avatars.getIndexByEquipmentUid(equipment_uid) != null)
            return session.sink.respondMinimal(
                .EquipmentSuitDressScRsp,
                .{ .retcode = .RET_AVATAR_OCCUPIED },
            );

        avatar_to_dress.dressed_equipment[dress_index] = .wrap(equipment_uid);
    }

    if (dressed_count != 0) {
        session.player.storage.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);
        session.playerModified();

        var avatar_list: protobuf.pack.AvatarInfoList = .empty;
        protobuf.pack.avatarInfo(avatar_list.addOne(), avatar_to_dress);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
        });
    }

    return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = .RET_SUCC });
}
