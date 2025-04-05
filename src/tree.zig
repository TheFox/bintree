const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const print = std.debug.print;
const fmtSliceHexUpper = std.fmt.fmtSliceHexUpper;

pub fn RootNode(allocator: Allocator) *Node {
    return Node.init(allocator, null);
}

pub const Node = struct {
    allocator: Allocator,
    parent: ?*Node,
    children: AutoHashMap(u8, *Node),
    value: u8 = undefined,
    count: usize = 0,
    node_level: usize = 0,
    max_node_level: usize = 0,

    pub fn init(allocator: Allocator, parent: ?*Node) *Node {
        const children = AutoHashMap(u8, *Node).init(allocator);
        // print("Node.init children cap A: {d}/{d}\n", .{ children.capacity(), children.count() });

        const node = allocator.create(Node) catch unreachable;
        node.* = Node{
            .allocator = allocator,
            .parent = parent,
            .children = children,
        };

        // print("Node.init children cap B: {d}/{d}\n", .{ children.capacity(), children.count() });
        return node;
    }

    pub fn deinit(self: *Node) void {
        // print("Node.deinit()\n", .{});

        var iter = self.children.iterator();
        while (iter.next()) |entry| {
            // print("Node.deinit subnode\n", .{});
            const node = entry.value_ptr.*;
            node.deinit();
        }

        // print("Node.deinit self.children.deinit\n", .{});
        self.children.deinit();

        // print("Node.deinit destroy self\n", .{});
        self.allocator.destroy(self);
    }

    pub fn reportMaxNodeLevel(self: *Node, max_node_level: usize) void {
        // print("reportMaxNodeLevel({d})\n", .{max_node_level});

        if (max_node_level > self.max_node_level) {
            self.max_node_level = max_node_level - self.node_level;
            // print("reportMaxNodeLevel new max: {d} ({d}-{d})\n", .{ self.max_node_level, max_node_level, self.node_level });
        }

        if (self.parent) |parent_node| {
            parent_node.reportMaxNodeLevel(max_node_level);
        }
    }

    pub fn addInput(self: *Node, input_line: []u8, max_parse_level: usize) !void {
        print("addInput({*}, {d})\n", .{ self, input_line.len });

        self.count += 1;
        if (input_line.len == 0) {
            return;
        }

        if (self.node_level >= max_parse_level) {
            return;
        }

        const key = input_line[0];
        // print("key: {X}\n", .{key});

        if (self.children.get(key)) |node| {
            try node.addInput(input_line[1..], max_parse_level);
            return;
        }

        var child = Node.init(self.allocator, self);
        child.value = key;
        child.node_level = self.node_level + 1;
        try child.addInput(input_line[1..], max_parse_level);

        try self.children.put(key, child);

        self.reportMaxNodeLevel(self.node_level);
    }

    pub fn show(
        self: *const Node,
        cur_level: usize, // Recursive Traverse
        max_show_level: usize,
        arg_min_count_level: usize,
        is_last: bool,
        prefix_path: *const ArrayList([]const u8),
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
            // const vh = fmtSliceHexUpper(self.value);

            const iprefix = if (is_last) "└" else "├";
            print("{s}─ 0x{X} count={d} level={d} depth={d} children={d}\n", .{
                iprefix,
                // fmtSliceHexUpper(self.value),
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

            var new_path = try ArrayList([]const u8).initCapacity(self.allocator, prefix_path.items.len);
            defer new_path.deinit();
            try new_path.appendSlice(prefix_path.items);

            try new_path.append(if (child_is_last) " " else "│");

            try child.show(cur_level + 1, max_show_level, arg_min_count_level, child_is_last, &new_path);
        }
    }
};
