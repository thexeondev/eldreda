const Session = @This();

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const eldreda = @import("eldreda.zig");
const Command = eldreda.Command;
const protobuf = eldreda.protobuf;
const Player = eldreda.Player;

time: Io.Timestamp,
command: Command,
sink: Sink,
player_uid: u32,
player: *Player,
player_needs_save: bool,

pub const Error = protobuf.DecodeError || Command.EncodeError;

/// Each handler should call this function in one exact place.
pub fn playerModified(session: *Session) void {
    assert(!session.player_needs_save); // see doc comment for `playerModified`
    session.player_needs_save = true;
}

pub const Sink = struct {
    buffer: []u8,
    bytes_written: usize = 0,
    decrypt_vector: *const [4096]u8,

    packet_id_counter: *u32,
    ack_packet_id: u32,

    pub fn respond(sink: *Sink, comptime Body: type, body: *const Body) Command.EncodeError!void {
        const packet_id = sink.packet_id_counter.*;
        sink.packet_id_counter.* +%= 1;

        sink.bytes_written += try Command.encode(Body, body, .{
            .head = .{ .packet_id = packet_id, .ack_packet_id = sink.ack_packet_id },
            .buffer = sink.buffer[sink.bytes_written..],
            .decrypt_vector = sink.decrypt_vector,
        });
    }

    pub fn notify(sink: *Sink, comptime Body: type, body: *const Body) Command.EncodeError!void {
        const packet_id = sink.packet_id_counter.*;
        sink.packet_id_counter.* +%= 1;

        sink.bytes_written += try Command.encode(Body, body, .{
            .head = .{ .packet_id = packet_id, .ack_packet_id = 0 },
            .buffer = sink.buffer[sink.bytes_written..],
            .decrypt_vector = sink.decrypt_vector,
        });
    }

    pub const RespondMinimalOptions = struct {
        retcode: protobuf.Retcode,
    };

    pub fn respondMinimal(
        sink: *Sink,
        comptime message_name: @EnumLiteral(),
        options: RespondMinimalOptions,
    ) Command.EncodeError!void {
        const Message = if (@hasDecl(protobuf.gen, @tagName(message_name)))
            @field(protobuf.gen, @tagName(message_name))
        else
            protobuf.gen.DummyScRsp;

        return respond(sink, Message, &.{ .retcode = @backingInt(options.retcode) });
    }
};
