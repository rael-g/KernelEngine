using System.Numerics;

using static KernelEngine.Result.Native.ResultDomain;

namespace KernelEngine.Result.Native;

[NativeTypeName("unsigned int")]
public enum Result : uint
{
    Ok = 0,
    General = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(1)))),
    NotFound = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(2)))),
    Io = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(3)))),
    OutOfMemory = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(4)))),
    InvalidArgument = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(5)))),
    NotInitialized = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(6)))),
    NotSupported = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(7)))),
    AlreadyExists = unchecked((uint)((int)(((uint)(KE_RESULT_DOMAIN_GENERAL) << 16) | (uint)(8)))),
    MaxEnum = 0x7fffffff,
}
