const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const bufPrint = std.fmt.bufPrint;
const types = @import("types.zig");
const PrefixPathT = types.PrefixPathT;
const LevelT = types.LevelT;

pub fn RootNode(allocator: Allocator) Node {
    return Node.init(allocator, null, 0, 0);
}

pub const Node = struct {
    allocator: Allocator,
    value: u8,
    parent: ?*Node,
    children: ArrayList(Node),
    count: usize,
    level: LevelT,
    max_level: LevelT,

    pub fn init(allocator: Allocator, parent: ?*Node, value: u8, level: LevelT) Node {
        const children = ArrayList(Node).init(allocator);
        return Node{
            .allocator = allocator,
            .value = value,
            .parent = parent,
            .children = children,
            .count = 0,
            .level = level,
            .max_level = 0,
        };
    }

    pub fn deinit(self: *const Node) void {
        print("Node.deinit: {any}\n", .{@intFromPtr(self.parent)});
        for (self.children.items) |node| {
            node.deinit();
        }
        self.children.deinit();
    }

    pub fn reportLevel(self: *Node, max_level: LevelT) void {
        print("reportLevel: {d} -> {d}\n", .{ self.level, max_level });
        // self.max_level = max_level;

        if (self.parent) |parent| {
            print("Parent exists at: {*}---\n", .{parent});
            parent.reportLevel(max_level);
            print("Parent exists OK\n", .{});
            // } else {
            //     print("No parent, stopping recursion.\n", .{});
        }
    }

    pub fn addBytes(self: *Node, bytes: []const u8) !void {
        print("addBytes\n", .{});
        self.count += 1;
        if (bytes.len == 0) {
            return;
        }

        // Search in children for exact value.
        // Should be Assoc Array instead.
        for (self.children.items) |*child| {
            if (child.value == bytes[0]) {
                try child.addBytes(bytes[1..]);
                return;
            }
        }

        // Debug
        print("addBytes A---\n", .{});
        for (self.children.items) |*achild| {
            print("addBytes A: {any}\n", .{@intFromPtr(achild)});
        }

        const new_level: LevelT = self.level + 1;
        var child = Node.init(self.allocator, self, bytes[0], new_level);
        // print("current node: {d} {*} new node: {*}\n", .{ self.level, self, &child });
        try child.addBytes(bytes[1..]);
        try self.children.append(child);

        // self.reportLevel(new_level); // ERROR

        // Debug
        print("addBytes B---\n", .{});
        for (self.children.items) |*bchild| {
            print("addBytes B: {any}\n", .{@intFromPtr(bchild)});
        }
    }

    pub fn show(self: *const Node, level: LevelT, max_level: LevelT, is_last: bool, prefix_path: *const PrefixPathT) !void {
        // https://stackoverflow.com/questions/21924487/how-get-ascii-characters-similar-to-output-of-the-linux-command-tree
        // Char: '├' => $'\342\224\234'
        // Char: '─' => $'\342\224\200'
        // Char: '│' => $'\342\224\202'
        // Char: ' ' => $'\302\240'
        // Char: '└' => $'\342\224\224'

        if (level > 0)
            for (0..(level - 1)) |n|
                print("{s}    ", .{prefix_path.items[n]});

        if (self.level == 0) {
            @branchHint(.unlikely);
            print("root c={d} ML={d} ({d})\n", .{
                self.count,
                self.max_level,
                self.children.items.len,
            });
        } else {
            const iprefix = if (is_last) "└" else "├";
            print("{s}─ 0x{X:0>2} c={d} ML={} ({d})\n", .{
                iprefix,
                self.value,
                self.count,
                self.max_level,
                self.children.items.len,
            });
        }

        if (level >= max_level) {
            return;
        }

        const child_len = self.children.items.len;
        var n: usize = 0;
        for (self.children.items) |child| {
            print("level {d}, child {*}\n", .{ self.level, &child });
            n += 1;
            const child_is_last = n == child_len;

            var new_path = try PrefixPathT.initCapacity(self.allocator, prefix_path.items.len);
            defer new_path.deinit();
            try new_path.appendSlice(prefix_path.items);

            if (child_is_last) {
                try new_path.append(" ");
            } else {
                try new_path.append("│");
            }

            try child.show(level + 1, max_level, child_is_last, &new_path);
        }
    }
};

test "simple_node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const root = Node.init(allocator, null, 0, 0, 2);
    defer root.deinit();
}

test "simple_string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const root = Node.init(allocator, null, 0, 0, 2);
    defer root.deinit();

    root.addBytes("ABCD");
}
