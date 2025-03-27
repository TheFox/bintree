const std = @import("std");
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const bufPrint = std.fmt.bufPrint;
const types = @import("types.zig");
const PrefixPathT = types.PrefixPathT;
const LevelT = types.LevelT;
const ChildList = AutoHashMap(u8, *Node);

pub fn RootNode(allocator: Allocator) *Node {
    return Node.init(allocator, null, 0, 0);
}

pub const Node = struct {
    allocator: Allocator,
    value: u8,
    parent: ?*Node,
    children: ChildList,
    count: usize,
    level: LevelT,
    max_depth: LevelT,

    pub fn init(allocator: Allocator, parent: ?*Node, value: u8, level: LevelT) *Node {
        const children = ChildList.init(allocator);
        const node = allocator.create(Node) catch unreachable;
        node.* = Node{
            .allocator = allocator,
            .value = value,
            .parent = parent,
            .children = children,
            .count = 0,
            .level = level,
            .max_depth = 0,
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        var iter = self.children.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr.*;
            node.deinit();
        }
        self.children.deinit();
        self.allocator.destroy(self);
    }

    pub fn reportMaxDepth(self: *Node, max_depth: LevelT) void {
        if (max_depth > self.max_depth)
            self.max_depth = max_depth;

        if (self.parent) |parent_node|
            parent_node.reportMaxDepth(max_depth);
    }

    pub fn addBytes(self: *Node, bytes: []const u8) !void {
        self.count += 1;
        if (bytes.len == 0)
            return;

        const key = bytes[0];

        if (self.children.get(key)) |node| {
            try node.addBytes(bytes[1..]);
            return;
        }

        const new_level: LevelT = self.level + 1;
        var child = Node.init(self.allocator, self, bytes[0], new_level);
        try child.addBytes(bytes[1..]);
        try self.children.put(key, child);

        self.reportMaxDepth(new_level);
    }

    pub fn show(self: *const Node, level: LevelT, max_depth: LevelT, is_last: bool, prefix_path: *const PrefixPathT) !void {
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
            print("root c={d} d={d} ({d})\n", .{
                self.count,
                self.max_depth,
                self.children.count(),
            });
        } else {
            const iprefix = if (is_last) "└" else "├";
            print("{s}─ 0x{X:0>2} c={d} d={} ({d})\n", .{
                iprefix,
                self.value,
                self.count,
                self.max_depth,
                self.children.count(),
            });
        }

        if (level >= max_depth) {
            return;
        }

        var iter = self.children.iterator();
        var keys = std.ArrayList(u8).init(self.allocator);
        defer keys.deinit();
        while (iter.next()) |entry|
            try keys.append(entry.key_ptr.*);
        std.mem.sort(u8, keys.items, {}, comptime std.sort.asc(u8));

        const child_len = self.children.count();
        var n: usize = 0;
        for (keys.items) |key| {
            const child = self.children.get(key).?;

            n += 1;
            const child_is_last = n == child_len;

            var new_path = try PrefixPathT.initCapacity(self.allocator, prefix_path.items.len);
            defer new_path.deinit();
            try new_path.appendSlice(prefix_path.items);

            try new_path.append(if (child_is_last) " " else "│");

            try child.show(level + 1, max_depth, child_is_last, &new_path);
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
