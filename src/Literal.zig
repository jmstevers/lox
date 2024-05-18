const std = @import("std");
const Expr = @import("expr.zig").Expr;
const Token = @import("Token.zig");
const Allocator = std.mem.Allocator;

const Self = @This();

value: Token.Literal,

pub fn toString(self: Self, allocator: Allocator) anyerror![]const u8 {
    return try self.value.toString(allocator);
}

pub fn expr(self: *Self) Expr {
    return Expr{ .literal = self };
}
