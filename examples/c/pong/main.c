#include "pong.h"

#include <kernel_engine/sdk/engine.h>

#include <stdio.h>

int main(void)
{
    ke_sdk_engine engine;
    ke_result made = ke_sdk_engine_create(&ke_sdk_engine_defaults, "pong", &engine);
    if (made == KE_OK)
    {
        pong_game game = { .types = engine.node_types.ref };
        made = pong_register(&game);
    }
    if (made == KE_OK) made = ke_sdk_engine_run(&engine, NULL);
    ke_sdk_engine_destroy(&engine);
    if (made != KE_OK)
    {
        fprintf(stderr, "pong failed with result code 0x%08x\n", (unsigned)made);
        return 1;
    }
    return 0;
}
