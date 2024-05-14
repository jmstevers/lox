const std = @import("std");
const Expr = @import("Expr.zig");
const Token = @import("../Token.zig");
const Allocator = std.mem.Allocator;
const Self = @This();

value: Token.Literal,

fn toString(self: *Self, allocator: Allocator) anyerror![]const u8 {
    const value = self.value.toString(allocator);
    defer allocator.free(value);

    return try std.fmt.allocPrint(allocator, "{s}", .{value});
}
