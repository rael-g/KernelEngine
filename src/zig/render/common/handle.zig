//! Packs the index and the generation of a render handle into one u32, index in the low bits, and
//! takes them apart again. The bit widths are the ones `kernel_engine/render/handles.h` defines.

const abi_render = @import("abi_render");
const index_bits: u5 = @intCast(abi_render.KE_HANDLE_INDEX_BITS);
pub const index_mask: u32 = (@as(u32, 1) << index_bits) - 1;
pub const generation_mask: u32 = (@as(u32, 1) << @as(u5, @intCast(abi_render.KE_HANDLE_GENERATION_BITS))) - 1;

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
