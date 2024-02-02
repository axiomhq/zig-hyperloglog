# Zig library for HyperLogLog cardinality estimation

[LogLog-Beta and More: A New Algorithm for Cardinality Estimation Based on LogLog Counting](https://arxiv.org/pdf/1612.02284.pdf) - by Jason Qin, Denys Kim, Yumei Tung

**TL;DR:**
Better than HyperLogLog in approximating the number unique elements in a set.

## LogLog-Beta

LogLog-Beta is a new algorithm for estimating cardinalities based on LogLog counting. The new algorithm uses only one formula and needs no additional bias corrections for the entire range of cardinalities, therefore, it is more efficient and simpler to implement. The simulations show that the accuracy provided by the new algorithm is as good as or better than the accuracy provided by either of HyperLogLog or HyperLogLog++.

## Example

```zig
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
        try hll.addHashed(x);
    }

    const est = hll.cardinality();
    std.debug.print("Estimated cardinality: {d}\n", .{est});
}
```
