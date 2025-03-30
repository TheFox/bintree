const std = @import("std");
const print = std.debug.print;
const tree = @import("tree.zig");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;

const UnmanagedXpath = struct {
    allocator: Allocator,
    next: ?*UnmanagedXpath = null,
    value: ?u8 = null,
    group: ?usize = null,
    xtype: enum {
        root,
        select,
        range,
        group,
    },

    pub fn deinit(self: *UnmanagedXpath) void {
        if (self.next) |sub| {
            sub.deinit();
        }
        self.allocator.destroy(self);
    }
};

fn Xpath(allocator: Allocator, query: []const u8) !*UnmanagedXpath {
    print("Xpath({s})\n", .{query});

    const xpath = allocator.create(UnmanagedXpath) catch unreachable;
    xpath.* = UnmanagedXpath{
        .allocator = allocator,
        .xtype = .root,
    };
    var qp: usize = 0;
    while (qp < query.len) {
        const qc = query[qp];
        print("query char: '{c}' @ {d}\n", .{ qc, qp });
        switch (qc) {
            '/' => {
                qp += 1;
                print("next: '{s}'\n", .{query[qp..]});
                // xpath.next = Xpath(allocator, query[qp..]);
            },
            's' => {
                // Select
                qp += 1;
                const end = qp + 2;
                print("select s: '{s}'\n", .{query[qp..end]});
                const c = try parseInt(u8, query[qp..end], 16);
                print("select c: {X}\n", .{c});
                xpath.xtype = .select;
                qp += 2;
            },
            'g' => {
                // Group
                qp += 1;
                var buf: [4096]u8 = undefined;
                var bn: u16 = 0;
                while (qp < query.len and bn < 4096 and query[qp] >= '0' and query[qp] <= '9') {
                    print("group c: '{c}'\n", .{query[qp]});
                    buf[bn] = query[qp];
                    qp += 1;
                    bn += 1;
                    // print("group cn: '{c}'\n", .{query[qp]});
                }
                xpath.group = try parseInt(usize, buf[0..bn], 10);
            },
            else => {
                print("Unknown query character: '{c}'\n", .{qc});
                @panic("Unknown query character");
            },
        }
    }
    return xpath;
}

test "null xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = Xpath(allocator, "/");
    defer xpath.deinit();

    try expect(xpath.value == null);
    try expect(xpath.next == null);
}

test "simple xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/s01/g3");
    defer xpath.deinit();
}

// test "group node with xpath" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();

//     const xpath = xpathFromUserInput(allocator, "/s01/g3");

//     var node = tree.RootNode(allocator);
//     defer node.deinit();

//     try node.addBytes("\x01\x02\x03\x04\x05", 256);
//     try node.addBytes("\x02\x03\x04\x05\x06", 256);
// }
