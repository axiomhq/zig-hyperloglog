const std = @import("std");
const math = std.math;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const RndGen = std.rand.DefaultPrng;
const sparse = @import("sparse.zig");
const AllocationError = error{OutOfMemory};

const precision = 14;
const m = 1 << precision;
const max = 64 - precision;
const maxX = math.maxInt(u64) >> max;
const alpha = 0.7213 / (1.0 + 1.079 / @intToFloat(f64, m));

var rnd = RndGen.init(0);

fn beta(z: f64) f64 {
    const zl = math.ln(z + 1);
    return -0.370393911 * z +
        0.070471823 * zl +
        0.17393686 * math.pow(f64, zl, 2) +
        0.16339839 * math.pow(f64, zl, 3) +
        -0.09237745 * math.pow(f64, zl, 4) +
        0.03738027 * math.pow(f64, zl, 5) +
        -0.005384159 * math.pow(f64, zl, 6) +
        0.00042419 * math.pow(f64, zl, 7);
}

const HyperLogLog = struct {
    const Self = @This();

    allocator: Allocator,
    dense: []u6,
    is_sparse: bool = true,
    set: sparse.Set,

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .allocator = allocator,
            .dense = try allocator.alloc(u6, 0),
            .set = sparse.Set.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.is_sparse) {
            self.set.deinit();
        }
        self.allocator.free(self.dense);
    }

    pub fn toDense(self: *Self) !void {
        defer self.set.deinit();
        self.dense = self.allocator.alloc(u6, m) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };

        for (self.dense) |*x| {
            x.* = 0;
        }
        var itr = self.set.set.iterator();

        while (itr.next()) |x| {
            try self.addToDense(x.key_ptr.*);
        }
        self.is_sparse = false;
    }

    fn addToSparse(self: *Self, hash: u64) !void {
        try self.set.add(hash);
    }

    fn addToDense(self: *Self, x: u64) !void {
        var k = x >> max;
        var val = @intCast(u6, @clz((x << precision) ^ maxX)) + 1;
        if (val > self.dense[k]) {
            self.dense[k] = val;
        }
    }

    pub fn addHashed(self: *Self, hash: u64) !void {
        if (self.is_sparse == true and self.set.len() * 4 < m) {
            return self.addToSparse(hash);
        } else if (self.is_sparse == true) {
            try self.toDense();
        }
        try self.addToDense(hash);
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

        var est = alpha * m_float * (m_float - z) / (beta(z) + sum);
        return @floatToInt(u64, est + 0.5);
    }

    pub fn merge(self: *Self, other: *Self) void {
        // if both sparse then merge
        if (self.is_sparse and other.is_sparse) {
            self.set.merge(&other.set);
            // if count is too high then switch to dense
            if (self.set.len() * 4 > m) {
                self.toDense() catch unreachable;
            }
            return;
        } else if (other.is_sparse) {
            // if other is sparse and self is dense then insert other into self
            var itr = other.set.set.iterator();
            while (itr.next()) |x| {
                var val: u64 = x.key_ptr.*;
                self.addHashed(val) catch unreachable;
            }
            return;
        } else if (self.is_sparse) {
            // if self is sparse and other is dense then switch to dense
            self.toDense() catch unreachable;
        }

        for (self.dense) |*x, i| {
            if (other.dense[i] > x.*) {
                x.* = other.dense[i];
            }
        }
    }
};

// ======== TESTS ========

fn estimateError(got: u64, expected: u64) f64 {
    var delta = @intToFloat(f64, got) - @intToFloat(f64, expected);
    return math.abs(delta) / @intToFloat(f64, expected);
}

test "init" {
    var hll = HyperLogLog.init(testing.allocator) catch unreachable;
    defer hll.deinit();

    var i: u64 = 0;
    while (i < 200000) : (i += 1) {
        var hash = rnd.random().int(u64);
        try hll.addHashed(hash);
    }

    // print cardinality
    std.debug.print("cardinality: {}\n", .{hll.cardinality()});
    //try testing.expect(hll.cardinality() == 1);
}
