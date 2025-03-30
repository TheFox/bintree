const std = @import("std");
const fmt = std.fmt;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const eql = std.mem.eql;
const bufPrint = std.fmt.bufPrint;
const types = @import("types.zig");
const PrefixPathT = types.PrefixPathT;
const LevelT = types.LevelT;
const ChildList = AutoHashMap(u8, *Node);
const expect = std.testing.expect;
const xpath = @import("xpath.zig");
const XpathList = xpath.XpathList;
const VAL_MAX_LEN = 128;
const NodeValue = [VAL_MAX_LEN]u8;

pub fn RootNode(allocator: Allocator) *Node {
    return Node.init(allocator, null);
}

pub const Node = struct {
    allocator: Allocator,
    value: NodeValue = undefined,
    vlen: u8 = 0,
    parent: ?*Node,
    children: ChildList,
    count: usize,
    node_level: LevelT,
    max_node_level: LevelT,
    // parse_xpaths: XpathList = XpathList.init(),

    pub fn init(allocator: Allocator, parent: ?*Node) *Node {
        const children = ChildList.init(allocator);
        const node = allocator.create(Node) catch unreachable;
        node.* = Node{
            .allocator = allocator,
            // .value = undefined,
            .parent = parent,
            .children = children,
            .count = 0,
            .node_level = 0,
            .max_node_level = 0,
            // .parse_xpaths = parse_xpaths,
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
            return;
        }

        var child = Node.init(self.allocator, self);
        child.node_level = self.node_level + 1;
        child.vlen = 1;
        @memcpy(child.value[0..1], bytes[0..1]);

        try child.addBytes(bytes[1..], max_parse_level);

        try self.children.put(key, child);
        self.reportMaxNodeLevel(child.node_level);
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
            const hex_val: [128]u8 = undefined;
            const hex_len = try bufPrint(&hex_val, "{X:0>2}", .{self.value});
            const iprefix = if (is_last) "└" else "├";
            print("{s}─ 0x{s} count={d} level={d} depth={d} children={d}\n", .{
                iprefix,
                hex_val[0..hex_len],
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

test "simple node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const node = RootNode(allocator);
    defer node.deinit();
}

test "simple string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const node = RootNode(allocator);
    defer node.deinit();

    try node.addBytes("\x01\x02\x03", 256);
    try node.addBytes("\x01\x02\x04", 256);

    try expect(node.count == 2);
    try expect(node.children.count() == 1);

    if (node.children.get(1)) |subnode1| {
        try expect(subnode1.children.count() == 1);
        try expect(eql(u8, subnode1.value[0..subnode1.vlen], "\x01"));

        if (subnode1.children.get(2)) |subnode2| {
            try expect(subnode2.children.count() == 2);
            try expect(eql(u8, subnode2.value[0..subnode2.vlen], "\x02"));

            if (subnode2.children.get(3)) |subnode3| {
                try expect(subnode3.children.count() == 0);
                try expect(eql(u8, subnode3.value[0..subnode3.vlen], "\x03"));
            } else {
                try expect(false);
            }

            if (subnode2.children.get(4)) |subnode4| {
                try expect(subnode4.children.count() == 0);
                try expect(eql(u8, subnode4.value[0..subnode4.vlen], "\x04"));
            } else {
                try expect(false);
            }
        } else {
            try expect(false);
        }
    } else {
        try expect(false);
    }
}
