const std = @import("std");
const Expr = @import("Expr.zig");
const Token = @import("../Token.zig");
const Allocator = std.mem.Allocator;
const Self = @This();

left: Expr,
operator: Token,
right: Expr,

fn toString(self: *Self, allocator: Allocator) anyerror![]const u8 {
    const left = try self.left.toString(allocator);
    defer allocator.free(left);

    const operator = self.operator.lexeme;

    const right = try self.right.toString(allocator);
    defer allocator.free(right);

    return try std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, operator, right });
}
