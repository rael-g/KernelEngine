#include <stddef.h>
#include <kernel_engine/extraction/extraction.h>
const unsigned long long layout_values[] = {
    sizeof(ke_extraction),
    offsetof(ke_extraction, handle),
    offsetof(ke_extraction, sync_component),
    offsetof(ke_extraction, extract_copy),
    offsetof(ke_extraction, extract_interpolate),
    offsetof(ke_extraction, extract_custom),
    offsetof(ke_extraction, render_entity),
    offsetof(ke_extraction, main_entity),
    offsetof(ke_extraction, extract),
    offsetof(ke_extraction, run),
    sizeof(ke_extraction_handle),
    offsetof(ke_extraction_handle, ref),
    offsetof(ke_extraction_handle, destroy),
    0,
};
