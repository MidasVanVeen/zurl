const std = @import("std");

const Scheme = enum {http, https};

const Configuration = struct {
    scheme: Scheme,
    host: []const u8,
    port: u16,
    remote_path: []const u8,
    headers: std.StringArrayHashMap([]const u8),
    outfile: std.fs.File,
};

/// Parses command-line arguments as a Configuration struct
fn parseArguments(allocator: std.mem.Allocator) !Configuration {
    var args = try std.process.argsAlloc(allocator);
    var args_it = try std.process.argsWithAllocator(allocator);

    _ = args_it.skip();
    var index: u32 = 1;

    var scheme = Scheme.http;
    var host: []const u8 = undefined;
    var port: u16 = 80;
    var remote_path: []const u8 = "/";
    var headers = std.StringArrayHashMap([]const u8).init(allocator);
    var outfile = std.io.getStdOut();
    while (args_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h")) {
            host = args[index+1];
        }
        if (std.mem.eql(u8, arg, "-p")) {
            port = try std.fmt.parseUnsigned(u16, args[index+1], 10);
        }
        if (std.mem.eql(u8, arg, "--remote-path")) {
            remote_path = args[index+1];
        }
        if (std.mem.eql(u8, arg, "-u")) {
            const uri = try std.Uri.parse(args[index+1]);
            host = uri.host;
            port = uri.port;
            remote_path = uri.path;
            if (std.mem.eql(u8, uri.scheme, "https")) {
                scheme = Scheme.https;
            }
        }
        if (std.mem.eql(u8, arg, "-H")) {
            var split = std.mem.split(u8, args[index+1], "','");
            var first = split.first();
            var last: []const u8 = undefined;
            while (split.next()) |p| {
                last = p;
            }
            split.index = 0;
            while (split.next()) |pair| {
                var strippedpair: []const u8 = undefined;
                if (std.mem.eql(u8, pair, first)) {
                    strippedpair = pair[1..];
                } else if (std.mem.eql(u8, pair, last)) {
                    strippedpair = pair[0..pair.len-1];
                } else {
                    strippedpair = pair;
                }
                var pairsplit = std.mem.split(u8, strippedpair, "':'");
                try headers.put(pairsplit.first(), pairsplit.rest());
            }
        }
        index += 1;
    }

    return Configuration{
        .scheme=scheme,
        .host=host,
        .port=80,
        .remote_path=remote_path,
        .headers=headers,
        .outfile=outfile,
    };
}

/// Method for sending a request and writing the output to a file, for example, stdout.
///
/// @param host: the host to send the request to, can be an ip or a hostname.
/// @param port: the port used for the tcp connection.
/// @param remote_path: the path used by the http request.
/// @param headers: a StringArrayHashMap containing the header pairs.
/// @param outfile: file descriptor to write the response to.
///
/// @returns usize, the amount of bytes recieved.
pub fn request(allocator: std.mem.Allocator, scheme: Scheme, host: []const u8, port: u16, remote_path: []const u8, headers: std.StringArrayHashMap([]const u8), outfile: std.fs.File) !usize {
    if (scheme == Scheme.http) {
        var requestBuffer: [1024]u8 = undefined;
        {
            var stream = std.io.fixedBufferStream(&requestBuffer);
            var writer = stream.writer();
            try std.fmt.format(writer, "GET {s} HTTP/1.1\r\nHost: {s}\r\nConnection: close\r\n", .{remote_path, host});

            // write all the headers to the requestBuffer
            var it = headers.iterator();
            while (it.next()) |pair| {
                try std.fmt.format(writer, "{s}: {s}\r\n", .{pair.key_ptr.*, pair.value_ptr.*});
            }

            // add the extra \r\n at the end
            try std.fmt.format(writer, "\r\n", .{});
        }

        var conn = try std.net.tcpConnectToHost(allocator, host, port);
        defer conn.close();

        // make the request
        _ = try conn.write(&requestBuffer);

        // create a buffered writer of the outfile
        var bw = std.io.bufferedWriter(outfile.writer());
        var writer = bw.writer();

        var total_bytes: usize = 0;
        var buf: [1024]u8 = undefined;

        // loops while the tcp connection is recieving data
        while (true) {
            const byte_count = try conn.read(&buf);
            if (byte_count == 0) break;

            _ = try writer.write(&buf);
            total_bytes += byte_count;
        }
        try bw.flush();
        return total_bytes;
    } else {
        return 0;
    }
}

/// Wrapper for request that accepts a Configuration struct
pub fn requestWithConfiguration(allocator: std.mem.Allocator, config: Configuration) !usize {
    return try request(allocator, config.scheme, config.host, config.port, config.remote_path, config.headers, config.outfile);
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const config = try parseArguments(arena.allocator());
    const bytes = try requestWithConfiguration(arena.allocator(), config);
    std.debug.print("{d} bytes recieved.\n", .{bytes});
}
