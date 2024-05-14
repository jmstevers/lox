const std = @import("std");

type: TokenType,
lexeme: []const u8,
line: usize,
literal: Literal = Literal.none,

const Self = @This();

pub const Literal = union(enum) {
    none,
    null,
    string: []const u8,
    number: f64,
    bool: bool,

    pub fn toString(self: Literal, allocator: std.mem.Allocator) []const u8 {
        return switch (self) {
            .null => "null",
            .string => self.string,
            .number => std.fmt.allocPrint(allocator, "{d}", .{self.number}),
            .bool => if (self.bool) "true" else "false",
            .none => unreachable,
        };
    }
};

pub fn init(token_type: TokenType, line: usize) Self {
    return Self{ .type = token_type, .lexeme = token_type.toValue().?, .line = line };
}

pub fn initWithLexeme(token_type: TokenType, line: usize, lexeme: []const u8) !Self {
    const literal: Literal = switch (token_type) {
        TokenType.STRING => Literal{ .string = lexeme },
        // try parse float else parse int
        TokenType.NUMBER => Literal{ .number = std.fmt.parseFloat(f64, lexeme) catch @as(f64, @floatFromInt(try std.fmt.parseInt(i32, lexeme, 10))) },
        TokenType.TRUE => Literal{ .bool = true },
        TokenType.FALSE => Literal{ .bool = false },
        TokenType.NULL => Literal.null,
        else => Literal.none,
    };

    return Self{ .type = token_type, .lexeme = lexeme, .line = line, .literal = literal };
}

pub const TokenType = enum {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,
    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,
    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FN,
    FOR,
    IF,
    NULL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    LET,
    WHILE,
    EOF,

    pub fn toValue(self: TokenType) ?[]const u8 {
        return for (multi_char_tokens) |item| {
            if (item.token == self) break item.str;
        } else for (single_char_tokens) |item| {
            if (item.token == self) break &[_]u8{item.char};
        } else null;
    }

    pub fn parse(str: []const u8) ?TokenType {
        return for (multi_char_tokens) |item| {
            if (std.mem.eql(u8, item.str, str)) break item.token;
        } else for (single_char_tokens) |item| {
            if (item.char == str[0]) break item.token;
        } else null;
    }

    pub fn parse_char(char: u8) ?TokenType {
        return for (single_char_tokens) |item| {
            if (item.char == char) break item.token;
        } else null;
    }

    pub fn toSuper(self: TokenType) ?TokenType {
        return switch (self) {
            .BANG => .BANG_EQUAL,
            .EQUAL => .EQUAL_EQUAL,
            .GREATER => .GREATER_EQUAL,
            .LESS => .LESS_EQUAL,
            else => null,
        };
    }
};

pub const single_char_tokens = [_]struct { token: TokenType, char: u8 }{
    .{ .token = .LEFT_PAREN, .char = '(' },
    .{ .token = .RIGHT_PAREN, .char = ')' },
    .{ .token = .LEFT_BRACE, .char = '{' },
    .{ .token = .RIGHT_BRACE, .char = '}' },
    .{ .token = .COMMA, .char = ',' },
    .{ .token = .DOT, .char = '.' },
    .{ .token = .MINUS, .char = '-' },
    .{ .token = .PLUS, .char = '+' },
    .{ .token = .SEMICOLON, .char = ';' },
    .{ .token = .SLASH, .char = '/' },
    .{ .token = .STAR, .char = '*' },
    .{ .token = .BANG, .char = '!' },
    .{ .token = .EQUAL, .char = '=' },
    .{ .token = .GREATER, .char = '>' },
    .{ .token = .LESS, .char = '<' },
};

pub const multi_char_tokens = [_]struct { token: TokenType, str: []const u8 }{
    .{ .token = .BANG_EQUAL, .str = "!=" },
    .{ .token = .EQUAL_EQUAL, .str = "==" },
    .{ .token = .GREATER_EQUAL, .str = ">=" },
    .{ .token = .LESS_EQUAL, .str = "<=" },
    .{ .token = .AND, .str = "and" },
    .{ .token = .CLASS, .str = "class" },
    .{ .token = .ELSE, .str = "else" },
    .{ .token = .FALSE, .str = "false" },
    .{ .token = .FN, .str = "fn" },
    .{ .token = .FOR, .str = "for" },
    .{ .token = .IF, .str = "if" },
    .{ .token = .NULL, .str = "null" },
    .{ .token = .OR, .str = "or" },
    .{ .token = .PRINT, .str = "print" },
    .{ .token = .RETURN, .str = "return" },
    .{ .token = .SUPER, .str = "super" },
    .{ .token = .THIS, .str = "this" },
    .{ .token = .TRUE, .str = "true" },
    .{ .token = .LET, .str = "let" },
    .{ .token = .WHILE, .str = "while" },
};

pub const longest_token_length = blk: {
    var max = 0;
    for (multi_char_tokens) |item| {
        if (item.str.len > max) {
            max = item.str.len;
        }
    }
    break :blk max;
};
