const Session = @This();

const std = @import("std");
const Io = std.Io;

const yuzuha = @import("yuzuha.zig");
const Command = yuzuha.Command;
const protobuf = yuzuha.protobuf;
const Player = yuzuha.Player;

command: Command,
player: Player,
time: Io.Timestamp,
sink: Sink,

pub const Error = protobuf.DecodeError || Command.EncodeError;

/// Deprecated.
pub fn playerModified(session: *Session) void {
    session.player.needs_save = true;
}

pub fn notify(session: *Session) Command.EncodeError!void {
    if (session.player.buildPlayerSyncScNotify()) |sync|
        try session.sink.notify(protobuf.gen.PlayerSyncScNotify, &sync);
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
