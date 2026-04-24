#pragma once

#ifndef KE_WINDOW_API
    #if defined(_WIN32) || defined(__CYGWIN__)
        #ifdef KE_WINDOW_EXPORT
            #define KE_WINDOW_API __declspec(dllexport)
        #elif defined(KE_WINDOW_STATIC)
            #define KE_WINDOW_API
        #else
            #define KE_WINDOW_API __declspec(dllimport)
        #endif
    #else
        #define KE_WINDOW_API __attribute__((visibility("default")))
    #endif
#endif
