const std = @import("std");
const Token = @import("Token.zig");
const TokenType = @import("Token.zig").TokenType;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const allocPrint = std.fmt.allocPrint;

pub const Binary = @import("Binary.zig");
pub const Unary = @import("Unary.zig");
pub const Grouping = @import("Grouping.zig");
pub const Literal = @import("Literal.zig");

pub const Expr = union(enum) {
    binary: *Binary,
    unary: *Unary,
    grouping: *Grouping,
    literal: *Literal,

    const Self = @This();

    pub fn expr(self: Self) Self {
        return switch (self) {
            inline else => |e| e.expr(),
        };
    }

    pub fn toString(self: Self, allocator: Allocator) anyerror![]const u8 {
        return switch (self) {
            inline else => |e| e.toString(allocator),
        };
    }

    pub fn parse(source: *ArrayList(Token)) anyerror!Self {
        var expression = try comparison(source);

        return switch (source.items[0].type) {
            TokenType.BANG_EQUAL, TokenType.EQUAL_EQUAL => |op| blk: {
                const operator = Token.init(op, 1);
                _ = source.orderedRemove(0);
                var right = try comparison(source);

                var binary = Binary{
                    .left = &expression,
                    .operator = operator,
                    .right = &right,
                };

                break :blk binary.expr();
            },
            else => expression,
        };
    }

    fn comparison(source: *ArrayList(Token)) anyerror!Self {
        var expression = try term(source);

        return switch (source.items[0].type) {
            TokenType.GREATER, TokenType.GREATER_EQUAL, TokenType.LESS, TokenType.LESS_EQUAL => |op| blk: {
                const operator = Token.init(op, 1);
                _ = source.orderedRemove(0);
                var right = try term(source);

                var binary = Binary{
                    .left = &expression,
                    .operator = operator,
                    .right = &right,
                };

                defer std.debug.print("comparison completed\n", .{});

                break :blk binary.expr();
            },
            else => expression,
        };
    }

    fn term(source: *ArrayList(Token)) anyerror!Self {
        var expression = try factor(source);

        return switch (source.items[0].type) {
            TokenType.MINUS, TokenType.PLUS => |op| blk: {
                const operator = Token.init(op, 1);
                _ = source.orderedRemove(0);
                var right = try factor(source);

                var binary = Binary{
                    .left = &expression,
                    .operator = operator,
                    .right = &right,
                };

                defer std.debug.print("term completed\n", .{});

                break :blk binary.expr();
            },
            else => expression,
        };
    }

    fn factor(source: *ArrayList(Token)) anyerror!Self {
        var expression = try unary(source);

        return switch (source.items[0].type) {
            TokenType.SLASH, TokenType.STAR => |op| blk: {
                const operator = Token.init(op, 1);
                _ = source.orderedRemove(0);
                var right = try unary(source);

                var binary = Binary{
                    .left = &expression,
                    .operator = operator,
                    .right = &right,
                };

                break :blk binary.expr();
            },
            else => expression,
        };
    }

    fn unary(source: *ArrayList(Token)) anyerror!Self {
        return switch (source.items[0].type) {
            TokenType.BANG, TokenType.MINUS => |op| blk: {
                const operator = Token.init(op, 1);
                _ = source.orderedRemove(0);
                var right = try unary(source);

                var unar = Unary{
                    .operator = operator,
                    .right = &right,
                };

                break :blk unar.expr();
            },
            else => try primary(source),
        };
    }

    fn primary(source: *ArrayList(Token)) anyerror!Self {
        return switch (source.items[0].type) {
            TokenType.TRUE, TokenType.FALSE, TokenType.NULL, TokenType.NUMBER, TokenType.STRING => blk: {
                const value = source.items[0].literal;

                var literal = Literal{ .value = value };

                break :blk literal.expr();
            },
            TokenType.LEFT_PAREN => blk: {
                _ = source.orderedRemove(0);
                var left = try parse(source);

                if (source.items[1].type != TokenType.RIGHT_PAREN) {
                    std.log.err("Expected ')' after {s}", .{@tagName(source.items[0].type)});
                    break :blk error.ExpectedRightParenthesis;
                }

                var grouping = Grouping{ .expression = &left };

                break :blk grouping.expr();
            },
            else => return error.ExpectedPrimary,
        };
    }
};

test "pretty print" {
    const allocator = std.testing.allocator;

    var source = ArrayList(Token).init(allocator);
    defer source.deinit();

    try source.appendSlice(&[_]Token{
        Token.init(TokenType.LEFT_PAREN, 1),
        Token.init(TokenType.LEFT_PAREN, 1),
        Token.init(
            TokenType.MINUS,
            1,
        ),
        try Token.initWithLexeme(TokenType.NUMBER, 1, "123"),
        Token.init(TokenType.RIGHT_PAREN, 1),
        Token.init(TokenType.STAR, 1),
        Token.init(TokenType.LEFT_PAREN, 1),
        try Token.initWithLexeme(TokenType.NUMBER, 1, "45.67"),
        Token.init(TokenType.RIGHT_PAREN, 1),
        Token.init(TokenType.RIGHT_PAREN, 1),
    });

    const expression = try Expr.parse(&source);

    const result = try expression.toString(allocator);
    defer allocator.free(result);

    std.debug.print("\n{s}\n", .{result});

    try std.testing.expectEqualStrings("((- 123) * (45.67))", result);
}
