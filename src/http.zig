const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const ascii = std.ascii;

pub const supported_version = "HTTP/1.1";

pub const Request = struct {
    line: Line,
    body: []u8,

    pub const ReceiveOptions = struct {
        /// The request target (path + query) will be copied into here.
        target_buffer: []u8,
        headers_limit: Io.Limit,
    };

    pub const ReceiveError = TakeLineError || Line.ParseError || HeadersLimitError || error{
        ContentLengthOversize,
    };

    pub const HeadersError = error{HttpRequestHeadersInvalid};

    pub const HeadersLimitError = error{HeadersLimitExceeded};

    const content_length_prefix = "content-length: ";

    pub fn receive(reader: *Io.Reader, options: ReceiveOptions) ReceiveError!Request {
        const request_line_string = try takeLine(reader);
        const request_line: Line = try .parse(request_line_string, options.target_buffer);

        var headers_limit = options.headers_limit;
        var content_length_maybe: ?u32 = null;

        while (true) {
            headers_limit = headers_limit.subtract(1) orelse break;

            const header_line = try takeLine(reader);
            if (header_line.len == 0) break;

            if (ascii.startsWithIgnoreCase(header_line, content_length_prefix)) {
                const value = header_line[content_length_prefix.len..];
                if (content_length_maybe != null) return error.HttpRequestHeadersInvalid;

                content_length_maybe = std.fmt.parseInt(u32, value, 10) catch
                    return error.HttpRequestHeadersInvalid;
            }
        } else return error.HeadersLimitExceeded;

        const body: []u8 = if (content_length_maybe) |content_length| take: {
            if (content_length > reader.buffer.len)
                return error.ContentLengthOversize;

            break :take try reader.take(content_length);
        } else &.{};

        return .{ .line = request_line, .body = body };
    }

    pub const Line = struct {
        method: Method,
        path: []const u8,
        query: []const u8,

        pub const ParseError = HeadersError || error{HttpRequestTargetOversize};

        pub fn parse(input: []const u8, target_buffer: []u8) ParseError!Line {
            var it = mem.tokenizeScalar(u8, input, ' ');
            const method_string = it.next() orelse
                return error.HttpRequestHeadersInvalid;
            const method = std.meta.stringToEnum(Method, method_string) orelse
                return error.HttpRequestHeadersInvalid;

            const target_string_input = it.next() orelse
                return error.HttpRequestHeadersInvalid;
            if (target_string_input.len > target_buffer.len)
                return error.HttpRequestTargetOversize;

            const version_string = it.next() orelse
                return error.HttpRequestHeadersInvalid;
            if (!mem.eql(u8, supported_version, version_string))
                return error.HttpRequestHeadersInvalid;

            const target = target_buffer[0..target_string_input.len];
            @memcpy(target, target_string_input);

            const path, const query = mem.cutScalar(u8, target, '?') orelse .{ target, "" };
            return .{ .method = method, .path = path, .query = query };
        }

        pub const Method = enum {
            GET,
            POST,
            HEAD,
        };

        pub fn getParamByNameOrEmpty(
            line: *const Line,
            get_name: []const u8,
        ) []const u8 {
            var it = mem.splitScalar(u8, line.query, '&');
            while (it.next()) |part| {
                const param_name, const param_value = mem.cutScalar(u8, part, '=') orelse
                    continue;

                if (mem.eql(u8, param_name, get_name)) return param_value;
            }

            return "";
        }
    };

    const TakeLineError = Io.Reader.DelimiterError || HeadersError;

    fn takeLine(reader: *Io.Reader) TakeLineError![]const u8 {
        const line = try reader.takeDelimiterInclusive('\n');
        if (!mem.endsWith(u8, line, "\r\n")) return error.HttpRequestHeadersInvalid;

        return line[0 .. line.len - 2];
    }
};
