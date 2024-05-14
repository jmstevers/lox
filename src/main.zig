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
        defer allocator.free(tokens);

        for (tokens) |token| {
            std.log.info("{s}", .{@tagName(token.type)});
        }
    } else {
        const stdin = std.io.getStdIn().reader();
        const bytes_read = try stdin.readUntilDelimiterAlloc(allocator, '\n', 1024);
        defer allocator.free(bytes_read);

        const tokens = try scanTokens(allocator, bytes_read);
        defer allocator.free(tokens);

        for (tokens) |token| {
            std.log.info("{s}", .{@tagName(token.type)});
        }
    }
}

pub fn scanTokens(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    // tokens is turned into owned slice at the end so no need to free it
    var tokens = std.ArrayList(Token).init(allocator);
    var line: usize = 1;

    var start: usize = 0;
    var end: usize = 1;
    while (start < source.len) : ({
        start = end;
        end += 1;
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
                break :blk try Token.initWithLexeme(token_type, line, source[start..end]);
            },
            '0'...'9' => blk: {
                while (end < source.len and std.ascii.isDigit(source[end])) end += 1;

                if (end + 1 < source.len and source[end] == '.' and std.ascii.isDigit(source[end + 1])) {
                    end += 1;
                    while (end < source.len and std.ascii.isDigit(source[end])) end += 1;
                }

                break :blk try Token.initWithLexeme(TokenType.NUMBER, line, source[start..end]);
            },
            '"' => blk: {
                while (end < source.len and source[end] != '"') : (end += 1) {
                    if (source[end] == '\n') {
                        line += 1;
                    }
                }
                end += 1;

                break :blk try Token.initWithLexeme(TokenType.STRING, line, source[start + 1 .. end - 1]);
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
    return tokens.toOwnedSlice();
}

test "Scans correctly" {
    const tokens = try scanTokens(std.testing.allocator, "1 + 2 * 3 - 4");
    defer std.testing.allocator.free(tokens);

    // std.debug.print("token: {s}\n", .{@tagName(tokens.items[0].type)});

    try std.testing.expectEqual(7, tokens.len);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[0].type);
    try std.testing.expectEqual(TokenType.PLUS, tokens[1].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[2].type);
    try std.testing.expectEqual(TokenType.STAR, tokens[3].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[4].type);
    try std.testing.expectEqual(TokenType.MINUS, tokens[5].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[6].type);
}
