const std = @import("std");
const Expr = @import("Expr.zig").Expr;
const Token = @import("Token.zig");
const Allocator = std.mem.Allocator;
const Self = @This();

operator: Token,
right: Expr,

pub fn toString(self: *Self, allocator: Allocator) anyerror![]const u8 {
    const operator = self.operator.type.toValue().?;

    const right = try self.right.toString(allocator);
    defer allocator.free(right);

    return try std.fmt.allocPrint(allocator, "({s} {s})", .{ operator, right });
}

pub fn expr(self: *Self) Expr {
    return Expr{ .unary = self };
}
