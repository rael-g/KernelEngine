//! Packs the index and the generation of a render handle into one u32, index in the low bits, and
//! takes them apart again. The bit widths come from the C namespace `Handles` is instantiated over.

/// The packing for one C namespace, whose two width constants fix `index_mask` and
/// `generation_mask`, the only data. `make` followed by `index` and `generation` gives back parts
/// that fit their widths.
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

        /// Cuts each part to its width before placing it, so a wider value is
        /// truncated, not refused.
        pub fn make(idx: u32, gen: u32) u32 {
            return (idx & index_mask) | ((gen & generation_mask) << index_bits);
        }
    };
}
