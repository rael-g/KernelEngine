#pragma once

#ifndef KE_ASSET_STB_IMAGE_API
    #if defined(_WIN32) || defined(__CYGWIN__)
        #ifdef KE_ASSET_STB_IMAGE_EXPORT
            #define KE_ASSET_STB_IMAGE_API __declspec(dllexport)
        #elif defined(KE_ASSET_STB_IMAGE_STATIC)
            #define KE_ASSET_STB_IMAGE_API
        #else
            #define KE_ASSET_STB_IMAGE_API __declspec(dllimport)
        #endif
    #else
        #define KE_ASSET_STB_IMAGE_API __attribute__((visibility("default")))
    #endif
#endif
