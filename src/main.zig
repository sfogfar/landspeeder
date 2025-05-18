const std = @import("std");

const config = struct {
    const prompt_symbol = symbols.lambda;
};

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

    // TODO: refactor so all git is got from one call
    const maybe_branch = try getBranch(alloc);
    defer if (maybe_branch) |branch| alloc.free(branch);

    const maybe_unpushed_unpulled = try getUnpushedUnpulled(alloc);
    defer if (maybe_unpushed_unpulled) |unpushed_unpulled| alloc.free(unpushed_unpulled);

    const prompt = try getPrompt(alloc, &env_map);
    defer alloc.free(prompt);

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
    try stdout.print("{s}", .{prompt});

    try bw.flush();
}

/// Returns a formatted path.
/// Caller owns resulting string and should free it when done.
fn getPath(alloc: std.mem.Allocator, env_map: *const std.process.EnvMap) ![]const u8 {
    const pwd = env_map.get("PWD") orelse "pwd-unknown";
    const home = env_map.get("HOME") orelse "";

    // Attempt to replace full $HOME with ~
    if (std.mem.startsWith(u8, pwd, home) and home.len > 0) {
        return try std.fmt.allocPrint(alloc, "{s}~{s}{s}", .{ ansi.blue, pwd[home.len..], ansi.reset });
    } else {
        return try alloc.dupe(u8, pwd);
    }
}

/// Returns the prompt, using colour to indicate the last command status.
/// Caller owns resulting string and should free it when done.
fn getPrompt(alloc: std.mem.Allocator, env_map: *const std.process.EnvMap) ![]const u8 {
    const status_str = env_map.get("LAST_CMD_STATUS") orelse "0";
    const status = try std.fmt.parseInt(u8, status_str, 10);

    const colour_seq = if (status == 0) ansi.magenta else ansi.red;

    return std.fmt.allocPrint(alloc, "{s}{s}{s}{s} ", .{ ansi.bold, colour_seq, config.prompt_symbol, ansi.reset });
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
    if (dirty_res.stdout.len == 0) {
        return try std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ ansi.magenta, branch_name, ansi.reset });
    }

    return try std.fmt.allocPrint(alloc, "{s}{s}*{s}", .{ ansi.magenta, branch_name, ansi.reset });
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
        return try std.fmt.allocPrint(alloc, "{s}{s}{d} {s}{d}{s}", .{ ansi.cyan, symbols.up_arrow, unpushed, symbols.down_arrow, unpulled, ansi.reset });
    } else if (unpushed > 0) {
        return try std.fmt.allocPrint(alloc, "{s}{s}{d}{s}", .{ ansi.cyan, symbols.up_arrow, unpushed, ansi.reset });
    } else {
        return try std.fmt.allocPrint(alloc, "{s}{s}{d}{s}", .{ ansi.cyan, symbols.down_arrow, unpulled, ansi.reset });
    }
}

const ansi = struct {
    const reset = ansiSeq("0");

    const bold = ansiSeq("1");
    const italic = ansiSeq("3");

    const black = ansiSeq("30");
    const red = ansiSeq("31");
    const green = ansiSeq("32");
    const yellow = ansiSeq("33");
    const blue = ansiSeq("34");
    const magenta = ansiSeq("35");
    const cyan = ansiSeq("36");
    const white = ansiSeq("37");
};
fn ansiSeq(comptime code: []const u8) []const u8 {
    return "\x1b[" ++ code ++ "m";
}

const symbols = struct {
    const lambda = "λ";
    const up_arrow = "↑";
    const down_arrow = "↓";
};
