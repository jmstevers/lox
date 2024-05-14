const std = @import("std");
const Expr = @import("Expr.zig");
const Token = @import("../Token.zig");
const Allocator = std.mem.Allocator;
const Self = @This();

expression: Expr,

fn toString(self: *Self, allocator: Allocator) anyerror![]const u8 {
    const expression = try self.expression.toString(allocator);
    defer allocator.free(expression);

    return try std.fmt.allocPrint(allocator, "({s})", .{expression});
}
