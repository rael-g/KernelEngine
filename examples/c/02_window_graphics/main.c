#include <kernel_engine/common/error.h>
#include <kernel_engine/logger/logger.h>
#include <kernel_engine/render/render.h>
#include <kernel_engine/window/window.h>
#include <stdio.h>

// NOTE: This example uses stale low-level vtable APIs and is pending a full
// rewrite to match the current plugin factory/handle pattern (ke_window_handle,
// ke_render_handle). It is kept here as a placeholder only.

int main(void)
{
    printf("--- KernelEngine C Window/Graphics Demo (placeholder) ---\n");
    printf("Example pending rewrite to current factory API.\n");
    return 0;
}
