const std = @import("std");
const Expr = @import("expr.zig").Expr;
const Token = @import("Token.zig");
const Allocator = std.mem.Allocator;

const Self = @This();

expression: Expr,

pub fn toString(self: Self, allocator: Allocator) anyerror![]const u8 {
    const expression = try self.expression.toString(allocator);
    defer allocator.free(expression);

    return try std.fmt.allocPrint(allocator, "({s})", .{expression});
}

pub fn expr(self: *Self) Expr {
    return Expr{ .grouping = self };
}
