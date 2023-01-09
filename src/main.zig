const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const sparse = @import("sparse.zig");
const beta = @import("beta.zig").beta;
const AllocationError = error{OutOfMemory};

fn alpha(comptime p: u8) f64 {
    switch (p) {
        4 => return 0.673,
        5 => return 0.697,
        6 => return 0.709,
        else => return 0.7213 / (1.0 + 1.079 / @intToFloat(f64, 1 << p)),
    }
}

pub fn HyperLogLog(comptime p: u8) type {

    // check limits if p < 4 or p > 18 return error
    assert(p >= 4 and p <= 18);

    return struct {
        const Self = @This();

        const m = 1 << p;
        const alpha_m = alpha(p);
        const max = 64 - p;
        const maxx = math.maxInt(u64) >> max;
        const sparse_threshold = m * 3 / 4;

        allocator: Allocator,
        set: sparse.Set,
        dense: []u6,
        is_sparse: bool = true,

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .allocator = allocator,
                .set = sparse.Set.init(allocator),
                .dense = try allocator.alloc(u6, 0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.set.deinit();
            self.allocator.free(self.dense);
        }

        fn to_dense(self: *Self) !void {
            self.dense = try self.allocator.alloc(u6, m);

            for (self.dense) |*x| {
                x.* = 0;
            }
            var itr = self.set.set.iterator();

            while (itr.next()) |x| {
                try self.add_to_dense(x.key_ptr.*);
            }
            self.is_sparse = false;
            self.set.clear();
        }

        fn add_to_sparse(self: *Self, hash: u64) !void {
            try self.set.add(hash);
        }

        fn add_to_dense(self: *Self, x: u64) !void {
            var k = x >> max;
            var val = @intCast(u6, @clz((x << p) ^ maxx)) + 1;
            if (val > self.dense[k]) {
                self.dense[k] = val;
            }
        }

        pub fn add_hashed(self: *Self, hash: u64) !void {
            if (self.is_sparse == true and self.set.len() < sparse_threshold) {
                return self.add_to_sparse(hash);
            } else if (self.is_sparse == true) {
                try self.to_dense();
            }
            try self.add_to_dense(hash);
        }

        pub fn cardinality(self: *Self) u64 {
            if (self.is_sparse) {
                return @intCast(u64, self.set.len());
            }

            var sum: f64 = 0;
            var z: f64 = 0;

            for (self.dense) |x| {
                if (x == 0) {
                    z += 1;
                }
                sum += 1.0 / math.pow(f64, 2.0, @intToFloat(f64, x));
            }
            const m_float = @intToFloat(f64, m);

            const beta_value: f64 = beta(p, z);
            var est = alpha(p) * m_float * (m_float - z) / (beta_value + sum);

            return @floatToInt(u64, est + 0.5);
        }

        pub fn merge(self: *Self, other: *Self) !void {
            // if other is sparse then just add all the elements
            if (other.is_sparse) {
                var itr = other.set.set.iterator();
                while (itr.next()) |x| {
                    var val: u64 = x.key_ptr.*;
                    try self.add_hashed(val);
                }
                return;
            }

            if (self.is_sparse and !other.is_sparse) {
                // if self is sparse and other is dense then switch to dense
                try self.to_dense();
            }

            for (self.dense) |*x, i| {
                if (other.dense[i] > x.*) {
                    x.* = other.dense[i];
                }
            }
        }

        pub fn debug(self: *Self) void {
            std.debug.print("p = {d}\n", .{p});
            std.debug.print("m = {d}\n", .{m});
            std.debug.print("alpha_m = {d}\n", .{alpha_m});
            std.debug.print("max = {d}\n", .{max});
            std.debug.print("maxx = {d}\n", .{maxx});
            std.debug.print("sparse_threshold = {d}\n", .{sparse_threshold});
            std.debug.print("dense.len = {d}\n", .{self.dense.len});
        }
    };
}

// ======== TESTS ========

const testing = std.testing;
const RndGen = std.rand.DefaultPrng;
const autoHash = std.hash.autoHash;
const Wyhash = std.hash.Wyhash;
const tolerated_err = 0.008;

var rnd = RndGen.init(0);

fn testHash(key: anytype) u64 {
    // Any hash could be used here, for testing autoHash.
    var hasher = Wyhash.init(0);
    autoHash(&hasher, key);
    return hasher.final();
}

fn estimateError(got: u64, expected: u64) f64 {
    var delta = @intToFloat(f64, got) - @intToFloat(f64, expected);
    if (delta < 0) {
        delta = -delta;
    }
    return delta / @intToFloat(f64, expected);
}

test "init" {
    var hll = try HyperLogLog(14).init(testing.allocator);
    hll.debug();
}

test "add sparse" {
    const p = 14;
    const m = 1 << p;
    const sparse_threshold = (m) * 3 / 4;

    var hll = try HyperLogLog(p).init(testing.allocator);
    defer hll.deinit();

    var i: u64 = 0;
    while (i < sparse_threshold) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll.add_hashed(hash);
    }

    try testing.expect(hll.is_sparse);
    try testing.expect(hll.set.len() == sparse_threshold);
    try testing.expect(hll.dense.len == 0);
}

