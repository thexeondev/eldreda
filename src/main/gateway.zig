const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const IpAddress = std.Io.net.IpAddress;

const eldreda = @import("eldreda");
const rsa = eldreda.rsa;
const sdk = eldreda.sdk;
const Player = eldreda.Player;
const Command = eldreda.Command;
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;
const PacketHead = protobuf.gen.PacketHead;
const PlayerGetTokenCsReq = protobuf.gen.PlayerGetTokenCsReq;
const PlayerGetTokenScRsp = protobuf.gen.PlayerGetTokenScRsp;

const log = std.log.scoped(.@"eldreda::gateway");

const Server = @import("root").Server;

pub const Options = struct {
    address: IpAddress,
};

pub fn start(io: Io, gpa: Allocator, server: *Server, options: Options) !void {
    var net_server = try options.address.listen(io, .{
        .reuse_address = true,
        .kernel_backlog = 64,
    });
    defer net_server.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    log.info("gateway is listening at tcp://{f}", .{net_server.socket.address});

    while (true) {
        const stream = net_server.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.SocketNotListening => unreachable,
            else => continue,
        };

        group.concurrent(io, runClientTask, .{ io, gpa, server, stream }) catch |err|
            switch (err) {
                error.ConcurrencyUnavailable => stream.close(io),
            };
    }
}

fn runClientTask(
    io: Io,
    gpa: Allocator,
    server: *Server,
    stream: Io.net.Stream,
) Io.Cancelable!void {
    defer stream.close(io);

    log.info("new client from {f}", .{stream.socket.address});
    defer log.info("client from {f} disconnected", .{stream.socket.address});

    var read_buffer: [8192]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);
    var stream_writer = stream.writer(io, &.{});

    serveConnection(io, gpa, server, .{
        .address = stream.socket.address,
        .reader = &stream_reader.interface,
        .writer_unbuffered = &stream_writer.interface,
    }) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.EndOfStream => return,
        error.ReadFailed => switch (stream_reader.err.?) {
            error.Canceled => |e| return e,
            else => return,
        },
        error.WriteFailed => switch (stream_writer.err.?) {
            error.Canceled => |e| return e,
            else => return,
        },
        else => |e| return log.err(
            "failed to serve client from {f}: {t}",
            .{ stream.socket.address, e },
        ),
    };
}

const Connection = struct {
    address: IpAddress,
    reader: *Io.Reader,
    writer_unbuffered: *Io.Writer,
};

fn serveConnection(
    io: Io,
    gpa: Allocator,
    server: *Server,
    connection: Connection,
) !void {
    _ = gpa;

    const token = try handleFirstCommand(io, server, &connection);
    var client: Client = undefined;
    client.init(token);

    var player_file_path_buffer: ["4294967295.bin".len]u8 = undefined;
    const player_file_path = mem.print(&player_file_path_buffer, "{d}.bin", .{client.player_uid}) catch |err| switch (err) {
        error.NoSpaceLeft => unreachable,
    };

    var player: Player = undefined;
    var player_load_diagnostics: Player.LoadDiagnostics = undefined;
    player.loadFromFile(io, .{
        .dir = server.storage.player_dir,
        .sub_path = player_file_path,
        .diagnostics = &player_load_diagnostics,
    }) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound => {
            player.initDefaults();

            { // TODO: move this into a separate utility
                var rng: std.Random.DefaultPrng = .init(
                    @bitCast(Io.Clock.now(.real, io).toMilliseconds()),
                );

                player.addRandomEquipment(rng.random(), 500) catch |e| switch (e) {
                    error.NoSpaceLeft => unreachable,
                };
            }

            try player.saveToFile(io, server.storage.player_dir, player_file_path);
        },
        error.CheckDiagnostics => return log.err(
            "failed to load save file for player with uid {d}:\n{f}",
            .{ client.player_uid, &player_load_diagnostics },
        ),
    };

    var send_buffer: [64 * 1024]u8 = undefined;

    while (true) {
        const command: Command = try .receive(connection.reader);
        const head = try protobuf.decode(PacketHead.Decoded, command.head);
        Command.xor(command.body, &client.decrypt_vector);

        var session: Session = .{
            .time = .now(io, .real),
            .command = command,
            .sink = .{
                .buffer = &send_buffer,
                .decrypt_vector = &client.decrypt_vector,
                .packet_id_counter = &client.packet_id_counter,
                .ack_packet_id = head.packet_id,
            },
            .player_uid = client.player_uid,
            .player = &player,
            .player_needs_save = false,
        };

        try eldreda.commands.execute(&session);

        if (session.player_needs_save) {
            try player.saveToFile(io, server.storage.player_dir, player_file_path);
        }

        try connection.writer_unbuffered.writeAll(send_buffer[0..session.sink.bytes_written]);
    }
}

