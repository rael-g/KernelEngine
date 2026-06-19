// ke_result in C is typedef int32_t — ClangSharp maps it to int everywhere in generated code.
// This alias re-exposes it as a named type so NativeResultExtensions and other managed code
// can reference it by name without depending on a generated file that may be regenerated away.
namespace KernelEngine.Common.Native;

public enum ke_result
{
    KE_OK = 0,
    KE_ERROR = -1,
    KE_ERROR_OUT_OF_MEMORY = -2,
    KE_ERROR_INVALID_ARGUMENT = -3,
    KE_ERROR_NOT_FOUND = -4,
    KE_ERROR_NOT_INITIALIZED = -5,
    KE_ERROR_NOT_SUPPORTED = -6,
    KE_ERROR_ALREADY_EXISTS = -7,
    KE_ERROR_IO = -8,
}
