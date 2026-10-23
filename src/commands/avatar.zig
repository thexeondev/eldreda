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
        session.player.avatars.keys(),
        session.player.avatars.data(),
    ) |id, data| {
        protobuf.pack.avatarInfo(
            avatar_list.addOneAssumeCapacity(),
            .{ .id = id, .data = data },
        );
    }

    try session.sink.respond(protobuf.gen.GetAvatarDataScRsp, &.{
        .avatar_list = avatar_list.items,
    });
}

pub fn AvatarFavoriteCsReq(session: *Session) !void {
    const request = try session.command.decodeBody(protobuf.gen.AvatarFavoriteCsReq.Decoded);
    const avatar_id = Player.Avatar.Id.fromInt(request.avatar_id) orelse
        return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = 1 });
    const avatar_index = session.player.avatars.getIndexById(avatar_id) orelse
        return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = 1 });

    const data = &session.player.avatars.data()[avatar_index];

    if (data.flags.favorite != request.is_favorite) {
        session.playerModified();
        data.flags.favorite = true;

        var avatar_info: protobuf.gen.AvatarInfo = undefined;
        protobuf.pack.avatarInfo(
            &avatar_info,
            .{ .id = avatar_id, .data = data.* },
        );

        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &.{
            .avatar = .{ .avatar_list = (&avatar_info)[0..1] },
        });
    }

    return session.sink.respondMinimal(.AvatarFavoriteScRsp, .{ .retcode = 0 });
}
