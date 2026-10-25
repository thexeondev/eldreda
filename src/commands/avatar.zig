const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const templates = eldreda.templates;

pub fn GetAvatarDataCsReq(session: *Session) !void {
    const buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(Player.Avatar.count_max);
    var buffer: [buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) = undefined;
    var avatar_list: protobuf.pack.AvatarInfoList = .init(&buffer);

    for (
        session.player.avatars.ids(),
        session.player.avatars.bits(),
        session.player.avatars.weaponUids(),
        session.player.avatars.dressedEquipment(),
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
    const index, var avatar = session.player.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = 1 });

    if (avatar.bits.flags.favorite != request.is_favorite) {
        avatar.bits.flags.favorite = true;

        session.playerModified();
        session.player.avatars.replaceAt(index, avatar);

        const avatar_buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(1);
        var avatar_buffer: [avatar_buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) =
            undefined;
        var avatar_list: protobuf.pack.AvatarInfoList = .init(&avatar_buffer);

        protobuf.pack.avatarInfo(avatar_list.addOne(), avatar);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
        });
    }

    return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = 0 });
}

pub fn WeaponDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.WeaponDressCsReq.Decoded);
    const weapon_uid: Player.Weapon.Uid = @fromBackingInt(request.weapon_uid);

    if (session.player.weapons.getIndexByUid(weapon_uid) == null)
        return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = 1 });

    const avatar_to_dress_index, var avatar_to_dress =
        session.player.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = 1 });

    session.playerModified();

    const avatar_buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(2);
    var avatar_buffer: [avatar_buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) =
        undefined;
    var avatar_sync: protobuf.pack.AvatarInfoList = .init(&avatar_buffer);

    if (session.player.avatars.getByWeaponUid(weapon_uid)) |previous_owner| {
        const avatar_to_undress_index, var avatar_to_undress = previous_owner;
        avatar_to_undress.weapon_uid_maybe = .none;
        session.player.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);

        protobuf.pack.avatarInfo(
            avatar_sync.addOne(),
            avatar_to_undress,
        );
    }

    avatar_to_dress.weapon_uid_maybe = .wrap(weapon_uid);
    session.player.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);

    protobuf.pack.avatarInfo(
        avatar_sync.addOne(),
        avatar_to_dress,
    );

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_sync.items(.avatar_info) },
    });

    return session.sink.respondMinimal(.WeaponDressScRsp, .{ .retcode = 0 });
}

pub fn WeaponUnDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.WeaponUnDressCsReq.Decoded);

    const avatar_to_undress_index, var avatar_to_undress =
        session.player.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = 1 });

    session.playerModified();

    avatar_to_undress.weapon_uid_maybe = .none;
    session.player.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);

    const avatar_buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(1);
    var avatar_buffer: [avatar_buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) =
        undefined;
    var avatar_list: protobuf.pack.AvatarInfoList = .init(&avatar_buffer);

    protobuf.pack.avatarInfo(avatar_list.addOne(), avatar_to_undress);

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
    });

    return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = 0 });
}

pub fn EquipmentDressCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.EquipmentDressCsReq.Decoded);
    const equipment_uid: Player.Equipment.Uid = @fromBackingInt(request.equip_uid);

    if (request.dress_index < 1 or request.dress_index > Player.Avatar.equipment_count)
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = 1 });

    const dress_index = request.dress_index - 1;

    if (session.player.equipment.getIndexByUid(equipment_uid) == null)
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = 1 });

    const avatar_to_dress_index, var avatar_to_dress =
        session.player.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = 1 });

    const avatar_buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(2);
    var avatar_buffer: [avatar_buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) =
        undefined;
    var avatar_sync: protobuf.pack.AvatarInfoList = .init(&avatar_buffer);

    if (session.player.avatars.getByEquipmentUid(equipment_uid)) |previous_owner| {
        if (previous_owner.avatar_index == avatar_to_dress_index)
            return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = 1 });

        var avatar_to_undress = previous_owner.avatar;
        avatar_to_undress.dressed_equipment[previous_owner.equipment_slot_index] = .none;
        session.player.avatars.replaceAt(previous_owner.avatar_index, avatar_to_undress);

        protobuf.pack.avatarInfo(avatar_sync.addOne(), avatar_to_undress);
    }

    session.playerModified();

    avatar_to_dress.dressed_equipment[dress_index] = .wrap(equipment_uid);
    session.player.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);
    protobuf.pack.avatarInfo(avatar_sync.addOne(), avatar_to_dress);

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_sync.items(.avatar_info) },
    });

    return session.sink.respondMinimal(.EquipmentDressScRsp, .{ .retcode = 0 });
}

pub fn EquipmentUnDressCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.EquipmentUnDressCsReq.Decoded);

    const avatar_to_undress_index, var avatar_to_undress =
        session.player.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{ .retcode = 1 });

    var undressed_count: usize = 0;
    while (try request.undress_index_list.next()) |undress_index_plus_one| {
        defer undressed_count += 1;

        if (undressed_count == Player.Avatar.equipment_count)
            return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{ .retcode = 1 });

        if (undress_index_plus_one < 1 or undress_index_plus_one > Player.Avatar.equipment_count)
            return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{ .retcode = 1 });

        const undress_index = undress_index_plus_one - 1;
        avatar_to_undress.dressed_equipment[undress_index] = .none;
    }

    if (undressed_count != 0) {
        session.player.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);
        session.playerModified();

        const avatar_buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(1);
        var avatar_buffer: [avatar_buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) =
            undefined;
        var avatar_list: protobuf.pack.AvatarInfoList = .init(&avatar_buffer);

        protobuf.pack.avatarInfo(avatar_list.addOne(), avatar_to_undress);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
        });
    }

    return session.sink.respondMinimal(.EquipmentUnDressScRsp, .{ .retcode = 0 });
}

pub fn EquipmentSuitDressCsReq(session: *Session) !void {
    var request = try session.command.decodeBody(protobuf.gen.EquipmentSuitDressCsReq.Decoded);

    const avatar_to_dress_index, var avatar_to_dress =
        session.player.avatars.get(request.avatar_id) orelse
        return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = 1 });

    var dressed_count: usize = 0;
    while (try request.param_list.next()) |dress_param| {
        defer dressed_count += 1;

        if (dressed_count == Player.Avatar.equipment_count)
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = 1 });

        if (dress_param.dress_index < 1 or dress_param.dress_index > Player.Avatar.equipment_count)
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = 1 });
        const dress_index = dress_param.dress_index - 1;

        const equipment_uid: Player.Equipment.Uid = @fromBackingInt(dress_param.equip_uid);
        if (session.player.equipment.getIndexByUid(equipment_uid) == null)
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = 1 });

        if (session.player.avatars.getIndexByEquipmentUid(equipment_uid) != null)
            return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = 1 });

        avatar_to_dress.dressed_equipment[dress_index] = .wrap(equipment_uid);
    }

    if (dressed_count != 0) {
        session.player.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);
        session.playerModified();

        const avatar_buffer_size = protobuf.pack.AvatarInfoList.bufferSizeFor(1);
        var avatar_buffer: [avatar_buffer_size]u8 align(protobuf.pack.AvatarInfoList.alignment) =
            undefined;
        var avatar_list: protobuf.pack.AvatarInfoList = .init(&avatar_buffer);

        protobuf.pack.avatarInfo(avatar_list.addOne(), avatar_to_dress);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = avatar_list.items(.avatar_info) },
        });
    }

    return session.sink.respondMinimal(.EquipmentSuitDressScRsp, .{ .retcode = 0 });
}