test "add dense" {
    const p = 14;
    const m = 1 << p;
    const sparse_threshold = (m) * 3 / 4;

    var hll = try HyperLogLog(p).init(testing.allocator);
    defer hll.deinit();

    var i: u64 = 0;
    while (i < sparse_threshold + 1) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll.add_hashed(hash);
    }
    var est_err = estimateError(hll.cardinality(), sparse_threshold + 1);

    try testing.expect(!hll.is_sparse);
    try testing.expect(hll.set.len() == 0);
    try testing.expect(hll.dense.len == 1 << 14);
    try testing.expect(est_err < tolerated_err);
}

test "merge sparse same" {
    const p = 14;
    //const sparse_threshold = (1 << 14) * 3 / 4;

    var hll1 = try HyperLogLog(p).init(testing.allocator);
    defer hll1.deinit();
    var hll2 = try HyperLogLog(p).init(testing.allocator);
    defer hll2.deinit();

    var i: u64 = 0;
    while (i < 10) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll1.add_hashed(hash);
        try hll2.add_hashed(hash);
    }

    try hll1.merge(&hll2);

    try testing.expect(hll1.is_sparse);
    try testing.expect(hll1.dense.len == 0);
    try testing.expect(hll1.set.len() == 10);
    try testing.expect(hll1.cardinality() == 10);
}

test "merge sparse different" {
    const p = 14;
    //const sparse_threshold = (1 << 14) * 3 / 4;

    var hll1 = try HyperLogLog(p).init(testing.allocator);
    defer hll1.deinit();
    var hll2 = try HyperLogLog(p).init(testing.allocator);
    defer hll2.deinit();

    var i: u64 = 0;
    while (i < 10) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll1.add_hashed(hash);
        hash = rnd.random().int(u64);
        try hll2.add_hashed(hash);
    }

    try hll1.merge(&hll2);

    try testing.expect(hll1.is_sparse);
    try testing.expect(hll1.dense.len == 0);
    try testing.expect(hll1.set.len() == 20);
    try testing.expect(hll1.cardinality() == 20);
}

test "merge sparse into dense" {
    const p = 14;
    const m = 1 << p;
    const sparse_threshold = (m) * 3 / 4;

    var hll1 = try HyperLogLog(p).init(testing.allocator);
    defer hll1.deinit();
    var hll2 = try HyperLogLog(p).init(testing.allocator);
    defer hll2.deinit();
    var i: u64 = 0;
    while (i < sparse_threshold + 1) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll1.add_hashed(hash);
    }
    i = 0;
    while (i < sparse_threshold) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll2.add_hashed(hash);
    }

    try hll1.merge(&hll2);
    var est_err = estimateError(hll1.cardinality(), 2 * sparse_threshold + 1);

    try testing.expect(hll1.dense.len == m);
    try testing.expect(hll1.set.len() == 0);
    try testing.expect(est_err < tolerated_err);
}

test "merge dense into sparse" {
    const p = 14;
    const m = 1 << p;
    const sparse_threshold = (m) * 3 / 4;

    var hll1 = try HyperLogLog(p).init(testing.allocator);
    defer hll1.deinit();
    var hll2 = try HyperLogLog(p).init(testing.allocator);
    defer hll2.deinit();

    var i: u64 = 0;
    while (i < sparse_threshold + 1) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll1.add_hashed(hash);
    }
    i = 0;
    while (i < 10) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll2.add_hashed(hash);
    }

    try hll2.merge(&hll1);
    var est_err = estimateError(hll2.cardinality(), 10 + sparse_threshold + 1);

    try testing.expect(!hll1.is_sparse);
    try testing.expect(hll1.dense.len == m);
    try testing.expect(hll1.set.len() == 0);
    try testing.expect(est_err < tolerated_err);
}

test "merge dense same" {
    const p = 14;
    const m = 1 << p;
    const sparse_threshold = (m) * 3 / 4;

    var hll1 = try HyperLogLog(p).init(testing.allocator);
    defer hll1.deinit();
    var hll2 = try HyperLogLog(p).init(testing.allocator);
    defer hll2.deinit();

    var i: u64 = 0;
    while (i < sparse_threshold + 1) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll1.add_hashed(hash);
        try hll2.add_hashed(hash);
    }

    try hll1.merge(&hll2);
    var est_err = estimateError(hll1.cardinality(), sparse_threshold + 1);

    try testing.expect(!hll1.is_sparse);
    try testing.expect(hll1.dense.len == m);
    try testing.expect(hll1.set.len() == 0);
    try testing.expect(est_err < tolerated_err);
}

test "merge dense different" {
    const p = 14;
    const m = 1 << p;
    const sparse_threshold = (m) * 3 / 4;

    var hll1 = try HyperLogLog(p).init(testing.allocator);
    defer hll1.deinit();
    var hll2 = try HyperLogLog(p).init(testing.allocator);
    defer hll2.deinit();

    var i: u64 = 0;
    while (i < sparse_threshold + 1) : (i += 1) {
        var hash = testHash(i);
        try hll1.add_hashed(hash);
        hash = testHash(sparse_threshold + 1 + i);
        try hll2.add_hashed(hash);
    }

    try hll1.merge(&hll2);
    var est_err = estimateError(hll1.cardinality(), 2 * sparse_threshold + 2);

    try testing.expect(!hll1.is_sparse);
    try testing.expect(hll1.dense.len == m);
    try testing.expect(hll1.set.len() == 0);
    try testing.expect(est_err < tolerated_err);
}
