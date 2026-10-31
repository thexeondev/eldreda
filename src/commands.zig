const std = @import("std");

const eldreda = @import("eldreda.zig");
const Session = eldreda.Session;
const protobuf = eldreda.protobuf;

const log = std.log.scoped(.@"eldreda::commands");

const namespaces: []const type = &.{
    @import("commands/player.zig"),
    @import("commands/avatar.zig"),
    @import("commands/item.zig"),
    @import("commands/quest.zig"),
    @import("commands/misc.zig"),
    @import("commands/world.zig"),
    @import("commands/map.zig"),
};

const HandlerFn = *const fn (*Session) Session.Error!void;

const cmd_count: usize = 10_000;
const handlers: *const [cmd_count]?HandlerFn = handlers: {
    var array: [cmd_count]?HandlerFn = @splat(null);
    for (namespaces) |namespace| {
        for (@typeInfo(namespace).@"struct".decl_names) |decl_name| {
            if (!@hasDecl(protobuf.gen, decl_name)) continue;

            const cmd_id = @field(protobuf.gen, decl_name).cmd_id;
            if (array[cmd_id] != null) @compileError("duplicated handler for " ++ decl_name);
            array[cmd_id] = &@field(namespace, decl_name);
        }
    }

    const final = array;
    break :handlers &final;
};

pub const ExecuteError = Session.Error || error{CommandIdIllegal};

pub fn execute(session: *Session) ExecuteError!void {
    if (session.command.id >= cmd_count) return error.CommandIdIllegal;

    if (handlers[session.command.id]) |handlerFn| {
        try handlerFn(session);
    } else if (session.sink.ack_packet_id != 0) {
        log.debug("unhandled command id: {d}", .{session.command.id});
        try session.sink.respond(protobuf.gen.DummyScRsp, &.{});
    }
}
