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
    ) |id, bits| {
        protobuf.pack.avatarInfo(
            avatar_list.addOneAssumeCapacity(),
            .{ .id = id, .bits = bits },
        );
    }

    try session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
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
