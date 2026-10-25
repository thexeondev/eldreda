const builtin = @import("builtin");
const native_os = builtin.target.os.tag;

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const log = std.log;
const process = std.process;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const Allocator = std.mem.Allocator;
const IpAddress = std.Io.net.IpAddress;

const eldreda = @import("eldreda");
const sdk = eldreda.sdk;
const http = eldreda.http;
const Configuration = eldreda.Configuration;

const build_options = @import("build_options");

const gateway = @import("main/gateway.zig");

var safe_allocator: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
const build_mode_has_safety = switch (builtin.optimize) {
    .debug, .safe => true,
    .small, .fast => false,
};

const default_http_address = "127.0.0.1:12401";
const default_gate_address = "127.0.0.1:20501";
const default_public_url_prefix = "http://127.0.0.1:12401";
const sdk_account_storage_filename = "sdk_accounts.bin";
const default_config_path = "eldreda.zon";

pub const Storage = struct {
    const default_root_path = "eldreda-storage";
    const player_dir_sub_path = "players";

    root: Io.Dir,
    player_dir: Io.Dir,

    fn open(io: Io, root_path: []const u8) Storage {
        const root = Io.Dir.cwd().createDirPathOpen(io, root_path, .{}) catch |err| fatal(
            "failed to open storage root at {q}: {t}",
            .{ root_path, err },
        );

        const player_dir = root.createDirPathOpen(io, player_dir_sub_path, .{}) catch |err| fatal(
            "failed to open player storage sub-directory {q}: {t}",
            .{ player_dir_sub_path, err },
        );

        return .{ .root = root, .player_dir = player_dir };
    }

    fn close(storage: Storage, io: Io) void {
        storage.player_dir.close(io);
        storage.root.close(io);
    }
};

pub const Server = struct {
    conf: *const Configuration,
    storage: Storage,
    query_dispatch_response: []const u8,
    query_gateway_response: []const u8,
    fallback_dispatch_response: []const u8,
    /// Not threadsafe. Lock `sdk_account_storage_mutex` before accessing.
    sdk_account_storage: *sdk.Account.Storage,
    /// Guards `sdk_account_storage`.
    sdk_account_storage_mutex: Io.Mutex,
};

fn generalUsage(io: Io) noreturn {
    Io.File.stdout().writeStreamingAll(io,
        \\Usage: eldreda [command] [options]
        \\
        \\Commands:
        \\  serve    (default) Start the game server
        \\  version  Print version number and exit
        \\
        \\General Options:
        \\  --help, -h  Print this help and exit
        \\
    ) catch {};
    process.exit(0);
}

fn serveUsage(io: Io) noreturn {
    Io.File.stdout().writeStreamingAll(io, std.fmt.comptimePrint(
        \\Usage: eldreda serve [options]
        \\
        \\Options:
        \\  --help, -h             Print this help and exit
        \\  --config-path          Path to the configuration file; default is {q}
        \\  --http-listen-address  Address for dispatch and sdk service; default is {q}
        \\  --gate-listen-address  Address for the game gateway service; default is {q}
        \\  --public-url-prefix    Prefix for publicly shared http URLs; default is {q}
        \\  --storage-path         Path to storage directory; default is {q}
        \\
    , .{
        default_config_path,
        default_http_address,
        default_gate_address,
        default_public_url_prefix,
        Storage.default_root_path,
    })) catch {};
    process.exit(0);
}

const Command = enum {
    serve,
    version,
};

