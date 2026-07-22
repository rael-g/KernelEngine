#pragma once

#include <kernel_engine/common/export.h>

#ifndef KE_RESOURCE_CACHE_API
#  ifdef KE_RESOURCE_CACHE_STATIC
#    define KE_RESOURCE_CACHE_API
#  elif defined(KE_RESOURCE_CACHE_EXPORT)
#    define KE_RESOURCE_CACHE_API KE_EXPORT
#  else
#    define KE_RESOURCE_CACHE_API KE_IMPORT
#  endif
#endif
