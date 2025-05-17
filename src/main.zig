pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var env_map = try std.process.getEnvMap(alloc);
    defer env_map.deinit();

    const cwd_path = env_map.get("PWD") orelse "";
    const home_path = env_map.get("HOME") orelse "";

    // Replace full $HOME with ~
    const display_path = dp_blk: {
        if (std.mem.startsWith(u8, cwd_path, home_path) and home_path.len > 0) {
            break :dp_blk try std.fmt.allocPrint(alloc, "~{s}", .{cwd_path[home_path.len..]});
        }
        break :dp_blk cwd_path;
    };
    defer if (cwd_path.ptr != display_path.ptr) alloc.free(display_path);

    try stdout.print("{s}\n", .{display_path});
    try stdout.print("\u{03BB} ", .{});

    try bw.flush();
}

const std = @import("std");