pub fn main(init: process.Init.Minimal) !void {
    const gpa = if (build_mode_has_safety) safe_allocator.allocator() else std.heap.smp_allocator;
    defer if (build_mode_has_safety) assert(safe_allocator.deinit() == 0);

    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer if (build_mode_has_safety) arena_instance.deinit();
    const arena = arena_instance.allocator();

    var threaded: Io.Threaded = .init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();

    const args_slice = try init.args.toSlice(arena);
    var args_i: usize = 1;

    const command_string = nextArg(args_slice, &args_i) orelse "serve";
    const command_tag = std.meta.stringToEnum(Command, command_string) orelse {
        if (!mem.eql(u8, command_string, "-h") and
            !mem.eql(u8, command_string, "--help"))
            log.err("unknown command {q}", .{command_string});

        generalUsage(io);
    };

    switch (command_tag) {
        .serve => {},
        .version => {
            Io.File.stdout().writeStreamingAll(io, build_options.version ++ "\n") catch {};
            process.exit(0);
        },
    }

    var config_path_maybe: ?[]const u8 = null;
    var http_address = comptime IpAddress.parseLiteral(default_http_address) catch unreachable;
    var gate_address = comptime IpAddress.parseLiteral(default_gate_address) catch unreachable;
    var storage_path: []const u8 = Storage.default_root_path;
    var public_url_prefix: []const u8 = default_public_url_prefix;

    while (nextArg(args_slice, &args_i)) |arg| {
        if (mem.eql(u8, "-h", arg) or mem.eql(u8, "--help", arg)) {
            serveUsage(io);
        } else if (mem.cutPrefix(u8, arg, "--config-path=")) |path_string| {
            config_path_maybe = path_string;
        } else if (mem.cutPrefix(u8, arg, "--http-listen-address=")) |address_string| {
            http_address = IpAddress.parseLiteral(address_string) catch
                fatal("bad --http-listen-address specified: {q}", .{address_string});
        } else if (mem.cutPrefix(u8, arg, "--gate-listen-address=")) |address_string| {
            gate_address = IpAddress.parseLiteral(address_string) catch
                fatal("bad --gate-listen-address specified: {q}", .{address_string});
        } else if (mem.cutPrefix(u8, arg, "--public-url-prefix=")) |prefix_string| {
            public_url_prefix = prefix_string;
        } else if (mem.cutPrefix(u8, arg, "--storage-path=")) |path_string| {
            storage_path = path_string;
        } else {
            log.err("unrecognized argument: {q}", .{arg});
            serveUsage(io);
        }
    }

    var conf: Configuration = .defaults;
    try conf.updateFromFileOrExit(io, .{
        .gpa = gpa,
        .arena = arena,
        .path_cwd_relative = config_path_maybe orelse default_config_path,
        .exit_if_not_found = config_path_maybe != null,
    });

    const query_dispatch_response = try eldreda.dispatch.buildQueryDispatchResponse(.{
        .gpa = gpa,
        .arena = arena,
        .region_name = "eldreda",
        .region_title = "Eldreda",
        .public_url_prefix = public_url_prefix,
    });

    var ip4_string_buffer: ["255.255.255.255".len]u8 = undefined;
    const query_gateway_response = try eldreda.dispatch.buildQueryGatewayResponse(.{
        .gpa = gpa,
        .arena = arena,
        .region_name = "eldreda",
        .region_title = "Eldreda",
        .client_secret_key = conf.client_secret_key,
        .cdn = &conf.version.cdn,
        .gateway = switch (gate_address) {
            .ip4 => |ip4| ip4: {
                // TODO: technically this can be achieved if desired,
                // move gateway's `net.Server` initialization to be before
                // this response is serialized.
                if (ip4.port == 0) fatal("gateway port cannot be random", .{});

                break :ip4 .{
                    .ip = mem.print(
                        &ip4_string_buffer,
                        "{d}.{d}.{d}.{d}",
                        .{ ip4.bytes[0], ip4.bytes[1], ip4.bytes[2], ip4.bytes[3] },
                    ) catch unreachable,
                    .port = ip4.port,
                };
            },
            .ip6 => fatal("ipv6 is not supported for gateway", .{}),
        },
    });

    const fallback_dispatch_response = try eldreda.dispatch.buildFallbackResponse(.{
        .gpa = gpa,
        .arena = arena,
        .supported_version = conf.version.tag,
    });

    const storage: Storage = .open(io, storage_path);
    defer storage.close(io);

    var sdk_account_storage = sdk.loadAccountStorageFromFileIfExists(
        io,
        gpa,
        storage.root,
        sdk_account_storage_filename,
    ) catch |err| fatal("failed to load account storage: {t}", .{err});
    defer sdk_account_storage.deinit(gpa);

    var server: Server = .{
        .conf = &conf,
        .storage = storage,
        .query_dispatch_response = query_dispatch_response,
        .query_gateway_response = query_gateway_response,
        .fallback_dispatch_response = fallback_dispatch_response,
        .sdk_account_storage = &sdk_account_storage,
        .sdk_account_storage_mutex = .init,
    };
    defer assert(server.sdk_account_storage_mutex.tryLock()); // leaked mutex lock

    var select: Io.Select(union(enum) {
        shutdown: Io.Cancelable!void,
        http: @typeInfo(@TypeOf(startHttp)).@"fn".return_type.?,
        gateway: @typeInfo(@TypeOf(gateway.start)).@"fn".return_type.?,
    }) = .init(io, &.{});
    defer select.cancelDiscard();

    try select.concurrent(.shutdown, waitShutdown, .{io});

    try select.concurrent(.http, startHttp, .{ io, gpa, &server, .{
        .address = http_address,
    } });

    try select.concurrent(.gateway, gateway.start, .{ io, gpa, &server, .{
        .address = gate_address,
    } });

    switch (try select.await()) {
        .shutdown => log.info("shutting down...", .{}),
        .http => |result| result catch |err| switch (err) {
            error.AddressInUse => log.err("http listen address is already in use", .{}),
            else => |e| log.err("failed to initialize http server: {t}", .{e}),
        },
        .gateway => |result| result catch |err| switch (err) {
            error.AddressInUse => log.err("gateway listen address is already in use", .{}),
            else => |e| log.err("failed to initialize gateway: {t}", .{e}),
        },
    }
}

