#pragma once

#include <kernel_engine/common/export.h>

#ifndef KE_COMMON_API
#  ifdef KE_COMMON_STATIC
#    define KE_COMMON_API
#  elif defined(KE_COMMON_EXPORT)
#    define KE_COMMON_API KE_EXPORT
#  else
#    define KE_COMMON_API KE_IMPORT
#  endif
#endif
