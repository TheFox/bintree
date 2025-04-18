const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const StringArrayHashMap = std.StringArrayHashMap(*Node);
const sort = std.mem.sort;
const print = std.debug.print;
const fmtSliceHexUpper = std.fmt.fmtSliceHexUpper;
const expect = std.testing.expect;
const dupe = std.mem.Allocator.dupe;
const xpath_import = @import("xpath.zig");
const Xpath = xpath_import.Xpath;
const XpathList = xpath_import.XpathList;

fn compareStringsAsc(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn RootNode(allocator: Allocator, parse_rules: *XpathList) *Node {
    return Node.init(allocator, null, parse_rules);
}

pub const Node = struct {
    allocator: Allocator,
    parse_rules: *XpathList,
    parent: ?*Node,
    children: StringArrayHashMap,
    value: []const u8 = undefined,
    count: usize = 0,
    node_level: usize = 0,
    max_node_level: usize = 0,

    pub fn init(allocator: Allocator, parent: ?*Node, parse_rules: *XpathList) *Node {
        const children = StringArrayHashMap.init(allocator);

        const node = allocator.create(Node) catch unreachable;
        node.* = Node{
            .allocator = allocator,
            .parse_rules = parse_rules,
            .parent = parent,
            .children = children,
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

    pub fn reportMaxNodeLevel(self: *Node, max_node_level: usize) void {
        print("-> reportMaxNodeLevel: {any}\n", .{max_node_level});
        if (max_node_level > self.max_node_level) {
            self.max_node_level = max_node_level - self.node_level;
        }

        if (self.parent) |parent_node| {
            parent_node.reportMaxNodeLevel(max_node_level);
        }
    }

    pub fn addInput(self: *Node, input_line: []u8, max_parse_level: usize) !void {
        self.count += 1;
        print("\x1b[0;31maddInput({*}, {d}, {d}) -> count: {d}\x1b[0m\n", .{ self, input_line.len, max_parse_level, self.count });
        // defer print("\n", .{});

        if (input_line.len == 0) {
            print("-> input line is empty\n", .{});
            return;
        }
        print("-> input_line: {any}\n", .{input_line});

        var rest_parse_rules = XpathList.init(self.allocator);
        defer rest_parse_rules.deinit();

        var selected = ArrayList(u8).init(self.allocator);
        defer selected.deinit();
        var rest: []u8 = undefined;

        for (self.parse_rules.items) |rule| {
            print("\x1b[32m-> parse rule: {d} {any} {any}\x1b[0m\n", .{ selected.items.len, rule.kind, rule.nvalue });

            var break_rules = false;
            var currx: *Xpath = rule;
            var next_xpath = false;
            var xpath_left = true;
            var input_pos: usize = 0;
            var select_left: usize = 0;
            for (input_line) |input_c| {
                print("--> input_c: {X} {d}\n", .{ input_c, input_pos });
                print("--> currx: {any}\n", .{currx.nvalue});

                switch (currx.kind) {
                    .init, .root => {
                        unreachable;
                    },
                    .level => {
                        unreachable;
                    },
                    .select => {
                        if (currx.nvalue == input_c) {
                            print("\x1b[32m---> equals: {X}\x1b[0m\n", .{input_c});
                            try selected.append(input_c);
                            break_rules = true;
                            next_xpath = true;
                        } else {
                            print("\x1b[32m---> break input [select]\x1b[0m\n", .{});
                            break;
                        }
                    },
                    .ignore => {
                        unreachable;
                    },
                    .delete => {
                        print("---> delete\n", .{});

                        if (currx.nvalue == input_c) {
                            print("\x1b[32m---> delete: {X}\x1b[0m\n", .{input_c});
                            break_rules = true;
                            next_xpath = true;
                        }
                    },
                    .group => {
                        if (select_left > 0) {
                            try selected.append(input_c);
                            print("---> group: left={d} {any}\n", .{ select_left, selected.items });
                            select_left -= 1;
                            if (select_left == 0) {
                                break_rules = true;
                                next_xpath = true;
                            }
                        } else {
                            if (currx.nvalue) |nvalue| {
                                print("---> nvalue={d}\n", .{nvalue});
                                select_left = @intCast(nvalue);
                                select_left -= 1;
                                try selected.append(input_c);
                                print("---> group: left={d} {any}\n", .{ select_left, selected.items });
                            }
                        }
                    },
                }

                input_pos += 1;

                if (next_xpath) {
                    if (currx.next) |next| {
                        currx = next;
                    } else {
                        print("-> xpath_left is false\n", .{});
                        xpath_left = false;
                        break;
                    }
                }
            }

            if (xpath_left) {
                print("-> has xpath_left\n", .{});
                try rest_parse_rules.append(currx);
            } else {
                print("-> NO xpath_left\n", .{});
            }

            rest = input_line[input_pos..];
            print("-> rest: {X}\n", .{input_line[input_pos..]});
            print("-> selected: {X}\n", .{selected.items});
            print("-> break_rules: {any}\n", .{break_rules});

            if (break_rules) {
                break;
            }
        }

        print("-> rest_parse_rules: len={d}\n", .{rest_parse_rules.items.len});
        print("-> rest: {*} {d}\n", .{ rest, rest.len });
        print("-> rest is same input: {any}\n", .{rest.len == input_line.len});

        if (self.node_level >= max_parse_level) {
            print("-> max parse level reached: {d}\n", .{self.node_level});
            return;
        }

        var key: []u8 = undefined;
        if (self.parse_rules.items.len > 0 and selected.items.len > 0) {
            print("\x1b[33m-> parse_rules: {d}\x1b[0m\n", .{self.parse_rules.items.len});
            print("\x1b[33m-> selected.items: {d}\x1b[0m\n", .{selected.items.len});
            key = selected.items;
            print("-> key A: {X}\n", .{key});
        } else {
            print("\x1b[33m-> parse_rules & selected: (0)\x1b[0m\n", .{});
            key = input_line[0..1];
            rest = input_line[1..];
            print("-> key B: {X}\n", .{key});
        }

        print("-> key X: {X}\n", .{key});
        print("-> rest X: {X}\n", .{rest});

        print("-> get()\n", .{});
        if (self.children.get(key)) |node| {
            print("-> get() -> found\n", .{});
            try node.addInput(rest, max_parse_level);
            return;
        }
        print("-> get() -> not found\n", .{});

        print("-> key X2: {X}\n", .{key});
        const key_str = try std.fmt.allocPrint(self.allocator, "{s}", .{key});
        print("-> key_str: {X}\n", .{key_str});

        var child = Node.init(self.allocator, self, &rest_parse_rules);
        child.value = key_str;
        child.node_level = self.node_level + 1;
        try child.addInput(rest, max_parse_level);

        print("-> key C: {X}\n", .{key_str});
        try self.children.put(key_str, child);

        print("-> children: {d}\n", .{self.children.count()});

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

        // print("show()\n", .{});
        // print("-> node_level: {d}\n", .{self.node_level});

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
                self.value,
                self.count,
                self.node_level,
                self.max_node_level,
                self.children.count(),
            });
        }

        if (cur_level >= max_show_level) {
            // print("cur_level: {d}\n", .{cur_level});
            // print("max_show_level: {d}\n", .{max_show_level});
            return;
        }

        // Sort by key.
        var iter = self.children.iterator();
        var keys = ArrayList([]const u8).init(self.allocator);
        defer keys.deinit();
        while (iter.next()) |entry| {
            // print("-> iter key: {X}\n", .{entry.key_ptr.*});
            try keys.append(entry.key_ptr.*);
        }
        sort([]const u8, keys.items, {}, comptime compareStringsAsc);
        // print("keys: {d}\n", .{keys.items.len});

        // Filter
        var filered = ArrayList(*Node).init(self.allocator);
        defer filered.deinit();
        for (keys.items) |key|
            if (self.children.get(key)) |child|
                if (child.count >= arg_min_count_level)
                    try filered.append(child);

        // for (keys.items) |key| {
        //     print("-> key: {X}\n", .{key});
        // }
        // print("filered: {d}\n", .{filered.items.len});

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

test "simple_node" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var rules: XpathList = XpathList.init(allocator);
    const node = RootNode(allocator, &rules);
    defer node.deinit();
}

test "simple_string" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var rules: XpathList = XpathList.init(allocator);

    const buffer1 = dupe(allocator, u8, "\x01\x02\x03") catch unreachable;
    const buffer2 = dupe(allocator, u8, "\x01\x02\x04") catch unreachable;

    const node = RootNode(allocator, &rules);
    defer node.deinit();

    try node.addInput(buffer1, 256);
    try node.addInput(buffer2, 256);

    print("node.count: {d}\n", .{node.count});
    try expect(node.count == 2);
    try expect(node.children.count() == 1);

    // if (node.children.get(1)) |subnode1| {
    //     try expect(subnode1.value == 1);
    //     try expect(subnode1.children.count() == 1);

    //     if (subnode1.children.get(2)) |subnode2| {
    //         try expect(subnode2.value == 2);
    //         try expect(subnode2.children.count() == 2);

    //         if (subnode2.children.get(3)) |subnode3| {
    //             try expect(subnode3.value == 3);
    //             try expect(subnode3.children.count() == 0);
    //         } else {
    //             try expect(false);
    //         }

    //         if (subnode2.children.get(4)) |subnode4| {
    //             try expect(subnode4.value == 4);
    //             try expect(subnode4.children.count() == 0);
    //         } else {
    //             try expect(false);
    //         }
    //     } else {
    //         try expect(false);
    //     }
    // } else {
    //     try expect(false);
    // }
}
