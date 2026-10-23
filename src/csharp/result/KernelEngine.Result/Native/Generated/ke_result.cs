using static KernelEngine.Result.Native.ke_result_domain;

namespace KernelEngine.Result.Native;

[NativeTypeName("unsigned int")]
public enum ke_result : uint
{
    KE_OK = 0,
    KE_RESULT_GENERAL = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(1)))),
    KE_RESULT_NOT_FOUND = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(2)))),
    KE_RESULT_IO = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(3)))),
    KE_RESULT_OUT_OF_MEMORY = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(4)))),
    KE_RESULT_INVALID_ARGUMENT = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(5)))),
    KE_RESULT_NOT_INITIALIZED = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(6)))),
    KE_RESULT_NOT_SUPPORTED = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(7)))),
    KE_RESULT_ALREADY_EXISTS = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(8)))),
    KE_RESULT_MAX_ENUM = 0x7fffffff,
}
