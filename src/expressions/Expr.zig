const std = @import("std");
const Binary = @import("Binary.zig");
const Unary = @import("Unary.zig");
const Grouping = @import("Grouping.zig");
const Literal = @import("Literal.zig");
const Token = @import("../Token.zig");
const Allocator = std.mem.Allocator;
const allocPrint = std.fmt.allocPrint;

const Self = @This();

ptr: *anyopaque,
toStringFn: *const fn (ptr: *anyopaque, allocator: Allocator) anyerror![]const u8,

pub fn init(ptr: anytype) Self {
    const Ptr = @TypeOf(ptr);
    const ptr_info = @typeInfo(Ptr);

    std.debug.assert(ptr_info == .Pointer);
    std.debug.assert(ptr_info.Pointer.size == .One);
    std.debug.assert(@typeInfo(ptr_info.Pointer.child) == .Struct);

    const gen = struct {
        pub fn toStringImpl(pointer: *anyopaque, allocator: Allocator) anyerror![]const u8 {
            const self: Ptr = @ptrCast(@alignCast(pointer));
            return @call(.{ .modifier = .always_inline }, ptr_info.Pointer.child.toString, .{ self, allocator });
        }
    };

    return .{
        .ptr = ptr,
        .toStringFn = gen.toStringImpl,
    };
}

pub inline fn toString(self: Self, allocator: Allocator) anyerror![]const u8 {
    return self.toStringFn(self.ptr, allocator);
}

pub fn expr(self: *Self) Self {
    return Self.init(self);
}

test "pretty print" {
    const number1 = Literal{ .value = Token.Literal{ .number = 123.0 } };
    const number2 = Literal{ .value = Token.Literal{ .number = 45.67 } };
    const unary = Unary{
        .operator = Token.init(Token.TokenType.MINUS, 1),
        .right = number1,
    };
    const grouping = Grouping{
        .expression = number2,
    };
    const binary = Binary{
        .left = unary,
        .operator = Token.init(Token.TokenType.STAR, 1),
        .right = grouping,
    };

    const allocator = std.testing.allocator;

    const result = try binary.toString(allocator);
    defer allocator.free(result);

    std.debug.print("{s}", .{result});
    std.testing.expectEqualStrings("((- 123) * (45.67))", result);
}
