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

    // Gather information
    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const path = try getPath(alloc, &env_map);
    defer alloc.free(path);

    const status_colour_code = try getStatusColourCode(&env_map);

    const maybe_branch = try getBranch(alloc);
    defer if (maybe_branch) |branch| alloc.free(branch);

    // Display information
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    if (maybe_branch) |branch| {
        try stdout.print("{s} {s}\n", .{ path, branch });
    } else {
        try stdout.print("{s}\n", .{path});
    }
    try stdout.print("{s}{s}{u} ", .{ status_colour_code, BOLD, LAMBDA_CHAR });

    try bw.flush();
}

/// Returns a formatted path.
/// Caller owns resulting string and should free it when done.
fn getPath(alloc: std.mem.Allocator, env_map: *const std.process.EnvMap) ![]const u8 {
    const pwd = env_map.get("PWD") orelse "pwd-unknown";
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

/// Returns a git branch name if in a git repo.
/// Appends a `*` if the branch is dirty.
/// Caller owns resulting string and should free it when done.
fn getBranch(alloc: std.mem.Allocator) !?[]const u8 {
    const branch_cmd = &[_][]const u8{ "git", "branch", "--show-current" };
    const branch_res = try std.process.Child.run(.{ .allocator = alloc, .argv = branch_cmd });
    defer alloc.free(branch_res.stdout);
    defer alloc.free(branch_res.stderr);

    // `git branch --show-current` failed, so assume we're not in a Git repo
    if (branch_res.term.Exited != 0) return null;

    const branch_name = std.mem.trimRight(u8, branch_res.stdout, "\n");

    const dirty_cmd = &[_][]const u8{ "git", "status", "--porcelain" };
    const dirty_res = try std.process.Child.run(.{ .allocator = alloc, .argv = dirty_cmd });
    defer alloc.free(dirty_res.stdout);
    defer alloc.free(dirty_res.stderr);

    // Clean branch
    if (dirty_res.stdout.len == 0) return try alloc.dupe(u8, branch_name);

    return try std.fmt.allocPrint(alloc, "{s}*", .{branch_name});
}
