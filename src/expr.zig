const std = @import("std");
const Token = @import("Token.zig");
const TokenType = @import("Token.zig").TokenType;
const Allocator = std.mem.Allocator;
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

    pub fn expr(self: *Self) Self {
        return switch (self) {
            inline else => |e| e.expr(),
        };
    }

    pub fn toString(self: Self, allocator: Allocator) anyerror![]const u8 {
        return switch (self) {
            inline else => |e| e.toString(allocator),
        };
    }

    pub fn parse(source: []Token, i: *usize) anyerror!?Self {
        var expression = try comparison(source, i) orelse return null;

        while (i.* < source.len) {
            switch (source[i.*].type) {
                TokenType.BANG_EQUAL, TokenType.EQUAL_EQUAL => |op| {
                    const operator = Token.init(op, 1);
                    const right = try comparison(source[i.* + 1 ..], i) orelse return null;

                    var binary = Binary{
                        .left = expression,
                        .operator = operator,
                        .right = right,
                    };

                    expression = binary.expr();
                },
                else => return expression,
            }
        }
        return expression;
    }

    fn comparison(source: []Token, i: *usize) anyerror!?Self {
        var expression = try term(source, i) orelse return null;

        while (i.* < source.len) {
            switch (source[i.*].type) {
                TokenType.GREATER, TokenType.GREATER_EQUAL, TokenType.LESS, TokenType.LESS_EQUAL => |op| {
                    const operator = Token.init(op, 1);
                    const right = try term(source[i.* + 1 ..], i) orelse return null;

                    var binary = Binary{
                        .left = expression,
                        .operator = operator,
                        .right = right,
                    };

                    expression = binary.expr();
                },
                else => return expression,
            }
        }
        return expression;
    }

    fn term(source: []Token, i: *usize) anyerror!?Self {
        var expression = try factor(source, i) orelse return null;

        while (i.* < source.len) {
            switch (source[i.*].type) {
                TokenType.MINUS, TokenType.PLUS => |op| {
                    const operator = Token.init(op, 1);
                    const right = try factor(source[i.* + 1 ..], i) orelse return null;

                    var binary = Binary{
                        .left = expression,
                        .operator = operator,
                        .right = right,
                    };

                    expression = binary.expr();
                },
                else => return expression,
            }
        }
        return expression;
    }

    fn factor(source: []Token, i: *usize) anyerror!?Self {
        var expression = try unary(source, i) orelse return null;

        while (i.* < source.len) {
            switch (source[i.*].type) {
                TokenType.SLASH, TokenType.STAR => |op| {
                    const operator = Token.init(op, 1);
                    const right = try unary(source[i.* + 1 ..], i) orelse return null;

                    var binary = Binary{
                        .left = expression,
                        .operator = operator,
                        .right = right,
                    };

                    expression = binary.expr();
                },
                else => return expression,
            }
        }
        return expression;
    }

    fn unary(source: []Token, i: *usize) anyerror!?Self {
        switch (source[i.*].type) {
            TokenType.BANG, TokenType.MINUS => |op| {
                const operator = Token.init(op, 1);
                const right = try unary(source[i.* + 1 ..], i) orelse return null;

                var unar = Unary{
                    .operator = operator,
                    .right = right,
                };

                return unar.expr();
            },
            else => return try primary(source, i) orelse null,
        }
    }

    fn primary(source: []Token, i: *usize) anyerror!?Self {
        switch (source[i.*].type) {
            TokenType.TRUE, TokenType.FALSE, TokenType.NULL, TokenType.NUMBER, TokenType.STRING => {
                const value = source[i.*].literal;
                var literal = Literal{ .value = value };

                return literal.expr();
            },
            TokenType.LEFT_PAREN => {
                const left = try parse(source[i.* + 1 ..], i) orelse return null;
                if (source[i.*].type != TokenType.RIGHT_PAREN) {
                    std.log.err("Expected ')' after expression", .{});
                    return error.LexerError;
                }
                var grouping = Grouping{ .expression = left };
                return grouping.expr();
            },
            else => return null,
        }
    }
};

test "pretty print" {
    var source = [_]Token{
        Token.init(
            TokenType.MINUS,
            1,
        ),
        try Token.initWithLexeme(TokenType.NUMBER, 1, "123"),
        Token.init(TokenType.STAR, 1),
        Token.init(TokenType.LEFT_PAREN, 1),
        try Token.initWithLexeme(TokenType.NUMBER, 1, "45.67"),
        Token.init(TokenType.RIGHT_PAREN, 1),
    };

    var i: usize = 0;
    const expression = (try Expr.parse(&source, &i)).?;

    const allocator = std.testing.allocator;

    const result = try expression.toString(allocator);
    defer allocator.free(result);

    std.debug.print("\n{s}\n", .{result});

    try std.testing.expectEqualStrings("((- 123) * (45.67))", result);
}
