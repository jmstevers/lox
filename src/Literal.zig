const std = @import("std");
const Expr = @import("expr.zig").Expr;
const Token = @import("Token.zig");
const Allocator = std.mem.Allocator;
const Self = @This();

value: Token.Literal,

pub fn toString(self: Self, allocator: Allocator) anyerror![]const u8 {
    const value = try self.value.toString(allocator);
    defer allocator.free(value);

    return try std.fmt.allocPrint(allocator, "{s}", .{value});
}

pub fn expr(self: *Self) Expr {
    return Expr{ .literal = self };
}