const Client = struct {
    player_uid: u32,
    decrypt_vector: [4096]u8,
    packet_id_counter: u32,

    pub const Token = struct {
        player_uid: u32,
        rand_key: u64,
    };

    pub fn init(client: *Client, token: Token) void {
        client.player_uid = token.player_uid;
        client.packet_id_counter = 0;

        eldreda.random.getDecryptVector(&client.decrypt_vector, token.rand_key);
    }
};

fn handleFirstCommand(io: Io, server: *Server, connection: *const Connection) !Client.Token {
    const command: Command = try .receive(connection.reader);
    if (command.id != PlayerGetTokenCsReq.cmd_id) {
        log.debug(
            "unexpected first cmd with id {d} from {f}",
            .{ command.id, connection.address },
        );
        return error.UnexpectedFirstCommand;
    }

    Command.xor(command.body, server.conf.gateway_initial_decrypt_vector);
    const request = try protobuf.decode(PlayerGetTokenCsReq.Decoded, command.body);

    const client_rand_key = rsa.decryptStringAsArray(
        // TODO: make compile-proto output []u8 in `Decoded` messages to avoid this @constCast.
        @constCast(request.client_rand_key),
        @sizeOf(u64),
    ) orelse return failPlayerGetToken(
        "failed to decrypt client_rand_key from {f}",
        .{connection.address},
    );

    const player_uid = try verifyToken(io, server, request.account_uid, request.token) orelse
        return failPlayerGetToken("token verification failed for {f}", .{connection.address});

    var server_rand_key: [8]u8 = undefined;
    io.random(&server_rand_key);

    var encrypted_server_rand_key: rsa.EncryptAndSignBuffer = undefined;
    rsa.encryptAndSign(&encrypted_server_rand_key, &server_rand_key);

    const response: PlayerGetTokenScRsp = .{
        .uid = player_uid,
        .server_rand_key = &encrypted_server_rand_key.ciphertext,
        .sign = &encrypted_server_rand_key.sign,
    };

    var response_buffer: [1024]u8 = undefined;
    const response_size = try Command.encode(PlayerGetTokenScRsp, &response, .{
        .buffer = &response_buffer,
        .decrypt_vector = server.conf.gateway_initial_decrypt_vector,
        .head = .{},
    });
    try connection.writer_unbuffered.writeAll(response_buffer[0..response_size]);

    return .{
        .player_uid = player_uid,
        .rand_key = mem.readInt(u64, client_rand_key, .little) ^
            mem.readInt(u64, &server_rand_key, .little),
    };
}

fn verifyToken(io: Io, server: *Server, account_uid: []const u8, token: []const u8) !?u32 {
    const id_int = std.fmt.parseInt(u32, account_uid, 10) catch return error.InvalidUid;
    const account_index = sdk.Account.Index.fromUid(id_int) orelse return error.InvalidUid;

    try server.sdk_account_storage_mutex.lock(io);
    defer server.sdk_account_storage_mutex.unlock(io);

    const account = server.sdk_account_storage.getByIndex(account_index) orelse
        return error.AccountNotFound;

    return if (account.token.eql(token)) account_index.toUid() else null;
}

fn failPlayerGetToken(comptime log_fmt: []const u8, fmt_args: anytype) error{PlayerGetTokenFail} {
    log.debug(log_fmt, fmt_args);
    return error.PlayerGetTokenFail;
}
