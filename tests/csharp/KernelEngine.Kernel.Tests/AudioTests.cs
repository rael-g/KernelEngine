using System.Runtime.InteropServices;

using KernelEngine.Result.Native;

using Xunit;

namespace EngineTests;

public class AudioTests
{
    private static bool LastResult = true;
    private static uint LastSoundId = 0;
    private static float LastVolume = 0;
    private static bool LastLoop;
    private static bool DestroyCalled = false;
    private static string? LastPath = null;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe ke_result MockLoadSound(ke_audio* self, sbyte* path, uint* outSound)
    {
        LastPath = Marshal.PtrToStringAnsi((IntPtr)path);
        *outSound = LastResult ? 42u : 0u;
        return LastResult ? ke_result.KE_OK : ke_result.KE_RESULT_NOT_FOUND;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockUnloadSound(ke_audio* self, uint soundId)
    {
        LastSoundId = soundId;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe ke_result MockPlay(ke_audio* self, uint soundId, float volume, bool loop)
    {
        LastSoundId = soundId;
        LastVolume = volume;
        LastLoop = loop;
        return ke_result.KE_OK;
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

    private unsafe ke_audio_handle CreateMockHandle()
    {
        var ptr = (ke_audio*)NativeMemory.Alloc((nuint)sizeof(ke_audio));
        ptr->load_sound = &MockLoadSound;
        ptr->unload_sound = &MockUnloadSound;
        ptr->play = &MockPlay;
        ptr->stop = &MockStop;
        ptr->set_master_volume = &MockSetMasterVolume;
        return new ke_audio_handle { @ref = ptr, destroy = &MockDestroy };
    }

    [Fact]
    public unsafe void Constructor_Throws_WhenNativeIsNull()
    {
        Assert.Throws<ArgumentNullException>(() => new Audio(new ke_audio_handle()));
    }

    [Fact]
    public unsafe void LoadSound_CallsNative()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastPath = null;

        var handle = audio.LoadSound("test.wav");

        Assert.Equal("test.wav", LastPath);
        Assert.Equal(42u, handle.Value);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void LoadSound_Throws_WhenNativeFails()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastResult = false;

        Assert.Throws<KeyNotFoundException>(() => audio.LoadSound("test.wav"));
        LastResult = true;
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void UnloadSound_CallsNative()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastSoundId = 0;

        audio.UnloadSound(new SoundHandle(123));

        Assert.Equal(123u, LastSoundId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Play_CallsNative()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastSoundId = 0;

        audio.Play(new SoundHandle(123), 0.5f, true);

        Assert.Equal(123u, LastSoundId);
        Assert.Equal(0.5f, LastVolume);
        Assert.True(LastLoop);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Stop_CallsNative()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastSoundId = 0;

        audio.Stop(new SoundHandle(123));

        Assert.Equal(123u, LastSoundId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void SetMasterVolume_CallsNative()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);

        audio.SetMasterVolume(0.8f);

        Assert.Equal(0.8f, LastVolume);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void Dispose_CallsDestroy()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        DestroyCalled = false;

        audio.Dispose();

        Assert.True(DestroyCalled);
    }
}
