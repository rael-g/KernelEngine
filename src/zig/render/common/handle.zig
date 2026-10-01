pub fn Handles(comptime c: type) type {
    return struct {
        const index_bits: u5 = @intCast(c.KE_HANDLE_INDEX_BITS);
        pub const index_mask: u32 = (@as(u32, 1) << index_bits) - 1;
        pub const generation_mask: u32 = (@as(u32, 1) << @as(u5, @intCast(c.KE_HANDLE_GENERATION_BITS))) - 1;

        pub fn index(bits: u32) u32 {
            return bits & index_mask;
        }

        pub fn generation(bits: u32) u32 {
            return (bits >> index_bits) & generation_mask;
        }

        pub fn make(idx: u32, gen: u32) u32 {
            return (idx & index_mask) | ((gen & generation_mask) << index_bits);
        }
    };
}
