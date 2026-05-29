#ifndef KERNEL_ENGINE_TEXT_STB_TRUETYPE_EXPORT_H_
#define KERNEL_ENGINE_TEXT_STB_TRUETYPE_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef KE_TEXT_STB_TRUETYPE_STATIC
        #define KE_TEXT_STB_TRUETYPE_API
    #else
        #ifdef KE_TEXT_STB_TRUETYPE_EXPORT
            #define KE_TEXT_STB_TRUETYPE_API __declspec(dllexport)
        #else
            #define KE_TEXT_STB_TRUETYPE_API __declspec(dllimport)
        #endif
    #endif
#else
    #define KE_TEXT_STB_TRUETYPE_API __attribute__((visibility("default")))
#endif

#endif
