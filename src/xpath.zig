const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;
const ArrayList = std.ArrayList;
const TOKEN_VAL_MAX_LEN = 8;
const eql = std.mem.eql;

const Kind = enum {
    init,
    slash,
    number,
    char,
    point,
};

const Token = struct {
    kind: Kind = undefined,

    value: [TOKEN_VAL_MAX_LEN]u8 = undefined,
    vlen: u8 = 0,

    fn deinit(self: *Token) void {
        print("Token.deinit({s})\n", .{self.value});
    }
};

fn scanner(allocator: Allocator, query: []const u8) !ArrayList(Token) {
    print("scanner({s})\n", .{query});
    var tokenz = ArrayList(Token).init(allocator);

    var qpos: usize = 0;
    while (qpos < query.len) {
        const qc = query[qpos];
        print("query c: {d} '{c}'\n", .{ qpos, qc });

        var token = Token{};
        token.value[0] = qc;

        switch (qc) {
            '/' => {
                token.kind = .slash;
            },
            '.' => {
                token.kind = .point;
            },
            '0'...'9' => {
                token.kind = .number;
            },
            's', 'i', 'g', 'a'...'f', 'A'...'F' => {
                token.kind = .char;
            },
            else => {
                print("scanner: unknown qc: {c}\n", .{qc});
                unreachable;
            },
        }
        qpos += 1;

        try tokenz.append(token);
    }
    return tokenz;
}

test "scanner" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const tokenz = try scanner(allocator, "/s30/g5/.");
    defer tokenz.deinit();

    // try expect(tokenz.items.len == 8);

    // try expect(tokenz.items[0].ttype == .slash);
    // try expect(tokenz.items[1].ttype == .xtype);
    // try expect(tokenz.items[2].ttype == .number);
    // try expect(tokenz.items[3].ttype == .slash);
    // try expect(tokenz.items[4].ttype == .xtype);
    // try expect(tokenz.items[5].ttype == .number);
    // try expect(tokenz.items[6].ttype == .slash);
    // try expect(tokenz.items[7].ttype == .xtype);

    // try expect(tokenz.items[1].xsubtype == .xselect);
    // try expect(tokenz.items[4].xsubtype == .xgroup);
    // try expect(tokenz.items[7].xsubtype == .xany);

    // var item = tokenz.items[2];
    // try expect(eql(u8, item.value[0..item.vlen], "30"));

    // item = tokenz.items[5];
    // try expect(eql(u8, item.value[0..item.vlen], "5"));
}

pub const Xpath = struct {
    allocator: Allocator,
    next: ?*Xpath = null,
    nvalue: ?u16 = null,
    bvalue: [5]u8 = undefined,
    blen: u8 = 0,
    kind: enum {
        init,
        root,
        level,
        select,
        ignore,
        delete,
        group,
    } = undefined,

    pub fn init(allocator: Allocator, query: []const u8) !*Xpath {
        // print("Xpath scanner\n", .{});
        const tokenz = try scanner(allocator, query);
        defer tokenz.deinit();

        const root = allocator.create(Xpath) catch unreachable;
        root.* = Xpath{
            .allocator = allocator,
            .kind = .root,
        };

        // print("\nXpath tokenz\n", .{});
        var currx1: *Xpath = root;
        var pre_kind: Kind = .init;
        var token_c: usize = 0;
        var read_bin_val: u8 = 0;
        var read_num_val: u8 = 0;
        for (tokenz.items) |token| {
            var next_xpath: bool = false;

            // print("\n", .{});
            // print("currx1: {*}\n", .{currx1});
            // print("blen: {d}\n", .{currx1.blen});
            // print("pre_kind: {any}\n", .{pre_kind});

            switch (token.kind) {
                .slash => {
                    // print("slash\n", .{});
                    currx1.kind = .level;
                    next_xpath = true;
                },
                .number, .char => {
                    // print("char: {c}\n", .{token.value[0]});
                    if (read_bin_val > 0) {
                        currx1.bvalue[currx1.blen] = token.value[0];
                        currx1.blen += 1;

                        read_bin_val -= 1;
                        if (read_bin_val == 0) {
                            next_xpath = true;
                        }
                    } else if (read_num_val > 0) {
                        currx1.bvalue[currx1.blen] = token.value[0];
                        currx1.blen += 1;

                        read_num_val -= 1;
                        if (read_num_val == 0) {
                            next_xpath = true;
                        }
                    } else {
                        switch (token.value[0]) {
                            's' => {
                                // select a specific byte value
                                currx1.kind = .select;
                                read_bin_val = 2;
                            },
                            'i' => {
                                // ignore the next n bytes
                                // n = decimal number
                                currx1.kind = .ignore;
                                read_num_val = 5; // max '65535'
                            },
                            'd' => {
                                // delete a specific byte value.
                                // like ignore (i) but with a specific byte value.
                                currx1.kind = .delete;
                                read_bin_val = 2;
                            },
                            'g' => {
                                // group the next n bytes
                                // n = decimal number
                                currx1.kind = .group;
                                read_num_val = 5; // max '65535'
                            },
                            else => {
                                // print("Undefined token.value[0]: {c}\n", .{token.value[0]});
                                unreachable;
                            },
                        }
                    }
                },
                else => {
                    // print("Undefined token.kind: {any}\n", .{token});
                    unreachable;
                },
            }

            // print("token.item: {any}\n", .{token});

            token_c += 1;
            if (token_c == tokenz.items.len) {
                break;
            }

            if (next_xpath) {
                const next = allocator.create(Xpath) catch unreachable;
                next.* = Xpath{
                    .allocator = allocator,
                };
                currx1.next = next;
                currx1 = next;
                // print("next: {*}\n", .{next});
            }

            pre_kind = token.kind;
        }

        // print("\nfrom root\n", .{});
        var currx2: ?*Xpath = root;
        while (currx2) |xitem| {
            // print("curr2: {any}\n", .{xitem.kind});

            if (xitem.blen > 0) {
                switch (xitem.kind) {
                    .init, .root, .level => {},
                    .select, .delete => {
                        xitem.nvalue = try parseInt(u16, xitem.bvalue[0..xitem.blen], 16);
                    },
                    .ignore, .group => {
                        xitem.nvalue = try parseInt(u16, xitem.bvalue[0..xitem.blen], 10);
                    },
                }

                // print("currx2.nvalue: {any}\n", .{xitem.nvalue});
            }

            currx2 = xitem.next;
        }

        // print("\nxprint\n", .{});
        root.xprint(0);

        return root;
    }

    pub fn deinit(self: *Xpath) void {
        if (self.next) |sub| {
            sub.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn xprint(self: *Xpath, n: u8) void {
        print("Xpath: {d} kind={any} nv={any} bv={any}({d})\n", .{
            n,
            self.kind,
            self.nvalue,
            self.bvalue,
            self.blen,
        });
        if (self.next) |sub| {
            sub.xprint(n + 1);
        }
    }
};

pub const XpathList = ArrayList(*Xpath);

// zig test src/xpath.zig --test-filter xpath_dev
test "xpath_dev" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath.init(allocator, "/sFEi65535g42");
    defer xpath.deinit();
}

test "null_xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath.init(allocator, "/");
    defer xpath.deinit();

    try expect(xpath.next == null);
    try expect(xpath.nvalue == null);
}

test "simple_xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath.init(allocator, "/sAB");
    defer xpath.deinit();

    if (xpath.next) |xpath1| {
        print("xpath1.kind: {any}\n", .{xpath1.kind});
    } else try expect(false);
}
