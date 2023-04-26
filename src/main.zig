const std = @import("std");
const parseArgs = @import("argparse.zig").parseArgs;

const Args = struct {
    url: []const u8,
    headers: ?[]const u8,
    proxy: ?[]const u8,
    method: ?[]const u8,
};

const Configuration = struct {
    url: std.Uri,
    host: []const u8,
    port: u16,
    // headers are initialized by parsing json passed as a command-line parameter.
    headers: ?std.http.Headers,
    proxy: ?std.http.Client.HttpProxy,
    method: ?std.http.Method,
    protocol: std.http.Client.Connection.Protocol,
};

/// Parses command-line arguments as a Configuration struct
fn argsToConfiguration(allocator: std.mem.Allocator, args: Args) !Configuration {
    var url = try std.Uri.parse(args.url);
    var config: Configuration = .{
        .url=url,
        .host = url.host.?,
        .port = url.port orelse 80,
        .headers = null,
        .proxy = null,
        .method = null,
        .protocol = .plain,
    };

    if (std.mem.eql(u8, config.url.scheme, "https")) {
        config.port = 443;
        config.protocol = .tls;
    }

    if (args.headers) |_headers| {
        config.headers = std.http.Headers.init(allocator);
        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();
        var tree = try parser.parse(_headers);
        var it = tree.root.Object.iterator();
        while (it.next()) |pair| {
            try config.headers.?.append(pair.key_ptr.*, pair.value_ptr.*.String);
        }
    }

    if (args.proxy) |_proxy| {
        config.proxy = std.http.Client.HttpProxy{.host="",.protocol=.plain};
        var proxyuri = try std.Uri.parse(_proxy);
        if (std.mem.eql(u8, proxyuri.scheme, "https")) {
            config.proxy.?.protocol = .tls;
        }
        config.proxy.?.host = proxyuri.host.?;
        config.proxy.?.port = proxyuri.port.?;
    }

    if (args.method) |_proxy| {
        if (std.mem.eql(u8, _proxy, "POST")) {
            config.method = std.http.Method.POST;
        }
    }

    return config;
}

pub fn request(allocator: std.mem.Allocator, config: Configuration) ![]const u8 {
    var client: std.http.Client = .{ .allocator = allocator, .proxy = config.proxy};
    defer client.deinit();
    if (config.protocol == .tls) {
        // Code for ssl request.
        var connection = try client.connectUnproxied(config.host, config.port, config.protocol);
        var req = try client.request(config.method.?, config.url, config.headers.?, .{ .connection = connection });
        defer req.deinit();
        std.debug.print("{s}\n", req.response.reason);
    }
    return "";
}

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const args = try parseArgs(Args);
    const config = try argsToConfiguration(arena.allocator(), args);
    const bytes = try request(arena.allocator(), config);
    std.debug.print("{d} bytes recieved.\n", .{bytes});
}
