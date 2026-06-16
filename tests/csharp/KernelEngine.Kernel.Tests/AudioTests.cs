using System.Runtime.InteropServices;
using Xunit;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel.Tests;

public class AudioTests
{
    private static int LastResult = (int)ke_result.KE_OK;
    private static uint LastSoundId = 0;
    private static float LastVolume = 0;
    private static byte LastLoop = 0;
    private static bool DestroyCalled = false;
    private static string? LastPath = null;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe int MockLoadSound(ke_audio* self, sbyte* path, uint* outId)
    {
        LastPath = Marshal.PtrToStringAnsi((IntPtr)path);
        *outId = 42;
        return LastResult;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockUnloadSound(ke_audio* self, uint soundId)
    {
        LastSoundId = soundId;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe int MockPlay(ke_audio* self, uint soundId, float volume, bool loop)
    {
        LastSoundId = soundId;
        LastVolume = volume;
        LastLoop = loop ? (byte)1 : (byte)0;
        return (int)ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockStop(ke_audio* self, uint soundId)
    {
        LastSoundId = soundId;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockSetMasterVolume(ke_audio* self, float volume)
    {
        LastVolume = volume;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockDestroy(ke_audio* self)
    {
        DestroyCalled = true;
    }

    private unsafe ke_audio* CreateMockNative()
    {
        var ptr = (ke_audio*)NativeMemory.Alloc((nuint)sizeof(ke_audio));
        ptr->load_sound = &MockLoadSound;
        ptr->unload_sound = &MockUnloadSound;
        ptr->play = &MockPlay;
        ptr->stop = &MockStop;
        ptr->set_master_volume = &MockSetMasterVolume;
        ptr->destroy = &MockDestroy;
        return ptr;
    }

    [Fact]
    public unsafe void Constructor_Throws_WhenNativeIsNull()
    {
        Assert.Throws<ArgumentNullException>(() => new Audio(null));
    }

    [Fact]
    public unsafe void LoadSound_CallsNative()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        LastPath = null;
        
        var handle = audio.LoadSound("test.wav");
        
        Assert.Equal("test.wav", LastPath);
        Assert.Equal(42u, handle.Value);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void LoadSound_ReturnsNone_WhenNativeFails()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        LastResult = (int)ke_result.KE_ERROR_IO;

        var handle = audio.LoadSound("test.wav");

        Assert.Equal(SoundHandle.None, handle);
        LastResult = (int)ke_result.KE_OK;
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void UnloadSound_CallsNative()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        LastSoundId = 0;
        
        audio.UnloadSound(new SoundHandle(123));
        
        Assert.Equal(123u, LastSoundId);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void Play_CallsNative()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        LastSoundId = 0;
        
        audio.Play(new SoundHandle(123), 0.5f, true);
        
        Assert.Equal(123u, LastSoundId);
        Assert.Equal(0.5f, LastVolume);
        Assert.Equal(1, LastLoop);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void Stop_CallsNative()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        LastSoundId = 0;
        
        audio.Stop(new SoundHandle(123));
        
        Assert.Equal(123u, LastSoundId);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void SetMasterVolume_CallsNative()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        
        audio.SetMasterVolume(0.8f);
        
        Assert.Equal(0.8f, LastVolume);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void Dispose_CallsDestroy()
    {
        var native = CreateMockNative();
        var audio = new Audio(native);
        DestroyCalled = false;
        
        audio.Dispose();
        
        Assert.True(DestroyCalled);
        NativeMemory.Free(native);
    }
}
