const std = @import("std");

const LAMBDA_CHAR = 0x03BB;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    // TODO: switch to the arena alloc once stable(ish)
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const display_path = try getDisplayPath(alloc);
    defer alloc.free(display_path);

    // TODO: use a struct for prompt
    try stdout.print("{s}\n", .{display_path});
    try stdout.print("{u} ", .{LAMBDA_CHAR});

    try bw.flush();
}

/// Returns a formatted path.
/// Caller owns resulting string and should free it when done.
fn getDisplayPath(alloc: std.mem.Allocator) ![]const u8 {
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const pwd = env_map.get("PWD") orelse "";
    const home = env_map.get("HOME") orelse "";

    // Attempt to replace full $HOME with ~
    if (std.mem.startsWith(u8, pwd, home) and home.len > 0) {
        return try std.fmt.allocPrint(alloc, "~{s}", .{pwd[home.len..]});
    } else {
        return try alloc.dupe(u8, pwd);
    }
}
