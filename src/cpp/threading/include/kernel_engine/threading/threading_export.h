#pragma once

#ifndef KE_THREADING_API
#    if defined(_WIN32) || defined(__CYGWIN__)
#        ifdef KE_THREADING_EXPORT
#            define KE_THREADING_API __declspec(dllexport)
#        elif defined(KE_THREADING_STATIC)
#            define KE_THREADING_API
#        else
#            define KE_THREADING_API __declspec(dllimport)
#        endif
#    else
#        define KE_THREADING_API __attribute__((visibility("default")))
#    endif
#endif
