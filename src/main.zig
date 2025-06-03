const std = @import("std");

const config = struct {
    const prompt_symbol = symbols.lambda;
};

const promptError = error{ NotAGitRepo, UnexpectedResponse };

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
    const maybe_branch = try getBranchName(alloc);
    defer if (maybe_branch) |branch| alloc.free(branch);

    const maybe_unpushed_unpulled = try getGitDivergence(alloc);
    defer if (maybe_unpushed_unpulled) |unpushed_unpulled| alloc.free(unpushed_unpulled);

    // const prompt = try getPrompt(alloc, &env_map);
    // defer alloc.free(prompt);

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
    // try stdout.print("{s}", .{prompt});

    try bw.flush();
}

/// Returns the pwd. Replaces $HOME with ~ for brevity.
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

fn lastCmdSucceeded(env_map: *const std.process.EnvMap) bool {
    const status_str = env_map.get("LAST_CMD_STATUS") orelse "0";
    const status = std.fmt.parseInt(u8, status_str, 10) catch return error.UnexpectedResponse;

    return status == 0;
}

/// Caller owns resulting string and should free it when done.
fn getBranchName(alloc: std.mem.Allocator) ![]const u8 {
    const get_branch_cmd = &[_][]const u8{ "git", "branch", "--show-current" };
    const get_branch_res = try std.process.Child.run(.{ .allocator = alloc, .argv = get_branch_cmd });
    defer alloc.free(get_branch_res.stdout);
    defer alloc.free(get_branch_res.stderr);

    if (get_branch_res.term.Exited != 0) return error.NotAGitRepo;

    const branch_name = std.mem.trimRight(u8, get_branch_res.stdout, "\n");

    return try std.fmt.allocPrint(alloc, "{s}", .{branch_name});
}

fn isDirtyBranch(alloc: std.mem.Allocator) !bool {
    const git_status_cmd = &[_][]const u8{ "git", "status", "--porcelain" };
    const git_status_res = try std.process.Child.run(.{ .allocator = alloc, .argv = git_status_cmd });
    defer alloc.free(git_status_res.stdout);
    defer alloc.free(git_status_res.stderr);

    if (git_status_res.term.Exited != 0) return error.NotAGitRepo;

    return git_status_res.stdout.len > 0;
}

fn getGitDivergence(alloc: std.mem.Allocator) !struct { ahead: u16, behind: u16 } {
    // Prints the number of commits unique commits on each side separated by a tab.
    const rev_list_cmd = &[_][]const u8{ "git", "rev-list", "--count", "--left-right", "HEAD...@{upstream}" };
    const rev_list_res = try std.process.Child.run(.{ .allocator = alloc, .argv = rev_list_cmd });
    defer alloc.free(rev_list_res.stdout);
    defer alloc.free(rev_list_res.stderr);

    if (rev_list_res.term.Exited != 0) return error.NotAGitRepo;

    const tab_idx = std.mem.indexOf(u8, rev_list_res.stdout, "\t") orelse return error.UnexpectedResponse;

    const ahead_str = rev_list_res.stdout[0..tab_idx];
    const ahead = std.fmt.parseInt(u16, ahead_str, 10) catch return error.UnexpectedResponse;

    const behind_str = std.mem.trimRight(u8, rev_list_res.stdout[tab_idx + 1 ..], "\n");
    const behind = std.fmt.parseInt(u16, behind_str, 10) catch return error.UnexpectedResponse;

    return .{ .ahead = ahead, .behind = behind };
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
    return "\x1b[0;" ++ code ++ "m";
}

const symbols = struct {
    const lambda = "λ";
    const up_arrow = "↑";
    const down_arrow = "↓";
};
