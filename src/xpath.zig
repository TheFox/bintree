const std = @import("std");
const print = std.debug.print;
const tree = @import("tree.zig");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;
const ArrayList = std.ArrayList;
const TOKEN_VAL_MAX_LEN = 8;
const eql = std.mem.eql;

const TokenType = enum {
    init,
    slash,
    number,
    xtype,
};

const XsubType = enum {
    xinit,
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
    var pre_tt: TokenType = .init;
    var qpos: usize = 0;
    while (qpos < query.len) {
        const qc = query[qpos];
        // print("query c: {d} '{c}' {any}\n", .{ qpos, qc, pre_tt });

        var token = Token{
            .ttype = undefined,
            .xsubtype = undefined,
        };

        switch (qc) {
            '/' => {
                token.ttype = .slash;
                qpos += 1;
            },
            's', 'g', '.' => {
                switch (pre_tt) {
                    .slash => {
                        token.ttype = .xtype;

                        token.xsubtype = switch (qc) {
                            's' => .xselect,
                            'g' => .xgroup,
                            '.' => .xany,
                            else => unreachable,
                        };
                    },
                    else => unreachable,
                }

                qpos += 1;
            },
            '0'...'9' => {
                token.ttype = .number;

                var qpos_fwd = qpos;
                while (qpos_fwd < query.len and token.vlen < TOKEN_VAL_MAX_LEN and query[qpos_fwd] >= '0' and query[qpos_fwd] <= '9') : (qpos_fwd += 1) {
                    // print("fwd: '{c}' {d} {any} {any}\n", .{ query[qpos_fwd], qpos_fwd, query[qpos_fwd] >= '0', query[qpos_fwd] <= '9' });
                    token.value[token.vlen] = query[qpos_fwd];
                    token.vlen += 1;
                }
                // print("number value: '{s}'\n", .{token.value[0..token.vlen]});
                qpos = qpos_fwd;
            },

            else => unreachable,
        }

        // print("new token: {any}\n", .{token});

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

    var item = tokenz.items[2];
    try expect(eql(u8, item.value[0..item.vlen], "30"));

    item = tokenz.items[5];
    try expect(eql(u8, item.value[0..item.vlen], "5"));
}

const UnmanagedXpath = struct {
    allocator: Allocator,
    next: ?*UnmanagedXpath = null,
    value: ?u16 = null,
    xtype: enum {
        init,
        root,
        // level,
        select,
        group,
        any,
    },

    pub fn deinit(self: *UnmanagedXpath) void {
        if (self.next) |sub| {
            sub.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn xprint(self: *UnmanagedXpath) void {
        print("UnmanagedXpath: v={any} xtype={any}\n", .{
            self.value,
            self.xtype,
        });
        if (self.next) |sub| {
            sub.xprint();
        }
    }
};

pub fn Xpath(allocator: Allocator, query: []const u8) !*UnmanagedXpath {
    // print("Xpath scanner\n", .{});
    const tokenz = try scanner(allocator, query);
    defer tokenz.deinit();

    // print("Xpath tokenz\n", .{});
    // for (tokenz.items) |token| {
    //     print("token: {any}\n", .{token});
    // }

    const xpath = allocator.create(UnmanagedXpath) catch unreachable;
    xpath.* = UnmanagedXpath{
        .allocator = allocator,
        .xtype = .root,
    };

    // print("Xpath build\n", .{});

    var currx: *UnmanagedXpath = xpath;
    var pre_tt: TokenType = .init;
    var pre_stt: XsubType = .xinit;
    for (tokenz.items) |token| {
        // print("currx: {any} -> {any} ({any})\n", .{ currx.xtype, token.ttype, token.xsubtype });
        // print("token: {any}\n", .{token});

        switch (token.ttype) {
            .init => unreachable,
            .slash => {
                const subpath = allocator.create(UnmanagedXpath) catch unreachable;
                subpath.* = UnmanagedXpath{
                    .allocator = allocator,
                    .xtype = .init,
                };
                currx.next = subpath;
                currx = subpath;
            },
            .xtype => {
                // print("-> xtype: {any} -> {any}\n", .{ currx.xtype, token.xsubtype });
                currx.xtype = switch (token.xsubtype) {
                    .xinit => .init,
                    .xselect => .select,
                    .xgroup => .group,
                    .xany => .any,
                };
            },
            .number => {
                // const old = currx.value;
                currx.value = switch (pre_stt) {
                    .xinit => null,
                    .xselect => try parseInt(u16, token.value[0..token.vlen], 16),
                    .xgroup => try parseInt(u16, token.value[0..token.vlen], 10),
                    .xany => null,
                };
                // print("-> number: {any} -> {any}\n", .{
                //     old,
                //     currx.value,
                // });
            },
        }
        // print("token: {any}\n", .{token});
        // print("\n\n", .{});

        pre_tt = token.ttype;
        pre_stt = token.xsubtype;
    }

    // xpath.xprint();

    return xpath;
}

pub const XpathList = ArrayList(*UnmanagedXpath);

test "null xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/");
    defer xpath.deinit();

    try expect(xpath.next != null);
    try expect(xpath.next.?.xtype == .init);
}

test "simple_xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/s01/g3");
    defer xpath.deinit();

    try expect(xpath.xtype == .root);

    if (xpath.next) |xpath1| {
        // print("xpath1.xtype: {any}\n", .{xpath1});
        try expect(xpath1.xtype == .select);
        try expect(xpath1.value == 1);

        if (xpath1.next) |xpath2| {
            try expect(xpath2.xtype == .group);
            try expect(xpath2.value == 3);
        } else try expect(false);
    } else try expect(false);
}

// test "group node with xpath" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();

//     const xpath = try Xpath(allocator, "/s01/g3");
//     defer xpath.deinit();

//     var node = tree.RootNode(allocator);
//     defer node.deinit();

//     try node.addBytes("\x01\x02\x03\x04\x05", 256);
//     try node.addBytes("\x02\x03\x04\x05\x06", 256);
// }
