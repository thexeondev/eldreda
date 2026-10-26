const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const process = std.process;
const Allocator = std.mem.Allocator;

const eldreda = @import("eldreda");
const Player = eldreda.Player;
const templates = eldreda.templates;

const log = std.log.scoped(.@"eldreda-pack-player");

pub fn usage(io: Io) noreturn {
    Io.File.stdout().writeStreamingAll(io,
        \\Usage: eldreda pack-player [input] [options]
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
        break :default_path try arena.print("{s}.bin", .{Io.Dir.path.stem(basename)});
    };

    var text_map: templates.Text.Map = try .init(gpa);
    defer text_map.deinit(gpa);

    var name_map: Player.Zon.NameMap = try .init(gpa, &text_map);
    defer name_map.deinit(gpa);

    const player_zon_contents = Io.Dir.cwd().readFileAllocOptions(
        io,
        input_path,
        arena,
        .unlimited,
        .@"1",
        0,
    ) catch |err| switch (err) {
        error.FileNotFound => {
            log.err("input file {q} doesn't exist", .{input_path});
            process.exit(1);
        },
        else => |e| {
            log.err("failed to open input file {q}: {t}", .{ input_path, e });
            process.exit(1);
        },
    };

    var player_zon_diag: std.zon.parse.Diagnostics = undefined;
    const player_zon = std.zon.parse.fromSlice(Player.Zon, .{
        .gpa = gpa,
        .arena = arena,
        .source = player_zon_contents,
        .diagnostics = &player_zon_diag,
    }) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        error.ParseZon => {
            log.err("failed to parse input file:\n{f}", .{player_zon_diag.fmt(input_path)});
            process.exit(1);
        },
    };

    var pack_diag: Player.Zon.PackDiagnostics = undefined;
    var player = player_zon.pack(&name_map, &pack_diag) catch |err| switch (err) {
        error.CheckDiagnostics => {
            log.err("player data is invalid:\n{f}", .{&pack_diag});
            process.exit(1);
        },
    };

    try player.saveToFile(io, .cwd(), output_path);

    log.info("created file {q}", .{output_path});
}

fn nextArg(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* >= args.len) return null;
    defer i.* += 1;
    return args[i.*];
}
