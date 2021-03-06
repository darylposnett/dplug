import std.math;
import dplug.core, dplug.client, dplug.vst;

// This create the DLL entry point
mixin(DLLEntryPoint!());

// This create the VST entry point
mixin(VSTEntryPoint!SimpleMonoSynth);

/// Simplest VST synth you could make.
final class SimpleMonoSynth : dplug.client.Client
{
public:
nothrow:
@nogc:   

    override PluginInfo buildPluginInfo()
    {
        // Plugin info is parsed from plugin.json here at compile time
        static immutable PluginInfo pluginInfo = parsePluginInfo(import("plugin.json"));
        return pluginInfo;
    }

    override Parameter[] buildParameters()
    {
        auto params = makeVec!Parameter();
        return params.releaseData();
    }

    override LegalIO[] buildLegalIO()
    {
        auto io = makeVec!LegalIO();
        io.pushBack(LegalIO(0, 1));
        io.pushBack(LegalIO(0, 2));
        return io.releaseData();
    }

    override int maxFramesInProcess() pure const
    {
        return 32; // samples only processed by a maximum of 32 samples
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs)
    {
        _phase = 1+0i;        
        _sampleRate = sampleRate;
        _voiceStatus.initialize();
    }

    override void processAudio(const(float*)[] inputs, float*[]outputs, int frames, TimeInfo info)
    {
        foreach(msg; getNextMidiMessages(frames))
        {
            if (msg.isNoteOn())
                _voiceStatus.markNoteOn(msg.noteNumber());
            if (msg.isNoteOff())
                _voiceStatus.markNoteOff(msg.noteNumber());
        }

        if (_voiceStatus.isAVoicePlaying)
        {
            float freq = convertMIDINoteToFrequency(_voiceStatus.lastNotePlayed);
            cfloat phasor = cos(2 * PI * freq / _sampleRate) + 1i * sin(2 * PI * freq / _sampleRate);

            foreach(smp; 0..frames)
            {
                outputs[0][smp] = _phase.im;
                _phase *= phasor;
            }
            _phase /= abs(_phase); // resync oscillator
        }
        else
        {
            outputs[0][0..frames] = 0;
        }

        // Copy output to every channel
        foreach(chan; 1..outputs.length)
            outputs[chan][0..frames] = outputs[0][0..frames];
    }

private:
    VoicesStatus _voiceStatus;
    cfloat _phase;
    float _sampleRate;
}

// Maintain list of active voices/notes
struct VoicesStatus
{
nothrow:
@nogc:

    // Reset state
    void initialize()
    {
        _played[] = 0;
        _currentNumberOfNotePlayed = 0;
        _timestamp = 0;
    }

    bool isAVoicePlaying()
    {
        return _currentNumberOfNotePlayed > 0;
    }

    int lastNotePlayed()
    {
        return _lastNotePlayed;
    }

    // useful to maintain list of msot recently played note
    void timeHasElapsed(int frames)
    {
        _timestamp += frames;
    }

    void markNoteOn(int note)
    {
        _lastNotePlayed = note;

        _played[note]++;
        _currentNumberOfNotePlayed++;

        _timestamps[note] = _timestamp;
    }

    void markNoteOff(int note)
    {
        if (_played[note] > 0)
        {
            _played[note]--;
            _currentNumberOfNotePlayed--;
            if (_currentNumberOfNotePlayed > 0)
                lookForMostRecentlyPlayedActiveNote();
        }
    }

private:

    int _currentNumberOfNotePlayed;

    int _lastNotePlayed;
    int _timestamp;

    int[128] _played;
    int[128] _timestamps;


    // looking for most recently played note still in activity
    void lookForMostRecentlyPlayedActiveNote()
    {
        assert(_currentNumberOfNotePlayed > 0);
        int mostRecent = int.min; // will wrap in 26H, that would be a long note
        for (int n = 0; n < 128; n++)
        {
            if (_played[n] && _timestamps[n] > mostRecent)
            {
                mostRecent = _timestamps[n];
                _lastNotePlayed = n;
            }
        }
    }
}
