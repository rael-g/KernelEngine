#ifndef KE_AUDIO_MINIAUDIO_EXPORT_H_
#define KE_AUDIO_MINIAUDIO_EXPORT_H_

#if defined(_WIN32) || defined(__CYGWIN__)
#  if defined(KE_AUDIO_MINIAUDIO_STATIC)
#    define KE_AUDIO_MINIAUDIO_API
#  elif defined(KE_AUDIO_MINIAUDIO_EXPORT)
#    define KE_AUDIO_MINIAUDIO_API __declspec(dllexport)
#  else
#    define KE_AUDIO_MINIAUDIO_API __declspec(dllimport)
#  endif
#else
#  define KE_AUDIO_MINIAUDIO_API __attribute__((visibility("default")))
#endif

#endif // KE_AUDIO_MINIAUDIO_EXPORT_H_
