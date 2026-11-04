const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

const yuzuha = @import("yuzuha.zig");
const Configuration = yuzuha.Configuration;
const rsa = yuzuha.rsa;

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
    public_url_prefix: []const u8,
    gateway: struct { ip: []const u8, port: u16 },
};

pub fn buildQueryGatewayResponse(
    options: QueryGatewayResponseOptions,
) Allocator.Error![]const u8 {
    var scratch_arena_instance: std.heap.ArenaAllocator = .init(options.gpa);
    defer scratch_arena_instance.deinit();
    const scratch_arena = scratch_arena_instance.allocator();

    var cdn_conf_ext = options.cdn.hotfix;
    if (options.cdn.audio_overlay) |*audio_overlay| {
        try patchCdnHotfix(scratch_arena, &cdn_conf_ext, audio_overlay, options.public_url_prefix);
    }

    const data = try scratch_arena.print("{f}", .{std.json.fmt(.{
        .retcode = 0,
        .region_name = options.region_name,
        .title = options.region_title,
        .gateway = options.gateway,
        .cdn_conf_ext = cdn_conf_ext,
        .client_secret_key = options.client_secret_key,
        .region_ext = .{ .func_switch = .{ .isKcp = 0 } },
    }, .{})});
    const ciphertext = try rsa.encryptAlloc(scratch_arena, data);

    var sign: rsa.Block = undefined;
    rsa.server_private_key.sign(&sign, data);

    return try options.arena.print(
        \\{{"content":"{b64}","sign":"{b64}"}}
    , .{ ciphertext, &sign });
}

fn patchCdnHotfix(
    scratch_arena: Allocator,
    hotfix: *Configuration.Version.Cdn.Hotfix,
    overlay: *const Configuration.Version.Cdn.AudioOverlay,
    public_url_prefix: []const u8,
) Allocator.Error!void {
    const Md5FileEntry = struct {
        fileName: []const u8,
        fileSize: u64,
        fileMD5: []const u8,
    };

    const game_res_md5_files = std.json.parseFromSliceLeaky(
        []Md5FileEntry,
        scratch_arena,
        hotfix.game_res.md5_files,
        .{},
    ) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => return std.log.warn(
            "couldn't apply hotfix overlay, game_res.md5_files is not a valid json",
            .{},
        ),
    };

    for (game_res_md5_files) |*file_entry| {
        if (mem.eql(u8, file_entry.fileName, "audio_version")) {
            file_entry.fileSize = overlay.audio_version_size;
            file_entry.fileMD5 = overlay.audio_version_md5;
        }
    }

    hotfix.game_res.md5_files = try scratch_arena.print(
        "{f}",
        .{std.json.fmt(game_res_md5_files, .{})},
    );

    const game_res_base_url_path = getUrlPath(hotfix.game_res.base_url);
    hotfix.game_res.base_url = try scratch_arena.print(
        "{s}/{s}",
        .{ public_url_prefix, game_res_base_url_path },
    );
}

fn getUrlPath(url: []const u8) []const u8 {
    var cut_url = url;
    var cut_times: usize = 3;

    while (cut_times > 0) : (cut_times -= 1) {
        _, cut_url = mem.cutScalar(u8, cut_url, '/') orelse break;
    }

    return cut_url;
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
