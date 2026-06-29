// medium_dsp: shared medium-DSP closures (chain/blend/read), loaded at runtime
// by Engine_Princeton and Engine_Media. Returns an event of closures.
//   mediumChain.(med, input, amt, bbd_tone_fc)            -- medium colouring
//   mediumBlend.(med, input, amt, bbd_tone_fc)            -- dry/medium crossfade
//   mediumRead.(med, rd, bbd_tone_fc, wow_tape, wow_cas, chip_crush, speed_rate)
// Load via: File.readAllString(PathName(this.class.filenameSymbol.asString).pathOnly
//             ++ "medium_dsp.scd").interpret.value
{
    var mediumChain, mediumRead, mediumBlend;

    mediumChain = { |med, input, amt, bbd_tone_fc|
        med.switch(
            \bbd, {
                var sig, drv, bias, bias_lfo;
                bias_lfo = LFNoise2.kr(0.1);
                sig  = HPF.ar(input, 80);
                sig  = LPF.ar(sig, bbd_tone_fc);
                bias = bias_lfo * amt.linlin(0, 100, 0.0, 0.05);
                drv  = 1.1 + amt.linlin(0, 100, 0.0, 6.4);
                sig  = ((sig + bias) * drv).tanh * (0.95 / drv);
                sig  = LeakDC.ar(sig);
                sig  = sig + WhiteNoise.ar(Amplitude.kr(sig, 0.01, 0.2) * amt.linlin(0, 100, 0.0, 0.05));
                sig
            },
            \cas, {
                var amt_fc, fc, rq, sig, drv, bias, comp_fc, crinkle, fm_idx, fm_out, bias_lfo, fm_carrier;
                bias_lfo   = LFNoise2.kr(0.15);
                fm_carrier = LFNoise2.kr(0.1).exprange(120, 400);
                amt_fc  = amt.linlin(0, 100, 3200, 800);
                fc      = amt_fc.clip(200, 8000);
                rq      = amt.linlin(0, 100, 3.0, 1.0);
                sig     = BPF.ar(input, fc, rq);
                drv     = amt.linlin(0, 100, 1.0, 4.5);
                bias    = bias_lfo * amt.linlin(0, 100, 0.0, 0.07);
                sig     = ((sig + bias) * drv).tanh / drv.sqrt;
                sig     = LeakDC.ar(sig);
                comp_fc = (Amplitude.kr(sig, 0.005, 0.15) * amt.linlin(0, 100, 0.0, -6000) + 5000).clip(2000, 5000);
                sig     = LPF.ar(sig, comp_fc);
                crinkle = (LFNoise0.kr(amt.linlin(0, 100, 0.5, 15)) * (amt - 68).max(0).linlin(0, 32, 0.0, 0.5) + 1.0).clip(0.2, 1.5);
                sig     = sig * crinkle;
                fm_idx  = amt.linlin(0, 100, 0.0, 0.012);
                fm_out  = SinOsc.ar(fm_carrier + (sig * fm_carrier * fm_idx));
                sig     = sig + (fm_out * fm_idx * 0.2);
                sig
            },
            \cd, {
                LPF.ar(input, amt.linexp(0, 100, 18000, 6000))
            },
            \chip, {
                var step, sr, sig, noise_src;
                noise_src = LFNoise0.ar(48000);
                sr   = amt.linexp(0, 100, 24000, 4500);
                step = amt.linlin(0, 100, 0.00001, 0.05);
                sig  = Latch.ar(input, Impulse.ar(sr));
                sig  = (sig / step).round(1.0) * step;
                sig  = sig + (noise_src * step * amt.linlin(0, 100, 0.0, 0.08));
                sig
            },
            \tape, {
                var amt_fc, fc, sig, drv, bias, comp_fc, print, bias_lfo;
                bias_lfo = LFNoise2.kr(0.12);
                amt_fc  = amt.linlin(0, 100, 16000, 400);
                fc      = amt_fc.clip(100, 18000);
                sig     = LPF.ar(input, fc);
                print   = DelayN.ar(input, 0.025, 0.019) * amt.linlin(0, 100, 0.0, 0.04);
                drv     = amt.linlin(0, 100, 1.0, 5.0);
                bias    = bias_lfo * amt.linlin(0, 100, 0.0, 0.06);
                sig     = ((sig + bias) * drv).tanh * (1.0 / drv);
                sig     = LeakDC.ar(sig);
                comp_fc = (Amplitude.kr(sig, 0.005, 0.15) * amt.linlin(0, 100, 0.0, -5000) + 5500).clip(2500, 5500);
                sig     = LPF.ar(sig, comp_fc);
                sig     = sig + print;
                sig
            },
            \vinyl, {
                BHiShelf.ar(input, 4000, 1, amt.linlin(0, 100, 0.0, -8.0))
            }
        )
    };

    mediumBlend = { |med, input, amt, bbd_tone_fc|
        var m = amt / 100.0;
        (input * (1.0 - m)) + (mediumChain.(med, input, amt, bbd_tone_fc) * m)
    };

    mediumRead = { |med, rd, bbd_tone_fc, loop_wow_tape, loop_wow_cas, loop_chip_crush, speed_rate|
        med.switch(
            \bbd, { [LPF.ar(rd[0], bbd_tone_fc), LPF.ar(rd[1], bbd_tone_fc)] },
            \cas, {
                var depth, wl, wr, dl, dr;
                depth = loop_wow_cas.linlin(0, 100, 0.0, 0.018) / speed_rate.max(1.0);
                wl = SinOsc.kr(0.7 + LFNoise2.kr(0.3, 0.25), 0,         1.0);
                wr = SinOsc.kr(0.7 + LFNoise2.kr(0.3, 0.25), pi * 0.75, 1.0);
                dl = (depth * 0.5 + wl * depth * 0.5).clip(0.0001, 0.025);
                dr = (depth * 0.5 + wr * depth * 0.5).clip(0.0001, 0.025);
                [DelayC.ar(rd[0], 0.030, dl), DelayC.ar(rd[1], 0.030, dr)]
            },
            \cd, { rd },
            \chip, {
                var camt, cr, cb;
                camt = (loop_chip_crush * 0.01).pow(0.35);
                cr   = camt.linexp(0, 1, 48000, 12000);
                cb   = camt.linlin(0, 1, 24, 7);
                [Decimator.ar(rd[0], cr, cb), Decimator.ar(rd[1], cr, cb)]
            },
            \tape, {
                var depth, wl, wr, dl, dr;
                depth = loop_wow_tape.linlin(0, 100, 0.0, 0.025) / speed_rate.max(1.0);
                wl = SinOsc.kr(1.1 + LFNoise2.kr(0.2, 0.20), 0,        1.0);
                wr = SinOsc.kr(1.1 + LFNoise2.kr(0.2, 0.20), pi * 0.5,  1.0);
                dl = (depth * 0.5 + wl * depth * 0.5).clip(0.0001, 0.030);
                dr = (depth * 0.5 + wr * depth * 0.5).clip(0.0001, 0.030);
                [DelayC.ar(rd[0], 0.030, dl), DelayC.ar(rd[1], 0.030, dr)]
            },
            \vinyl, {
                var depth, wl, wr, dl, dr;
                depth = 0.025 / speed_rate.max(1.0);
                wl = SinOsc.kr(0.4 + LFNoise2.kr(0.05, 0.05), 0,        1.0);
                wr = SinOsc.kr(0.4 + LFNoise2.kr(0.05, 0.05), pi * 0.6,  1.0);
                dl = (depth * 0.5 + wl * depth * 0.5).clip(0.0001, 0.030);
                dr = (depth * 0.5 + wr * depth * 0.5).clip(0.0001, 0.030);
                [DelayC.ar(rd[0], 0.030, dl), DelayC.ar(rd[1], 0.030, dr)]
            }
        )
    };

    (mediumChain: mediumChain, mediumBlend: mediumBlend, mediumRead: mediumRead)
}