const HttpServerOptions = struct {
    address: IpAddress,
};

fn startHttp(io: Io, gpa: Allocator, server: *Server, options: HttpServerOptions) !void {
    var net_server = try options.address.listen(io, .{
        .reuse_address = true,
        .kernel_backlog = 64,
    });
    defer net_server.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    const scoped_log = std.log.scoped(.@"eldreda::http");
    scoped_log.info(
        "waiting for dispatch and sdk requests at http://{f}",
        .{net_server.socket.address},
    );

    while (true) {
        const stream = net_server.accept(io) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.SocketNotListening => unreachable,
            else => continue,
        };

        group.concurrent(io, handleHttpClient, .{ io, gpa, server, stream }) catch |err|
            switch (err) {
                error.ConcurrencyUnavailable => stream.close(io),
            };
    }
}

const HttpRequestScope = struct {
    server: *Server,
    request: http.Request,
    stream_writer: *Io.Writer,
    /// Request scope lifetime.
    arena: Allocator,

    fn respond(scope: *const HttpRequestScope, json: anytype) !void {
        const json_fmt = std.json.fmt(json, .{});
        const content_length = std.fmt.count("{f}", .{json_fmt});
        try scope.sendHeaders(.ok, content_length);

        if (scope.request.line.method != .HEAD) {
            try scope.stream_writer.print("{f}", .{json_fmt});
        }

        try scope.stream_writer.flush();
    }

    fn respondStatic(scope: *const HttpRequestScope, json: []const u8) !void {
        try scope.sendHeaders(.ok, json.len);

        if (scope.request.line.method != .HEAD) {
            try scope.stream_writer.writeAll(json);
        }

        try scope.stream_writer.flush();
    }

    const Status = enum(u16) {
        ok = 200,
        bad_request = 400,
        not_found = 404,
        internal_server_error = 500,

        fn phrase(s: Status) []const u8 {
            return switch (s) {
                .ok => "OK",
                .bad_request => "Bad Request",
                .not_found => "Not Found",
                .internal_server_error => "Internal Server Error",
            };
        }
    };

    fn fail(scope: *const HttpRequestScope, status: Status) !void {
        try scope.sendHeaders(status, 0);
        try scope.stream_writer.flush();
    }

    fn sendHeaders(scope: *const HttpRequestScope, status: Status, content_length: usize) !void {
        try scope.stream_writer.print("HTTP/1.1 {d} {t}\r\n" ++
            "Connection: Keep-Alive\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n", .{ @backingInt(status), status, content_length });
    }
};

fn handleHttpClient(
    io: Io,
    gpa: Allocator,
    server: *Server,
    stream: Io.net.Stream,
) Io.Cancelable!void {
    defer stream.close(io);

    var per_request_arena_instance: std.heap.ArenaAllocator = .init(gpa);
    defer per_request_arena_instance.deinit();
    const per_request_arena = per_request_arena_instance.allocator();

    var read_buffer: [16384]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);

    var write_buffer: [16384]u8 = undefined;
    var stream_writer = stream.writer(io, &write_buffer);

    var target_buffer: [1024]u8 = undefined;

    while (http.Request.receive(&stream_reader.interface, .{
        .target_buffer = &target_buffer,
        .headers_limit = .limited(32),
    })) |request| {
        defer _ = per_request_arena_instance.reset(.retain_capacity);

        const scope: HttpRequestScope = .{
            .server = server,
            .request = request,
            .stream_writer = &stream_writer.interface,
            .arena = per_request_arena,
        };

        serveHttpRequest(io, gpa, &scope) catch |serve_err| switch (serve_err) {
            error.Canceled => |e| return e,
            error.WriteFailed => switch (stream_writer.err.?) {
                error.Canceled => |e| return e,
                else => return,
            },
            else => {
                log.err("failed to serve {q}: {t}", .{ request.line.path, serve_err });
                scope.fail(.internal_server_error) catch |fail_err| switch (fail_err) {
                    error.WriteFailed => switch (stream_writer.err.?) {
                        error.Canceled => |e| return e,
                        else => return,
                    },
                };

                continue;
            },
        };
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.ReadFailed => switch (stream_reader.err.?) {
            error.Canceled => |e| return e,
            else => {},
        },

        error.StreamTooLong,
        error.HttpRequestHeadersInvalid,
        error.HttpRequestTargetOversize,
        error.HeadersLimitExceeded,
        error.ContentLengthOversize,
        => {},
    }
}

