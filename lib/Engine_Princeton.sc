Engine_Princeton : CroneEngine {

    var synth;
    var in_synth, tune_synth;
    var push_synth, push_gain_v, push_tone_v, push_level_v, push_mix_v;
    var distort_synth, distort_gain_v, distort_tone_v, distort_level_v, distort_lowcut_v;
    var fray_synth, fray_drive_v, fray_tone_v, fray_gate_v, fray_comp_v, fray_stab_v, fray_octave_v, fray_octave_mode_v, fray_volume_v;
    var cut_synth, cut_thresh_v, cut_attack_v, cut_hold_v, cut_release_v, cut_range_v, cut_hyst_v, cut_detect_v;
    var hold_synth, hold_rec_synth, hold_rec_buf, hold_play_bufs, hold_play_idx, hold_phase_bus, hold_wants_on, hold_out_bus, hold_env_bufs, hold_shape_v, hold_interp_v, hold_gain_v, hold_rise_v, hold_fall_v, hold_level_v, hold_size_v, hold_density_v, hold_pitch_v, hold_spread_v, hold_pmix_v, hold_rev_v;
    var loop_buf;
    var tune_freq_bus;
    var count_bus;
    var env1_bus, env2_bus;
    var pedal_bus;
    var looper_in_bus, looper_out_bus, mediaNames, looperModule;

    alloc {

        var mediumDsp, mediumRead, mediumBlend;

        loop_buf = Buffer.alloc(context.server, (48000 * 60), 2);
        tune_freq_bus = Bus.control(context.server, 1);
        count_bus = Bus.audio(context.server, 1);
        env1_bus = Bus.control(context.server, 1);
        env2_bus = Bus.control(context.server, 1);
        pedal_bus = Bus.audio(context.server, 2);
        looper_in_bus   = Bus.audio(context.server, 2);
        looper_out_bus  = Bus.audio(context.server, 2);
        // Two Hold instances run in parallel: 2 x 4 stereo output slots.
        hold_out_bus    = Bus.audio(context.server, 16);
        // ONE shared rolling recorder feeds both instances (they capture the same signal).
        hold_rec_buf    = Buffer.alloc(context.server, (48000 * 1.2).asInteger, 1);
        hold_phase_bus  = Bus.control(context.server, 1);
        // Per instance: pool of play buffers, cycled per hold_on so a fresh snapshot never
        // overwrites the buffer an older, still-fading grain synth reads (that stomp clicks).
        hold_play_bufs  = Array.fill(2, { Array.fill(4, { Buffer.alloc(context.server, (48000 * 1.2).asInteger, 1) }) });
        hold_play_idx   = Array.fill(2, 0);
        hold_synth      = Array.fill(2, nil);
        hold_wants_on   = Array.fill(2, false);
        // Grain windows for the Shape param, read through GrainBuf envbufnum.
        // Plateau does not reach zero at its edges and can click; that is accepted by design.
        hold_env_bufs = [
            Env([0, 1, 0],    [0.5,  0.5 ],        \sine).asSignal(1024),
            Env([0, 1, 0],    [0.5,  0.5 ],      [4, -4]).asSignal(1024),
            Env([0, 1, 0],    [0.85, 0.15],      [2, -4]).asSignal(1024),
            Env([0, 1, 0],    [0.15, 0.85],      [-4, 2]).asSignal(1024),
            Env([0, 1, 1, 0], [0.08, 0.84, 0.08], \lin).asSignal(1024)
        ].collect({ |sig| Buffer.sendCollection(context.server, sig, 1) });
        push_gain_v = 5; push_tone_v = 5; push_level_v = 5; push_mix_v = 25;
        distort_gain_v = 5; distort_tone_v = 7.5; distort_level_v = 5; distort_lowcut_v = 0;
        fray_drive_v = 5; fray_tone_v = 10; fray_gate_v = 0; fray_comp_v = 5;
        fray_stab_v = 0; fray_octave_v = 0; fray_octave_mode_v = 1; fray_volume_v = 5;
        cut_thresh_v = -50; cut_attack_v = 1; cut_hold_v = 20; cut_release_v = 100; cut_range_v = -75; cut_hyst_v = 0; cut_detect_v = 0;
        // Instance 2 starts longer/denser/wider (7.5) so the two layers differ by default.
        hold_gain_v = [5, 5];      hold_rise_v  = [0.25, 0.25]; hold_fall_v   = [2.5, 2.5];
        hold_level_v = [5, 5];     hold_size_v  = [5, 7.5];     hold_density_v = [5, 7.5];
        hold_pitch_v = [-12, 12];  hold_spread_v = [5, 7.5];    hold_pmix_v   = [10, 10];
        hold_rev_v   = [0, 0];
        hold_shape_v = [0, 0]; hold_interp_v = [4, 4];
        mediaNames = [\bbd, \cas, \cd, \chip, \tape, \vinyl];

        context.server.sync;

        mediumDsp   = File.readAllString(PathName(this.class.filenameSymbol.asString).pathOnly ++ "medium_dsp.scd").interpret.value;
        mediumBlend = mediumDsp[\mediumBlend];
        mediumRead  = mediumDsp[\mediumRead];

        SynthDef(\princeton_silence, {
            arg hold_bus = 0, looper_bus = 0;
            ReplaceOut.ar(hold_bus,   DC.ar(0) ! 16);
            ReplaceOut.ar(looper_bus, DC.ar(0) ! 2);
            Line.kr(0, 0, 0.02, doneAction: 2);
        }).add;

        SynthDef(\princeton_in, {
            arg in_bus = 0, in_bus_r = 0, signal_input = 1, input_trim = 1, count_bus_num = 0,
                env1_attack = 0.05, env1_release = 0.05, env1_bus_num = 0,
                env2_attack = 0.05, env2_release = 0.05, env2_bus_num = 0,
                pedal_bus_num = 0;
            var sig, sig_l_in, sig_r_in, count_in, sig_input_norm, input_level_gain;
            var env_src, env1_amp, env2_amp;

            signal_input = Lag.kr(signal_input, 0.05);
            input_trim   = Lag.kr(input_trim,   0.05);
            env1_attack  = Lag.kr(env1_attack,  0.05);
            env1_release = Lag.kr(env1_release, 0.05);
            env2_attack  = Lag.kr(env2_attack,  0.05);
            env2_release = Lag.kr(env2_release, 0.05);

            sig_l_in = In.ar(in_bus,   1);
            sig_r_in = In.ar(in_bus_r, 1);
            count_in = In.ar(count_bus_num, 1);

            sig_input_norm   = (signal_input - 1).clip(0, 1);
            input_level_gain = ((1 - sig_input_norm) * 1.0) + (sig_input_norm * 0.31623);

            sig = [
                (sig_l_in                                                          * input_level_gain),
                ((sig_l_in * (1 - sig_input_norm)) + (sig_r_in * sig_input_norm))  * input_level_gain
            ];
            sig = (sig * input_trim) + count_in;
            sig = LeakDC.ar(sig);
            sig = HPF.ar(sig, 40);
            sig = LPF.ar(sig, 7500);

            env_src = Select.ar(sig_input_norm.round(1).clip(0, 1), [
                sig_l_in,
                (sig_l_in + sig_r_in) * 0.5
            ]);
            env1_amp = Amplitude.kr(env_src, env1_attack, env1_release).clip(0, 1);
            env2_amp = Amplitude.kr(env_src, env2_attack, env2_release).clip(0, 1);
            Out.kr(env1_bus_num, env1_amp);
            Out.kr(env2_bus_num, env2_amp);

            Out.ar(pedal_bus_num, sig);
        }).add;

        SynthDef(\princeton_push, {
            arg bus = 0, gate = 1, fade = 0.025,
                push_gain = 5, push_tone = 5, push_level = 5, push_mix = 25;
            var dry, push_drive, push_sig, wet, env;
            push_gain  = Lag.kr(push_gain,  0.05);
            push_tone  = Lag.kr(push_tone,  0.05);
            push_level = Lag.kr(push_level, 0.05);
            push_mix   = Lag.kr(push_mix,   0.05);
            env = EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            dry = In.ar(bus, 2);
            push_drive = HPF.ar(dry, 100);
            push_drive = LPF.ar(push_drive, 2200);
            push_drive = push_drive * push_gain.linexp(0, 10, 1.0, 100.0);
            push_drive = LPF.ar(push_drive, 2400);
            push_drive = (push_drive.max(0) * 1.02).tanh + (push_drive.min(0) * 0.96).tanh;
            push_drive = LeakDC.ar(push_drive);
            push_drive = HPF.ar(push_drive, push_tone.linexp(0, 10, 100, 750));
            push_drive = LPF.ar(push_drive, 3200);
            push_sig   = push_drive * push_level.linlin(0, 10, 0.0, 1.3);
            wet = XFade2.ar(push_sig, dry, push_mix.linlin(0, 100, -1, 1));
            ReplaceOut.ar(bus, LinXFade2.ar(dry, wet, env * 2 - 1));
        }).add;

        SynthDef(\princeton_distort, {
            arg bus = 0, gate = 1, fade = 0.025,
                distort_gain = 5, distort_tone = 7.5, distort_level = 5, distort_lowcut = 0;
            var dry, distort_drive, distort_sig, env;
            distort_gain  = Lag.kr(distort_gain,  0.05);
            distort_tone  = Lag.kr(distort_tone,  0.05);
            distort_level = Lag.kr(distort_level, 0.05);
            env = EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            dry = In.ar(bus, 2);
            distort_drive = HPF.ar(dry, 150);
            distort_drive = LPF.ar(distort_drive, 4500);
            distort_drive = distort_drive * distort_gain.linexp(0, 10, 10.0, 500.0);
            distort_drive = LPF.ar(distort_drive, 7000);
            distort_drive = distort_drive.clip2(1.0);
            distort_drive = LeakDC.ar(distort_drive);
            distort_drive = LPF.ar(distort_drive, distort_tone.linexp(0, 10, 300, 5000));
            distort_drive = HPF.ar(distort_drive, Select.kr(distort_lowcut.round(1), [20, 100, 250]));
            distort_sig   = distort_drive * distort_level.linlin(0, 10, 0.0, 0.170);
            ReplaceOut.ar(bus, LinXFade2.ar(dry, distort_sig, env * 2 - 1));
        }).add;

        SynthDef(\princeton_fray, {
            arg bus = 0, gate = 1, fade = 0.025,
                fray_drive = 5, fray_tone = 10, fray_gate = 0, fray_comp = 5,
                fray_stab = 0, fray_octave = 0, fray_octave_mode = 1, fray_volume = 5;
            var dry, sig, env, amp, sag, gain, pre, fb, fb_amt, starve, bias;
            var oct_up, oct_down, oct, ring, open, wet;
            fray_drive  = Lag.kr(fray_drive,  0.05);
            fray_tone   = Lag.kr(fray_tone,   0.05);
            fray_gate   = Lag.kr(fray_gate,   0.05);
            fray_comp   = Lag.kr(fray_comp,   0.05);
            fray_stab   = Lag.kr(fray_stab,   0.05);
            fray_octave = Lag.kr(fray_octave, 0.05);
            fray_volume = Lag.kr(fray_volume, 0.05);
            env = EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            dry = In.ar(bus, 2);
            sig = HPF.ar(dry, 60);

            amp = Amplitude.kr(dry.sum * 0.5, 0.005, fray_stab.linexp(0, 10, 0.08, 0.5)).clip(0, 1);

            sag  = 1 - (fray_stab * 0.06 * amp);
            gain = fray_drive.linexp(0, 10, 8.0, 900.0) * sag;

            pre = (sig * gain).tanh;

            fb     = LocalIn.ar(2);
            fb_amt = fray_stab * 0.085;
            pre    = pre + (fb * fb_amt);

            starve = fray_comp * 0.1;
            bias   = starve * 0.7 * (1 - amp);
            pre    = ((pre + bias).tanh - bias.tanh) * 1.313;
            pre    = LeakDC.ar(pre);

            oct_up   = LeakDC.ar((pre.abs * 2) - 1) * 0.9;
            oct_down = LeakDC.ar(((ToggleFF.ar(pre) * 2) - 1) * Amplitude.kr(pre, 0.01, 0.08));
            oct      = Select.ar(fray_octave_mode.round(1), [
                oct_down,
                oct_up,
                (oct_down + oct_up) * 0.6
            ]);
            pre = XFade2.ar(pre, oct, (fray_octave * 0.2) - 1);

            ring = BPF.ar(pre, 320, fray_stab.linexp(0, 10, 1.5, 0.08));
            LocalOut.ar(LPF.ar(ring, 2600) * 0.87);

            open = Amplitude.kr(dry.sum * 0.5, 0.001, 0.04) > fray_gate.linexp(0, 10, 0.0005, 0.0112);
            pre  = pre * Lag.kr(open, 0.004);

            pre = LPF.ar(pre, fray_tone.linexp(0, 10, 750, 7500));
            wet = pre * fray_volume.linlin(0, 10, 0.0, 0.55);
            ReplaceOut.ar(bus, LinXFade2.ar(dry, wet, env * 2 - 1));
        }).add;

        SynthDef(\princeton_gate, {
            arg bus = 0, gate = 1, fade = 0.025,
                cut_thresh = -50, cut_attack = 1, cut_hold = 20,
                cut_release = 100, cut_range = -75, cut_hyst = 0, cut_detect = 0;
            var dry, monoA, det, openThr, closeThr, opened, fell, heldOpen, target, g, env;
            cut_thresh = Lag.kr(cut_thresh, 0.05);
            cut_range  = Lag.kr(cut_range,  0.05);
            cut_hyst   = Lag.kr(cut_hyst,   0.05);
            env = EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            dry   = In.ar(bus, 2);
            monoA = (dry[0] + dry[1]) * 0.5;
            // Detection: Peak = fast follower, RMS = slower/smoother follower
            det = Select.kr(cut_detect.round(1), [
                Amplitude.kr(monoA, 0.001, 0.01),
                Amplitude.kr(monoA, 0.02,  0.05)
            ]);
            // Schmitt trigger gives the open/close hysteresis
            openThr  = cut_thresh.dbamp;
            closeThr = (cut_thresh - cut_hyst).dbamp;
            opened   = Schmidt.kr(det, closeThr, openThr);
            // Hold: keep open for cut_hold ms after a falling edge
            fell     = (Delay1.kr(opened) - opened).max(0);
            heldOpen = opened.max(Trig1.kr(fell, cut_hold * 0.001));
            // Gain envelope: floor (cut_range dB) when closed, unity when open,
            // asymmetric attack (up) / release (down)
            target = heldOpen.linlin(0, 1, cut_range.dbamp, 1.0);
            g      = LagUD.kr(target, cut_attack * 0.001, cut_release * 0.001);
            ReplaceOut.ar(bus, LinXFade2.ar(dry, dry * g, env * 2 - 1));
        }).add;

        // ── Hold recorder: always-rolling capture of the post-amp signal ──
        SynthDef(\princeton_hold_rec, {
            arg looper_in_bus_num = 0, hold_buf_num = 0, phase_out = 0;
            // Always-rolling circular capture via Phasor + BufWr; the write head is exposed
            // on a control bus so hold_on can linearise the snapshot (seam -> buffer end).
            var sig   = In.ar(looper_in_bus_num, 2).sum * 0.5;
            var phase = Phasor.ar(0, 1, 0, BufFrames.kr(hold_buf_num));
            BufWr.ar(sig, hold_buf_num, phase, loop: 1);
            ReplaceOut.kr(phase_out, A2K.kr(phase));
        }).add;

        // ── Hold: granular playback of the frozen buffer, before the looper ──
        SynthDef(\princeton_hold, {
            arg hold_buf_num = 0, hold_out_bus_num = 0,
                gate = 1,
                hold_gain = 5, hold_rise = 0.25, hold_fall = 2.5,
                hold_level = 5, hold_size = 5, hold_density = 5, hold_pitch = 0,
                hold_spread = 5, hold_pmix = 10, hold_rev = 0, hold_envbuf = -1, hold_interp = 4;
            var grains, pad, env, gain_lin, level_lin, rate, bufdur, spread, ov, pmix, rmix;
            hold_gain    = Lag.kr(hold_gain,    0.05);
            hold_level   = Lag.kr(hold_level,   0.05);
            hold_size    = Lag.kr(hold_size,    0.05);
            hold_pitch   = Lag.kr(hold_pitch,   0.05);
            hold_spread  = Lag.kr(hold_spread,  0.05);
            hold_density = Lag.kr(hold_density, 0.05);
            hold_pmix    = Lag.kr(hold_pmix,    0.05);
            hold_rev     = Lag.kr(hold_rev,     0.05);
            rate   = hold_pitch.midiratio;      // semitones -> playback ratio
            bufdur = BufDur.kr(hold_buf_num);
            spread = hold_spread * 0.1;         // 0 = regular grid, 1 = full temporal scatter
            pmix   = hold_pmix * 0.01;          // fraction of grains that get the pitch shift
            rmix   = hold_rev  * 0.01;
            // Density = grain overlap of the 6 always-on layers. Two-part curve: the low
            // end stays cheap (Density 1 = 1.2) and the default (Density 5) stays ~6, but the
            // top is capped at 8 (was 12) to bound CPU at high Density. CPU scales with it.
            ov     = hold_density.min(5).linlin(1, 5, 1.2, 6) + (hold_density - 5).max(0).linlin(0, 5, 0, 2);

            // 8 always-on grain layers reading the frozen buffer; Density sets their
            // overlap, Size the grain length. Per-grain gain normalised so the layered
            // texture matches the old 5-layer loudness (sqrt(5/8) * 0.3 ~= 0.235).
            grains = Mix.fill(6, { |i|
                var dur  = hold_size.linexp(0, 10, 0.15, 0.6) * (1 + (i * 0.1));
                var trig, pos, pan, span, base_rate, imp, coin, grate, rcoin, rev;
                // Cap the grain length so the read never runs past the buffer end at the
                // current pitch (that hard jump to silence is the click source); then keep
                // the random start position inside the remaining room.
                dur  = dur.min(bufdur / rate * 0.9);
                span = rate.max(1) * dur / bufdur;
                base_rate = ov / dur * (1 + (i * 0.04));
                imp  = Impulse.ar(base_rate);
                // Spread scatters each grain's onset within its own interval (capped below
                // the interval so no trigger is dropped): 0 = regular grid, 1 = diffuse cloud.
                trig = TDelay.ar(imp, TRand.ar(0, spread * base_rate.reciprocal * 0.9, imp));
                pos  = TRand.ar(0.04, (0.98 - span).max(0.04), trig);
                pan  = TRand.ar(-1.0, 1.0, trig);
                // Per-grain coin: with probability pmix this grain gets the pitch shift,
                // otherwise it plays at original pitch -> blend of pitched and dry grains.
                coin  = TRand.ar(0, 1, trig);
                grate = 1 + ((rate - 1) * (coin < pmix));
                rcoin = TRand.ar(0, 1, trig);
                rev   = rcoin < rmix;
                grate = grate * (1 - (2 * rev));
                pos   = pos + (span * rev);
                GrainBuf.ar(2, trig, dur, hold_buf_num, grate, pos, hold_interp, pan, hold_envbuf) * 0.27;
            });
            pad = LeakDC.ar(grains);

            // Gain = drive into a soft saturation (character/thickness of the pad),
            // distinct from Level which is the output mix.
            gain_lin = hold_gain.linexp(0, 10, 0.5, 4.0);
            pad = (pad * gain_lin).tanh;
            // Gentle low-pass tames the granular high-frequency splatter for a softer pad.
            pad = LPF.ar(pad, 5000);

            env = EnvGen.kr(Env.asr(hold_rise, 1, hold_fall.max(0.01)), gate, doneAction: 2);
            level_lin = hold_level.linlin(0, 10, 0.0, 0.9);
            ReplaceOut.ar(hold_out_bus_num, pad * env * level_lin);
        }).add;

        // ── Looper subsystem (SynthDefs + commands), shared, runtime-loaded ──
        looperModule = { |eng|
            var lp = PathName(eng.class.filenameSymbol.asString).pathOnly ++ "looper_engine.scd";
            File.readAllString(lp).interpret.value(eng, (
                mediaNames: mediaNames, mediumBlend: mediumBlend, mediumRead: mediumRead,
                server: context.server, mainSynth: { synth }, loopBuf: loop_buf,
                looperInBus: looper_in_bus, looperOutBus: looper_out_bus
            ));
        }.value(this);

        SynthDef(\princeton, {

            arg out_bus = 0, pedal_bus_num = 0, hold_out_bus_num = 0,
                looper_in_bus_num = 0, looper_out_bus_num = 0,
                volume = 5.0, bass = 5, treble = 5, master = 7.5,
                reverb = 25, reverb_length = 2.5, reverb_low_shelf = 0, reverb_high_shelf = 0,
                trem_speed = 2.5, trem_intensity = 0,
                mic = 1, characteristic = 0,
                warp_rate = 2.5, warp_depth = 5, warp_rise = 2.5, warp_bypass = 1, warp_mix = 0,
                repeat_time = 250, repeat_feedback = 50, repeat_level = 50, repeat_bypass = 1,
                mute = 0, amp_bypass = 0,
                reverb_mute = 0, cab_mode = 1,
                cab_level = 1.0,
                eq_bypass = 1, eq_low_freq = 2, eq_low_boost = 0, eq_low_cut = 0,
                eq_high_freq = 2, eq_high_bw = 0, eq_high_boost = 0, eq_high_cut = 0, eq_gain = 0,
                limit_bypass = 1, limit_threshold = 0.31623, limit_ratio = 4.0, limit_gain = 1.0, limit_attack = 10, limit_decay = 50,
                send_a_source = 2, send_a_level = 1.0, send_b_source = 2, send_b_level = 1.0;

            var sig;
            var repeat_delay, repeat_fb, pre1, toned, pre2, power;
            var cab, cab_work, mic_freq, mic_rq, mic_db, mic_hpf, mic_lpf;
            var trem_lfo, trem_out, trem_depth, trem_dry;
            var sp1, sp2, sp3, diff, spring_wet, wetmix;
            var spring_in, preDel, twang;
            var input_gain, sag, sag_gain;
            var rev_decay, rev_send;
            var out_sig;
            var bass_gain, treble_gain;
            var bass_lf, bass_hf, treble_lf, treble_hf;
            var final_sig, loop_mix;
            var repeat_fb_lp, repeat_jitter, repeat_noise, repeat_dt;
            var warp_lfo, warp_sig, warp_depth_env;
            var sig_mono;
            var repeat_gate;
            var cab_dsp;
            var eq_work, eq_lf, eq_hf, eq_hrq;
            var limit_ctrl, limit_out;
            var send_input_tap, looper_ret, send_a, send_b;

            volume         = Lag.kr(volume,         0.05);
            bass           = Lag.kr(bass,           0.05);
            treble         = Lag.kr(treble,         0.05);
            master         = Lag.kr(master,         0.05);
            reverb         = Lag.kr(reverb,         0.10);
            reverb_length     = Lag.kr(reverb_length,     0.10);
            reverb_low_shelf  = Lag.kr(reverb_low_shelf,  0.05);
            reverb_high_shelf = Lag.kr(reverb_high_shelf, 0.05);
            trem_speed        = Lag.kr(trem_speed,        0.12);
            trem_intensity = Lag.kr(trem_intensity, 0.05);
            warp_rate      = Lag.kr(warp_rate,      0.05);
            warp_rise      = Lag.kr(warp_rise,      0.05);
            warp_mix       = Lag.kr(warp_mix,       0.05);
            repeat_feedback = Lag.kr(repeat_feedback, 0.05);
            repeat_level   = Lag.kr(repeat_level,   0.05);
            reverb_mute    = Lag.kr(reverb_mute,    0.05);
            mute           = Lag.kr(mute,           0.02);
            cab_level           = Lag.kr(cab_level,           0.05);
            eq_low_boost         = Lag.kr(eq_low_boost,         0.05);
            eq_low_cut           = Lag.kr(eq_low_cut,           0.05);
            eq_high_boost        = Lag.kr(eq_high_boost,        0.05);
            eq_high_cut          = Lag.kr(eq_high_cut,          0.05);
            eq_gain              = Lag.kr(eq_gain,              0.05);
            limit_threshold      = Lag.kr(limit_threshold,      0.05);
            limit_ratio          = Lag.kr(limit_ratio,          0.05);
            limit_gain           = Lag.kr(limit_gain,           0.05);
            limit_attack         = Lag.kr(limit_attack,         0.10);
            limit_decay          = Lag.kr(limit_decay,          0.10);
            characteristic       = Lag.kr(characteristic,       0.05);
            mic                  = Lag.kr(mic,                  0.05);
            cab_mode             = Lag.kr(cab_mode,             0.05);
            send_a_level         = Lag.kr(send_a_level,         0.05);
            send_b_level         = Lag.kr(send_b_level,         0.05);

            // ── Input (from pedal bus, post Push + Distort inserts) ──────────
            sig = In.ar(pedal_bus_num, 2);
            send_input_tap = sig;

            // ── Warp ─────────────────────────────────────────────────────────
            warp_depth_env = Lag.kr(warp_depth.linlin(0, 100, 0.0, 0.012) * (1 - warp_bypass.round(1)),
                              warp_rise);
            warp_lfo = SinOsc.ar(warp_rate + LFNoise2.kr(4, 0.08), 0, warp_depth_env, 0.007);
            warp_sig = DelayC.ar(sig, 0.02, warp_lfo.clip(0.0001, 0.02));
            sig = XFade2.ar(warp_sig, sig, LagUD.kr(Select.kr(warp_bypass.round(1), [warp_mix.linlin(0, 100, -1, 1), 1]), warp_rise, 0.008));

            // ── Repeat ───────────────────────────────────────────────────────
            repeat_gate   = Lag.kr(1 - repeat_bypass.round(1), 0.008);
            sig_mono      = (sig[0] + sig[1]) * 0.5;
            repeat_jitter = SinOsc.kr(0.3, 0, 0.0003) + LFNoise2.kr(8, 0.0002);
            repeat_dt     = Lag.kr(repeat_time * 0.001, 0.15) + repeat_jitter;
            repeat_fb    = LocalIn.ar(1) * (repeat_feedback / 100.0);
            repeat_fb_lp = SelectX.kr(characteristic, [5000, 2500]);
            repeat_fb    = repeat_fb * 1.063;
            repeat_fb    = LPF.ar(repeat_fb, repeat_fb_lp);
            repeat_fb    = (repeat_fb * 1.1).tanh * 0.95;
            repeat_delay = DelayL.ar(sig_mono * repeat_gate + repeat_fb, 1.001, repeat_dt.clip(0.001, 1.0));
            repeat_noise = WhiteNoise.ar(Amplitude.kr(repeat_fb, 0.01, 0.2) * 0.015);
            LocalOut.ar(repeat_delay + repeat_noise);
            sig = sig + (repeat_delay * (repeat_level / 100.0));

            // ── Amp: preamp → tone stack → power amp ─────────────────────────
            input_gain = volume.clip(0.01, 10).linexp(0.01, 10, 0.35, 22.6);
            pre1 = (sig * input_gain).tanh;
            pre1 = HPF.ar(pre1, 100);

            toned = MidEQ.ar(pre1, 650, 1.33, -8.0);

            bass_gain = bass.linlin(0, 10, 0.251, 3.981);
            bass_lf   = LPF.ar(toned, 250);
            bass_hf   = HPF.ar(toned, 250);
            toned     = (bass_lf * bass_gain) + bass_hf;

            treble_gain = treble.linlin(0, 10, 0.251, 3.981);
            treble_hf   = HPF.ar(toned, 2500);
            treble_lf   = LPF.ar(toned, 2500);
            toned       = treble_lf + (treble_hf * treble_gain);

            pre2 = (toned * 1.7).tanh * 0.55;
            pre2 = HPF.ar(pre2, 80);

            sag      = Amplitude.ar((pre2[0] + pre2[1]) * 0.5, 0.004, 0.12);
            sag_gain = 1.0 / (1.0 + sag * 0.35);
            power    = (pre2 * sag_gain * 2.2).softclip * 0.5;

            // ── Tremolo ───────────────────────────────────────────────────────
            trem_lfo   = SinOsc.kr(trem_speed, 0, 0.5, 0.5);
            trem_dry   = Lag.kr(trem_intensity.linlin(0, 15, 1.0, 0.0).clip(0, 1), 0.05);
            trem_depth = Lag.kr(trem_intensity.linlin(16, 100, 0.0, 0.9).clip(0, 1), 0.05);
            trem_out = [
                power[0] * (trem_dry + (1.0 - trem_dry) * (trem_depth * trem_lfo                              + (1.0 - trem_depth))),
                power[1] * (trem_dry + (1.0 - trem_dry) * (trem_depth * SinOsc.kr(trem_speed, pi * 0.5, 0.5, 0.5) + (1.0 - trem_depth)))
            ];

            // ── Looper ───────────────────────────────────────────────
            ReplaceOut.ar(looper_in_bus_num, trem_out);
            looper_ret = InFeedback.ar(looper_out_bus_num, 2);
            loop_mix = trem_out + looper_ret + InFeedback.ar(hold_out_bus_num, 16).clump(2).sum;

            // ── Spring reverb ─────────────────────────────────────────────────
            rev_decay = reverb_length;
            rev_send  = (reverb * 0.85 / 100.0).sqrt * 0.25 * (1 - reverb_mute);

            spring_in = (loop_mix[0] + loop_mix[1]) * 0.5 * rev_send;
            preDel    = DelayN.ar(spring_in, 0.02, 0.008);

            twang = BPF.ar(preDel, 1350 + LFNoise1.kr(0.5, 100), 3.0);
            twang = twang * rev_decay.linlin(0.5, 5.0, 0.05, 0.22);

            sp1 = AllpassL.ar(preDel, 0.04, 0.0163, 0.05);
            sp1 = AllpassL.ar(sp1,    0.04, 0.0271, 0.08);
            sp1 = CombL.ar(sp1, 0.1, 0.02974, rev_decay * 0.9);
            sp1 = LPF.ar(sp1, 2200);

            sp2 = AllpassL.ar(preDel, 0.04, 0.0213, 0.06);
            sp2 = AllpassL.ar(sp2,    0.04, 0.0347, 0.09);
            sp2 = CombL.ar(sp2, 0.1, 0.03511, rev_decay);
            sp2 = LPF.ar(sp2, 2000);

            sp3 = AllpassL.ar(preDel, 0.04, 0.0129, 0.04);
            sp3 = CombL.ar(sp3, 0.1, 0.04423, rev_decay * 1.12);
            sp3 = LPF.ar(sp3, 1800);

            diff       = AllpassN.ar(sp1 + sp2 + sp3 + (twang * 0.4), 0.05, [0.0137, 0.0211], 0.4);
            diff       = AllpassN.ar(diff[0] + diff[1], 0.03, [0.0091, 0.0173], 0.3);
            spring_wet = diff * 0.35;
            spring_wet = BLowShelf.ar(spring_wet, 250,  1.0, reverb_low_shelf);
            spring_wet = BHiShelf.ar(spring_wet,  3500, 1.0, reverb_high_shelf);

            wetmix = loop_mix + spring_wet;

            // ── Cabinet (parametric mic, single chain) ───────────────────────
            mic_freq = SelectX.kr(mic, [3200, 2000, 1200]);
            mic_rq   = SelectX.kr(mic, [1.0,  1.11, 1.25]);
            mic_db   = SelectX.kr(mic, [4.0,  1.5,  -2.0]);
            mic_hpf  = SelectX.kr(mic, [90,   95,   100]);
            mic_lpf  = SelectX.kr(mic, [6500, 5000, 3800]);
            cab_work = MidEQ.ar(wetmix,   120, 1.4, 3.5);
            cab_work = MidEQ.ar(cab_work, mic_freq, mic_rq, mic_db);
            cab_work = LPF.ar(HPF.ar(cab_work, mic_hpf), mic_lpf);
            cab_dsp  = cab_work * cab_level;
            cab = [
                SelectX.ar(cab_mode, [wetmix[0], cab_dsp[0]]),
                SelectX.ar(cab_mode, [wetmix[1], cab_dsp[1]])
            ];
            cab = LinXFade2.ar(cab, sig, Lag.kr(amp_bypass.round(1) * 2 - 1, 0.008));

            out_sig   = cab * (master / 10.0).squared * 2.0;
            final_sig = out_sig.softclip * (1.0 - mute);

            // ── EQ (Pultec-style) ────────────────────────────────────────────
            eq_lf  = Select.kr(eq_low_freq.round(1),  [100, 140, 200, 300]);
            eq_hf  = Select.kr(eq_high_freq.round(1), [1000, 1500, 2000, 3000, 4000, 5000]);
            eq_hrq = Select.kr(eq_high_bw.round(1),   [0.7, 2.0]);
            eq_work = BLowShelf.ar(final_sig, eq_lf,     0.7,    eq_low_boost);
            eq_work = BPeakEQ.ar(  eq_work,   eq_lf * 3, 1.2,    eq_low_cut    * -1);
            eq_work = BPeakEQ.ar(  eq_work,   eq_hf,     eq_hrq, eq_high_boost);
            eq_work = BHiShelf.ar( eq_work,   3000,      0.7,    eq_high_cut   * -1);
            eq_work = eq_work * eq_gain.dbamp;
            final_sig = LinXFade2.ar(eq_work, final_sig, Lag.kr(eq_bypass.round(1) * 2 - 1, 0.008));

            // ── Limit ────────────────────────────────────────────────────────
            limit_ctrl   = (final_sig[0] + final_sig[1]) * 0.5;
            limit_out    = Compander.ar(
                final_sig, limit_ctrl, limit_threshold,
                1.0, 1.0 / limit_ratio.max(1.0),
                limit_attack * 0.001, limit_decay * 0.001
            ) * limit_gain;
            final_sig   = LinXFade2.ar(limit_out, final_sig, Lag.kr(limit_bypass.round(1) * 2 - 1, 0.008));

            Out.ar(out_bus, final_sig);

            // ── fx send buses ────────────────────────────────────────────────
            send_a = [
                Select.ar(send_a_source.round(1), [send_input_tap[0], looper_ret[0], final_sig[0]]),
                Select.ar(send_a_source.round(1), [send_input_tap[1], looper_ret[1], final_sig[1]])
            ] * send_a_level;
            send_b = [
                Select.ar(send_b_source.round(1), [send_input_tap[0], looper_ret[0], final_sig[0]]),
                Select.ar(send_b_source.round(1), [send_input_tap[1], looper_ret[1], final_sig[1]])
            ] * send_b_level;
            if(~sendA.notNil) { ReplaceOut.ar(~sendA, send_a) };
            if(~sendB.notNil) { ReplaceOut.ar(~sendB, send_b) };

        }).add;

        SynthDef(\count_click, {
            arg out_bus = 0, level = 0.5, pitch = 0, length = 50, count_bus_num = 0, position = 0;
            var freq = 440 * (2 ** (pitch / 12));
            var env  = EnvGen.ar(Env.perc(0.001, length * 0.001), doneAction: 2);
            var sig  = SinOsc.ar(freq) * env * level.clip(0, 1);
            Out.ar(out_bus,       [sig, sig] * (1 - position.round(1)));
            Out.ar(count_bus_num, sig * position.round(1));
        }).add;

        SynthDef(\princeton_tuner, {
            arg in_bus = 0, tune_freq_bus_num = 0, gate = 1, fade = 0.02;
            var sig, freq, has;
            EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            sig = In.ar(in_bus, 1) * 4.0;
            sig = HPF.ar(sig, 70);
            sig = LPF.ar(sig, 2000);
            # freq, has = Pitch.kr(sig,
                minFreq: 60, maxFreq: 1500,
                ampThreshold: 0.003, median: 7);
            Out.kr(tune_freq_bus_num, freq * has);
        }).add;

        context.server.sync;

        Synth.head(context.xg, \princeton_silence, [
            \hold_bus,   hold_out_bus.index,
            \looper_bus, looper_out_bus.index
        ]);

        in_synth = Synth(\princeton_in, [
            \in_bus,        context.in_b[0].index,
            \in_bus_r,      context.in_b[1].index,
            \count_bus_num, count_bus.index,
            \env1_bus_num,  env1_bus.index,
            \env2_bus_num,  env2_bus.index,
            \pedal_bus_num, pedal_bus.index
        ], context.xg);

        synth = Synth.after(in_synth, \princeton, [
            \out_bus,             context.out_b.index,
            \pedal_bus_num,       pedal_bus.index,
            \looper_in_bus_num,   looper_in_bus.index,
            \looper_out_bus_num,  looper_out_bus.index,
            \hold_out_bus_num,    hold_out_bus.index
        ]);

        hold_rec_synth = Synth.after(synth, \princeton_hold_rec, [
            \looper_in_bus_num, looper_in_bus.index,
            \hold_buf_num,      hold_rec_buf.bufnum,
            \phase_out,         hold_phase_bus.index
        ]);

        // ── Simple param commands ────────────────────────────────────────
        [
            ["repeat_bypass",        \repeat_bypass],
            ["repeat_level",         \repeat_level],
            ["repeat_feedback",      \repeat_feedback],
            ["repeat_time",          \repeat_time],
            ["repeat_characteristic",\characteristic],
            ["amp_bypass",           \amp_bypass],
            ["amp_bass",             \bass],
            ["amp_treble",           \treble],
            ["amp_master",           \master],
            ["amp_volume",           \volume],
            ["warp_bypass",          \warp_bypass],
            ["warp_depth",           \warp_depth],
            ["warp_mix",             \warp_mix],
            ["warp_rate",            \warp_rate],
            ["warp_rise",            \warp_rise],
            ["tremolo_intensity",    \trem_intensity],
            ["tremolo_speed",        \trem_speed],
            ["reverb_amount",        \reverb],
            ["reverb_length",        \reverb_length],
            ["reverb_low_shelf",     \reverb_low_shelf],
            ["reverb_high_shelf",    \reverb_high_shelf],
            ["reverb_mute",          \reverb_mute],
            ["cab_mode",             \cab_mode],
            ["cab_level",            \cab_level],
            ["mic_position",         \mic],
            ["eq_bypass",            \eq_bypass],
            ["eq_low_freq",          \eq_low_freq],
            ["eq_low_boost",         \eq_low_boost],
            ["eq_low_cut",           \eq_low_cut],
            ["eq_high_freq",         \eq_high_freq],
            ["eq_high_bw",           \eq_high_bw],
            ["eq_high_boost",        \eq_high_boost],
            ["eq_high_cut",          \eq_high_cut],
            ["eq_gain",              \eq_gain],
            ["limit_bypass",         \limit_bypass],
            ["limit_threshold",      \limit_threshold],
            ["limit_ratio",          \limit_ratio],
            ["limit_gain",           \limit_gain],
            ["limit_attack",         \limit_attack],
            ["limit_decay",          \limit_decay],
            ["mute",                 \mute],
            ["fx_send_a_source",     \send_a_source],
            ["fx_send_a_level",      \send_a_level],
            ["fx_send_b_source",     \send_b_source],
            ["fx_send_b_level",      \send_b_level]
        ].do { |pair|
            this.addCommand(pair[0], "f", { |msg| synth.set(pair[1], msg[1]) });
        };

        this.addCommand("signal_input", "f", { |msg| in_synth.set(\signal_input, msg[1]) });
        this.addCommand("input_trim",   "f", { |msg| in_synth.set(\input_trim,   msg[1]) });
        this.addCommand("env1_attack",  "f", { |msg| in_synth.set(\env1_attack,  msg[1]) });
        this.addCommand("env1_release", "f", { |msg| in_synth.set(\env1_release, msg[1]) });
        this.addCommand("env2_attack",  "f", { |msg| in_synth.set(\env2_attack,  msg[1]) });
        this.addCommand("env2_release", "f", { |msg| in_synth.set(\env2_release, msg[1]) });

        this.addCommand("cut_on", "", {
            if(cut_synth.isNil) {
                cut_synth = Synth.after(in_synth, \princeton_gate, [
                    \bus,          pedal_bus.index,
                    \cut_thresh,  cut_thresh_v,
                    \cut_attack,  cut_attack_v,
                    \cut_hold,    cut_hold_v,
                    \cut_release, cut_release_v,
                    \cut_range,   cut_range_v,
                    \cut_hyst,    cut_hyst_v,
                    \cut_detect,  cut_detect_v,
                    \gate,         1
                ]);
            };
        });

        this.addCommand("cut_off", "", {
            if(cut_synth.notNil) {
                cut_synth.set(\gate, 0);
                cut_synth = nil;
            };
        });

        this.addCommand("cut_thresh",  "f", { |msg| cut_thresh_v  = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_thresh,  msg[1]) } });
        this.addCommand("cut_attack",  "f", { |msg| cut_attack_v  = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_attack,  msg[1]) } });
        this.addCommand("cut_hold",    "f", { |msg| cut_hold_v    = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_hold,    msg[1]) } });
        this.addCommand("cut_release", "f", { |msg| cut_release_v = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_release, msg[1]) } });
        this.addCommand("cut_range",   "f", { |msg| cut_range_v   = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_range,   msg[1]) } });
        this.addCommand("cut_hyst",    "f", { |msg| cut_hyst_v    = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_hyst,    msg[1]) } });
        this.addCommand("cut_detect",  "f", { |msg| cut_detect_v  = msg[1]; if(cut_synth.notNil) { cut_synth.set(\cut_detect,  msg[1]) } });

        this.addCommand("hold_on", "i", { |msg|
            var i = msg[1].asInteger - 1;
            hold_wants_on[i] = true;
            if(hold_synth[i].isNil) {
                hold_play_idx[i] = (hold_play_idx[i] + 1) % 4;
                // Read the recorder's current write head, then copy the circular capture
                // into the pool buffer in two parts so it is time-ordered (oldest first).
                // The seam then sits at the buffer end, which grains never read across.
                hold_phase_bus.get({ |w|
                    var n, wi, play, slot;
                    if(hold_wants_on[i] and: { hold_synth[i].isNil }) {
                        n    = hold_rec_buf.numFrames;
                        wi   = w.floor.asInteger.clip(0, n - 1);
                        play = hold_play_bufs[i][hold_play_idx[i]];
                        slot = (i * 4) + hold_play_idx[i];
                        if(wi > 0) {
                            hold_rec_buf.copyData(play, 0,      wi, n - wi);
                            hold_rec_buf.copyData(play, n - wi, 0,  wi);
                        } {
                            hold_rec_buf.copyData(play, 0, 0, n);
                        };
                        hold_synth[i] = Synth.after(synth, \princeton_hold, [
                            \hold_buf_num,      play.bufnum,
                            \hold_out_bus_num,  hold_out_bus.index + (slot * 2),
                            \hold_envbuf,  hold_env_bufs[hold_shape_v[i]].bufnum,
                            \hold_interp,  hold_interp_v[i],
                            \hold_gain,    hold_gain_v[i],
                            \hold_rise,    hold_rise_v[i],
                            \hold_fall,    hold_fall_v[i],
                            \hold_level,   hold_level_v[i],
                            \hold_size,    hold_size_v[i],
                            \hold_density, hold_density_v[i],
                            \hold_pitch,   hold_pitch_v[i],
                            \hold_spread,  hold_spread_v[i],
                            \hold_pmix,    hold_pmix_v[i],
                            \hold_rev,     hold_rev_v[i],
                            \gate,         1
                        ]);
                    };
                });
            };
        });

        this.addCommand("hold_off", "i", { |msg|
            var i = msg[1].asInteger - 1;
            // Gate off: the pad fades over Fall on the play buffer, which the rolling
            // recorder never touches, so the fade stays clean and the next hold_on grabs
            // a fresh snapshot. Clearing hold_wants_on also cancels a pending grab.
            hold_wants_on[i] = false;
            if(hold_synth[i].notNil) {
                hold_synth[i].set(\gate, 0);
                hold_synth[i] = nil;
            };
        });

        this.addCommand("hold_gain", "if", { |msg| var i = msg[1].asInteger - 1; hold_gain_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_gain, msg[2]) } });
        this.addCommand("hold_rise", "if", { |msg| var i = msg[1].asInteger - 1; hold_rise_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_rise, msg[2]) } });
        this.addCommand("hold_fall", "if", { |msg| var i = msg[1].asInteger - 1; hold_fall_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_fall, msg[2]) } });
        this.addCommand("hold_level", "if", { |msg| var i = msg[1].asInteger - 1; hold_level_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_level, msg[2]) } });
        this.addCommand("hold_size", "if", { |msg| var i = msg[1].asInteger - 1; hold_size_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_size, msg[2]) } });
        this.addCommand("hold_density", "if", { |msg| var i = msg[1].asInteger - 1; hold_density_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_density, msg[2]) } });
        this.addCommand("hold_pitch", "if", { |msg| var i = msg[1].asInteger - 1; hold_pitch_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_pitch, msg[2]) } });
        this.addCommand("hold_spread", "if", { |msg| var i = msg[1].asInteger - 1; hold_spread_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_spread, msg[2]) } });
        this.addCommand("hold_pmix", "if", { |msg| var i = msg[1].asInteger - 1; hold_pmix_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_pmix, msg[2]) } });
        this.addCommand("hold_rev", "if", { |msg| var i = msg[1].asInteger - 1; hold_rev_v[i] = msg[2]; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_rev, msg[2]) } });
        this.addCommand("hold_shape", "if", { |msg| var i = msg[1].asInteger - 1; hold_shape_v[i] = msg[2].asInteger.clip(0, 4); if(hold_synth[i].notNil) { hold_synth[i].set(\hold_envbuf, hold_env_bufs[hold_shape_v[i]].bufnum) } });
        this.addCommand("hold_interp", "if", { |msg| var i = msg[1].asInteger - 1; hold_interp_v[i] = msg[2].asInteger; if(hold_synth[i].notNil) { hold_synth[i].set(\hold_interp, msg[2]) } });

        this.addCommand("fray_on", "", {
            if(fray_synth.isNil) {
                fray_synth = Synth.after(cut_synth ? in_synth, \princeton_fray, [
                    \bus,         pedal_bus.index,
                    \fray_drive,  fray_drive_v,
                    \fray_tone,   fray_tone_v,
                    \fray_gate,   fray_gate_v,
                    \fray_comp,   fray_comp_v,
                    \fray_stab,   fray_stab_v,
                    \fray_octave, fray_octave_v,
                    \fray_octave_mode, fray_octave_mode_v,
                    \fray_volume, fray_volume_v,
                    \gate,        1
                ]);
            };
        });

        this.addCommand("fray_off", "", {
            if(fray_synth.notNil) {
                fray_synth.set(\gate, 0);
                fray_synth = nil;
            };
        });

        this.addCommand("fray_drive",  "f", { |msg| fray_drive_v  = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_drive,  msg[1]) } });
        this.addCommand("fray_tone",   "f", { |msg| fray_tone_v   = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_tone,   msg[1]) } });
        this.addCommand("fray_octave", "f", { |msg| fray_octave_v = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_octave, msg[1]) } });
        this.addCommand("fray_octave_mode", "f", { |msg| fray_octave_mode_v = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_octave_mode, msg[1]) } });
        this.addCommand("fray_gate",   "f", { |msg| fray_gate_v   = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_gate,   msg[1]) } });
        this.addCommand("fray_comp",   "f", { |msg| fray_comp_v   = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_comp,   msg[1]) } });
        this.addCommand("fray_stab",   "f", { |msg| fray_stab_v   = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_stab,   msg[1]) } });
        this.addCommand("fray_volume", "f", { |msg| fray_volume_v = msg[1]; if(fray_synth.notNil) { fray_synth.set(\fray_volume, msg[1]) } });

        this.addCommand("push_on", "", {
            if(push_synth.isNil) {
                push_synth = Synth.after(fray_synth ? cut_synth ? in_synth, \princeton_push, [
                    \bus,        pedal_bus.index,
                    \push_gain,  push_gain_v,
                    \push_tone,  push_tone_v,
                    \push_level, push_level_v,
                    \push_mix,   push_mix_v,
                    \gate,       1
                ]);
            };
        });

        this.addCommand("push_off", "", {
            if(push_synth.notNil) {
                push_synth.set(\gate, 0);
                push_synth = nil;
            };
        });

        this.addCommand("push_gain",  "f", { |msg| push_gain_v  = msg[1]; if(push_synth.notNil) { push_synth.set(\push_gain,  msg[1]) } });
        this.addCommand("push_tone",  "f", { |msg| push_tone_v  = msg[1]; if(push_synth.notNil) { push_synth.set(\push_tone,  msg[1]) } });
        this.addCommand("push_level", "f", { |msg| push_level_v = msg[1]; if(push_synth.notNil) { push_synth.set(\push_level, msg[1]) } });
        this.addCommand("push_mix",   "f", { |msg| push_mix_v   = msg[1]; if(push_synth.notNil) { push_synth.set(\push_mix,   msg[1]) } });

        this.addCommand("distort_on", "", {
            if(distort_synth.isNil) {
                distort_synth = Synth.after(push_synth ? fray_synth ? cut_synth ? in_synth, \princeton_distort, [
                    \bus,            pedal_bus.index,
                    \distort_gain,   distort_gain_v,
                    \distort_tone,   distort_tone_v,
                    \distort_level,  distort_level_v,
                    \distort_lowcut, distort_lowcut_v,
                    \gate,           1
                ]);
            };
        });

        this.addCommand("distort_off", "", {
            if(distort_synth.notNil) {
                distort_synth.set(\gate, 0);
                distort_synth = nil;
            };
        });

        this.addCommand("distort_gain",   "f", { |msg| distort_gain_v   = msg[1]; if(distort_synth.notNil) { distort_synth.set(\distort_gain,   msg[1]) } });
        this.addCommand("distort_tone",   "f", { |msg| distort_tone_v   = msg[1]; if(distort_synth.notNil) { distort_synth.set(\distort_tone,   msg[1]) } });
        this.addCommand("distort_level",  "f", { |msg| distort_level_v  = msg[1]; if(distort_synth.notNil) { distort_synth.set(\distort_level,  msg[1]) } });
        this.addCommand("distort_lowcut", "f", { |msg| distort_lowcut_v = msg[1]; if(distort_synth.notNil) { distort_synth.set(\distort_lowcut, msg[1]) } });

        // ── Special commands ─────────────────────────────────────────────
        this.addCommand("count_tick", "ffff", { |msg|
            Synth(\count_click, [
                \out_bus,        context.out_b.index,
                \level,          msg[1],
                \pitch,          msg[2],
                \length,         msg[3],
                \count_bus_num,  count_bus.index,
                \position,       msg[4]
            ], context.xg);
        });

        this.addCommand("tune_on", "", {
            if(tune_synth.isNil) {
                tune_synth = Synth(\princeton_tuner, [
                    \in_bus,             context.in_b[0].index,
                    \tune_freq_bus_num, tune_freq_bus.index,
                    \gate,               1
                ], context.xg);
            };
        });

        this.addCommand("tune_off", "", {
            if(tune_synth.notNil) {
                tune_synth.set(\gate, 0);
                tune_synth = nil;
            };
        });

        this.addPoll("tune_pitch", {
            tune_freq_bus.getSynchronous;
        });

        this.addPoll("env1_value", {
            env1_bus.getSynchronous;
        });

        this.addPoll("env2_value", {
            env2_bus.getSynchronous;
        });
    }

    free {
        synth.free;
        in_synth.free;
        if(cut_synth.notNil) { cut_synth.free };
        hold_synth.do({ |s| if(s.notNil) { s.free } });
        if(hold_rec_synth.notNil) { hold_rec_synth.free };
        if(push_synth.notNil) { push_synth.free };
        if(distort_synth.notNil) { distort_synth.free };
        if(fray_synth.notNil)    { fray_synth.free };
        if(tune_synth.notNil) { tune_synth.free };
        loop_buf.free;
        hold_rec_buf.free;
        hold_play_bufs.do({ |pool| pool.do({ |b| b.free }) });
        hold_env_bufs.do({ |b| b.free });
        hold_phase_bus.free;
        hold_out_bus.free;
        tune_freq_bus.free;
        count_bus.free;
        env1_bus.free;
        env2_bus.free;
        pedal_bus.free;
        looperModule[\free].value;
        looper_in_bus.free;
        looper_out_bus.free;
    }
}
