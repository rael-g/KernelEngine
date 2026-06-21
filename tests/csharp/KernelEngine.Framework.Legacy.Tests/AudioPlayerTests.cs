using Xunit;
using NSubstitute;

namespace KernelEngine.Framework.Legacy.Tests;

public class AudioPlayerTests
{
    [Fact]
    public void Start_LoadsSound_WhenPathIsSet()
    {
        var service = Substitute.For<IAudioService>();
        var player = new AudioPlayer(service) { Path = "test.wav" };
        var world = Substitute.For<IWorld>();
        player.Initialize(1, world, "player");

        // Manually trigger protected Start via reflection if needed, 
        // or just use a helper to call lifecycle methods.
        // Actually, Node has a TickAwakeAndStart but it's internal to Tree.
        // I'll use reflection to call Start.
        var startMethod = typeof(AudioPlayer).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        service.Received(1).Load(Arg.Is<string>(s => s.EndsWith("test.wav")));
    }

    [Fact]
    public void Start_AutoPlays_WhenAutoPlayIsTrue()
    {
        var service = Substitute.For<IAudioService>();
        var player = new AudioPlayer(service) { Path = "test.wav", AutoPlay = true };
        var world = Substitute.For<IWorld>();
        player.Initialize(1, world, "player");
        
        var sound = new Sound(Substitute.For<IAudio>(), new SoundHandle(1));
        service.Load(Arg.Any<string>()).Returns(sound);

        var startMethod = typeof(AudioPlayer).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        service.Received(1).Play(sound, player.Volume, player.Loop);
    }

    [Fact]
    public void Play_CallsService_WhenSoundLoaded()
    {
        var service = Substitute.For<IAudioService>();
        var player = new AudioPlayer(service);
        var sound = new Sound(Substitute.For<IAudio>(), new SoundHandle(1));
        
        // Inject sound via reflection since it's private field _sound
        typeof(AudioPlayer).GetField("_sound", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.SetValue(player, sound);

        player.Play();

        service.Received(1).Play(sound, player.Volume, player.Loop);
    }

    [Fact]
    public void Stop_CallsService_WhenSoundLoaded()
    {
        var service = Substitute.For<IAudioService>();
        var player = new AudioPlayer(service);
        var sound = new Sound(Substitute.For<IAudio>(), new SoundHandle(1));
        
        typeof(AudioPlayer).GetField("_sound", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.SetValue(player, sound);

        player.Stop();

        service.Received(1).Stop(sound);
    }

    [Fact]
    public void Dispose_DisposesSound()
    {
        var service = Substitute.For<IAudioService>();
        var player = new AudioPlayer(service);
        var backend = Substitute.For<IAudio>();
        var handle = new SoundHandle(1);
        var sound = new Sound(backend, handle);
        
        typeof(AudioPlayer).GetField("_sound", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.SetValue(player, sound);

        player.Dispose();

        backend.Received(1).UnloadSound(handle);
    }
}
