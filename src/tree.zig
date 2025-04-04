const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const print = std.debug.print;

pub fn RootNode(allocator: Allocator) *Node {
    return Node.init(allocator, null);
}

pub const Node = struct {
    allocator: Allocator,
    parent: ?*Node,
    children: AutoHashMap(u8, *Node),
    value: u8 = undefined,

    pub fn init(allocator: Allocator, parent: ?*Node) *Node {
        const children = AutoHashMap(u8, *Node).init(allocator);
        print("Node.init children cap A: {d}/{d}\n", .{ children.capacity(), children.count() });

        const node = allocator.create(Node) catch unreachable;
        node.* = Node{
            .allocator = allocator,
            .parent = parent,
            .children = children,
        };

        print("Node.init children cap B: {d}/{d}\n", .{ children.capacity(), children.count() });
        return node;
    }

    pub fn deinit(self: *Node) void {
        print("Node.deinit()\n", .{});

        var iter = self.children.iterator();
        while (iter.next()) |entry| {
            print("Node.deinit subnode\n", .{});
            const node = entry.value_ptr.*;
            node.deinit();
        }

        print("Node.deinit self.children.deinit\n", .{});
        self.children.deinit();

        print("Node.deinit destroy self\n", .{});
        self.allocator.destroy(self);
    }

    pub fn addInput(self: *Node, input_line: []u8) !void {
        print("addInput({*}, {d})\n", .{ self, input_line.len });
        print("Node.addInput children cap A: {d}/{d}\n", .{ self.children.capacity(), self.children.count() });

        if (input_line.len == 0) {
            print("addInput input_line is empty\n", .{});
            return;
        }

        print("rest: {d}\n", .{input_line[1..].len});

        var child = Node.init(self.allocator, self);
        try child.addInput(input_line[1..]);

        const key = input_line[0];
        print("key: {X}\n", .{key});

        try self.children.put(key, child);
        print("Node.addInput children cap B: {d}/{d}\n", .{ self.children.capacity(), self.children.count() });
    }
};
