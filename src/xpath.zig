const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const parseInt = std.fmt.parseInt;
const indexOfScalar = std.mem.indexOfScalar;
const eql = std.mem.eql;
const ArrayList = std.ArrayList;
const TOKEN_VAL_MAX_LEN = 8;

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
        // print("query c: {d} '{c}'\n", .{ qpos, qc });

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
        print("Xpath scanner\n", .{});
        const tokenz = try scanner(allocator, query);
        defer tokenz.deinit();

        const root = allocator.create(Xpath) catch unreachable;
        root.* = Xpath{
            .allocator = allocator,
            .kind = .root,
        };

        print("\nXpath tokenz: {d}\n", .{tokenz.items.len});
        var currx: *Xpath = root;
        var tpos: usize = 0;
        while (tpos < tokenz.items.len) {
            const ctoken = tokenz.items[tpos];
            print("token: {d} {any}\n", .{ tpos, ctoken });

            var next_xpath: bool = false;

            switch (ctoken.kind) {
                .init => {
                    unreachable;
                },
                .slash => {
                    currx.kind = .level;
                    next_xpath = true;
                },
                .number => {
                    unreachable;
                },
                .char => {
                    switch (ctoken.value[0]) {
                        's' => {
                            // select a specific byte value
                            print("-> select\n", .{});
                            currx.kind = .select;
                        },
                        'i' => {
                            // ignore the next n bytes
                            // n = decimal number, max 65535
                            print("-> ignore\n", .{});
                            currx.kind = .ignore;
                        },
                        'd' => {
                            // delete a specific byte value.
                            // like (i)gnore but with a specific byte value.
                            print("-> delete\n", .{});
                            currx.kind = .delete;
                        },
                        'g' => {
                            // group the next n bytes
                            print("-> group\n", .{});
                            currx.kind = .group;
                        },
                        else => {
                            print("Undefined token.value[0]: {c}\n", .{ctoken.value[0]});
                            unreachable;
                        },
                    }

                    const min_read: u8 = switch (ctoken.value[0]) {
                        's', 'd' => 2,
                        'i', 'g' => 1,
                        else => 0,
                    };
                    const max_read: u8 = switch (ctoken.value[0]) {
                        's', 'd' => 2,
                        'i', 'g' => 5,
                        else => 0,
                    };

                    const nval_base: u8 = switch (ctoken.value[0]) {
                        's', 'd' => 16,
                        'i', 'g' => 10,
                        else => 0,
                    };

                    const valid_kinds: []const Kind = switch (ctoken.value[0]) {
                        's', 'd' => &[_]Kind{ .char, .number },
                        'i', 'g' => &[_]Kind{.number},
                        else => &[_]Kind{},
                    };

                    next_xpath = true;

                    if (max_read > 0) {
                        var n: u8 = 0;
                        while (tpos < tokenz.items.len and n < max_read) : (n += 1) {
                            const npos = tpos + 1;
                            if (npos >= tokenz.items.len) {
                                break;
                            }
                            const is_valid = indexOfScalar(Kind, valid_kinds, tokenz.items[npos].kind);
                            print("-> is_valid: {any}\n", .{is_valid});
                            if (is_valid == null) {
                                break;
                            }

                            tpos = npos;
                            const ntoken = tokenz.items[tpos];
                            print("-> next token: {any}\n", .{ntoken});
                            currx.bvalue[currx.blen] = ntoken.value[0];
                            currx.blen += 1;
                        }
                        if (currx.blen < min_read) {
                            print("-> ERROR: expected at least {d} byte(s), got {d} for type {any}\n", .{ min_read, currx.blen, currx.kind });
                            unreachable;
                        }
                        if (nval_base > 0) {
                            print("-> parseInt {d} {any}\n", .{ currx.blen, currx.bvalue[0..currx.blen] });
                            currx.nvalue = try parseInt(u16, currx.bvalue[0..currx.blen], nval_base);
                        }
                    }
                },
                .point => {
                    unreachable;
                },
            }

            tpos += 1;
            const is_last = tpos == tokenz.items.len;
            if (next_xpath and !is_last) {
                const next = allocator.create(Xpath) catch unreachable;
                next.* = Xpath{
                    .allocator = allocator,
                };
                currx.next = next;
                currx = next;
            }
        }

        print("root.xprint\n", .{});
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

test "scanner" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const tokenz = try scanner(allocator, "/s30/g5/.");
    defer tokenz.deinit();
}

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
