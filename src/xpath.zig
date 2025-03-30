const std = @import("std");
const print = std.debug.print;
const tree = @import("tree.zig");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;
const ArrayList = std.ArrayList;

const TokenType = enum {
    slash,
    number,
    xtype,
};

const XsubType = enum {
    xselect,
    xgroup,
    xany,
};

const Token = struct {
    ttype: TokenType,
    xsubtype: XsubType,
    value: u8,

    fn deinit(self: *Token) void {
        print("Token.deinit({s})\n", .{self.value});
    }
};

fn scanner(allocator: Allocator, query: []const u8) !ArrayList(Token) {
    var tokenz = ArrayList(Token).init(allocator);
    var pre_tt: TokenType = undefined;
    for (query) |qc| {
        print("query c: '{c}'\n", .{qc});
        var ttype: TokenType = undefined;
        var xsubtype: XsubType = undefined;
        switch (qc) {
            '/' => {
                ttype = .slash;
            },
            '0'...'9' => {
                ttype = .number;
            },
            's', 'g', '.' => {
                if (pre_tt == .slash) {
                    ttype = .xtype;
                    xsubtype = switch (qc) {
                        's' => .xselect,
                        'g' => .xgroup,
                        '.' => .xany,
                        else => unreachable,
                    };
                } else {
                    unreachable;
                }
            },
            else => unreachable,
        }
        const token = Token{
            .ttype = ttype,
            .xsubtype = xsubtype,
            .value = qc,
        };
        try tokenz.append(token);
        pre_tt = token.ttype;
    }
    return tokenz;
}

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
        any,
    },

    pub fn deinit(self: *UnmanagedXpath) void {
        if (self.next) |sub| {
            sub.deinit();
        }
        self.allocator.destroy(self);
    }
};

fn Xpath1(allocator: Allocator, query: []const u8) !*UnmanagedXpath {
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
                xpath.next = try Xpath(allocator, query[qp..]);
            },
            's' => {
                // Select
                xpath.xtype = .select;
                qp += 1;
                const end = qp + 2;
                print("select s: '{s}'\n", .{query[qp..end]});
                const c = try parseInt(u8, query[qp..end], 16);
                print("select c: {X}\n", .{c});
                xpath.value = c;
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
            '.' => {
                // Any
            },
            else => {
                print("Unknown query character: '{c}'\n", .{qc});
                @panic("Unknown query character");
            },
        }
    }
    return xpath;
}

fn Xpath(allocator: Allocator, query: []const u8) !*UnmanagedXpath {
    const tokenz = try scanner(allocator, query);
    defer tokenz.deinit();
}

test "scanner" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const tokenz = try scanner(allocator, "/s30/g5/.");
    defer tokenz.deinit();

    try expect(tokenz.items.len == 9);

    try expect(tokenz.items[0].value == '/');

    try expect(tokenz.items[0].ttype == .slash);
    try expect(tokenz.items[1].ttype == .xtype);
    try expect(tokenz.items[2].ttype == .number);
    try expect(tokenz.items[3].ttype == .number);
    try expect(tokenz.items[4].ttype == .slash);
    try expect(tokenz.items[5].ttype == .xtype);
    try expect(tokenz.items[6].ttype == .number);
    try expect(tokenz.items[7].ttype == .slash);
    try expect(tokenz.items[8].ttype == .xtype);

    try expect(tokenz.items[1].xsubtype == .xselect);
    try expect(tokenz.items[5].xsubtype == .xgroup);
    try expect(tokenz.items[8].xsubtype == .xany);
}

// test "null xpath" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();

//     const xpath = Xpath(allocator, "/");
//     defer xpath.deinit();

//     try expect(xpath.value == null);
//     try expect(xpath.next == null);
// }

// test "simple xpath" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();

//     const xpath = try Xpath(allocator, "/s01/g3");
//     defer xpath.deinit();

//     if (xpath.next) |xpath1| {
//         try expect(xpath1.value == 1);
//         try expect(xpath1.xtype == .select);

//         if (xpath1.next) |xpath2| {
//             try expect(xpath2.xtype == .group);
//             try expect(xpath2.group == 3);
//         } else {
//             try expect(false);
//         }
//     } else {
//         try expect(false);
//     }
// }

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
