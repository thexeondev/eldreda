const std = @import("std");
const Io = std.Io;
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "run the tests");
    const serve_step = b.step("serve", "start the server");

    const module = b.addModule("eldreda", .{
        .root_source_file = b.path("src/eldreda.zig"),
        .target = target,
        .optimize = optimize,
    });
    convertTemplates(b, module);
    importFile(b, module, "defaults/eldreda.zon");
    const module_tests = b.addTest(.{ .root_module = module });
    test_step.dependOn(&b.addRunArtifact(module_tests).step);

    const exe = b.addExecutable(.{
        .name = "eldreda",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "eldreda", .module = module }},
        }),
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.addPassthruArgs();
    serve_step.dependOn(&run_exe.step);

    if (maybeCompileProto(b)) |step| {
        exe.step.dependOn(step);
        module_tests.step.dependOn(step);
    }
}

fn importFile(b: *Build, module: *Build.Module, path: []const u8) void {
    module.addAnonymousImport(path, .{ .root_source_file = b.path(path) });
}

fn maybeCompileProto(b: *Build) ?*Build.Step {
    b.root.access(b.graph.io, "proto", .{}) catch return null;
    b.dependOnDirectoryContents(b.path("proto"));

    const compiler = b.addExecutable(.{
        .name = "eldreda-compile-proto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/compile-proto.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run = b.addRunArtifact(compiler);
    run.expectExitCode(0);

    const proto_dir = b.root.openDir(b.graph.io, "proto", .{ .iterate = true }) catch |err|
        std.debug.panic("failed to open proto dir: {t}", .{err});
    defer proto_dir.close(b.graph.io);

    var entries = proto_dir.iterateAssumeFirstIteration();
    while (entries.next(b.graph.io) catch @panic("failed to read dir")) |entry| {
        if (entry.kind != .file) continue;
        const path = b.fmt("proto/{s}", .{entry.name});
        run.addFileArg2(b.path(path), .{});
    }

    const update = b.addUpdateSourceFiles();
    update.addCopyFileToSource(
        run.captureStdOut(.{ .basename = "generated.zig" }),
        "src/protobuf/generated.zig",
    );
    return &update.step;
}

const template_dir_path = "assets/TemplateTb";

fn convertTemplates(b: *Build, eldreda_module: *Build.Module) void {
    b.dependOnDirectoryContents(b.path(template_dir_path));

    const converter = b.addExecutable(.{
        .name = "eldreda-convert-templatetb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/convert-templatetb.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const convert = b.addRunArtifact(converter);
    convert.expectExitCode(0);
    convert.addDirectoryArg2(b.path(template_dir_path), .{});
    const converted_dir_path = convert.addOutputDirectoryArg2("TemplateTb", .{});

    var template_dir = b.root.openDir(b.graph.io, template_dir_path, .{ .iterate = true }) catch |err|
        std.debug.panic("failed to open {q}: {t}", .{ template_dir_path, err });
    defer template_dir.close(b.graph.io);

    var template_dir_entries = template_dir.iterateAssumeFirstIteration();
    while (template_dir_entries.next(b.graph.io) catch @panic("failed to read dir")) |entry| {
        if (entry.kind != .file) continue;

        const converted_file_name = Io.Dir.path.stem(entry.name);
        const converted_file_path = converted_dir_path.path(b, converted_file_name);
        eldreda_module.addAnonymousImport(converted_file_name, .{
            .root_source_file = converted_file_path,
        });

        convert.addFileInput(b.path(b.fmt("assets/TemplateTb/{s}", .{entry.name})));
    }
}
