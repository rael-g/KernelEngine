using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class AudioServiceTests
{
    [Fact]
    public void Load_CallsBackend()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);
        backend.LoadSound("test.wav").Returns(new SoundHandle(42));

        var sound = service.Load("test.wav");

        Assert.Equal(42u, sound.Handle.Value);
        backend.Received(1).LoadSound("test.wav");
    }

    [Fact]
    public void Play_CallsBackend_WhenValid()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);
        var sound = new Sound(backend, new SoundHandle(42));

        service.Play(sound, 0.5f, true);

        backend.Received(1).Play(sound.Handle, 0.5f, true);
    }

    [Fact]
    public void Play_Throws_WhenSoundIsNull()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);

        Assert.Throws<ArgumentNullException>(() => service.Play(null!, 1.0f, false));
    }

    [Fact]
    public void Play_DoesNothing_WhenSoundIsInvalid()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);
        var sound = new Sound(backend, SoundHandle.None);

        service.Play(sound);

        backend.DidNotReceiveWithAnyArgs().Play(default, default, default);
    }

    [Fact]
    public void Stop_CallsBackend()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);
        var sound = new Sound(backend, new SoundHandle(42));

        service.Stop(sound);

        backend.Received(1).Stop(sound.Handle);
    }

    [Fact]
    public void Stop_Throws_WhenSoundIsNull()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);

        Assert.Throws<ArgumentNullException>(() => service.Stop(null!));
    }

    [Fact]
    public void SetMasterVolume_CallsBackend()
    {
        var backend = Substitute.For<IAudio>();
        var service = new AudioService(backend);

        service.SetMasterVolume(0.8f);

        backend.Received(1).SetMasterVolume(0.8f);
    }
}
