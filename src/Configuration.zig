const Configuration = @This();

const std = @import("std");
const Io = std.Io;
const fatal = std.process.fatal;
const Allocator = std.mem.Allocator;

pub const defaults: Configuration = @import("defaults/eldreda.zon");

version: Version,
client_secret_key: []const u8,
gateway_initial_decrypt_vector: *const [4096]u8,

pub const Version = struct {
    tag: []const u8,
    cdn: Cdn,

    pub const Cdn = struct {
        design_data: struct {
            base_url: []const u8,
            data_revision: []const u8,
            md5_files: []const u8,
        },
        game_res: struct {
            audio_revision: []const u8,
            base_url: []const u8,
            branch: []const u8,
            md5_files: []const u8,
            res_revision: []const u8,
        },
        silence_data: struct {
            base_url: []const u8,
            md5_files: []const u8,
            silence_revision: []const u8,
        },
    };
};

pub const UpdateFromFileOptions = struct {
    /// Used for scratch allocations.
    gpa: Allocator,
    /// Used for config contents.
    arena: Allocator,
    path_cwd_relative: []const u8,
    exit_if_not_found: bool,
};

pub fn updateFromFileOrExit(
    conf: *Configuration,
    io: Io,
    options: UpdateFromFileOptions,
) Io.Cancelable!void {
    const source = Io.Dir.cwd().readFileAllocOptions(
        io,
        options.path_cwd_relative,
        options.arena,
        .unlimited,
        .@"1",
        0,
    ) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound => {
            if (!options.exit_if_not_found) return;
            fatal("config file {q} doesn't exist", .{options.path_cwd_relative});
        },
        else => fatal("failed to read {q}: {t}", .{ options.path_cwd_relative, err }),
    };

    var diag: std.zon.parse.Diagnostics = undefined;
    std.zon.parse.updateFromSlice(Configuration, conf, .{
        .gpa = options.gpa,
        .arena = options.arena,
        .source = source,
        .diagnostics = &diag,
        .ignore_unknown_fields = false,
    }) catch |err| switch (err) {
        error.ParseZon => diag.fatal(options.path_cwd_relative),
        error.OutOfMemory => fatal(
            "parsing file {q} caused out of memory",
            .{options.path_cwd_relative},
        ),
    };
}