const HttpPath = enum {
    @"/query_dispatch",
    @"/query_gateway",
    @"/nap_global/mdk/shield/api/loadConfig",
    @"/nap_global/account/ma-passport/api/appLoginByPassword",
    @"/nap_global/account/ma-passport/token/verifySToken",
    @"/nap_global/combo/granter/login/v2/login",
};

fn serveHttpRequest(io: Io, gpa: Allocator, scope: *const HttpRequestScope) !void {
    const path = std.meta.stringToEnum(HttpPath, scope.request.line.path) orelse
        return try scope.fail(.not_found);

    switch (path) {
        .@"/query_dispatch" => {
            if (mem.eql(
                u8,
                scope.request.line.getParamByNameOrEmpty("version"),
                scope.server.conf.version.tag,
            ))
                try scope.respondStatic(scope.server.query_dispatch_response)
            else
                try scope.respondStatic(scope.server.fallback_dispatch_response);
        },
        .@"/query_gateway" => {
            if (mem.eql(
                u8,
                scope.request.line.getParamByNameOrEmpty("version"),
                scope.server.conf.version.tag,
            ))
                try scope.respondStatic(scope.server.query_gateway_response)
            else
                try scope.respondStatic(scope.server.fallback_dispatch_response);
        },
        .@"/nap_global/mdk/shield/api/loadConfig" => {
            try scope.respondStatic(sdk.shield_config_json);
        },
        .@"/nap_global/account/ma-passport/api/appLoginByPassword" => {
            try loginByPassword(io, gpa, scope);
        },
        .@"/nap_global/account/ma-passport/token/verifySToken" => {
            try loginByToken(io, scope);
        },
        .@"/nap_global/combo/granter/login/v2/login" => {
            try comboGranter(scope);
        },
    }
}

