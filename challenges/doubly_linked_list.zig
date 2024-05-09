const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn LinkedList(comptime T: type) type {
    return struct {
        const Node = struct { prev: ?*Node = null, next: ?*Node = null, data: T };
        const Self = @This();

        first: ?*Node = null,
        last: ?*Node = null,
        allocator: Allocator,

        fn deinit(self: *Self) void {
            var current = self.first;
            while (current) |n| {
                const next = n.next;
                self.allocator.destroy(n);
                current = next;
            }
            self.first = null;
            self.last = null;
        }

        pub fn init(allocator: Allocator, elements: []T) !Self {
            var list = Self{ .allocator = allocator };
            for (elements) |element| {
                try list.push(element);
            }
            return list;
        }

        pub fn is_empty(self: Self) bool {
            return self.first == null and self.last == null;
        }

        pub fn insert(self: *Self, data: T, new_data: T) !void {
            const node = self.find(data) orelse return error.NodeNotInList;
            const new_node = try self.allocator.create(Node);
            node.* = .{ .data = new_data };

            new_node.next = node;
            if (node.prev) |prev| {
                new_node.prev = prev;
                prev.next = &new_node;
            } else {
                new_node.prev = null;
                self.first = &new_node;
            }
            node.prev = &new_node;
        }

        pub fn push(self: *Self, data: T) !void {
            const node = try self.allocator.create(Node);
            node.* = .{ .data = data };

            if (self.last) |last| {
                last.next = node;
                node.prev = last;
                self.last = node;
            } else {
                self.first = node;
                node.prev = null;
            }

            node.next = null;
            self.last = node;
        }

        pub fn remove(self: *Self, data: T) !T {
            const node = self.find(data) orelse return error.NodeNotInList;

            if (node.prev) |prev| {
                prev.next = node.next;
            } else {
                self.first = node.next;
            }

            if (node.next) |next| {
                next.prev = node.prev;
            } else {
                self.last = node.prev;
            }

            return node;
        }

        pub fn find(self: Self, data: T) ?*Node {
            var current = self.first;
            return while (current) |cur| : (current = cur.next) {
                if (std.mem.eql(u8, cur.data, data)) {
                    break cur;
                }
            } else null;
        }
    };
}

test "initialization" {
    const testing = std.testing;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var data = [_][]const u8{ "hello", "world" };

    var list = try LinkedList([]const u8).new(allocator, &data);
    defer list.deinit();

    try testing.expect(list.find("hello") != null);
    try testing.expect(list.find("world") != null);
}
