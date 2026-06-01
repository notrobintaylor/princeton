Engine_Princeton : CroneEngine {

    var synth;
    var in_synth, tuner_synth;
    var push_synth, push_gain_v, push_tone_v, push_level_v, push_mix_v;
    var distort_synth, distort_gain_v, distort_tone_v, distort_level_v, distort_lowcut_v;
    var loop_buf;
    var tuner_freq_bus;
    var metro_bus;
    var env1_bus, env2_bus;
    var pedal_bus;
    var imprint_in_bus, imprint_out_bus, imprint_synth;
    var imp_amt_v, imp_bbd_tone_v, imp_medium_v;
    var looper_in_bus, looper_out_bus, looper_synth, mediaNames;

    alloc {

        var mediumChain, mediumRead, mediumBlend;

        loop_buf = Buffer.alloc(context.server, (48000 * 40), 2);
        tuner_freq_bus = Bus.control(context.server, 1);
        metro_bus = Bus.audio(context.server, 1);
        env1_bus = Bus.control(context.server, 1);
        env2_bus = Bus.control(context.server, 1);
        pedal_bus = Bus.audio(context.server, 2);
        imprint_in_bus  = Bus.audio(context.server, 2);
        imprint_out_bus = Bus.audio(context.server, 2);
        looper_in_bus   = Bus.audio(context.server, 2);
        looper_out_bus  = Bus.audio(context.server, 2);
        push_gain_v = 5; push_tone_v = 5; push_level_v = 5; push_mix_v = 25;
        distort_gain_v = 5; distort_tone_v = 7.5; distort_level_v = 5; distort_lowcut_v = 0;
        imp_amt_v = 50; imp_bbd_tone_v = 0; imp_medium_v = 3;
        mediaNames = [\bbd, \cas, \cd, \chip, \tape, \vinyl];  // variant order; index = imp_medium_v

        context.server.sync;

        // Single medium character chain (prc_t106): builds ONE medium's destructive
        // base DSP via .switch, so a per-medium SynthDef only instantiates that one
        // chain. Source of truth for all six media; wrapped by mediumBlend (the dry/wet
        // mix) and used by the per-medium looper wear and imprint variants (one each).
        // input is stereo; returns stereo. bbd_tone_fc supplied by the caller.
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

        // Single medium dry/wet blend (prc_t106): wraps mediumChain with the Imprint/Wear
        // amount mix. Used by BOTH the per-medium looper wear and the per-medium imprint
        // variants, so there is no all-six SelectX medium path left anywhere.
        mediumBlend = { |med, input, amt, bbd_tone_fc|
            var m = amt / 100.0;
            (input * (1.0 - m)) + (mediumChain.(med, input, amt, bbd_tone_fc) * m)
        };

        // Single medium read-path effect (prc_t106): the playback-side M: colouring for
        // ONE medium. rd is stereo [L, R]; returns stereo. Used by the per-medium looper
        // variants (one each) in place of the former SelectX-over-six.
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

        SynthDef(\princeton_in, {
            arg in_bus = 0, in_bus_r = 0, signal_input = 1, metro_bus_num = 0,
                env1_attack = 0.05, env1_release = 0.05, env1_bus_num = 0,
                env2_attack = 0.05, env2_release = 0.05, env2_bus_num = 0,
                pedal_bus_num = 0;
            var sig, sig_l_in, sig_r_in, metro_in, sig_input_norm, input_level_gain;
            var env_src, env1_amp, env2_amp;

            signal_input = Lag.kr(signal_input, 0.05);
            env1_attack  = Lag.kr(env1_attack,  0.05);
            env1_release = Lag.kr(env1_release, 0.05);
            env2_attack  = Lag.kr(env2_attack,  0.05);
            env2_release = Lag.kr(env2_release, 0.05);

            sig_l_in = In.ar(in_bus,   1);
            sig_r_in = In.ar(in_bus_r, 1);
            metro_in = In.ar(metro_bus_num, 1);

            sig_input_norm   = (signal_input - 1).clip(0, 1);
            input_level_gain = ((1 - sig_input_norm) * 1.0) + (sig_input_norm * 0.31623);

            sig = [
                (sig_l_in                                                          * input_level_gain) + metro_in,
                ((sig_l_in * (1 - sig_input_norm)) + (sig_r_in * sig_input_norm))  * input_level_gain  + metro_in
            ];
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
            ReplaceOut.ar(bus, XFade2.ar(dry, wet, env * 2 - 1));
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
            ReplaceOut.ar(bus, XFade2.ar(dry, distort_sig, env * 2 - 1));
        }).add;

        // ── Imprint sub-synths (prc_t100/t106): the record/dub base-character colouring,
        // one variant per medium (matches the looper variant, since the medium is fixed
        // for a loop's life). Spawned only while recording/dubbing, so playback pays
        // nothing. Reads trem_out from imprint_in_bus, writes the coloured result to
        // imprint_out_bus (main reads it with InFeedback, L50). Same mediumBlend as the
        // looper wear, so one medium's chain runs, not six.
        mediaNames.do { |med|
        SynthDef(("princeton_imprint_" ++ med).asSymbol, {
            arg in_bus = 0, out_bus = 0, gate = 1, fade = 0.025,
                amt = 50, loop_bbd_tone = 0;
            var input, bbd_tone_fc;
            amt           = Lag.kr(amt, 0.05);
            loop_bbd_tone = Lag.kr(loop_bbd_tone, 0.05);
            EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            input = In.ar(in_bus, 2);
            bbd_tone_fc = SelectX.kr(loop_bbd_tone, [5000, 2500]);
            ReplaceOut.ar(out_bus, mediumBlend.(med, input, amt, bbd_tone_fc));
        }).add;
        };

        // ── Looper sub-synths (prc_t106): one variant per medium, generated below.
        // The medium character is baked into each variant (only that medium's wear
        // chain, read-path effect, and for CD/Vinyl the event/noise blocks are
        // instantiated), so a running looper computes ONE medium, not six. The medium
        // is fixed for a loop's life: Lua spawns the matching variant at REC, and a
        // medium change while a loop exists clears it back to IDLE (prc_t106). Reads
        // trem_out from looper_in_bus, outputs loop_out to looper_out_bus (main reads
        // it via InFeedback, L50).
        mediaNames.do { |med|
        SynthDef(("princeton_looper_" ++ med).asSymbol, {
            arg looper_in_bus = 0, looper_out_bus = 0,
                imprint_in_bus_num = 0, imprint_out_bus_num = 0, loop_buf_num = 0,
                loop_rec = 0, loop_dub = 0, loop_play = 0,
                loop_frames = 1920000, loop_level = 0.75, loop_dub_level = 0.75, loop_fade = 0.75,
                loop_direction = 0, loop_speed = 1, loop_dub_style = 0,
                loop_wear_amt = 5,
                loop_play_from = 0, loop_sample_retrig = 0,
                loop_wow_tape = 5, loop_wow_cas = 5,
                loop_bbd_tone = 0, loop_chip_crush = 0, loop_cd_errors = 0, loop_vinyl_noise = 10;
            var input, trem_imprinted, loop_preserve_out;
            var frames, fade_samps, speed_rate, dub_style_r, is_resample;
            var loop_reset, retrig_kr, start_trig, loop_phase, play_phase;
            var direction_r, pend_phase, pend_read, wrap_trig, pend_wrap_trig, oneshot_trig, in_sample_mode, oneshot_done, sample_gate, rand_dir, rand_read;
            var read_pos, fade_norm, fade_gain, loop_rd, loop_preserve;
            var bbd_tone_fc;
            var cd_skip_out, cd_skip_env, cd_stutter_out, cd_stutter_env, cd_scratch_env;
            var write_sig, loop_rd_wow, loop_out;

            loop_level       = Lag.kr(loop_level,       0.05);
            loop_dub_level   = Lag.kr(loop_dub_level,   0.05);
            loop_fade        = Lag.kr(loop_fade,        0.05);
            loop_wear_amt    = Lag.kr(loop_wear_amt,    0.05);
            loop_wow_tape    = Lag.kr(loop_wow_tape,    0.05);
            loop_wow_cas     = Lag.kr(loop_wow_cas,     0.05);
            loop_chip_crush  = Lag.kr(loop_chip_crush,  0.05);
            loop_cd_errors   = Lag.kr(loop_cd_errors,   0.05);
            loop_vinyl_noise = Lag.kr(loop_vinyl_noise, 0.05);
            loop_bbd_tone    = Lag.kr(loop_bbd_tone,    0.05);
            loop_speed       = Lag.kr(loop_speed,       0.05);

            input = In.ar(looper_in_bus, 2);

            frames     = loop_frames.max(2);
            fade_samps = 512;
            speed_rate = loop_speed.clip(0.5, 2.0);

            dub_style_r = loop_dub_style.round(1);
            is_resample = dub_style_r > 2.5;

            loop_reset = Changed.kr(loop_rec)  * loop_rec;
            retrig_kr  = Changed.kr(loop_sample_retrig);
            start_trig = Changed.kr(loop_play) * loop_play * (1 - loop_play_from.round(1))
                       + retrig_kr             *             (1 - loop_play_from.round(1));
            loop_phase = Phasor.ar(loop_reset + start_trig, Select.kr(loop_rec.round(1), [Select.kr(is_resample * loop_dub.round(1), [speed_rate, 1]), speed_rate]), 0, frames, 0);
            play_phase = Phasor.ar(loop_reset + start_trig, speed_rate, 0, frames, 0);

            direction_r = loop_direction.round(1);

            pend_phase = Phasor.ar(loop_reset + start_trig, speed_rate, 0, (frames - 1) * 2, 0);
            pend_read  = pend_phase.fold(0, frames - 1);

            wrap_trig      = (play_phase < Delay1.ar(play_phase)) * (loop_play + loop_dub).min(1);
            pend_wrap_trig = (pend_phase < Delay1.ar(pend_phase)) * (loop_play + loop_dub).min(1);
            oneshot_trig   = Select.ar(direction_r, [wrap_trig, wrap_trig, pend_wrap_trig, wrap_trig]);
            in_sample_mode = (dub_style_r > 1.5) - is_resample;
            oneshot_done   = SetResetFF.ar(
                oneshot_trig * in_sample_mode,
                K2A.ar(loop_reset + retrig_kr + start_trig)
            );
            sample_gate    = 1 - (oneshot_done * in_sample_mode);
            rand_dir  = TRand.ar(0.0, 1.0, wrap_trig).round(1);
            rand_read = Select.ar(rand_dir, [play_phase, frames - 1 - play_phase]);

            read_pos   = Select.ar(direction_r, [
                play_phase,
                frames - 1 - play_phase,
                pend_read,
                rand_read
            ]);

            fade_norm  = (play_phase.min(frames - play_phase) / fade_samps).clip(0, 1);
            fade_norm  = Select.ar(direction_r, [
                fade_norm,
                fade_norm,
                (pend_read.min(frames - 1 - pend_read) / fade_samps).clip(0, 1),
                fade_norm
            ]);
            fade_gain  = (fade_norm * 0.5 * pi).sin;
            fade_gain  = fade_gain * fade_gain;

            loop_rd    = BufRd.ar(2, loop_buf_num, read_pos,   loop: 1, interpolation: 2);

            loop_preserve = BufRd.ar(2, loop_buf_num, loop_phase, loop: 1, interpolation: 1);

            bbd_tone_fc = SelectX.kr(loop_bbd_tone, [5000, 2500]);

            // Wear: only this variant's medium chain (prc_t106).
            loop_preserve_out = mediumBlend.(med, loop_preserve, loop_wear_amt, bbd_tone_fc);

            ReplaceOut.ar(imprint_in_bus_num, input);
            trem_imprinted    = InFeedback.ar(imprint_out_bus_num, 2);
            trem_imprinted    = LPF.ar(trem_imprinted, (speed_rate * 21600).clip(2000, 22000));

            // CD read-path events (skip/stutter/scratch): only the CD variant.
            if(med == \cd, {
                var cd_errors_curve, cd_skip_rate, cd_skip_trig, cd_skip_pos, cd_skip_phase, cd_skip_rd;
                var cd_stutter_rate, cd_stutter_trig, cd_stutter_lock_pos, cd_stutter_phase, cd_stutter_rd;
                cd_errors_curve = loop_cd_errors.max(0).sqrt * 10.0;
                cd_skip_rate    = cd_errors_curve.linlin(0, 100, 0.0, 2.0);
                cd_skip_trig    = Dust.kr(cd_skip_rate);
                cd_skip_pos     = TRand.kr(0.0, frames - 1.0, cd_skip_trig);
                cd_skip_phase   = Phasor.ar(K2A.ar(cd_skip_trig), speed_rate, 0, frames, cd_skip_pos);
                cd_skip_rd      = BufRd.ar(2, loop_buf_num, cd_skip_phase, loop: 1, interpolation: 2);
                cd_skip_env     = EnvGen.kr(Env.perc(0.001, 0.15, 1, -4), cd_skip_trig);
                cd_skip_out     = cd_skip_rd * cd_skip_env;
                cd_stutter_rate     = cd_errors_curve.linlin(0, 100, 0.0, 0.8);
                cd_stutter_trig     = Dust.kr(cd_stutter_rate);
                cd_stutter_lock_pos = Latch.kr(A2K.kr(play_phase), cd_stutter_trig);
                cd_stutter_phase    = (Phasor.ar(K2A.ar(cd_stutter_trig), speed_rate, 0, 4800, 0) + K2A.ar(cd_stutter_lock_pos)).wrap(0, frames - 1);
                cd_stutter_rd       = BufRd.ar(2, loop_buf_num, cd_stutter_phase, loop: 1, interpolation: 2);
                cd_stutter_env      = EnvGen.kr(Env([0, 1, 1, 0], [0.001, 0.3, 0.005]), cd_stutter_trig);
                cd_stutter_out      = cd_stutter_rd * cd_stutter_env;
                cd_scratch_env      = EnvGen.kr(Env.perc(0.002, 0.04, 1, -4), Dust.kr(cd_errors_curve.linlin(0, 100, 0.0, 5.0)));
            }, {
                cd_skip_out = 0; cd_skip_env = 0; cd_stutter_out = 0; cd_stutter_env = 0; cd_scratch_env = 0;
            });

            write_sig =
                (loop_preserve_out * (1 - (loop_rec + loop_dub).min(1)))
              + (trem_imprinted    * loop_dub_level * loop_rec)
              + (
                  (
                    (
                      ((loop_preserve_out * (1 - is_resample)) + (loop_rd * is_resample))
                      * (1 - dub_style_r.clip(0, 1) + is_resample)
                      * loop_fade
                    )
                    + (trem_imprinted * loop_dub_level)
                  ) * loop_dub
                );

            BufWr.ar(write_sig, loop_buf_num, loop_phase);

            // Read-path: only this variant's medium effect (prc_t106).
            loop_rd_wow = mediumRead.(med, loop_rd, bbd_tone_fc, loop_wow_tape, loop_wow_cas, loop_chip_crush, speed_rate);

            loop_out  = (loop_rd_wow * fade_gain * (1 - cd_skip_env) * (1 - cd_stutter_env)
                         + cd_skip_out + cd_stutter_out)
                        * (1 - cd_scratch_env)
                        * loop_level * (loop_play + loop_dub).min(1) * sample_gate;

            // Vinyl surface noise: only the vinyl variant.
            if(med == \vinyl, {
                var vinyl_noise_amt, vinyl_noise_sig;
                vinyl_noise_amt = loop_vinyl_noise / 100.0;
                vinyl_noise_sig = [
                    HPF.ar(Dust2.ar(vinyl_noise_amt.pow(1.5) * 20.0, vinyl_noise_amt * 0.5), 2000)
                      + LPF.ar(PinkNoise.ar(vinyl_noise_amt.pow(1.3) * 0.010), 8000),
                    HPF.ar(Dust2.ar(vinyl_noise_amt.pow(1.5) * 20.0, vinyl_noise_amt * 0.5), 2000)
                      + LPF.ar(PinkNoise.ar(vinyl_noise_amt.pow(1.3) * 0.010), 8000)
                ];
                loop_out = loop_out + (vinyl_noise_sig * loop_level * (loop_play + loop_dub).min(1));
            });

            ReplaceOut.ar(looper_out_bus, loop_out);
        }).add;
        };

        SynthDef(\princeton, {

            arg out_bus = 0, pedal_bus_num = 0,
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
                limit_bypass = 1, limit_threshold = 0.31623, limit_ratio = 4.0, limit_gain = 1.0, limit_attack = 10, limit_decay = 50;

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
            var limit_ctrl, limit_out;

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
            limit_threshold      = Lag.kr(limit_threshold,      0.05);
            limit_ratio          = Lag.kr(limit_ratio,          0.05);
            limit_gain           = Lag.kr(limit_gain,           0.05);
            limit_attack         = Lag.kr(limit_attack,         0.10);
            limit_decay          = Lag.kr(limit_decay,          0.10);
            characteristic       = Lag.kr(characteristic,       0.05);
            mic                  = Lag.kr(mic,                  0.05);
            cab_mode             = Lag.kr(cab_mode,             0.05);

            // ── Input (from pedal bus, post Push + Distort inserts) ──────────
            sig = In.ar(pedal_bus_num, 2);

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

            // ── Looper (per-medium \princeton_looper_* sub-synths, prc_t100/t106) ──
            // Amp/tremolo output goes to the looper sub; read its loop_out back with
            // InFeedback (the sub runs after main, L50). loop_mix feeds reverb + cab.
            ReplaceOut.ar(looper_in_bus_num, trem_out);
            loop_mix = trem_out + InFeedback.ar(looper_out_bus_num, 2);

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
            cab = XFade2.ar(cab, sig, Lag.kr(amp_bypass.round(1) * 2 - 1, 0.008));

            out_sig   = cab * (master / 10.0).squared * 2.0;
            final_sig = out_sig.softclip * (1.0 - mute);

            // ── Limit ────────────────────────────────────────────────────────
            limit_ctrl   = (final_sig[0] + final_sig[1]) * 0.5;
            limit_out    = Compander.ar(
                final_sig, limit_ctrl, limit_threshold,
                1.0, 1.0 / limit_ratio,
                limit_attack * 0.001, limit_decay * 0.001
            ) * limit_gain;
            final_sig   = XFade2.ar(limit_out, final_sig, Lag.kr(limit_bypass.round(1) * 2 - 1, 0.008));

            Out.ar(out_bus, final_sig);

            // ── fx send buses ────────────────────────────────────────────────
            if(~sendA.notNil) { Out.ar(~sendA, final_sig) };
            if(~sendB.notNil) { Out.ar(~sendB, final_sig) };

        }).add;

        SynthDef(\metro_click, {
            arg out_bus = 0, level = 0.5, pitch = 0, length = 50, metro_bus_num = 0, position = 0;
            var freq = 440 * (2 ** (pitch / 12));
            var env  = EnvGen.ar(Env.perc(0.001, length * 0.001), doneAction: 2);
            var sig  = SinOsc.ar(freq) * env * level.clip(0, 1);
            Out.ar(out_bus,       [sig, sig] * (1 - position.round(1)));
            Out.ar(metro_bus_num, sig * position.round(1));
        }).add;

        SynthDef(\princeton_tuner, {
            arg in_bus = 0, tuner_freq_bus_num = 0, gate = 1, fade = 0.02;
            var sig, freq, has;
            EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
            sig = In.ar(in_bus, 1) * 4.0;
            sig = HPF.ar(sig, 70);
            sig = LPF.ar(sig, 2000);
            # freq, has = Pitch.kr(sig,
                minFreq: 60, maxFreq: 1500,
                ampThreshold: 0.003, median: 7);
            Out.kr(tuner_freq_bus_num, freq * has);
        }).add;

        context.server.sync;

        in_synth = Synth(\princeton_in, [
            \in_bus,        context.in_b[0].index,
            \in_bus_r,      context.in_b[1].index,
            \metro_bus_num, metro_bus.index,
            \env1_bus_num,  env1_bus.index,
            \env2_bus_num,  env2_bus.index,
            \pedal_bus_num, pedal_bus.index
        ], context.xg);

        synth = Synth.after(in_synth, \princeton, [
            \out_bus,             context.out_b.index,
            \pedal_bus_num,       pedal_bus.index,
            \looper_in_bus_num,   looper_in_bus.index,
            \looper_out_bus_num,  looper_out_bus.index
        ]);

        // Looper sub-synth (prc_t100): spawned on demand (looper_on) by Lua only when
        // the looper is in use (not IDLE), so an idle script pays nothing for it. When
        // not spawned, looper_out_bus stays at 0 (the looper always reaches IDLE from a
        // loop_play = 0 state, so its last output was 0), so main reads 0 cleanly.

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
            ["limit_bypass",         \limit_bypass],
            ["limit_threshold",      \limit_threshold],
            ["limit_ratio",          \limit_ratio],
            ["limit_gain",           \limit_gain],
            ["limit_attack",         \limit_attack],
            ["limit_decay",          \limit_decay],
            ["mute",                 \mute]
        ].do { |pair|
            this.addCommand(pair[0], "f", { |msg| synth.set(pair[1], msg[1]) });
        };

        // ── Looper param commands -> looper sub-synth (prc_t100) ─────────
        [
            ["loop_rec",             \loop_rec],
            ["loop_dub",             \loop_dub],
            ["loop_play",            \loop_play],
            ["loop_frames",          \loop_frames],
            ["loop_sample_retrig",   \loop_sample_retrig],
            ["looper_wow_tape",      \loop_wow_tape],
            ["looper_wow_cas",       \loop_wow_cas],
            ["looper_chip_crush",    \loop_chip_crush],
            ["looper_cd_errors",     \loop_cd_errors],
            ["looper_level",         \loop_level],
            ["looper_dub_level",     \loop_dub_level],
            ["looper_fade_level",    \loop_fade],
            ["looper_dub_style",     \loop_dub_style],
            ["looper_direction",     \loop_direction],
            ["looper_speed",         \loop_speed],
            ["looper_play_from",     \loop_play_from],
            ["looper_wear",          \loop_wear_amt]
        ].do { |pair|
            this.addCommand(pair[0], "f", { |msg| if(looper_synth.notNil) { looper_synth.set(pair[1], msg[1]) } });
        };

        this.addCommand("signal_input", "f", { |msg| in_synth.set(\signal_input, msg[1]) });
        this.addCommand("env1_attack",  "f", { |msg| in_synth.set(\env1_attack,  msg[1]) });
        this.addCommand("env1_release", "f", { |msg| in_synth.set(\env1_release, msg[1]) });
        this.addCommand("env2_attack",  "f", { |msg| in_synth.set(\env2_attack,  msg[1]) });
        this.addCommand("env2_release", "f", { |msg| in_synth.set(\env2_release, msg[1]) });

        this.addCommand("push_on", "", {
            if(push_synth.isNil) {
                push_synth = Synth.after(in_synth, \princeton_push, [
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
                distort_synth = Synth.after(push_synth ? in_synth, \princeton_distort, [
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

        // ── Looper on-demand (prc_t100): spawned by Lua when leaving IDLE, freed on
        // entering IDLE. Immediate free is clean because loop_out is 0 at that point.
        this.addCommand("looper_on", "", {
            if(looper_synth.isNil) {
                var medName = mediaNames.clipAt(imp_medium_v.asInteger);
                looper_synth = Synth.after(synth, ("princeton_looper_" ++ medName).asSymbol, [
                    \looper_in_bus,       looper_in_bus.index,
                    \looper_out_bus,      looper_out_bus.index,
                    \imprint_in_bus_num,  imprint_in_bus.index,
                    \imprint_out_bus_num, imprint_out_bus.index,
                    \loop_buf_num,        loop_buf.bufnum
                ]);
            };
        });
        this.addCommand("looper_off", "", {
            if(looper_synth.notNil) {
                looper_synth.free;
                looper_synth = nil;
            };
        });

        // ── Imprint on-demand (prc_t100): spawned by Lua only during record/dub ──
        this.addCommand("imprint_on", "", {
            if(imprint_synth.isNil and: { looper_synth.notNil }) {
                var medName = mediaNames.clipAt(imp_medium_v.asInteger);
                imprint_synth = Synth.after(looper_synth, ("princeton_imprint_" ++ medName).asSymbol, [
                    \in_bus,           imprint_in_bus.index,
                    \out_bus,          imprint_out_bus.index,
                    \amt,              imp_amt_v,
                    \loop_bbd_tone,    imp_bbd_tone_v,
                    \gate,             1
                ]);
            };
        });
        this.addCommand("imprint_off", "", {
            if(imprint_synth.notNil) {
                imprint_synth.set(\gate, 0);
                imprint_synth = nil;
            };
        });

        // looper_imprint sets the imprint amount. looper_bbd_tone feeds the active
        // looper variant (its bbd read-path/wear cutoff) and the imprint when live.
        // looper_medium only caches imp_medium_v: that index picks which per-medium
        // variant looper_on/imprint_on spawn (prc_t106); there is no live medium arg.
        this.addCommand("looper_imprint", "f", { |msg|
            imp_amt_v = msg[1];
            if(imprint_synth.notNil) { imprint_synth.set(\amt, msg[1]) };
        });
        this.addCommand("looper_bbd_tone", "f", { |msg|
            imp_bbd_tone_v = msg[1];
            if(looper_synth.notNil) { looper_synth.set(\loop_bbd_tone, msg[1]) };
            if(imprint_synth.notNil) { imprint_synth.set(\loop_bbd_tone, msg[1]) };
        });
        this.addCommand("looper_medium", "f", { |msg|
            imp_medium_v = msg[1];
        });

        this.addCommand("looper_vinyl_noise", "f", { |msg| if(looper_synth.notNil) { looper_synth.set(\loop_vinyl_noise, msg[1]) } });

        // ── Special commands ─────────────────────────────────────────────
        this.addCommand("metro_tick", "ffff", { |msg|
            Synth(\metro_click, [
                \out_bus,        context.out_b.index,
                \level,          msg[1],
                \pitch,          msg[2],
                \length,         msg[3],
                \metro_bus_num,  metro_bus.index,
                \position,       msg[4]
            ], context.xg);
        });

        this.addCommand("loop_clear", "", {
            loop_buf.zero;
            if(looper_synth.notNil) { looper_synth.set(\loop_rec, 0, \loop_dub, 0, \loop_play, 0) };
        });

        this.addCommand("tuner_on", "", {
            if(tuner_synth.isNil) {
                tuner_synth = Synth(\princeton_tuner, [
                    \in_bus,             context.in_b[0].index,
                    \tuner_freq_bus_num, tuner_freq_bus.index,
                    \gate,               1
                ], context.xg);
            };
        });

        this.addCommand("tuner_off", "", {
            if(tuner_synth.notNil) {
                tuner_synth.set(\gate, 0);
                tuner_synth = nil;
            };
        });

        this.addPoll("tuner_pitch", {
            tuner_freq_bus.getSynchronous;
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
        if(push_synth.notNil) { push_synth.free };
        if(distort_synth.notNil) { distort_synth.free };
        if(tuner_synth.notNil) { tuner_synth.free };
        loop_buf.free;
        tuner_freq_bus.free;
        metro_bus.free;
        env1_bus.free;
        env2_bus.free;
        pedal_bus.free;
        if(imprint_synth.notNil) { imprint_synth.free };
        if(looper_synth.notNil) { looper_synth.free };
        imprint_in_bus.free;
        imprint_out_bus.free;
        looper_in_bus.free;
        looper_out_bus.free;
    }
}
