const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const Account = @import("sdk/Account.zig");

pub const shield_config_json =
    \\{"retcode":0,"message":"OK","data":{"id":31,"game_key":"nap_cn","client":"PC","identity":"I_IDENTITY","guest":false,"ignore_versions":"","scene":"S_NORMAL","name":"Nap","disable_regist":false,"enable_email_captcha":false,"thirdparty":[],"disable_mmt":false,"server_guest":false,"thirdparty_ignore":{},"enable_ps_bind_account":false,"thirdparty_login_configs":{},"initialize_firebase":false,"bbs_auth_login":false,"bbs_auth_login_ignore":[],"fetch_instance_id":false,"enable_flash_login":false,"enable_logo_18":false,"logo_height":"0","logo_width":"0","enable_cx_bind_account":false,"firebase_blacklist_devices_switch":false,"firebase_blacklist_devices_version":0,"hoyolab_auth_login":false,"hoyolab_auth_login_ignore":[],"hoyoplay_auth_login":true,"enable_douyin_flash_login":false,"enable_age_gate":false,"enable_age_gate_ignore":[]}}
;

pub fn loadAccountStorageFromFileIfExists(
    io: Io,
    gpa: Allocator,
    dir: Io.Dir,
    sub_path: []const u8,
) !Account.Storage {
    const file = dir.openFile(io, sub_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return .empty,
        else => |e| return e,
    };
    defer file.close(io);

    const file_size_in_bytes = try file.length(io);
    const accounts_count = Account.Storage.countFromByteCount(file_size_in_bytes);

    var storage: Account.Storage = try .initCapacity(gpa, accounts_count);
    errdefer storage.deinit(gpa);

    // with vectored read this buffer might be not useful,
    // but some operating systems may not support
    // vectored I/O, for these it is possible
    // to lower the amount of syscalls
    // by saving data to this extra buffer especially for small files.
    var file_reader_buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &file_reader_buffer);

    storage.list.len = accounts_count;
    var vector = storage.writableVector();
    file_reader.interface.readVecAll(&vector) catch |err| switch (err) {
        error.EndOfStream => |e| return e,
        error.ReadFailed => return file_reader.err.?,
    };

    storage.reIndexAssumeFirstIndexing();
    return storage;
}

pub fn saveAccountStorage(io: Io, dir: Io.Dir, sub_path: []const u8, storage: *Account.Storage) !void {
    var af = try dir.createFileAtomic(io, sub_path, .{ .replace = true });
    defer af.deinit(io);

    var file_writer_buffer: [1024]u8 = undefined;
    var file_writer = af.file.writer(io, &file_writer_buffer);

    var vector = storage.readableVector();
    file_writer.interface.writeVecAll(&vector) catch return file_writer.err.?;
    file_writer.interface.flush() catch return file_writer.err.?;

    try af.replace(io);
}
