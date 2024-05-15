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
        var expression: Expr = undefined;
        var start = 0;
        var end = 1;
        while (end < source.items.len) : ({
            start = end;
            end += 1;
        }) {
            const token = source[start];
            switch (token.type) {
                TokenType.LEFT_PAREN => {
                    _ = source.orderedRemove(0);
                    const left = try parse(source);

                    if (source.items[0].type == TokenType.RIGHT_PAREN) return error.ExpectedRightParenthesis;

                    _ = source.orderedRemove(0);

                    var grouping = Grouping{ .expression = &left };
                    expression = grouping.expr();
                },
                TokenType.BANG_EQUAL, TokenType.EQUAL_EQUAL, TokenType.MINUS, TokenType.PLUS, TokenType.GREATER, TokenType.GREATER_EQUAL, TokenType.LESS, TokenType.LESS_EQUAL, TokenType.SLASH, TokenType.STAR => {
                    _ = source.orderedRemove(0);
                    var right = try parse(source);

                    var binary = Binary{
                        .left = &expression,
                        .operator = token,
                        .right = &right,
                    };

                    expression = binary.expr();
                },
                TokenType.BANG, TokenType.MINUS => {
                    _ = source.orderedRemove(0);
                    var right = try parse(source);

                    var unar = Unary{
                        .operator = token,
                        .right = &right,
                    };

                    expression = unar.expr();
                },
                TokenType.TRUE, TokenType.FALSE, TokenType.NULL, TokenType.NUMBER, TokenType.STRING => blk: {
                    const value = source.items[0].literal;

                    var literal = Literal{ .value = value };

                    break :blk literal.expr();
                },
                TokenType.LEFT_PAREN => blk: {
                    _ = source.orderedRemove(0);
                    var left = try parse(source);

                    if (source.items[0].type != TokenType.RIGHT_PAREN) {
                        std.log.err("Expected ')' after {s}", .{@tagName(source.items[0].type)});
                        break :blk error.ExpectedRightParenthesis;
                    }

                    _ = source.orderedRemove(0);

                    var grouping = Grouping{ .expression = &left };

                    break :blk grouping.expr();
                },
                else => {},
            }
        }
    }

    // pub fn parse(source: *ArrayList(Token)) anyerror!Self {
    //     if (source.items.len == 0) {
    //         return error.ExpectedExpression;
    //     }
    //     std.debug.print("\nparse 1 {s}\n", .{@tagName(source.items[0].type)});

    //     var expression = try comparison(source);

    //     for (source.items) |token| {
    //         switch (token.type) {
    //             TokenType.BANG_EQUAL, TokenType.EQUAL_EQUAL => {
    //                 _ = source.orderedRemove(0);
    //                 std.debug.print("\nparse 2 {s}\n", .{@tagName(source.items[0].type)});

    //                 var right = try comparison(source);

    //                 var binary = Binary{
    //                     .left = &expression,
    //                     .operator = token,
    //                     .right = &right,
    //                 };

    //                 expression = binary.expr();
    //             },
    //             else => {},
    //         }
    //     }
    //     return expression;
    // }

    // fn comparison(source: *ArrayList(Token)) anyerror!Self {
    //     if (source.items.len == 0) {
    //         return error.ExpectedExpression;
    //     }

    //     std.debug.print("\ncomparison 1 {s}\n", .{@tagName(source.items[0].type)});

    //     var expression = try term(source);

    //     for (source.items) |token| {
    //         switch (token.type) {
    //             TokenType.GREATER, TokenType.GREATER_EQUAL, TokenType.LESS, TokenType.LESS_EQUAL => {
    //                 _ = source.orderedRemove(0);
    //                 std.debug.print("\ncomparison 2 {s}\n", .{@tagName(source.items[0].type)});

    //                 var right = try term(source);

    //                 var binary = Binary{
    //                     .left = &expression,
    //                     .operator = token,
    //                     .right = &right,
    //                 };

    //                 defer std.debug.print("comparison completed\n", .{});

    //                 expression = binary.expr();
    //             },
    //             else => {},
    //         }
    //     }
    //     return expression;
    // }

    // fn term(source: *ArrayList(Token)) anyerror!Self {
    //     if (source.items.len == 0) {
    //         return error.ExpectedExpression;
    //     }

    //     std.debug.print("\nterm 1 {s}\n", .{@tagName(source.items[0].type)});

    //     var expression = try factor(source);

    //     for (source.items) |token| {
    //         switch (token.type) {
    //             TokenType.MINUS, TokenType.PLUS => {
    //                 _ = source.orderedRemove(0);

    //                 std.debug.print("\nterm 2 {s}\n", .{@tagName(source.items[0].type)});

    //                 var right = try factor(source);

    //                 var binary = Binary{
    //                     .left = &expression,
    //                     .operator = token,
    //                     .right = &right,
    //                 };

    //                 defer std.debug.print("term completed\n", .{});

    //                 expression = binary.expr();
    //             },
    //             else => {},
    //         }
    //     }
    //     return expression;
    // }

    // fn factor(source: *ArrayList(Token)) anyerror!Self {
    //     if (source.items.len == 0) {
    //         return error.ExpectedExpression;
    //     }

    //     std.debug.print("\nfactor 1 {s}\n", .{@tagName(source.items[0].type)});

    //     var expression = try unary(source);

    //     for (source.items) |token| {
    //         switch (token.type) {
    //             TokenType.SLASH, TokenType.STAR => {
    //                 _ = source.orderedRemove(0);

    //                 std.debug.print("\nfactor 2 {s}\n", .{@tagName(source.items[0].type)});

    //                 var right = try unary(source);

    //                 var binary = Binary{
    //                     .left = &expression,
    //                     .operator = token,
    //                     .right = &right,
    //                 };

    //                 expression = binary.expr();
    //             },
    //             else => {},
    //         }
    //     }
    //     return expression;
    // }

    // fn unary(source: *ArrayList(Token)) anyerror!Self {
    //     if (source.items.len == 0) {
    //         return error.ExpectedExpression;
    //     }

    //     return switch (source.items[0].type) {
    //         TokenType.BANG, TokenType.MINUS => blk: {
    //             const operator = source.items[0];
    //             _ = source.orderedRemove(0);
    //             var right = try unary(source);

    //             var unar = Unary{
    //                 .operator = operator,
    //                 .right = &right,
    //             };

    //             break :blk unar.expr();
    //         },
    //         else => blk: {
    //             std.debug.print("\nunary {s}\n", .{@tagName(source.items[0].type)});

    //             break :blk try primary(source);
    //         },
    //     };
    // }

    // fn primary(source: *ArrayList(Token)) anyerror!Self {
    //     if (source.items.len == 0) {
    //         return error.ExpectedExpression;
    //     }

    //     std.debug.print("\nprimary {s}\n", .{@tagName(source.items[0].type)});

    //     return switch (source.items[0].type) {
    //         TokenType.TRUE, TokenType.FALSE, TokenType.NULL, TokenType.NUMBER, TokenType.STRING => blk: {
    //             const value = source.items[0].literal;

    //             var literal = Literal{ .value = value };

    //             break :blk literal.expr();
    //         },
    //         TokenType.LEFT_PAREN => blk: {
    //             _ = source.orderedRemove(0);
    //             var left = try parse(source);

    //             if (source.items[0].type != TokenType.RIGHT_PAREN) {
    //                 std.log.err("Expected ')' after {s}", .{@tagName(source.items[0].type)});
    //                 break :blk error.ExpectedRightParenthesis;
    //             }

    //             _ = source.orderedRemove(0);

    //             var grouping = Grouping{ .expression = &left };

    //             break :blk grouping.expr();
    //         },
    //         else => return error.ExpectedPrimary,
    //     };
    // }
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
