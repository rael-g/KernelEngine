#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    enum
    {
        KE_MSG_KEY_EVENT = 0x1001
    };

    /// @brief Data for a keyboard state change.
    typedef struct ke_msg_key_event
    {
        int key;
        int action;
    } ke_msg_key_event;

#ifdef __cplusplus
}
#endif
