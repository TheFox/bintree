const std = @import("std");
const print = std.debug.print;
const tree = @import("tree.zig");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;
const ArrayList = std.ArrayList;
const TOKEN_VAL_MAX_LEN = 128;
const eql = std.mem.eql;

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
    value: [TOKEN_VAL_MAX_LEN]u8 = undefined,
    vlen: u8 = 0,

    fn deinit(self: *Token) void {
        print("Token.deinit({s})\n", .{self.value});
    }
};

fn scanner(allocator: Allocator, query: []const u8) !ArrayList(Token) {
    var tokenz = ArrayList(Token).init(allocator);
    var pre_tt: TokenType = undefined;
    var qpos: usize = 0;
    while (qpos < query.len) {
        const qc = query[qpos];
        print("query c: '{c}'\n", .{qc});

        var token = Token{
            .ttype = undefined,
            .xsubtype = undefined,
        };

        switch (qc) {
            '/' => {
                token.ttype = .slash;
                qpos += 1;
            },
            '0'...'9' => {
                token.ttype = .number;

                var qpos_fwd = qpos;
                while (qpos_fwd < query.len and token.vlen < TOKEN_VAL_MAX_LEN and query[qpos_fwd] >= '0' and query[qpos_fwd] <= '9') : (qpos_fwd += 1) {
                    print("fwd: '{c}' {d} {any} {any}\n", .{ query[qpos_fwd], qpos_fwd, query[qpos_fwd] >= '0', query[qpos_fwd] <= '9' });
                    token.value[token.vlen] = query[qpos_fwd];
                    token.vlen += 1;
                }
                print("number value: '{s}'\n", .{token.value[0..token.vlen]});
                qpos = qpos_fwd;
            },
            's', 'g', '.' => {
                if (pre_tt == .slash) {
                    token.ttype = .xtype;

                    token.xsubtype = switch (qc) {
                        's' => .xselect,
                        'g' => .xgroup,
                        '.' => .xany,
                        else => unreachable,
                    };
                } else unreachable;

                qpos += 1;
            },
            else => unreachable,
        }

        try tokenz.append(token);
        pre_tt = token.ttype;
    }
    return tokenz;
}

test "scanner" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const tokenz = try scanner(allocator, "/s30/g5/.");
    defer tokenz.deinit();

    try expect(tokenz.items.len == 8);

    try expect(tokenz.items[0].ttype == .slash);
    try expect(tokenz.items[1].ttype == .xtype);
    try expect(tokenz.items[2].ttype == .number);
    try expect(tokenz.items[3].ttype == .slash);
    try expect(tokenz.items[4].ttype == .xtype);
    try expect(tokenz.items[5].ttype == .number);
    try expect(tokenz.items[6].ttype == .slash);
    try expect(tokenz.items[7].ttype == .xtype);

    try expect(tokenz.items[1].xsubtype == .xselect);
    try expect(tokenz.items[4].xsubtype == .xgroup);
    try expect(tokenz.items[7].xsubtype == .xany);

    // try expect(tokenz.items[2].value == '/');
    var item = tokenz.items[2];
    try expect(eql(u8, item.value[0..item.vlen], "30"));

    item = tokenz.items[5];
    try expect(eql(u8, item.value[0..item.vlen], "5"));
}

const UnmanagedXpath = struct {
    allocator: Allocator,
    next: ?*UnmanagedXpath = null,
    value: ?u8 = null,
    group: ?usize = null,
    xtype: enum {
        root,
        select,
        // range,
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

    const xpath = allocator.create(UnmanagedXpath) catch unreachable;
    xpath.* = UnmanagedXpath{
        .allocator = allocator,
        .xtype = .root,
    };

    var curr: *UnmanagedXpath = xpath;
    var pre_tt: TokenType = undefined;
    // var buf: [128]u8 = undefined;
    // var bn: u8 = 0;

    for (tokenz.items) |token| {
        print("token: {any}\n", .{token});

        switch (token.ttype) {
            .slash => {
                const subpath = allocator.create(UnmanagedXpath) catch unreachable;
                subpath.* = UnmanagedXpath{
                    .allocator = allocator,
                    .xtype = .root,
                };
                xpath.next = subpath;
                curr = subpath;
            },
            .number => {},
            // .xtype => {},
        }

        pre_tt = token.ttype;
    }

    return xpath;
}

test "null xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/");
    defer xpath.deinit();

    try expect(xpath.value == null);
    try expect(xpath.next == null);
}

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
