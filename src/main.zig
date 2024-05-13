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

                if (end + 1 < source.len and source[end] == '.' and std.ascii.isDigit(source[end + 1])) {
                    end += 1;
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
    equality: Equality,
    comparison: Comparison,
    term: Term,
    factor: Factor,
    unary: Unary,
    primary: Primary,

    pub const Primary = union(enum) {
        identifier: []const u8,
        number: f64,
        string: []const u8,
        bool: bool,
        null: struct {},
        expr: *const Expr,

        pub fn toString(self: Primary, allocator: std.mem.Allocator) ![]const u8 {
            return switch (self) {
                .identifier => self.identifier,
                .number => |num| try std.fmt.allocPrint(allocator, "{f}", .{num}),
                .string => |str| str,
                .bool => |b| if (b) "true" else "false",
                .null => "null",
                .expr => try self.expr.toString(allocator),
            };
        }

        pub fn toExpr(self: Primary) Expr {
            return Expr{ .primary = self };
        }

        pub fn up(self: Primary) Unary {
            return Unary{ .right = &self };
        }
    };

    pub const BangMinus = enum {
        BANG,
        MINUS,

        pub fn toValue(self: BangMinus) ![]const u8 {
            return switch (self) {
                .BANG => TokenType.BANG.toValue().?,
                .MINUS => TokenType.MINUS.toValue().?,
            };
        }
    };

    pub const Unary = struct {
        left: ?struct { left: BangMinus, right: ?*const Unary = null } = null,
        right: *const Primary,

        pub fn toString(self: Unary, allocator: std.mem.Allocator) ![]const u8 {
            if (self.left) |left| {
                const left_left = left.left.toValue().?;
                if (left.right) |left_right| {
                    const left_right_string = try left_right.toString(allocator);
                    defer allocator.free(left_right_string);

                    return try std.fmt.allocPrint(allocator, "({s} {s})", .{ left_left, left_right_string });
                }
                const right = try self.right.toString(allocator);
                defer allocator.free(right);

                return try std.fmt.allocPrint(allocator, "({s} {s})", .{ left_left, right });
            }
            const right = try self.right.toString(allocator);
            defer allocator.free(right);

            return right;
        }

        pub fn toExpr(self: Unary) Expr {
            return Expr{ .unary = self };
        }

        pub fn up(self: Unary) Factor {
            return Factor{ .left = &self };
        }
    };

    pub const StarSlash = enum {
        STAR,
        SLASH,

        pub fn toValue(self: StarSlash) ![]const u8 {
            return switch (self) {
                .STAR => TokenType.STAR.toValue().?,
                .SLASH => TokenType.SLASH.toValue().?,
            };
        }
    };

    pub const Factor = struct {
        left: *const Unary,
        right: ?struct { left: StarSlash, right: *Unary } = null,

        pub fn toString(self: Factor, allocator: std.mem.Allocator) ![]const u8 {
            const left = try self.left.toString(allocator);
            defer allocator.free(left);

            if (self.right) |right| {
                const right_left = right.left.toValue().?;

                const right_right = try right.right.toString(allocator);
                defer allocator.free(right_right);

                return try std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, right_left, right_right });
            }
            return try std.fmt.allocPrint(allocator, "({s})", .{left});
        }

        pub fn toExpr(self: Factor) Expr {
            return Expr{ .factor = self };
        }

        pub fn up(self: Factor) Term {
            return Term{ .left = &self };
        }
    };

    pub const PlusMinus = enum {
        PLUS,
        MINUS,

        pub fn toValue(self: PlusMinus) ![]const u8 {
            return switch (self) {
                .PLUS => TokenType.PLUS.toValue().?,
                .MINUS => TokenType.MINUS.toValue().?,
            };
        }
    };

    pub const Term = struct {
        left: *const Factor,
        right: ?struct {
            left: PlusMinus,
            right: *const Factor,
        } = null,

        pub fn toString(self: Term, allocator: std.mem.Allocator) ![]const u8 {
            const left = try self.left.toString(allocator);
            defer allocator.free(left);

            if (self.right) |right| {
                const right_left = right.left.toValue().?;

                const right_right = try right.right.toString(allocator);
                defer allocator.free(right_right);

                return try std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, right_left, right_right });
            }
            return try std.fmt.allocPrint(allocator, "({s})", .{left});
        }

        pub fn toExpr(self: Term) Expr {
            return Expr{ .term = self };
        }

        pub fn up(self: Term) Comparison {
            return Comparison{ .left = &self };
        }
    };

    pub const ComparisonOperators = enum {
        GREATER,
        GREATER_EQUAL,
        LESS,
        LESS_EQUAL,

        pub fn toValue(self: ComparisonOperators) ![]const u8 {
            return switch (self) {
                .GREATER => TokenType.GREATER.toValue().?,
                .GREATER_EQUAL => TokenType.GREATER_EQUAL.toValue().?,
                .LESS => TokenType.LESS.toValue().?,
                .LESS_EQUAL => TokenType.LESS_EQUAL.toValue().?,
            };
        }
    };

    pub const Comparison = struct {
        left: *const Term,
        right: ?struct {
            left: ComparisonOperators,
            right: *const Term,
        } = null,

        pub fn toString(self: Comparison, allocator: std.mem.Allocator) ![]const u8 {
            const left = try self.left.toString(allocator);
            defer allocator.free(left);

            if (self.right) |right| {
                const right_left = right.left.toValue().?;

                const right_right = try right.right.toString(allocator);
                defer allocator.free(right_right);

                return try std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, right_left, right_right });
            }
            return try std.fmt.allocPrint(allocator, "({s})", .{left});
        }

        pub fn toExpr(self: Comparison) Expr {
            return Expr{ .comparison = self };
        }

        pub fn up(self: Comparison) Equality {
            return Equality{ .left = &self };
        }
    };

    pub const EqualityOperators = enum {
        BANG_EQUAL,
        EQUAL_EQUAL,

        pub fn toValue(self: EqualityOperators) ![]const u8 {
            return switch (self) {
                .BANG_EQUAL => TokenType.BANG_EQUAL.toValue().?,
                .EQUAL_EQUAL => TokenType.EQUAL_EQUAL.toValue().?,
            };
        }
    };

    pub const Equality = struct {
        left: *const Comparison,
        right: ?struct {
            left: EqualityOperators,
            right: *const Comparison,
        } = null,

        pub fn toString(self: Equality, allocator: std.mem.Allocator) ![]const u8 {
            const left = try self.left.toString(allocator);
            defer allocator.free(left);

            if (self.right) |right| {
                const right_left = right.left.toValue().?;

                const right_right = try right.right.toString(allocator);
                defer allocator.free(right_right);

                return try std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, right_left, right_right });
            }
            return try std.fmt.allocPrint(allocator, "({s})", .{left});
        }

        pub fn toExpr(self: Equality) Expr {
            return Expr{ .equality = self };
        }

        pub fn up(self: Equality) Expr {
            return Expr{ .equality = self };
        }
    };

    const Self = @This();

    pub fn toString(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self) {
            .equality => |expr| try expr.toString(allocator),
            .comparison => |expr| try expr.toString(allocator),
            .term => |expr| try expr.toString(allocator),
            .factor => |expr| try expr.toString(allocator),
            .unary => |expr| try expr.toString(allocator),
            .primary => |expr| try expr.toString(allocator),
        };
    }

    pub fn toExpr(self: Self) Expr {
        return switch (self) {
            .equality => |expr| expr.toExpr(),
            .comparison => |expr| expr.toExpr(),
            .term => |expr| expr.toExpr(),
            .factor => |expr| expr.toExpr(),
            .unary => |expr| expr.toExpr(),
            .primary => |expr| expr.toExpr(),
        };
    }

    pub fn identifier(str: []const u8) Self {
        return Expr{ .primary = Expr.Primary{ .identifier = str } };
    }

    pub fn number(num: f64) Self {
        return Expr{ .primary = Expr.Primary{ .number = num } };
    }

    pub fn string(str: []const u8) Self {
        return Expr{ .primary = Expr.Primary{ .string = str } };
    }

    pub fn boolean(b: bool) Self {
        return Expr{ .primary = Expr.Primary{ .bool = b } };
    }

    pub fn nullVal() Self {
        return Expr{ .primary = Expr.Primary{ .null = {} } };
    }

    pub fn group(expr: *const Self) Self {
        return Expr{ .primary = Expr.Primary{ .expr = expr } };
    }

    pub fn multiply(left: *const Self, right: *const Self) Self {
        return Expr{ .factor = .{ .left = left, .right = .{ .left = StarSlash.STAR, .right = right } } };
    }

    pub fn divide(left: *const Self, right: *const Self) Self {
        return Expr{ .factor = .{ .left = left, .right = .{ .left = StarSlash.SLASH, .right = right } } };
    }

    pub fn add(left: *const Self, right: *const Self) Self {
        return Expr{ .term = .{ .left = left, .right = .{ .left = PlusMinus.PLUS, .right = right } } };
    }

    pub fn subtract(left: *const Self, right: *const Self) Self {
        return Expr{ .term = .{ .left = left, .right = .{ .left = PlusMinus.MINUS, .right = right } } };
    }

    pub fn bang(left: *const Self) Self {
        return Expr{ .unary = .{ .left = .{ .left = BangMinus.BANG }, .right = left } };
    }

    pub fn greaterThan(left: *const Self, right: *const Self) Self {
        return Expr{ .comparison = .{ .left = left, .right = .{ .left = ComparisonOperators.GREATER, .right = right } } };
    }

    pub fn greaterOrEqual(left: *const Self, right: *const Self) Self {
        return Expr{ .comparison = .{ .left = left, .right = .{ .left = ComparisonOperators.GREATER_EQUAL, .right = right } } };
    }

    pub fn lessThan(left: *const Self, right: *const Self) Self {
        return Expr{ .comparison = .{ .left = left, .right = .{ .left = ComparisonOperators.LESS, .right = right } } };
    }

    pub fn lessOrEqual(left: *const Self, right: *const Self) Self {
        return Expr{ .comparison = .{ .left = left, .right = .{ .left = ComparisonOperators.LESS_EQUAL, .right = right } } };
    }

    pub fn equal(left: *const Self, right: *const Self) Self {
        return Expr{ .equality = .{ .left = left, .right = .{ .left = EqualityOperators.EQUAL_EQUAL, .right = right } } };
    }

    pub fn notEqual(left: *const Self, right: *const Self) Self {
        return Expr{ .equality = .{ .left = left.comparison(), .right = .{ .left = EqualityOperators.BANG_EQUAL, .right = right.comparison() } } };
    }

    pub fn negate(left: *const Self) Self {
        return Expr{ .unary = .{ .left = .{ .left = BangMinus.MINUS }, .right = left.primary() } };
    }

    pub fn primary(self: Self) Self {
        return Expr{ .primary = Expr.Primary{ .expr = &self } };
    }

    pub fn unary(self: Self) Self {
        return switch (self) {
            .unary => return self,
            .primary => |expr| return Expr{ .unary = Unary{ .right = &expr } },
            .factor => |expr| return Expr{ .unary = Unary{ .right = &expr.toExpr().primary() } },
            .term => |expr| return Expr{ .unary = Unary{ .right = &expr.toExpr().primary() } },
            .comparison => |expr| return Expr{ .unary = Unary{ .right = &expr.toExpr().primary() } },
            .equality => |expr| return Expr{ .unary = Unary{ .right = &expr.toExpr().primary() } },
        };
    }

    pub fn factor(self: Self) Self {
        return switch (self) {
            .factor => return self,
            .unary => |expr| return Expr{ .factor = Factor{ .left = &expr } },
            .primary => |expr| return Expr{ .factor = Factor{ .left = &expr.toExpr().unary() } },
            .term => |expr| return Expr{ .factor = Factor{ .left = &expr.toExpr().unary() } },
            .comparison => |expr| return Expr{ .factor = Factor{ .left = &expr.toExpr().unary() } },
            .equality => |expr| return Expr{ .factor = Factor{ .left = &expr.toExpr().unary() } },
        };
    }

    pub fn term(self: Self) Self {
        return switch (self) {
            .term => return self,
            .factor => |expr| return Expr{ .term = Term{ .left = &expr } },
            .unary => |expr| return Expr{ .term = Term{ .left = &expr.toExpr().factor() } },
            .primary => |expr| return Expr{ .term = Term{ .left = &expr.toExpr().factor() } },
            .comparison => |expr| return Expr{ .term = Term{ .left = &expr.toExpr().factor() } },
            .equality => |expr| return Expr{ .term = Term{ .left = &expr.toExpr().factor() } },
        };
    }

    pub fn comparison(self: Self) Self {
        return switch (self) {
            .comparison => return self,
            .term => |expr| return Expr{ .comparison = Comparison{ .left = &expr } },
            .factor => |expr| return Expr{ .comparison = Comparison{ .left = &expr.toExpr().term() } },
            .unary => |expr| return Expr{ .comparison = Comparison{ .left = &expr.toExpr().term() } },
            .primary => |expr| return Expr{ .comparison = Comparison{ .left = &expr.toExpr().term() } },
            .equality => |expr| return Expr{ .comparison = Comparison{ .left = &expr.toExpr().term() } },
        };
    }

    pub fn equality(self: Self) Self {
        return switch (self) {
            .equality => return self,
            .comparison => |expr| return Expr{ .equality = Equality{ .left = &expr } },
            .term => |expr| return Expr{ .equality = Equality{ .left = &expr.toExpr().comparison() } },
            .factor => |expr| return Expr{ .equality = Equality{ .left = &expr.toExpr().comparison() } },
            .unary => |expr| return Expr{ .equality = Equality{ .left = &expr.toExpr().comparison() } },
            .primary => |expr| return Expr{ .equality = Equality{ .left = &expr.toExpr().comparison() } },
        };
    }
};

test "pretty print" {
    const expr = Expr.multiply(&Expr.negate(&Expr.number(123.0)), &Expr.group(&Expr.number(35.67)));

    const allocator = std.testing.allocator;
    const result = try expr.toString(allocator);
    defer allocator.free(result);

    std.debug.print("\n{s}\n", .{result});
    try std.testing.expectEqualStrings("((- 123) * (group 45.67))", result);
}
