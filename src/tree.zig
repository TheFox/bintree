const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const bufPrint = std.fmt.bufPrint;
const PrefixPathT = @import("types.zig").PrefixPathT;

pub fn RootNode(allocator: Allocator, max_level: usize) Node {
    return Node.init(allocator, 0, 0, max_level);
}

pub const Node = struct {
    allocator: Allocator,
    value: u8,
    children: ArrayList(Node),
    count: usize,
    level: usize,
    max_level: usize,

    pub fn init(allocator: Allocator, value: u8, level: usize, max_level: usize) Node {
        const children = ArrayList(Node).init(allocator);
        return Node{
            .allocator = allocator,
            .value = value,
            .children = children,
            .count = 0,
            .level = level,
            .max_level = max_level,
        };
    }

    pub fn deinit(self: *const Node) void {
        for (self.children.items) |node| {
            node.deinit();
        }
        self.children.deinit();
    }

    pub fn addChild(self: *Node, child: Node) !void {
        try self.children.append(child);
    }

    pub fn addBytes(self: *Node, bytes: []const u8) !void {
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

        if (self.level >= self.max_level) {
            return;
        }

        var child = Node.init(self.allocator, bytes[0], self.level + 1, self.max_level);
        try child.addBytes(bytes[1..]);
        try self.addChild(child);
    }

    pub fn show(self: *const Node, level: usize, is_last: bool, prefix_path: *const PrefixPathT) !void {
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
            print("root c={d} ({d})\n", .{
                self.count,
                self.children.items.len,
            });
        } else {
            const iprefix = if (is_last) "└" else "├";
            print("{s}─ 0x{X:0>2} c={d} ({d})\n", .{
                iprefix,
                self.value,
                self.count,
                self.children.items.len,
            });
        }
        const child_len = self.children.items.len;
        var n: usize = 0;
        for (self.children.items) |child| {
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

            try child.show(level + 1, child_is_last, &new_path);
        }
    }
};

test "simple_node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const root = Node.init(allocator, 0, 0, 2);
    defer root.deinit();
}

test "simple_string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const root = Node.init(allocator, 0, 0, 2);
    defer root.deinit();

    root.addBytes("ABCD");
}
