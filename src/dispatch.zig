const std = @import("std");
const Allocator = std.mem.Allocator;

const eldreda = @import("eldreda.zig");
const Configuration = eldreda.Configuration;
const rsa = eldreda.rsa;

pub const QueryDispatchResponseOptions = struct {
    /// Used for scratch allocations.
    gpa: Allocator,
    /// Used for the resulting string allocation.
    arena: Allocator,
    region_name: []const u8,
    region_title: []const u8,
    public_url_prefix: []const u8,
};

pub fn buildQueryDispatchResponse(
    options: QueryDispatchResponseOptions,
) Allocator.Error![]const u8 {
    const gpa = options.gpa;

    const dispatch_url = try gpa.print("{s}/query_gateway", .{options.public_url_prefix});
    defer gpa.free(dispatch_url);

    const response = .{
        .retcode = 0,
        .region_list = &.{.{
            .retcode = 0,
            .name = options.region_name,
            .title = options.region_title,
            .dispatch_url = dispatch_url,
            .game_biz = "nap_global",
            .area = 2,
            .env = 2,
        }},
    };

    return try options.arena.print("{f}", .{std.json.fmt(response, .{})});
}

pub const QueryGatewayResponseOptions = struct {
    /// Used for scratch allocations.
    gpa: Allocator,
    /// Used for the resulting string allocation.
    arena: Allocator,
    region_name: []const u8,
    region_title: []const u8,
    cdn: *const Configuration.Version.Cdn,
    client_secret_key: []const u8,
    gateway: struct { ip: []const u8, port: u16 },
};

pub fn buildQueryGatewayResponse(
    options: QueryGatewayResponseOptions,
) Allocator.Error![]const u8 {
    const gpa = options.gpa;

    const data = try gpa.print("{f}", .{std.json.fmt(.{
        .retcode = 0,
        .region_name = options.region_name,
        .title = options.region_title,
        .gateway = options.gateway,
        .cdn_conf_ext = options.cdn,
        .client_secret_key = options.client_secret_key,
        .region_ext = .{ .func_switch = .{ .isKcp = 0 } },
    }, .{})});
    defer gpa.free(data);

    const ciphertext = try rsa.encryptAlloc(gpa, data);
    defer gpa.free(ciphertext);

    var sign: rsa.Block = undefined;
    rsa.server_private_key.sign(&sign, data);

    return try options.arena.print(
        \\{{"content":"{b64}","sign":"{b64}"}}
    , .{ ciphertext, &sign });
}

const FallbackResponseOptions = struct {
    /// Used for scratch allocations.
    gpa: Allocator,
    /// Used for the resulting string allocation.
    arena: Allocator,
    supported_version: []const u8,
};

pub fn buildFallbackResponse(
    options: FallbackResponseOptions,
) Allocator.Error![]const u8 {
    const gpa = options.gpa;

    const message = try gpa.print(
        \\Your game version is not supported.
        \\Supported version: {s}
    , .{options.supported_version});
    defer gpa.free(message);

    return try options.arena.print("{f}", .{std.json.fmt(.{
        .retcode = 72,
        .msg = message,
    }, .{})});
}
