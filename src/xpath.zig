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

const Flag = enum(u8) {
    xselect = 0b001,
    xgroup = 0b010,
    xany = 0b100,
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

const UnmanagedXpath = struct {
    allocator: Allocator,
    next: ?*UnmanagedXpath = null,
    nvalue: ?u16 = null,
    bvalue: [5]u8 = undefined,
    blen: u8 = 0,
    kind: enum {
        init,
        root,
        level,
        select,
        ignore,
    } = undefined,

    pub fn deinit(self: *UnmanagedXpath) void {
        if (self.next) |sub| {
            sub.deinit();
        }
        self.allocator.destroy(self);
    }

    pub fn xprint(self: *UnmanagedXpath, n: u8) void {
        print("UnmanagedXpath: {d} kind={any} nv={any} bv={any}({d})\n", .{
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

pub fn Xpath(allocator: Allocator, query: []const u8) !*UnmanagedXpath {
    print("Xpath scanner\n", .{});
    const tokenz = try scanner(allocator, query);
    defer tokenz.deinit();

    const root = allocator.create(UnmanagedXpath) catch unreachable;
    root.* = UnmanagedXpath{
        .allocator = allocator,
        .kind = .root,
    };

    print("\nXpath tokenz\n", .{});
    var currx: *UnmanagedXpath = root;
    var pre_kind: Kind = .init;
    var token_c: usize = 0;
    var read_bin_val: u8 = 0;
    var read_num_val: u8 = 0;
    for (tokenz.items) |token| {
        var next_xpath: bool = false;

        print("\n", .{});
        print("currx: {*}\n", .{currx});
        print("blen: {d}\n", .{currx.blen});
        print("pre_kind: {any}\n", .{pre_kind});

        switch (token.kind) {
            .slash => {
                print("slash\n", .{});
                currx.kind = .level;
                next_xpath = true;
            },
            .number, .char => {
                print("char: {c}\n", .{token.value[0]});
                if (read_bin_val > 0) {
                    currx.bvalue[currx.blen] = token.value[0];
                    currx.blen += 1;

                    read_bin_val -= 1;
                    if (read_bin_val == 0) {
                        next_xpath = true;
                    }
                } else if (read_num_val > 0) {
                    currx.bvalue[currx.blen] = token.value[0];
                    currx.blen += 1;

                    read_num_val -= 1;
                    if (read_num_val == 0) {
                        next_xpath = true;
                    }
                } else {
                    switch (token.value[0]) {
                        's' => {
                            // select a specific byte value
                            currx.kind = .select;
                            read_bin_val = 2;
                        },
                        'i' => {
                            // ignore the next n bytes
                            // n = decimal number
                            currx.kind = .ignore;
                            read_num_val = 5;
                        },
                        else => {
                            print("Undefined token.value[0]: {c}\n", .{token.value[0]});
                            unreachable;
                        },
                    }
                }
            },
            else => {
                print("Undefined token.kind: {any}\n", .{token});
                unreachable;
            },
        }

        print("token.item: {any}\n", .{token});

        token_c += 1;
        if (token_c == tokenz.items.len) {
            break;
        }

        if (next_xpath) {
            const next = allocator.create(UnmanagedXpath) catch unreachable;
            next.* = UnmanagedXpath{
                .allocator = allocator,
            };
            currx.next = next;
            currx = next;
            print("next: {*}\n", .{next});
        }

        pre_kind = token.kind;
    }

    print("\nfrom root\n", .{});
    currx = root;
    while (true) {
        print("curr: {any}\n", .{currx.kind});

        if (currx.blen > 0) {
            switch (currx.kind) {
                .select => {
                    currx.nvalue = try parseInt(u16, currx.bvalue[0..currx.blen], 16);
                },
                .ignore => {
                    currx.nvalue = try parseInt(u16, currx.bvalue[0..currx.blen], 10);
                },
                else => unreachable,
            }

            print("currx.nvalue: {any}\n", .{currx.nvalue});
        }

        if (currx.next) |next| {
            currx = next;
        } else break;
    }

    print("\nxprint\n", .{});
    root.xprint(0);

    return root;
}

pub const XpathList = ArrayList(*UnmanagedXpath);

// zig test src/xpath.zig --test-filter xpath_dev
test "xpath_dev" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/sFEi65535");
    defer xpath.deinit();
}

test "null_xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/");
    defer xpath.deinit();

    try expect(xpath.next != null);
}

test "simple_xpath" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const xpath = try Xpath(allocator, "/sAB");
    defer xpath.deinit();

    // try expect(xpath.xtype == .root);

    // if (xpath.next) |xpath1| {
    //     print("xpath1.xtype: {any}\n", .{xpath1.xtype});
    //     try expect(xpath1.xtype == .select);

    //     print("xpath1.nvalue: {any}\n", .{xpath1.nvalue});
    //     try expect(xpath1.nvalue == 255);

    //     // if (xpath1.next) |xpath2| {
    //     //     try expect(xpath2.xtype == .group);
    //     //     try expect(xpath2.value == 3);
    //     // } else try expect(false);
    // } else try expect(false);
}
