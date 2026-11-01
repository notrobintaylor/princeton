// NamAmp: the wrapper for the NAM plugin (lib/nam/NamAmp.so), so that sclang knows the UGen.
// It plays the loaded Neural Amp Modeler profile; active = 0 silences it.
NamAmp : UGen {
    *ar { |in = 0, active = 1|
        ^this.multiNew('audio', in, active)
    }
}
