const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

pub const SetIterator = struct {
    const Self = @This();
    set: *const Set,
    iterator: AutoHashMap(u64, void).Iterator,

    pub fn next(self: *Self) ?u64 {
        if (self.iterator.next()) |entry| {
            return entry.key;
        }
        return null;
    }
};

pub const Set = struct {
    const Self = @This();

    allocator: Allocator,
    set: AutoHashMap(u64, void),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .set = AutoHashMap(u64, void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.set.deinit();
    }

    pub fn add(self: *Self, value: u64) !void {
        try self.set.put(value, {});
    }

    pub fn len(self: *const Self) usize {
        return self.set.count();
    }

    pub fn iterator(self: *const Self) SetIterator {
        return SetIterator{
            .set = self,
            .iterator = self.set.iterator(),
        };
    }
};
