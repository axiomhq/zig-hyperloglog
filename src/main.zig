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
    dense: []u8,
    is_sparse: bool = true,
    set: sparse.Set,
    counter: u64 = 0,

    pub fn init(allocator: Allocator) !Self {
        return Self{ .allocator = allocator, .dense = try allocator.alloc(u8, 0), .set = sparse.Set.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        if (self.is_sparse) {
            self.set.deinit();
        }
        self.allocator.free(self.dense);
    }

    // return void or error if out of memory
    pub fn toDense(self: *Self) !void {
        std.debug.print("switching to dense, len: {}\n", .{self.set.len()});
        self.dense = self.allocator.alloc(u8, m) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        for (self.dense) |*x| {
            x.* = 0;
        }
        if (self.is_sparse) {
            var itr = self.set.set.iterator();

            while (itr.next()) |x| {
                var val: u64 = x.key_ptr.*;
                try self.addToDense(val);
            }
            self.set.deinit();
            self.is_sparse = false;
        }
    }

    fn addToSparse(self: *Self, hash: u64) !void {
        try self.set.add(hash);
    }

    fn addToDense(self: *Self, x: u64) !void {
        var k = x >> max;
        var val = @intCast(u8, @clz((x << precision) ^ maxX)) + 1;
        if (val > self.dense[k]) {
            self.dense[k] = val;
        }
    }

    pub fn addHashed(self: *Self, hash: u64) !void {
        self.counter += 1;
        if (self.is_sparse == true and self.set.len() * 4 < m) {
            return self.addToSparse(hash);
        }
        if (self.is_sparse == true) {
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
        for (self.dense) |*x, i| {
            if (other.dense[i] > x.*) {
                x.* = other.dense[i];
            }
        }
    }
};

test "init" {
    var hll = HyperLogLog.init(testing.allocator) catch unreachable;
    defer hll.deinit();

    var i: u64 = 0;
    while (i < 20000) : (i += 1) {
        // hash i and add it to the hll
        var s = std.fmt.allocPrint(testing.allocator, "{}", .{i}) catch unreachable;
        defer testing.allocator.free(s);
        var hash = std.hash.CityHash64.hash(s);

        try hll.addHashed(hash);
    }

    // print cardinality
    std.debug.print("cardinality: {}\n", .{hll.cardinality()});
    std.debug.print("counter: {}\n", .{hll.counter});
    //try testing.expect(hll.cardinality() == 1);
}
