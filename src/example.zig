const std = @import("std");
const HyperLogLog = @import("hyperloglog.zig").DefaultHyperLogLog;
const RndGen = std.rand.DefaultPrng;

var rnd = RndGen.init(0);

pub fn main() !void {
    const count = 1e7;
    const alloc = std.heap.page_allocator;

    var hll = try HyperLogLog.init(alloc);
    defer hll.deinit();

    var i: u64 = 0;
    while (i < count) : (i += 1) {
        const x = rnd.random().int(u64);
        try hll.add_hashed(x);
    }

    const est = hll.cardinality();
    std.debug.print("Estimated cardinality: {d}\n", .{est});
}
