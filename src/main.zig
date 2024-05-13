const std = @import("std");
const Token = @import("Token.zig");
const TokenType = @import("Token.zig").TokenType;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 2) {
        std.log.err("Usage: zig build run -- <filename>", .{});
    } else if (args.len == 2) {
        const file = try std.fs.cwd().readFileAlloc(allocator, args[1], 100_000_000);
        defer allocator.free(file);

        const tokens = try scanTokens(allocator, file);
        defer tokens.deinit();

        for (tokens.items) |token| {
            std.log.info("{s}", .{@tagName(token.type)});
        }
    } else {
        const stdin = std.io.getStdIn().reader();
        const bytes_read = try stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
        defer allocator.free(bytes_read);

        const tokens = try scanTokens(allocator, bytes_read);
        defer tokens.deinit();

        for (tokens.items) |token| {
            std.log.info("{s}", .{@tagName(token.type)});
        }
    }
}

pub fn scanTokens(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(Token) {
    var tokens = std.ArrayList(Token).init(allocator);
    var line: usize = 1;

    var start: usize = 0;
    var end: usize = 1;
    while (start < source.len) : ({
        start = end;
        end = start + 1;
    }) {
        const token = switch (source[start]) {
            ' ', '\t', '\r' => continue,
            '\n' => {
                line += 1;
                continue;
            },
            // single char tokens with no super token
            '(', ')', '{', '}', ',', '.', ';', '+', '-', '*' => |c| blk: {
                const token_type = TokenType.parse_char(c).?;
                break :blk Token.init(token_type, line);
            },
            // identifiers
            'a'...'z', 'A'...'Z', '_' => blk: {
                while (end < source.len and (std.ascii.isAlphabetic(source[end]) or source[end] == '_')) end += 1;

                const token_type = TokenType.parse(source[start..end]) orelse TokenType.IDENTIFIER;
                break :blk Token.initWithLexeme(token_type, line, source[start..end]);
            },
            '0'...'9' => blk: {
                while (end < source.len and std.ascii.isDigit(source[end])) end += 1;

                end += 1;
                if (end < source.len and source[end - 1] == '.' and std.ascii.isDigit(source[end])) {
                    while (end < source.len and std.ascii.isDigit(source[end])) end += 1;
                }

                break :blk Token.initWithLexeme(TokenType.NUMBER, line, source[start .. end - 1]);
            },
            '"' => blk: {
                while (end < source.len and source[end] != '"') : (end += 1) {
                    if (source[end] == '\n') {
                        line += 1;
                    }
                }
                end += 1;

                break :blk Token.initWithLexeme(TokenType.STRING, line, source[start + 1 .. end - 1]);
            },
            // single char tokens with super tokens
            '!', '=', '<', '>' => |c| blk: {
                const token_type = TokenType.parse_char(c).?;
                const super = token_type.toSuper().?;

                if (start + 1 < source.len and source[start + 1] == super.toValue().?[1]) {
                    end += 1;
                    break :blk Token.init(super, line);
                }
                break :blk Token.init(token_type, line);
            },
            // special case for comments (we ignore everything)
            '/' => blk: {
                if (end < source.len) {
                    switch (source[end]) {
                        '/' => {
                            while (end < source.len and source[end] != '\n') end += 1;
                            continue;
                        },
                        '*' => {
                            end += 2;
                            while (end < source.len and !(source[end - 1] == '*' and source[end] == '/')) : (end += 1) {
                                if (source[end] == '\n') {
                                    line += 1;
                                }
                            }
                            end += 2;
                            continue;
                        },
                        else => {},
                    }
                }

                break :blk Token.init(TokenType.SLASH, line);
            },
            else => {
                std.log.err("Unknown token \"{s}\" at line {d}.\n", .{ source[start..end], line });
                continue;
            },
        };

        try tokens.append(token);
    }
    return tokens;
}

test "Scans correctly" {
    const tokens = try scanTokens(std.testing.allocator, "1 + 2 * 3 - 4");
    defer tokens.deinit();

    // std.debug.print("token: {s}\n", .{@tagName(tokens.items[0].type)});

    try std.testing.expectEqual(7, tokens.items.len);
    try std.testing.expectEqual(TokenType.NUMBER, tokens.items[0].type);
    try std.testing.expectEqual(TokenType.PLUS, tokens.items[1].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens.items[2].type);
    try std.testing.expectEqual(TokenType.STAR, tokens.items[3].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens.items[4].type);
    try std.testing.expectEqual(TokenType.MINUS, tokens.items[5].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens.items[6].type);
}

pub const Expr = union(enum) {
    BINARY: struct {
        left: *Expr,
        op: Token,
        right: *Expr,
    },
    GROUPING: *Expr,
    LITERAL: f64,
    UNARY: struct {
        op: Token,
        right: *Expr,
    },

    const Self = @This();

    pub fn initBinary(left: *Expr, op: Token, right: *Expr) Self {
        return .{ .BINARY = .{ .left = left, .op = op, .right = right } };
    }

    pub fn initGrouping(expr: *Expr) Self {
        return .{ .GROUPING = expr };
    }

    pub fn initLiteral(value: f64) Self {
        return .{ .LITERAL = value };
    }

    pub fn initUnary(op: Token, right: *Expr) Self {
        return .{ .UNARY = .{ .op = op, .right = right } };
    }

    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        switch (self) {
            .BINARY => |expr| {
                const left = try expr.left.toString(allocator);
                defer allocator.free(left);

                const right = try expr.right.toString(allocator);
                defer allocator.free(right);

                return std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ expr.op.type.toValue().?, left, right });
            },
            .GROUPING => |expr| {
                const group = try expr.toString(allocator);
                defer allocator.free(group);

                return std.fmt.allocPrint(allocator, "(group {s})", .{group});
            },
            .LITERAL => |value| {
                return std.fmt.allocPrint(allocator, "{d}", .{value});
            },
            .UNARY => |expr| {
                const right = try expr.right.toString(allocator);
                defer allocator.free(right);

                return std.fmt.allocPrint(allocator, "({s} {s})", .{ expr.op.type.toValue().?, right });
            },
        }
    }
};

test "pretty print" {
    var literal1 = Expr.initLiteral(123.0);
    var literal2 = Expr.initLiteral(45.67);
    var grouping = Expr.initGrouping(&literal2);
    var minus = Expr.initUnary(Token.init(TokenType.MINUS, 1), &literal1);
    const expression = Expr.initBinary(&minus, Token.init(TokenType.STAR, 1), &grouping);

    const allocator = std.testing.allocator;
    const result = try expression.toString(allocator);
    defer allocator.free(result);

    std.debug.print("\n{s}\n", .{result});
    try std.testing.expectEqualStrings("(* (- 123) (group 45.67))", result);
}
