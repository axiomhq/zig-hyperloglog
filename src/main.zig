const std = @import("std");
const math = std.math;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const RndGen = std.rand.DefaultPrng;

const precision = 14;
const m = 1 << precision;
const max = 64 - precision;
const maxX = math.maxInt(u64) >> max;
const alpha = 0.7213 / (1.0 + 1.079 / @intToFloat(f64, m));

var rnd = RndGen.init(0);

fn beta(z: f64) f64 {
    const zl = math.log10(z + 1);
    return -0.370393911 * z +
        0.070471823 * zl +
        0.17393686 * math.pow(f64, zl, 2) +
        0.16339839 * math.pow(f64, zl, 3) +
        -0.09237745 * math.pow(f64, zl, 4) +
        0.03738027 * math.pow(f64, zl, 5) +
        -0.005384159 * math.pow(f64, zl, 6) +
        0.00042419 * math.pow(f64, zl, 7);
}

pub fn HyperLogLog(allocator: *Allocator) type {
    return struct {
        const Self = @This();

        data: []u8,

        pub fn init() !Self {
            var data = allocator.alloc(u8, m) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
            for (data) |*x| {
                x.* = 0;
            }
            return Self{ .data = data };
        }

        pub fn deinit(self: *Self) void {
            allocator.free(self.data);
        }

        pub fn addHashed(self: *Self, hash: u64) void {
            var k = hash >> max;
            var val = @intCast(u8, @clz(u64, (hash << precision) ^ maxX)) + 1;
            if (val > self.data[k]) {
                self.data[k] = val;
            }
        }

        pub fn cardinality(self: *Self) f64 {
            var sum: f64 = 0;
            var z: f64 = 0;
            for (self.data) |x| {
                if (x == 0) {
                    z += 1;
                }
                sum += 1.0 / math.pow(f64, 2.0, @intToFloat(f64, x));
            }
            const m_float = @intToFloat(f64, @intCast(u64, self.data.len));

            var est = alpha * m_float * (m_float - z) / (beta(z) + sum);
            return est;
        }

        pub fn merge(self: *Self, other: *Self) void {
            for (self.data) |*x, i| {
                if (other.data[i] > x.*) {
                    x.* = other.data[i];
                }
            }
        }

        pub fn toBinary(self: *Self) ![]u8 {
            // return copy of data
            var data = allocator.alloc(u8, self.data.len) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
        }
    };
}

test "init" {
    var hll = HyperLogLog(testing.allocator).init() catch unreachable;
    testing.expect(hll.data.len == m) catch unreachable;

    const x = 3 << 50;

    hll.addHashed(x);

    // add a bunch of hashes
    var i: u32 = 1;
    while (i <= 10000000) : (i += 1) {
        // create random u64
        const r = rnd.random.int(u64);
        hll.addHashed(r);
    }

    const est = hll.cardinality();

    // print the estimate
    std.debug.print("estimate: {}\n", .{est});

    testing.expect(est >= 1000) catch unreachable;

    defer hll.deinit();
}