fn loginByPassword(io: Io, gpa: Allocator, scope: *const HttpRequestScope) !void {
    const Request = struct {
        account: []u8,
        password: []u8,
    };

    const request = std.json.parseFromSliceLeaky(Request, scope.arena, scope.request.body, .{
        .ignore_unknown_fields = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => return try scope.fail(.bad_request),
    };

    const username = eldreda.rsa.decryptString(request.account) orelse
        return try scope.fail(.bad_request);

    const password = eldreda.rsa.decryptString(request.password) orelse
        return try scope.fail(.bad_request);

    const account_index, const account = try getAndVerifyAccountByPassword(
        io,
        gpa,
        scope,
        username,
        password,
    ) orelse return;

    try respondLoginSuccess(scope, account_index, &account);
}

fn loginByToken(io: Io, scope: *const HttpRequestScope) !void {
    const Request = struct {
        mid: []const u8,
        stoken: []const u8,
    };

    const request = std.json.parseFromSliceLeaky(Request, scope.arena, scope.request.body, .{
        .ignore_unknown_fields = true,
    }) catch
        return try scope.fail(.bad_request);

    const id_int = std.fmt.parseInt(u32, request.mid, 10) catch
        return try scope.fail(.bad_request);

    const account_index = sdk.Account.Index.fromUid(id_int) orelse
        return try scope.fail(.bad_request);

    try scope.server.sdk_account_storage_mutex.lock(io);
    defer scope.server.sdk_account_storage_mutex.unlock(io);

    const account = scope.server.sdk_account_storage.getByIndex(account_index) orelse
        return try scope.fail(.bad_request);

    if (!account.token.eql(request.stoken)) return try scope.fail(.bad_request);

    try respondLoginSuccess(scope, account_index, &account);
}

fn getAndVerifyAccountByPassword(
    io: Io,
    gpa: Allocator,
    scope: *const HttpRequestScope,
    username: []const u8,
    password: []const u8,
) !?struct { sdk.Account.Index, sdk.Account } {
    const random: std.Random.IoSource = .{ .io = io };

    const account_input: sdk.Account = .{
        .username = sdk.Account.Username.fromSlice(username) orelse {
            try scope.fail(.bad_request);
            return null;
        },
        .token = .random(random.interface()),
        .password = .init(random.interface(), password),
    };

    try scope.server.sdk_account_storage_mutex.lock(io);
    defer scope.server.sdk_account_storage_mutex.unlock(io);
    const storage = scope.server.sdk_account_storage;

    const result = try storage.getOrInsertByUsername(gpa, account_input);

    if (!result.found) try sdk.saveAccountStorage(
        io,
        scope.server.storage.root,
        sdk_account_storage_filename,
        storage,
    );

    const account_output = storage.getByIndex(result.index).?;
    if (!account_output.password.verify(password)) {
        try scope.fail(.bad_request);
        return null;
    }

    return .{ result.index, account_output };
}

fn respondLoginSuccess(
    scope: *const HttpRequestScope,
    account_index: sdk.Account.Index,
    account: *const sdk.Account,
) !void {
    var id_buf: ["4294967295".len]u8 = undefined;
    const id = mem.print(&id_buf, "{d}", .{account_index.toUid()}) catch unreachable;

    try scope.respond(.{
        .retcode = 0,
        .message = "OK",
        .data = .{
            .token = .{ .token_type = 1, .token = &account.token.chars },
            .user_info = .{
                .aid = id,
                .mid = id,
                .account_name = "",
                .email = account.username.toSlice(),
                .is_email_verify = 0,
                .area_code = "**",
                .mobile = "",
                .safe_area_code = "",
                .safe_mobile = "",
                .realname = "",
                .identity_code = "",
                .rebind_area_code = "",
                .rebind_mobile = "",
                .rebind_mobile_time = "228",
                .links = @as([]const u32, &.{}),
                .country = "RU",
                .password_time = "1337",
                .is_adult = 0,
                .unmasked_email = "",
                .unmasked_email_type = 0,
            },
            .ext_user_info = .{
                .guardian_email = "",
                .birth = "0",
            },
            .reactivate_action_ticket = "",
            .bind_email_action_ticket = "",
        },
    });
}

fn comboGranter(scope: *const HttpRequestScope) !void {
    const Request = struct {
        data: []const u8,

        const Data = struct {
            uid: []const u8,
            token: []const u8,
        };
    };

    const request = std.json.parseFromSliceLeaky(Request, scope.arena, scope.request.body, .{
        .ignore_unknown_fields = true,
    }) catch
        return try scope.fail(.bad_request);

    const data = std.json.parseFromSliceLeaky(Request.Data, scope.arena, request.data, .{
        .ignore_unknown_fields = true,
    }) catch
        return try scope.fail(.bad_request);

    try scope.respond(.{
        .retcode = 0,
        .message = "OK",
        .data = .{
            .account_type = 1,
            .combo_id = data.uid,
            .combo_token = data.token,
            .data = .{ .guest = false },
            .heartbeat = false,
            .open_id = data.uid,
        },
    });
}

fn waitShutdown(io: Io) Io.Cancelable!void {
    shutdown.setup(io);
    try shutdown.event.wait(io);
}

const shutdown = struct {
    var global_io: Io = undefined;
    var event: Io.Event = .unset;

    fn setup(io: Io) void {
        global_io = io;

        switch (native_os) {
            .windows => setupWindows(),
            else => setupPosix(),
        }
    }

    fn setupPosix() void {
        const rc = std.posix.system.sigaction(.INT, &.{
            .handler = .{ .handler = posixSigIntHandler },
            .mask = std.mem.zeroes(@FieldType(std.posix.system.Sigaction, "mask")),
            .flags = 0,
        }, null);

        switch (std.posix.errno(rc)) {
            .SUCCESS => {},
            else => |err| fatal(
                \\couldn't setup shutdown handler
                \\sigaction errno={t}
                \\
            , .{err}),
        }
    }

    fn posixSigIntHandler(_: std.posix.SIG) callconv(.c) void {
        event.set(global_io);
    }

    extern "kernel32" fn SetConsoleCtrlHandler(
        *const fn (std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL,
        std.os.windows.BOOL,
    ) callconv(.winapi) std.os.windows.BOOL;

    fn setupWindows() void {
        if (SetConsoleCtrlHandler(windowsCtrlHandler, .TRUE).toBool()) return;
        fatal("SetConsoleCtrlHandler failed: {t}", .{std.os.windows.GetLastError()});
    }

    fn windowsCtrlHandler(_: std.os.windows.DWORD) callconv(.winapi) std.os.windows.BOOL {
        event.set(global_io);
        return .TRUE;
    }
};

fn nextArg(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* >= args.len) return null;
    defer i.* += 1;
    return args[i.*];
}
