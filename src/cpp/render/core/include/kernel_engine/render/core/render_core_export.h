#pragma once

#ifndef KE_RENDER_CORE_API
    #if defined(_WIN32) || defined(__CYGWIN__)
        #ifdef KE_RENDER_CORE_EXPORT
            #define KE_RENDER_CORE_API __declspec(dllexport)
        #elif defined(KE_RENDER_CORE_STATIC)
            #define KE_RENDER_CORE_API
        #else
            #define KE_RENDER_CORE_API __declspec(dllimport)
        #endif
    #else
        #define KE_RENDER_CORE_API __attribute__((visibility("default")))
    #endif
#endif
