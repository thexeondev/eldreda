const std = @import("std");

const eldreda = @import("../eldreda.zig");
const Player = eldreda.Player;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const templates = eldreda.templates;

pub fn GetAvatarDataCsReq(session: *Session) !void {
    var avatars_buffer: [Player.Avatar.count_max]protobuf.gen.AvatarInfo = undefined;
    var avatar_list: std.ArrayList(protobuf.gen.AvatarInfo) = .initBuffer(&avatars_buffer);

    for (
        session.player.avatars.ids(),
        session.player.avatars.bits(),
        session.player.avatars.weaponUids(),
    ) |id, bits, weapon_uid_maybe| {
        protobuf.pack.avatarInfo(
            avatar_list.addOneAssumeCapacity(),
            .{ .id = id, .bits = bits, .weapon_uid_maybe = weapon_uid_maybe },
        );
    }

    return session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
        .avatar_list = avatar_list.items,
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

        var avatar_info: protobuf.gen.AvatarInfo = undefined;
        protobuf.pack.avatarInfo(&avatar_info, avatar);

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = (&avatar_info)[0..1] },
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

    var avatar_sync_buffer: [2]protobuf.gen.AvatarInfo = undefined;
    var avatar_sync: std.ArrayList(protobuf.gen.AvatarInfo) = .initBuffer(&avatar_sync_buffer);

    if (session.player.avatars.getByWeaponUid(weapon_uid)) |previous_owner| {
        const avatar_to_undress_index, var avatar_to_undress = previous_owner;
        avatar_to_undress.weapon_uid_maybe = .none;
        session.player.avatars.replaceAt(avatar_to_undress_index, avatar_to_undress);

        protobuf.pack.avatarInfo(
            avatar_sync.addOneAssumeCapacity(),
            avatar_to_undress,
        );
    }

    avatar_to_dress.weapon_uid_maybe = .wrap(weapon_uid);
    session.player.avatars.replaceAt(avatar_to_dress_index, avatar_to_dress);

    protobuf.pack.avatarInfo(
        avatar_sync.addOneAssumeCapacity(),
        avatar_to_dress,
    );

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = avatar_sync.items },
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

    var avatar_info: protobuf.gen.AvatarInfo = undefined;
    protobuf.pack.avatarInfo(&avatar_info, avatar_to_undress);

    try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
        .avatar = .{ .avatar_list = (&avatar_info)[0..1] },
    });

    return session.sink.respondMinimal(.WeaponUnDressScRsp, .{ .retcode = 0 });
}
