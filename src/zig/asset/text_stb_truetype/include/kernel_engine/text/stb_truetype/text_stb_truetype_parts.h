#ifndef KERNEL_ENGINE_TEXT_STB_TRUETYPE_TEXT_STB_TRUETYPE_PARTS_H_
#define KERNEL_ENGINE_TEXT_STB_TRUETYPE_TEXT_STB_TRUETYPE_PARTS_H_

#include <kernel_engine/text/stb_truetype/stb_font.h>
#include <kernel_engine/assembly/part.h>

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

/**
 * Gives the parts ke_text_stb_truetype contains: `font_loader_stb`, providing ke_font_loader, with the slot
 * `io`.
 * @param out_count [out] Receives how many parts the returned array holds.
 * @return [borrowed] The parts, valid while the library is loaded.
 */
KE_TEXT_STB_TRUETYPE_API const ke_part *ke_text_stb_truetype_parts(size_t *out_count);

#ifdef __cplusplus
}
#endif

#endif
