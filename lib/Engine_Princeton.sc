// Engine_Princeton.sc
// Princeton — Engine for monome norns
// [Push] -> [Distort] -> [Warp] -> [Repeat] -> preamp -> tone stack -> power amp
// -> cabinet -> tremolo -> [looper] -> reverb -> master -> out

Engine_Princeton : CroneEngine {

    var synth;
    var loop_buf;

    alloc {

        // 60s mono buffer for looper
        loop_buf = Buffer.alloc(context.server, (48000 * 60), 1);

        context.server.sync;

        SynthDef(\princeton, {

            arg out_bus = 0, in_bus = 0,
                volume = 5, bass = 5, treble = 5, master = 5,
                reverb = 2.5, trem_speed = 0, trem_intensity = 0,
                mic = 0, characteristic = 0,
                push_gain = 0, push_tone = 5, push_level = 5, push_bypass = 1,
                distort_gain = 0, distort_tone = 5, distort_level = 5, distort_bypass = 1,
                warp_rate = 2.5, warp_depth = 2.5, warp_rise = 5, warp_bypass = 1,
                repeat_time = 5, repeat_feedback = 5, repeat_level = 5, repeat_bypass = 1,
                loop_rec = 0, loop_dub = 0, loop_play = 0,
                loop_frames = 2880000, loop_level = 0.75, dub_level = 0.75,
                loop_buf_num = 0, direction = 0, loop_speed = 1, dub_style = 0,
                mute = 0, amp_bypass = 0;

            var sig, push_sig, push_drive, distort_sig, distort_drive, repeat_sig, repeat_delay, repeat_fb, pre1, toned, pre2, power;
            var cab_center, cab_mid, cab_edge, cab;
            var trem_lfo, trem_out, trem_depth, trem_dry;
            var sp1, sp2, sp3, diff, spring_wet, wetmix;
            var input_gain, sag, sag_gain;
            var rev_decay, rev_send;
            var out_sig;
            var bass_gain, treble_gain;
            var bass_lf, bass_hf, treble_lf, treble_hf;
            var loop_reset, loop_phase, loop_rd, loop_preserve;
            var write_sig, loop_out, final_sig, loop_mix;
            var repeat_fb_lp, repeat_jitter, repeat_noise, repeat_dt;
            var warp_lfo, warp_depth_env, warp_dt, warp_sig;
            var frames, read_pos, fade_gain, fade_samps, fade_norm, speed_rate, play_phase;

            volume     = Lag.kr(volume,     0.05);
            bass       = Lag.kr(bass,       0.05);
            treble     = Lag.kr(treble,     0.05);
            master     = Lag.kr(master,     0.05);
            reverb     = Lag.kr(reverb,     0.10);
            trem_speed = Lag.kr(trem_speed, 0.12);

            sig = In.ar(in_bus, 1);

            // Push: HPF input (coupling cap ~720Hz), asymmetric diode clipping,
            // mid hump, bridged-T tone filter
            push_drive = HPF.ar(sig, 720);
            push_drive = push_drive * push_gain.linexp(0, 10, 1.0, 200.0);
            // Asymmetric: positive half harder (diode pair approximation)
            push_drive = (push_drive.max(0) * 1.3).tanh + (push_drive.min(0) * 0.7).tanh;
            push_drive = MidEQ.ar(push_drive, 720, 0.9, push_gain.linlin(0, 10, 2, 10));
            // Bridged-T tone: blend LP and peaking band
            push_drive = XFade2.ar(
                LPF.ar(push_drive, 500),
                BPF.ar(push_drive, 1000, 0.7) * 2 + push_drive,
                push_tone.linlin(0, 10, -1, 1)
            );
            push_drive = LPF.ar(push_drive, 3500);
            push_sig   = push_drive * push_level.linlin(0, 10, 0.0, 1.3);
            sig      = XFade2.ar(push_sig, sig, Lag.kr(push_bypass.round(1) * 2 - 1, 0.008));

            // Distort: LM308-style hard clipping, asymmetric rails, LP filter
            // Hard clip (not tanh) preserves transient attack and sounds heavier.
            // Asymmetric: +rail at 0.7, -rail at -0.85 (LM308 supply asymmetry).
            distort_drive = HPF.ar(sig, 100);
            // Remapped: knob 5 ≈ old 8.5. Bottom is crunchy, top very heavy.
            distort_drive = distort_drive * distort_gain.linexp(0, 10, 50.0, 1500.0);
            distort_drive = distort_drive.clip(-0.85, 0.7);
            distort_drive = LeakDC.ar(distort_drive);
            distort_drive = LPF.ar(distort_drive, (distort_tone / 10.0).pow(0.35).linexp(0.0001, 1, 150, 8000));
            distort_sig   = distort_drive * distort_level.linlin(0, 10, 0.0, 0.210);
            sig       = XFade2.ar(distort_sig, sig, Lag.kr(distort_bypass.round(1) * 2 - 1, 0.008));

            // Warp: BBD pitch vibrato, 100% wet
            // Slightly uneven LFO (LFNoise2 wobble) for analog character.
            // Rise time: Lag on depth creates slow onset when pedal engages.
            warp_depth_env = Lag.kr(warp_depth.linlin(0, 10, 0.0, 0.012) * (1 - warp_bypass.round(1)),
                              warp_rise.linlin(0, 10, 0.01, 4.0));
            warp_lfo = SinOsc.ar(
                warp_rate.linexp(0, 10, 0.3, 8.0) + LFNoise2.kr(4, 0.08),
                0, warp_depth_env, 0.007);
            warp_sig = DelayC.ar(sig, 0.02, warp_lfo.clip(0.0001, 0.02));
            sig     = XFade2.ar(warp_sig, sig, Lag.kr(warp_bypass.round(1) * 2 - 1, 0.008));

            // Repeat: BBD delay with analog artifacts
            // - LPF per repeat pass (~3.5kHz) simulates chip bandwidth loss
            // - Subtle noise injected into feedback: each repeat gets grainier
            // - Mild tanh saturation in feedback (BBD chips clip gently)
            // - Tiny pitch modulation (LFO on delay time) simulates clock jitter
            repeat_jitter = SinOsc.kr(0.3, 0, 0.0003) + LFNoise2.kr(8, 0.0002);
            repeat_dt     = Lag.kr(repeat_time.linlin(0, 10, 0.001, 0.60), 0.15) + repeat_jitter;
            repeat_fb    = LocalIn.ar(1) * repeat_feedback.linlin(0, 10, 0.0, 1.0);
            repeat_fb_lp = Select.kr(characteristic.round(1), [5000, 2500]);
            repeat_fb    = repeat_fb * Select.kr(characteristic.round(1), [1.0, 1.5]);
            repeat_fb    = LPF.ar(repeat_fb, repeat_fb_lp);
            repeat_fb    = (repeat_fb * 1.1).tanh * 0.95;
            repeat_delay = DelayL.ar(sig + repeat_fb, 0.62, repeat_dt.clip(0.001, 0.62));
            // Noise added only to LocalOut — stays in repeat path, never in repeat_delay output
            repeat_noise = WhiteNoise.ar(Amplitude.kr(repeat_fb, 0.01, 0.2) * 0.015);
            LocalOut.ar(repeat_delay + repeat_noise);
            repeat_sig    = sig + (repeat_delay * repeat_level.linlin(0, 10, 0.0, 1.0));
            sig        = XFade2.ar(repeat_sig, sig, Lag.kr(repeat_bypass.round(1) * 2 - 1, 0.008));

            // -- Preamp Stage 1 (12AX7 V1a) --
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

            // -- Power Amp (6V6 + supply sag) --
            sag      = Amplitude.ar(pre2, 0.004, 0.12);
            sag_gain = 1.0 / (1.0 + sag * 0.35);
            power    = (pre2 * sag_gain * 2.2).softclip * 0.5;

            cab_center = MidEQ.ar(power, 2500, 1.0,   4.0);
            cab_center = LPF.ar(HPF.ar(cab_center, 90),  6500);

            cab_mid    = MidEQ.ar(power, 2000, 1.11,  1.5);
            cab_mid    = LPF.ar(HPF.ar(cab_mid,   95),  5000);

            cab_edge   = MidEQ.ar(power, 1200, 1.25, -2.0);
            cab_edge   = LPF.ar(HPF.ar(cab_edge, 100), 3800);

            cab = Select.ar(mic.round(1), [cab_center, cab_mid, cab_edge]);
            cab = XFade2.ar(cab, sig, Lag.kr(amp_bypass.round(1) * 2 - 1, 0.008));  // amp bypass: dry signal skips preamp+cab

            // Tremolo: wet/dry mix, peaks always at full amplitude
            // 0:    pure dry (no tremolo)
            // 1-5:  dry fades out, wet fades in, peaks stay at 1.0
            // 5-10: pure tremolo, depth increases (trough goes lower)
            // 0..1.5: dry fades out, peaks stay at 1.0 (no depth yet)
            // 1.6..10: pure tremolo, depth increases
            trem_lfo   = SinOsc.kr(trem_speed.linlin(0, 10, 0.5, 12.0), 0, 0.5, 0.5);
            trem_dry   = Lag.kr(trem_intensity.linlin(0, 1.5, 1.0, 0.0).clip(0, 1), 0.05);
            trem_depth = Lag.kr(trem_intensity.linlin(1.6, 10, 0.0, 0.9).clip(0, 1), 0.05);
            trem_out   = cab * (trem_dry + (1.0 - trem_dry) * (trem_depth * trem_lfo + (1.0 - trem_depth)));

            // Looper: write@1x, read@speed, sine-squared fade at boundaries
            frames     = loop_frames.max(2);
            fade_samps = 512;
            speed_rate = Select.kr(loop_speed.round(1), [0.5, 1.0, 2.0]);

            loop_reset = Changed.kr(loop_rec) * loop_rec;
            loop_phase = Phasor.ar(loop_reset, 1,          0, frames, 0);
            play_phase = Phasor.ar(loop_reset,  speed_rate, 0, frames, 0);

            read_pos   = Select.ar(direction.round(1), [
                play_phase,
                frames - 1 - play_phase
            ]);

            fade_norm  = (play_phase.min(frames - play_phase) / fade_samps).clip(0, 1);
            fade_gain  = (fade_norm * 0.5 * pi).sin;
            fade_gain  = fade_gain * fade_gain;

            loop_rd    = BufRd.ar(1, loop_buf_num, read_pos,   loop: 1, interpolation: 2);

            loop_preserve = BufRd.ar(1, loop_buf_num, loop_phase, loop: 1, interpolation: 1);

            write_sig =
                (loop_preserve                                                              * (1 - (loop_rec + loop_dub).min(1)))
              + (trem_out                                                                   * loop_rec)
              + ((trem_out * dub_level + loop_rd * loop_level * (1 - dub_style.round(1))) * loop_dub);

            BufWr.ar(write_sig, loop_buf_num, loop_phase);

            loop_out  = loop_rd * fade_gain * loop_level * (loop_play + loop_dub).min(1);

            loop_mix = trem_out + loop_out;

            rev_decay = reverb.linlin(0, 10, 0.6, 3.5);
            rev_send  = (reverb / 10.0).sqrt * 0.25;

            sp1 = CombL.ar(loop_mix * rev_send, 0.1, 0.02974, rev_decay);
            sp2 = CombL.ar(loop_mix * rev_send, 0.1, 0.03511, rev_decay * 1.12);
            sp3 = CombL.ar(loop_mix * rev_send, 0.1, 0.04423, rev_decay * 0.88);

            sp1 = LPF.ar(sp1, 3500);
            sp2 = LPF.ar(sp2, 3200);
            sp3 = LPF.ar(sp3, 2900);

            diff       = AllpassN.ar(sp1 + sp2 + sp3, 0.05, [0.0137, 0.0211], 0.4);
            spring_wet = (diff[0] + diff[1]) * 0.35;

            wetmix = loop_mix + spring_wet;

            out_sig   = wetmix * (master / 10.0).squared * 2.0;
            final_sig = out_sig.softclip * (1.0 - mute);

            Out.ar(out_bus, [final_sig, final_sig]);

        }).add;

        context.server.sync;

        synth = Synth(\princeton, [
            \out_bus,      context.out_b.index,
            \in_bus,       context.in_b[0].index,
            \loop_buf_num, loop_buf.bufnum
        ], context.xg);

        this.addCommand("repeat_bypass",        "f", { |msg| synth.set(\repeat_bypass,        msg[1]) });
        this.addCommand("repeat_level",         "f", { |msg| synth.set(\repeat_level,         msg[1]) });
        this.addCommand("repeat_feedback",        "f", { |msg| synth.set(\repeat_feedback,        msg[1]) });
        this.addCommand("repeat_time",          "f", { |msg| synth.set(\repeat_time,          msg[1]) });
        this.addCommand("amp_bypass",     "f", { |msg| synth.set(\amp_bypass,     msg[1]) });
        this.addCommand("bass",           "f", { |msg| synth.set(\bass,           msg[1]) });
        this.addCommand("characteristic",  "f", { |msg| synth.set(\characteristic,  msg[1]) });
        this.addCommand("direction",       "f", { |msg| synth.set(\direction,       msg[1]) });
        this.addCommand("dub_level",      "f", { |msg| synth.set(\dub_level,      msg[1]) });
        this.addCommand("dub_style",       "f", { |msg| synth.set(\dub_style,       msg[1]) });
        this.addCommand("loop_dub",       "f", { |msg| synth.set(\loop_dub,       msg[1]) });
        this.addCommand("loop_frames",    "f", { |msg| synth.set(\loop_frames,    msg[1]) });
        this.addCommand("loop_level",     "f", { |msg| synth.set(\loop_level,     msg[1]) });
        this.addCommand("loop_play",      "f", { |msg| synth.set(\loop_play,      msg[1]) });
        this.addCommand("loop_rec",       "f", { |msg| synth.set(\loop_rec,       msg[1]) });
        this.addCommand("loop_speed",      "f", { |msg| synth.set(\loop_speed,      msg[1]) });
        this.addCommand("master",         "f", { |msg| synth.set(\master,         msg[1]) });
        this.addCommand("mic",            "f", { |msg| synth.set(\mic,            msg[1]) });
        this.addCommand("mute",             "f", { |msg| synth.set(\mute,             msg[1]) });
        this.addCommand("distort_bypass",       "f", { |msg| synth.set(\distort_bypass,       msg[1]) });
        this.addCommand("distort_gain",         "f", { |msg| synth.set(\distort_gain,         msg[1]) });
        this.addCommand("distort_tone",       "f", { |msg| synth.set(\distort_tone,       msg[1]) });
        this.addCommand("distort_level",          "f", { |msg| synth.set(\distort_level,          msg[1]) });
        this.addCommand("reverb",         "f", { |msg| synth.set(\reverb,         msg[1]) });
        this.addCommand("treble",         "f", { |msg| synth.set(\treble,         msg[1]) });
        this.addCommand("trem_intensity", "f", { |msg| synth.set(\trem_intensity, msg[1]) });
        this.addCommand("trem_speed",     "f", { |msg| synth.set(\trem_speed,     msg[1]) });
        this.addCommand("push_bypass",       "f", { |msg| synth.set(\push_bypass,       msg[1]) });
        this.addCommand("push_gain",         "f", { |msg| synth.set(\push_gain,         msg[1]) });
        this.addCommand("push_level",        "f", { |msg| synth.set(\push_level,        msg[1]) });
        this.addCommand("push_tone",         "f", { |msg| synth.set(\push_tone,         msg[1]) });
        this.addCommand("warp_bypass",       "f", { |msg| synth.set(\warp_bypass,       msg[1]) });
        this.addCommand("warp_depth",        "f", { |msg| synth.set(\warp_depth,        msg[1]) });
        this.addCommand("warp_rate",         "f", { |msg| synth.set(\warp_rate,         msg[1]) });
        this.addCommand("warp_rise",         "f", { |msg| synth.set(\warp_rise,         msg[1]) });
        this.addCommand("volume",         "f", { |msg| synth.set(\volume,         msg[1]) });
        this.addCommand("loop_clear",     "",  {
            loop_buf.zero;
            synth.set(\loop_rec, 0, \loop_dub, 0, \loop_play, 0);
        });
    }

    free {
        synth.free;
        loop_buf.free;
    }
}
