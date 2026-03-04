using System;
using System.Runtime.InteropServices;
using KernelEngine.Core;
using KernelEngine.Core.Native;
using KernelEngine.ShaderCompiler.Native;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;

namespace KernelEngine.ShaderCompiler;

public unsafe class BgfxShaderCompiler : ISystem, INativeHandle
{
    private ke_system* _systemHandle;
    private ke_shader_compiler* _compilerHandle;
    private readonly IAllocator _allocator;

    IntPtr INativeHandle.Handle => (IntPtr)_systemHandle;

    public BgfxShaderCompiler(IAllocator allocator, string shadercPath, NativeLogger? logger = null)
    {
        _allocator = allocator;
        
        IntPtr pathPtr = Marshal.StringToHGlobalAnsi(shadercPath);
        try
        {
            ke_shader_compiler_bgfx_descriptor desc = new ke_shader_compiler_bgfx_descriptor
            {
                allocator = (ke_allocator*)((INativeHandle)allocator).Handle,
                logger = logger != null ? (ke_logger*)((INativeHandle)logger).Handle : null,
                shaderc_path = (sbyte*)pathPtr
            };

            ke_system* system = null;
            var res = KernelEngine.ShaderCompiler.Native.NativeMethods.shader_compiler_bgfx_create(&desc, &system);
            if (res != ke_result.KE_OK) throw new Exception($"Failed to create BGFX shader compiler: {res}");
            
            _systemHandle = system;
            _compilerHandle = (ke_shader_compiler*)system->handle;
        }
        finally
        {
            Marshal.FreeHGlobal(pathPtr);
        }
    }

    public ke_result CompileShader(string filePath, string varyingDefPath, string type, string platform, string profile, string[] includes)
    {
        if (_compilerHandle == null) return ke_result.KE_ERROR;

        IntPtr filePtr = Marshal.StringToHGlobalAnsi(filePath);
        IntPtr varyingPtr = Marshal.StringToHGlobalAnsi(varyingDefPath);
        IntPtr typePtr = Marshal.StringToHGlobalAnsi(type);
        IntPtr platformPtr = Marshal.StringToHGlobalAnsi(platform);
        IntPtr profilePtr = Marshal.StringToHGlobalAnsi(profile);

        IntPtr[] includePtrs = new IntPtr[includes.Length];
        for (int i = 0; i < includes.Length; i++) includePtrs[i] = Marshal.StringToHGlobalAnsi(includes[i]);

        try
        {
            fixed (IntPtr* pIncludes = includePtrs)
            {
                return _compilerHandle->compile_shader(_compilerHandle, 
                    (sbyte*)filePtr, (sbyte*)varyingPtr, (sbyte*)typePtr, (sbyte*)platformPtr, (sbyte*)profilePtr, 
                    (sbyte**)pIncludes, (nuint)includes.Length);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(filePtr);
            Marshal.FreeHGlobal(varyingPtr);
            Marshal.FreeHGlobal(typePtr);
            Marshal.FreeHGlobal(platformPtr);
            Marshal.FreeHGlobal(profilePtr);
            foreach (var ptr in includePtrs) Marshal.FreeHGlobal(ptr);
        }
    }

    public void Dispose()
    {
        if (_systemHandle != null)
        {
            _systemHandle->destroy(_systemHandle);
            _systemHandle = null;
            _compilerHandle = null;
        }
        GC.SuppressFinalize(this);
    }

    ~BgfxShaderCompiler()
    {
        Dispose();
    }
}
