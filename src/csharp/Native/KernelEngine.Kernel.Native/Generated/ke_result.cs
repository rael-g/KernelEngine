namespace KernelEngine.Kernel.Native;

public enum ke_result
{
    KE_OK = 0,
    KE_ERROR = 1,
    KE_ERROR_OUT_OF_MEMORY = 2,
    KE_ERROR_INVALID_ARGUMENT = 3,
    KE_ERROR_NOT_FOUND = 4,
    KE_ERROR_ALREADY_EXISTS = 5,
    KE_ERROR_NOT_INITIALIZED = 6,
    KE_ERROR_NOT_SUPPORTED = 7,
    KE_ERROR_IO = 100,
    KE_ERROR_WINDOW = 200,
    KE_ERROR_RENDER = 300,
}
