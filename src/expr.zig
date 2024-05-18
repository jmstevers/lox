const std = @import("std");
const Token = @import("Token.zig");
const TokenType = @import("Token.zig").TokenType;
const pretty = @import("pretty.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const allocPrint = std.fmt.allocPrint;

pub const Binary = @import("Binary.zig");
pub const Unary = @import("Unary.zig");
pub const Grouping = @import("Grouping.zig");
pub const Literal = @import("Literal.zig");

const Parser = struct {
    tokens: []Token,
    current: usize,

    const Self = @This();

    fn match(self: *Self, types: []const TokenType) bool {
        for (types) |t| {
            if (self.check(t)) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn check(self: Self, t: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == t;
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) self.current += 1;
        return self.previous();
    }

    fn isAtEnd(
        self: Self,
    ) bool {
        return self.peek().type == TokenType.EOF;
    }

    fn peek(self: Self) Token {
        return self.tokens[self.current];
    }

    fn previous(self: Self) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Self, t: TokenType, message: []const u8) Token {
        if (self.check(t)) return self.advance();
        std.debug.panic("Expecting token {s}: {s}", .{ t.toValue().?, message });
    }

    fn expression(self: *Self) Expr {
        return self.equality();
    }

    fn equality(self: *Self) Expr {
        var expr = self.comparison();

        while (self.match(&[_]TokenType{ TokenType.BANG_EQUAL, TokenType.EQUAL_EQUAL })) {
            const op = self.previous();
            const right = self.comparison();
            var binary = Binary{ .left = expr, .operator = op, .right = right };
            expr = binary.expr();
        }

        return expr;
    }

    fn comparison(self: *Self) Expr {
        var expr = self.term();

        while (self.match(&[_]TokenType{ TokenType.GREATER, TokenType.GREATER_EQUAL, TokenType.LESS, TokenType.LESS_EQUAL })) {
            const op = self.previous();
            const right = self.term();
            var binary = Binary{ .left = expr, .operator = op, .right = right };
            expr = binary.expr();
        }

        return expr;
    }

    fn term(self: *Self) Expr {
        var expr = self.factor();

        while (self.match(&[_]TokenType{ TokenType.MINUS, TokenType.PLUS })) {
            const op = self.previous();
            const right = self.factor();
            var binary = Binary{ .left = expr, .operator = op, .right = right };
            expr = binary.expr();
        }

        return expr;
    }

    fn factor(self: *Self) Expr {
        var expr = self.unary();

        while (self.match(&[_]TokenType{ TokenType.SLASH, TokenType.STAR })) {
            const op = self.previous();
            const right = self.unary();
            var binary = Binary{ .left = expr, .operator = op, .right = right };
            expr = binary.expr();
        }

        return expr;
    }

    fn unary(self: *Self) Expr {
        if (self.match(&[_]TokenType{ TokenType.BANG, TokenType.MINUS })) {
            const op = self.previous();
            const right = self.unary();
            var unar = Unary{ .operator = op, .right = right };
            return unar.expr();
        }

        return self.primary();
    }

    fn primary(self: *Self) Expr {
        if (self.match(&[_]TokenType{TokenType.FALSE})) {
            var literal = Literal{ .value = Token.Literal{ .bool = false } };
            return literal.expr();
        }
        if (self.match(&[_]TokenType{TokenType.TRUE})) {
            var literal = Literal{ .value = Token.Literal{ .bool = true } };
            return literal.expr();
        }
        if (self.match(&[_]TokenType{TokenType.NULL})) {
            var literal = Literal{ .value = Token.Literal.null };
            return literal.expr();
        }

        if (self.match(&[_]TokenType{ TokenType.NUMBER, TokenType.STRING })) {
            var literal = Literal{ .value = self.previous().literal };
            return literal.expr();
        }

        if (self.match(&[_]TokenType{TokenType.LEFT_PAREN})) {
            const expr = self.expression();
            _ = self.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression.");
            var grouping = Grouping{ .expression = expr };
            return grouping.expr();
        }

        std.debug.panic("Expect expression.", .{});
    }

    pub fn init(tokens: []Token) Self {
        return Self{ .tokens = tokens, .current = 0 };
    }

    pub fn parse(self: *Self) Expr {
        return self.expression();
    }
};

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
};

test "pretty print" {
    const allocator = std.testing.allocator;

    var source = [_]Token{
        Token.init(
            TokenType.MINUS,
            1,
        ),
        try Token.initWithLexeme(TokenType.NUMBER, 1, "123"),
        Token.init(TokenType.STAR, 1),
        try Token.initWithLexeme(TokenType.NUMBER, 1, "45.67"),
        try Token.initWithLexeme(TokenType.EOF, 1, ""),
    };

    var parser = Parser.init(&source);

    const expression = parser.parse();

    // const expected = Expr{ .binary = @constCast(&Binary{
    //     .left = blk: {
    //         var unar = Unary{ .operator = Token.init(
    //             TokenType.MINUS,
    //             1,
    //         ), .right = blk2: {
    //             var lit = Literal{ .value = Token.Literal{ .number = 123 } };
    //             break :blk2 lit.expr();
    //         } };
    //         break :blk unar.expr();
    //     },
    //     .operator = Token.init(TokenType.STAR, 1),
    //     .right = blk: {
    //         var lit = Literal{ .value = Token.Literal{ .number = 45.67 } };
    //         break :blk lit.expr();
    //     },
    // }) };

    // try std.testing.expectEqualDeep(expected, expression);

    // const result = try expression.toString(allocator);
    // defer allocator.free(result);

    // try std.json.stringify(&expression, .{}, std.io.getStdOut().writer());

    // try std.testing.expectEqualStrings("((- 123) * (45.67))", result);
}
