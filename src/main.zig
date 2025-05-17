const std = @import("std");

const LAMBDA_CHAR = 0x03BB;

// ANSI escape codes
const BOLD = "\x1b[1m";
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const RESET = "\x1b[0m";

pub fn main() !void {
    // TODO: switch to the arena alloc once stable(ish)
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const display_path = try getDisplayPath(alloc, &env_map);
    defer alloc.free(display_path);

    const status_colour_code = try getStatusColourCode(&env_map);

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("{s}\n", .{display_path});
    try stdout.print("{s}{s}{u} ", .{ status_colour_code, BOLD, LAMBDA_CHAR });

    try bw.flush();
}

/// Returns a formatted path.
/// Caller owns resulting string and should free it when done.
fn getDisplayPath(alloc: std.mem.Allocator, env_map: *const std.process.EnvMap) ![]const u8 {
    const pwd = env_map.get("PWD") orelse "unknown";
    const home = env_map.get("HOME") orelse "";

    // Attempt to replace full $HOME with ~
    if (std.mem.startsWith(u8, pwd, home) and home.len > 0) {
        return try std.fmt.allocPrint(alloc, "~{s}", .{pwd[home.len..]});
    } else {
        return try alloc.dupe(u8, pwd);
    }
}

/// Returns the exit code of the last command.
fn getStatusColourCode(env_map: *const std.process.EnvMap) ![]const u8 {
    const status_str = env_map.get("LAST_CMD_STATUS") orelse "0";
    const status_code = try std.fmt.parseInt(u8, status_str, 10);
    return if (status_code > 0) RED else GREEN;
}
