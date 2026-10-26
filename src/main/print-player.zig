const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;
const Allocator = std.mem.Allocator;

const eldreda = @import("eldreda");
const Player = eldreda.Player;
const templates = eldreda.templates;

const log = std.log.scoped(.@"eldreda-print-player");

fn usage(io: Io) noreturn {
    Io.File.stdout().writeStreamingAll(io,
        \\Usage: eldreda print-player [input] [options]
        \\
        \\Options:
        \\  --help, -h  Print this help and exit
        \\  --output    Output file path; default is to put it in current working directory
        \\
    ) catch {};
    process.exit(0);
}

pub fn run(io: Io, gpa: Allocator, args_slice: []const []const u8) !void {
    var input_path_maybe: ?[]const u8 = null;
    var output_path_maybe: ?[]const u8 = null;

    var args_i: usize = 0;
    while (nextArg(args_slice, &args_i)) |arg| {
        if (!mem.startsWith(u8, arg, "-")) {
            if (input_path_maybe == null) {
                input_path_maybe = arg;
            } else {
                log.err("unexpected trailing argument: {q}", .{arg});
                usage(io);
            }
        } else if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            usage(io);
        } else if (mem.cutPrefix(u8, arg, "--output=")) |output_path_string| {
            output_path_maybe = output_path_string;
        } else {
            log.err("unrecognized argument: {q}", .{arg});
            usage(io);
        }
    }

    var arena_instance: std.heap.ArenaAllocator = .init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const input_path = input_path_maybe orelse {
        log.err("no input file specified", .{});
        usage(io);
    };

    const output_path = output_path_maybe orelse default_path: {
        const basename = Io.Dir.path.basename(input_path);
        break :default_path try arena.print("{s}.zon", .{Io.Dir.path.stem(basename)});
    };

    var text_map: templates.Text.Map = try .init(gpa);
    defer text_map.deinit(gpa);

    var name_map: Player.Zon.NameMap = try .init(gpa, &text_map);
    defer name_map.deinit(gpa);

    var player: Player = undefined;
    var player_diag: Player.LoadDiagnostics = undefined;
    player.loadFromFile(io, .{
        .dir = .cwd(),
        .sub_path = input_path,
        .diagnostics = &player_diag,
    }) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound => {
            log.err("input file {q} doesn't exist", .{input_path});
            process.exit(1);
        },
        error.CheckDiagnostics => {
            log.err("failed to read player save file:\n{f}", .{&player_diag});
            process.exit(1);
        },
    };

    const player_zon: Player.Zon = try .init(arena, &name_map, &player);

    const output_file = Io.Dir.cwd().createFile(io, output_path, .{}) catch |err| {
        log.err("failed to create output file {q}: {t}", .{ output_path, err });
        process.exit(1);
    };
    defer output_file.close(io);

    var file_write_buffer: [4096]u8 = undefined;
    var file_writer = output_file.writer(io, &file_write_buffer);

    // std.zon.stringify.serialize kills itself because of `typeIsRecursiveInner` checks
    // that exceed eval branch quota. Nothing is recursive about our types, but these safety checks
    // are not considering raising eval branch quota at all.
    try std.zon.stringify.serializeArbitraryDepth(player_zon, .{}, &file_writer.interface);
    try file_writer.interface.flush();

    log.info("created file {q}", .{output_path});
}

fn nextArg(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* >= args.len) return null;
    defer i.* += 1;
    return args[i.*];
}
