#ifndef KE_PHYSICS_BOX2D_EXPORT_H_
#define KE_PHYSICS_BOX2D_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
#  if defined(KE_PHYSICS_BOX2D_STATIC)
#    define KE_PHYSICS_BOX2D_API
#  elif defined(KE_PHYSICS_BOX2D_EXPORT)
#    define KE_PHYSICS_BOX2D_API __declspec(dllexport)
#  else
#    define KE_PHYSICS_BOX2D_API __declspec(dllimport)
#  endif
#else
#  define KE_PHYSICS_BOX2D_API __attribute__((visibility("default")))
#endif

#endif // KE_PHYSICS_BOX2D_EXPORT_H_
