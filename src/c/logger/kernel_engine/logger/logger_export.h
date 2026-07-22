#pragma once

#include <kernel_engine/common/export.h>

#ifndef KE_LOGGER_API
#  ifdef KE_LOGGER_STATIC
#    define KE_LOGGER_API
#  elif defined(KE_LOGGER_EXPORT)
#    define KE_LOGGER_API KE_EXPORT
#  else
#    define KE_LOGGER_API KE_IMPORT
#  endif
#endif
