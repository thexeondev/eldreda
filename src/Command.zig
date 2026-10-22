const Command = @This();

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;

const eldreda = @import("eldreda.zig");
const protobuf = eldreda.protobuf;
const PacketHead = eldreda.protobuf.gen.PacketHead;

id: u16,
head: []u8,
body: []u8,

pub const ReceiveError = Io.Reader.Error || error{
    MagicMismatch,
    CommandOversize,
};

pub const header_overhead = 12;
const tail_overhead = 4;

const head_magic: *const [4]u8 = &.{ 0x01, 0x23, 0x45, 0x67 };
const tail_magic: *const [4]u8 = &.{ 0x89, 0xab, 0xcd, 0xef };

/// Asserts `reader.buffer` is at least `header_overhead`.
pub fn receive(reader: *Io.Reader) ReceiveError!Command {
    const header = try reader.peek(header_overhead);
    const head_len: usize = mem.readInt(u16, header[6..8], .big);
    const body_len: usize = mem.readInt(u32, header[8..12], .big);

    const full_len: usize = header_overhead + head_len + body_len + tail_overhead;
    if (reader.buffer.len < full_len) return error.CommandOversize;

    const bytes = try reader.take(full_len);
    return .fromBytes(bytes);
}

/// Asserts valid length prefixes.
pub fn fromBytes(bytes: []u8) error{MagicMismatch}!Command {
    if (!mem.startsWith(u8, bytes, head_magic)) return error.MagicMismatch;

    const head_len = mem.readInt(u16, bytes[6..8], .big);
    const body_len = mem.readInt(u32, bytes[8..12], .big);

    assert(bytes.len == header_overhead + head_len + body_len + tail_overhead);

    if (!mem.endsWith(u8, bytes, tail_magic)) return error.MagicMismatch;

    return .{
        .id = mem.readInt(u16, bytes[4..6], .big),
        .head = bytes[header_overhead..][0..head_len],
        .body = bytes[header_overhead + head_len ..][0..body_len],
    };
}

pub fn decodeBody(command: *const Command, comptime Body: type) protobuf.DecodeError!Body {
    return protobuf.decode(Body, command.body);
}

pub const EncodeOptions = struct {
    buffer: []u8,
    decrypt_vector: *const [4096]u8,
    head: PacketHead,
};

pub const EncodeError = error{EncodeBufferExceeded};

/// Returns number of bytes written into `options.buffer`.
pub fn encode(comptime Body: type, body: *const Body, options: EncodeOptions) EncodeError!usize {
    const head_len = protobuf.encodingLength(PacketHead, &options.head);
    const body_len = protobuf.encodingLength(Body, body);
    const full_len = header_overhead + head_len + body_len + tail_overhead;

    if (options.buffer.len < full_len) return error.EncodeBufferExceeded;
    errdefer comptime unreachable;

    const buffer = options.buffer[0..full_len];
    @memcpy(buffer[0..4], head_magic);
    mem.writeInt(u16, buffer[4..6], Body.cmd_id, .big);
    mem.writeInt(u16, buffer[6..8], @intCast(head_len), .big);
    mem.writeInt(u32, buffer[8..12], @intCast(body_len), .big);
    @memcpy(buffer[buffer.len - 4 ..][0..4], tail_magic);

    const head_buffer = buffer[12..][0..head_len];
    var head_writer: Io.Writer = .fixed(head_buffer);
    protobuf.encode(PacketHead, &options.head, &head_writer) catch |err| switch (err) {
        error.WriteFailed => unreachable,
    };

    const body_buffer = buffer[12 + head_len ..][0..body_len];
    var body_writer: Io.Writer = .fixed(body_buffer);
    protobuf.encode(Body, body, &body_writer) catch |err| switch (err) {
        error.WriteFailed => unreachable,
    };

    xor(body_buffer, options.decrypt_vector);
    return full_len;
}

pub fn xor(body: []u8, vector: *const [4096]u8) void {
    for (body, 0..) |*byte, index|
        byte.* ^= vector[index % 4096];
}
