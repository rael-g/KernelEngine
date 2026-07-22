#pragma once

#include <kernel_engine/common/export.h>

#ifndef KE_INPUT_API
#  ifdef KE_INPUT_STATIC
#    define KE_INPUT_API
#  elif defined(KE_INPUT_EXPORT)
#    define KE_INPUT_API KE_EXPORT
#  else
#    define KE_INPUT_API KE_IMPORT
#  endif
#endif
