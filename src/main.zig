const std = @import("std");

// Symbols
const LAMBDA = 0x03BB;
const UP_ARROW = 0x2191;
const DOWN_ARROW = 0x2193;

// ANSI escape codes
const BOLD = "\x1b[1m";
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const RESET = "\x1b[0m";

// TODO: pass buffers to fns returning strs to simplify memory mgmt
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

    // TODO: refactor so all git is got from one call
    const maybe_branch = try getBranch(alloc);
    defer if (maybe_branch) |branch| alloc.free(branch);

    const maybe_unpushed_unpulled = try getUnpushedUnpulled(alloc);
    defer if (maybe_unpushed_unpulled) |unpushed_unpulled| alloc.free(unpushed_unpulled);

    // Display information
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("\n", .{});
    if (maybe_branch != null and maybe_unpushed_unpulled != null) {
        try stdout.print("{s} {s} {s}\n", .{ path, maybe_branch.?, maybe_unpushed_unpulled.? });
    } else if (maybe_branch != null) {
        try stdout.print("{s} {s}\n", .{ path, maybe_branch.? });
    } else {
        try stdout.print("{s}\n", .{path});
    }
    try stdout.print("{s}{s}{u}{s} ", .{ status_colour_code, BOLD, LAMBDA, RESET });

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

fn getUnpushedUnpulled(alloc: std.mem.Allocator) !?[]const u8 {
    const cmd = &[_][]const u8{ "git", "rev-list", "--count", "--left-right", "HEAD...@{upstream}" };
    const res = try std.process.Child.run(.{ .allocator = alloc, .argv = cmd });
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);

    if (res.term.Exited != 0) return null;

    const tab_idx = std.mem.indexOf(u8, res.stdout, "\t");

    // TODO: error here?
    if (tab_idx == null) return null;

    const unpushed_str = res.stdout[0..tab_idx.?];
    const unpushed = std.fmt.parseInt(u16, unpushed_str, 10) catch 0;

    const unpulled_str = std.mem.trimRight(u8, res.stdout[tab_idx.? + 1 ..], "\n");
    const unpulled = std.fmt.parseInt(u16, unpulled_str, 10) catch 0;

    // TODO: show only the arrow for 1, arrow + count for > 1
    if (unpushed == 0 and unpulled == 0) {
        return null;
    } else if (unpushed > 0 and unpulled > 0) {
        return try std.fmt.allocPrint(alloc, "{u}{d} {u}{d}", .{ UP_ARROW, unpushed, DOWN_ARROW, unpulled });
    } else if (unpushed > 0) {
        return try std.fmt.allocPrint(alloc, "{u}{d}", .{ UP_ARROW, unpushed });
    } else {
        return try std.fmt.allocPrint(alloc, "{u}{d}", .{ DOWN_ARROW, unpulled });
    }
}
