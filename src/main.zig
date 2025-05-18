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

    const in_git_repo = try inGitRepo(alloc, &env_map);

    try stdout.print("{s}\n", .{display_path});
    try stdout.print("Git? {any}\n", .{in_git_repo});
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

fn inGitRepo(alloc: std.mem.Allocator, env_map: *const std.process.EnvMap) !bool {
    const home = env_map.get("HOME") orelse "";

    var dir_to_check = env_map.get("PWD") orelse home;
    // Limit dirs to check, if deeply nested this may mean we miss the git repo
    for (0..5) |_| {
        const path_to_check = try std.fs.path.join(alloc, &[_][]const u8{ dir_to_check, ".git" });
        defer alloc.free(path_to_check);

        if (std.fs.openDirAbsolute(path_to_check, std.fs.Dir.OpenOptions{ .access_sub_paths = false })) |gitdir| {
            @constCast(&gitdir).close(); // gitdir is a *const fs.Dir, we need a *fs.Dir
            return true;
        } else |_| {
            // Return early if we're already at root or $HOME
            if (dir_to_check.len <= 1) return false;
            if (std.mem.eql(u8, dir_to_check, home)) return false;

            const last_slash_idx = std.mem.lastIndexOf(u8, dir_to_check, "/") orelse dir_to_check.len;
            dir_to_check = dir_to_check[0..last_slash_idx];
        }
    } else return false;
}
