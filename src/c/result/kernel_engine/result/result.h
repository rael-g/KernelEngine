#ifndef KERNEL_ENGINE_RESULT_RESULT_H_
#define KERNEL_ENGINE_RESULT_RESULT_H_

#ifdef __cplusplus
extern "C"
{
#endif

#if (defined(__cplusplus) && __cplusplus >= 201703L) || (defined(__STDC_VERSION__) && __STDC_VERSION__ >= 202311L)
#define KE_MUST_USE [[nodiscard]]
#elif defined(__clang__)
#define KE_MUST_USE __attribute__((warn_unused_result))
#else
#define KE_MUST_USE
#endif

    /**
     * The domains that own a range of result codes. A domain's own codes are written
     * `KE_RESULT_CODE(KE_RESULT_DOMAIN_<DOMAIN>, n)` in its header, with `n` from 1 up.
     */
    typedef enum ke_result_domain
    {
        KE_RESULT_DOMAIN_GENERAL        = 0,
        KE_RESULT_DOMAIN_ASSET          = 1,
        KE_RESULT_DOMAIN_AUDIO          = 2,
        KE_RESULT_DOMAIN_CONFIGURATION  = 3,
        KE_RESULT_DOMAIN_ECS            = 4,
        KE_RESULT_DOMAIN_FRAMEWORK      = 5,
        KE_RESULT_DOMAIN_INPUT          = 6,
        KE_RESULT_DOMAIN_LOGGER         = 7,
        KE_RESULT_DOMAIN_MATH           = 8,
        KE_RESULT_DOMAIN_PHYSICS        = 9,
        KE_RESULT_DOMAIN_RENDER         = 10,
        KE_RESULT_DOMAIN_RESOURCE_CACHE = 11,
        KE_RESULT_DOMAIN_RUNTIME        = 12,
        KE_RESULT_DOMAIN_SCHEDULER      = 13,
        KE_RESULT_DOMAIN_SPATIAL        = 14,
        KE_RESULT_DOMAIN_TEXT           = 15,
        KE_RESULT_DOMAIN_VIEW           = 16,
        KE_RESULT_DOMAIN_WINDOW         = 17,
    } ke_result_domain;

/** The value of code `code` of domain `domain`: the domain in the high 16 bits, the code in the low. */
#define KE_RESULT_CODE(domain, code) ((int)(((unsigned)(domain) << 16) | (unsigned)(code)))

    /**
     * What a fallible call returns: `KE_OK`, or the code of the failure. The detail of a
     * failure goes to the failing library's log, never into the code. A caller treats a code
     * it does not know as `KE_RESULT_GENERAL`. Ignoring the result of a call is a compiler
     * warning where the compiler supports it.
     */
    typedef enum KE_MUST_USE ke_result
    {
        KE_OK                           = 0,
        KE_RESULT_GENERAL               = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 1),
        KE_RESULT_NOT_FOUND             = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 2),
        KE_RESULT_IO                    = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 3),
        KE_RESULT_OUT_OF_MEMORY         = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 4),
        KE_RESULT_INVALID_ARGUMENT      = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 5),
        KE_RESULT_NOT_INITIALIZED       = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 6),
        KE_RESULT_NOT_SUPPORTED         = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 7),
        KE_RESULT_ALREADY_EXISTS        = KE_RESULT_CODE(KE_RESULT_DOMAIN_GENERAL, 8),
        KE_RESULT_MAX_ENUM              = 0x7fffffff,
    } ke_result;

#ifdef __cplusplus
}
#endif

#endif
