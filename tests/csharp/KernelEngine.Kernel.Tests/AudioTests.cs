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
    private static float LastPitch;
    private static bool DestroyCalled = false;
    private static string? LastPath = null;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe global::KernelEngine.Result.Native.Result MockLoadSound(ke_audio* self, sbyte* path, uint* outSound)
    {
        LastPath = Marshal.PtrToStringAnsi((IntPtr)path);
        *outSound = LastResult ? 42u : 0u;
        return LastResult ? global::KernelEngine.Result.Native.Result.Ok : global::KernelEngine.Result.Native.Result.NotFound;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockUnloadSound(ke_audio* self, uint soundId)
    {
        LastSoundId = soundId;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe global::KernelEngine.Result.Native.Result MockVoiceStart(ke_audio* self, uint soundId, float volume, float pitch, bool loop, uint* outVoice)
    {
        LastSoundId = soundId;
        LastVolume = volume;
        LastPitch = pitch;
        LastLoop = loop;
        *outVoice = 7u;
        return global::KernelEngine.Result.Native.Result.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe bool MockVoicePlaying(ke_audio* self, uint voice) => voice == 7u;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockVoiceStop(ke_audio* self, uint voice)
    {
        LastSoundId = voice;
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
        ptr->voice_start = &MockVoiceStart;
        ptr->voice_playing = &MockVoicePlaying;
        ptr->voice_stop = &MockVoiceStop;
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
        Assert.Equal(42u, handle);
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

        audio.UnloadSound(123u);

        Assert.Equal(123u, LastSoundId);
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void VoiceStart_CallsNative_AndReturnsTheVoice()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastSoundId = 0;

        var voice = audio.VoiceStart(123u, 0.5f, 1.5f, true);

        Assert.Equal(7u, voice);
        Assert.Equal(123u, LastSoundId);
        Assert.Equal(0.5f, LastVolume);
        Assert.Equal(1.5f, LastPitch);
        Assert.True(LastLoop);
        Assert.True(audio.VoicePlaying(voice));
        NativeMemory.Free(h.@ref);
    }

    [Fact]
    public unsafe void VoiceStop_CallsNative()
    {
        var h = CreateMockHandle();
        IAudio audio = new Audio(h);
        LastSoundId = 0;

        audio.VoiceStop(7u);

        Assert.Equal(7u, LastSoundId);
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
