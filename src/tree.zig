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
    node_level: LevelT,
    max_node_level: LevelT,

    pub fn init(allocator: Allocator, parent: ?*Node, value: u8, node_level: LevelT) *Node {
        const children = ChildList.init(allocator);
        const node = allocator.create(Node) catch unreachable;
        node.* = Node{
            .allocator = allocator,
            .value = value,
            .parent = parent,
            .children = children,
            .count = 0,
            .node_level = node_level,
            .max_node_level = 0,
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

    pub fn reportMaxNodeLevel(self: *Node, max_node_level: LevelT) void {
        if (max_node_level > self.max_node_level)
            self.max_node_level = max_node_level - self.node_level;

        if (self.parent) |parent_node|
            parent_node.reportMaxNodeLevel(max_node_level);
    }

    pub fn reportMaxNodeLevel2(self: *Node) void {
        self.max_node_level += 1;

        if (self.parent) |parent_node|
            parent_node.reportMaxNodeLevel2();
    }

    pub fn addBytes(self: *Node, bytes: []const u8, max_parse_level: LevelT) !void {
        self.count += 1;
        if (bytes.len == 0)
            return;

        const key = bytes[0];
        if (self.children.get(key)) |node| {
            try node.addBytes(bytes[1..], max_parse_level);
            return;
        }

        if (self.node_level >= max_parse_level) {
            // print("max_parse_level reached: {d}={d}\n", .{ self.node_level, max_parse_level });
            return;
        }

        const new_level: LevelT = self.node_level + 1;
        var child = Node.init(self.allocator, self, bytes[0], new_level);
        try child.addBytes(bytes[1..], max_parse_level);
        try self.children.put(key, child);

        self.reportMaxNodeLevel(new_level);
        // self.reportMaxNodeLevel2();
    }

    pub fn show(
        self: *const Node,
        cur_level: LevelT, // Recursive Traverse
        max_show_level: LevelT,
        arg_min_count_level: usize,
        is_last: bool,
        prefix_path: *const PrefixPathT,
    ) !void {
        // https://stackoverflow.com/questions/21924487/how-get-ascii-characters-similar-to-output-of-the-linux-command-tree
        // Char: '├' => $'\342\224\234'
        // Char: '─' => $'\342\224\200'
        // Char: '│' => $'\342\224\202'
        // Char: ' ' => $'\302\240'
        // Char: '└' => $'\342\224\224'

        if (cur_level > 0)
            for (0..(cur_level - 1)) |n|
                print("{s}    ", .{prefix_path.items[n]});

        if (self.node_level == 0) {
            @branchHint(.unlikely);
            print("root count={d} depth={d} children={d}\n", .{
                self.count,
                self.max_node_level,
                self.children.count(),
            });
        } else {
            const iprefix = if (is_last) "└" else "├";
            print("{s}─ 0x{X:0>2} count={d} level={d} depth={d} children={d}\n", .{
                iprefix,
                self.value,
                self.count,
                self.node_level,
                self.max_node_level,
                self.children.count(),
            });
        }

        if (cur_level >= max_show_level) {
            return;
        }

        // Sort by key.
        var iter = self.children.iterator();
        var keys = ArrayList(u8).init(self.allocator);
        defer keys.deinit();
        while (iter.next()) |entry|
            try keys.append(entry.key_ptr.*);
        std.mem.sort(u8, keys.items, {}, comptime std.sort.asc(u8));

        // Filter
        var filered = ArrayList(*Node).init(self.allocator);
        defer filered.deinit();
        for (keys.items) |key| {
            if (self.children.get(key)) |child| {
                if (child.count >= arg_min_count_level) {
                    try filered.append(child);
                }
            }
        }

        // Print
        const child_len = filered.items.len;
        var loop_n: usize = 0;
        for (filered.items) |child| {
            loop_n += 1;

            const child_is_last = loop_n == child_len;

            var new_path = try PrefixPathT.initCapacity(self.allocator, prefix_path.items.len);
            defer new_path.deinit();
            try new_path.appendSlice(prefix_path.items);

            try new_path.append(if (child_is_last) " " else "│");

            try child.show(cur_level + 1, max_show_level, arg_min_count_level, child_is_last, &new_path);
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
