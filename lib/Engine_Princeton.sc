Engine_Princeton : CroneEngine {

    var synth;
    var loop_buf;

    alloc {

        loop_buf = Buffer.alloc(context.server, (48000 * 40), 2);

        context.server.sync;

        SynthDef(\princeton, {

            arg out_bus = 0, in_bus = 0,
                volume = 7.5, bass = 5, treble = 5, master = 5,
                reverb = 2.5, trem_speed = 0, trem_intensity = 0,
                mic = 1, characteristic = 0,
                push_gain = 5, push_tone = 5, push_level = 5, push_bypass = 1, push_mix = 2.5,
                distort_gain = 5, distort_tone = 7.5, distort_level = 5, distort_bypass = 1, distort_lowcut = 0,
                warp_rate = 2.5, warp_depth = 2.5, warp_rise = 5, warp_bypass = 1, warp_mix = 0,
                repeat_time = 7.5, repeat_feedback = 5, repeat_level = 5, repeat_bypass = 1,
                loop_rec = 0, loop_dub = 0, loop_play = 0,
                loop_frames = 2880000, loop_level = 0.75, dub_level = 0.75,
                loop_buf_num = 0, direction = 0, loop_speed = 1, dub_style = 0,
                loop_degrade_amount = 0, loop_degrade_type = 2,
                loop_play_from = 0,
                mute = 0, amp_bypass = 0,
                reverb_mute = 0, speaker_bypass = 0;

            var sig, push_sig, push_drive, distort_sig, distort_drive, repeat_delay, repeat_fb, pre1, toned, pre2, power;
            var cab_center, cab_mid, cab_edge, cab;
            var trem_lfo, trem_out, trem_depth, trem_dry;
            var sp1, sp2, sp3, diff, spring_wet, wetmix;
            var spring_in, preDel, twang;
            var input_gain, sag, sag_gain;
            var rev_decay, rev_send;
            var out_sig;
            var bass_gain, treble_gain;
            var bass_lf, bass_hf, treble_lf, treble_hf;
            var loop_reset, loop_phase, loop_rd, loop_preserve;
            var bbd_sig, bbd_drv;
            var dig_step, dig_sig, drop_rate, drop_env;
            var wow_lfo, flt_lfo, tape_fc, tape_sig, sat_drv;
            var cas_wow, cas_wonk, cas_sig, cas_fc, cas_rq, cas_crinkle;
            var loop_preserve_deg, loop_preserve_out, deg_mix, type_r;
            var write_sig, loop_out, final_sig, loop_mix;
            var repeat_fb_lp, repeat_jitter, repeat_noise, repeat_dt;
            var warp_lfo, warp_sig, warp_depth_env;
            var frames, read_pos, fade_gain, fade_samps, fade_norm, speed_rate, play_phase, start_trig;
            var sig_mono;
            var repeat_gate;

            volume         = Lag.kr(volume,         0.05);
            bass           = Lag.kr(bass,           0.05);
            treble         = Lag.kr(treble,         0.05);
            master         = Lag.kr(master,         0.05);
            reverb         = Lag.kr(reverb,         0.10);
            trem_speed     = Lag.kr(trem_speed,     0.12);
            trem_intensity = Lag.kr(trem_intensity, 0.05);
            push_gain      = Lag.kr(push_gain,      0.05);
            push_tone      = Lag.kr(push_tone,      0.05);
            push_level     = Lag.kr(push_level,     0.05);
            push_mix       = Lag.kr(push_mix,       0.05);
            distort_gain     = Lag.kr(distort_gain,     0.05);
            distort_tone     = Lag.kr(distort_tone,     0.05);
            distort_level    = Lag.kr(distort_level,    0.05);
            warp_rate      = Lag.kr(warp_rate,      0.05);
            warp_rise      = Lag.kr(warp_rise,      0.05);
            warp_mix       = Lag.kr(warp_mix,       0.05);
            repeat_feedback = Lag.kr(repeat_feedback, 0.05);
            repeat_level   = Lag.kr(repeat_level,   0.05);
            loop_level           = Lag.kr(loop_level,           0.05);
            dub_level            = Lag.kr(dub_level,            0.05);
            loop_degrade_amount  = Lag.kr(loop_degrade_amount,  0.05);
            reverb_mute    = Lag.kr(reverb_mute,    0.05);
            mute           = Lag.kr(mute,           0.02);

            // ── Input ────────────────────────────────────────────────────────
            sig = In.ar(in_bus, 1);
            sig = LeakDC.ar(sig);
            sig = HPF.ar(sig, 40);
            sig = LPF.ar(sig, 7500);

            // ── Push ─────────────────────────────────────────────────────────
            push_drive = HPF.ar(sig, 100);
            push_drive = LPF.ar(push_drive, 2200);           // was 3000 — narrower input band reduces intermod
            push_drive = push_drive * push_gain.linexp(0, 10, 1.0, 100.0);
            push_drive = LPF.ar(push_drive, 2400);           // was 5000 — tight pre-clip filter, now useful
            push_drive = (push_drive.max(0) * 1.02).tanh + (push_drive.min(0) * 0.96).tanh;  // was 1.08/0.75 — near-symmetric, fewer even harmonics
            push_drive = LeakDC.ar(push_drive);
            push_drive = HPF.ar(push_drive, push_tone.linexp(0, 10, 100, 750));
            push_drive = LPF.ar(push_drive, 3200);           // was 3800 — tighter post-clip filter
            push_sig   = push_drive * push_level.linlin(0, 10, 0.0, 1.3);
            sig      = XFade2.ar(push_sig, sig, Lag.kr(Select.kr(push_bypass.round(1), [push_mix.linlin(0, 10, -1, 1), 1]), 0.008));

            // ── Distort ──────────────────────────────────────────────────────
            distort_drive = HPF.ar(sig, 150);
            distort_drive = LPF.ar(distort_drive, 4500);
            distort_drive = distort_drive * distort_gain.linexp(0, 10, 10.0, 500.0);
            distort_drive = LPF.ar(distort_drive, 7000);
            distort_drive = distort_drive.clip2(1.0);
            distort_drive = LeakDC.ar(distort_drive);
            distort_drive = LPF.ar(distort_drive, distort_tone.linexp(0, 10, 300, 5000));
            distort_drive = HPF.ar(distort_drive, Select.kr(distort_lowcut.round(1), [20, 100, 250]));
            distort_sig   = distort_drive * distort_level.linlin(0, 10, 0.0, 0.170);
            sig       = XFade2.ar(distort_sig, sig, Lag.kr(distort_bypass.round(1) * 2 - 1, 0.008));

            // ── Warp ─────────────────────────────────────────────────────────
            // Lag on warp_depth (not bypass) creates slow onset when pedal engages
            warp_depth_env = Lag.kr(warp_depth.linlin(0, 10, 0.0, 0.012) * (1 - warp_bypass.round(1)),
                              warp_rise.linlin(0, 10, 0.01, 4.0));
            // Mono warp
            warp_lfo = SinOsc.ar(warp_rate.linexp(0, 10, 0.3, 8.0) + LFNoise2.kr(4, 0.08), 0, warp_depth_env, 0.007);
            warp_sig = DelayC.ar(sig, 0.02, warp_lfo.clip(0.0001, 0.02));
            sig = XFade2.ar(warp_sig, sig, LagUD.kr(Select.kr(warp_bypass.round(1), [warp_mix.linlin(0, 10, -1, 1), 1]), warp_rise.linlin(0, 10, 0.01, 4.0), 0.008));

            // ── Repeat ───────────────────────────────────────────────────────
            // Repeat bypass: gate the INPUT only — tail rings out and can self-feedback
            repeat_gate   = Lag.kr(1 - repeat_bypass.round(1), 0.008);
            sig_mono      = sig;
            repeat_jitter = SinOsc.kr(0.3, 0, 0.0003) + LFNoise2.kr(8, 0.0002);
            repeat_dt     = Lag.kr(repeat_time.linlin(0, 10, 0.001, 0.60), 0.15) + repeat_jitter;
            repeat_fb    = LocalIn.ar(1) * repeat_feedback.linlin(0, 10, 0.0, 1.0);
            repeat_fb_lp = Select.kr(characteristic.round(1), [5000, 2500]);
            repeat_fb    = repeat_fb * Select.kr(characteristic.round(1), [1.063, 1.063]);
            repeat_fb    = LPF.ar(repeat_fb, repeat_fb_lp);
            repeat_fb    = (repeat_fb * 1.1).tanh * 0.95;
            // New material enters delay only when active; feedback always circulates
            repeat_delay = DelayL.ar(sig_mono * repeat_gate + repeat_fb, 0.62, repeat_dt.clip(0.001, 0.62));
            // noise goes to LocalOut only — not present in repeat_delay output
            repeat_noise = WhiteNoise.ar(Amplitude.kr(repeat_fb, 0.01, 0.2) * 0.015);
            LocalOut.ar(repeat_delay + repeat_noise);
            // Wet always added — dry sig preserved mono; tail decays naturally after bypass
            sig = sig + (repeat_delay * repeat_level.linlin(0, 10, 0.0, 1.0));

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

            sag      = Amplitude.ar(pre2, 0.004, 0.12);
            sag_gain = 1.0 / (1.0 + sag * 0.35);
            power    = (pre2 * sag_gain * 2.2).softclip * 0.5;

            // ── Tremolo ───────────────────────────────────────────────────────
            trem_lfo   = SinOsc.kr(trem_speed.linlin(0, 10, 0.5, 12.0), 0, 0.5, 0.5);
            trem_dry   = Lag.kr(trem_intensity.linlin(0, 1.5, 1.0, 0.0).clip(0, 1), 0.05);
            trem_depth = Lag.kr(trem_intensity.linlin(1.6, 10, 0.0, 0.9).clip(0, 1), 0.05);
            // Stereo tremolo: mono power expanded to [L, R]; R uses inverted LFO (alternating pulses)
            trem_out = [
                power * (trem_dry + (1.0 - trem_dry) * (trem_depth * trem_lfo         + (1.0 - trem_depth))),
                power * (trem_dry + (1.0 - trem_dry) * (trem_depth * (1.0 - trem_lfo) + (1.0 - trem_depth)))
            ];

            // ── Looper ───────────────────────────────────────────────────────
            frames     = loop_frames.max(2);
            fade_samps = 512;
            speed_rate = Select.kr(loop_speed.round(1), [0.5, 1.0, 2.0]);

            loop_reset = Changed.kr(loop_rec)  * loop_rec;
            start_trig = Changed.kr(loop_play) * loop_play * (1 - loop_play_from.round(1));
            loop_phase = Phasor.ar(loop_reset + start_trig, 1,          0, frames, 0);
            play_phase = Phasor.ar(loop_reset + start_trig, speed_rate, 0, frames, 0);

            read_pos   = Select.ar(direction.round(1), [
                play_phase,
                frames - 1 - play_phase
            ]);

            fade_norm  = (play_phase.min(frames - play_phase) / fade_samps).clip(0, 1);
            fade_gain  = (fade_norm * 0.5 * pi).sin;
            fade_gain  = fade_gain * fade_gain;

            loop_rd    = BufRd.ar(2, loop_buf_num, read_pos,   loop: 1, interpolation: 2);

            loop_preserve = BufRd.ar(2, loop_buf_num, loop_phase, loop: 1, interpolation: 1);

            // BBD: LPF (linear, more aggressive), tanh saturation, delayed noise
            bbd_sig = LPF.ar(loop_preserve, loop_degrade_amount.linlin(0, 10, 14000, 800));
            bbd_drv = 1.0 + loop_degrade_amount.linlin(0, 10, 0.0, 2.5);
            bbd_sig = (bbd_sig * bbd_drv).tanh * (1.0 / bbd_drv);
            bbd_sig = bbd_sig + WhiteNoise.ar((loop_degrade_amount - 5).max(0).linlin(0, 5, 0.0, 0.012));

            // Digital: quantisation + dropouts
            dig_step  = loop_degrade_amount.linexp(0, 10, 0.001, 0.12);
            dig_sig   = (loop_preserve / dig_step).round(1.0) * dig_step;
            drop_rate = loop_degrade_amount.linlin(0, 10, 0.0, 3.0);
            drop_env  = EnvGen.kr(Env.perc(0.002, 0.04, 1, -4), Dust.kr(drop_rate));
            dig_sig   = dig_sig * (1.0 - drop_env);

            // Tape: linexp LPF (audible from ~amount 3), gentle saturation, stronger wow/flutter
            wow_lfo  = SinOsc.kr(0.4 + LFNoise2.kr(0.15, 0.2), 0,
                         loop_degrade_amount.linlin(0, 10, 0.0, 5000));
            flt_lfo  = SinOsc.kr(7.0 + LFNoise2.kr(1.0, 2.0), 0,
                         loop_degrade_amount.linlin(0, 10, 0.0, 1200));
            tape_fc  = (loop_degrade_amount.linexp(0, 10, 12000, 800) + wow_lfo + flt_lfo).clip(100, 18000);
            tape_sig = LPF.ar(loop_preserve, tape_fc);
            sat_drv  = loop_degrade_amount.linlin(0, 10, 1.0, 3.5);
            tape_sig = (tape_sig * sat_drv).tanh * (1.0 / sat_drv);

            // Cassette: LFO-modulated BPF centre (no delay — avoids comb filter decay), crinkle
            cas_wow  = SinOsc.kr(0.4 + LFNoise2.kr(0.25, 0.3), 0,
                         loop_degrade_amount.linlin(0, 10, 0.0, 500));
            cas_wonk = LFNoise2.kr(loop_degrade_amount.linlin(0, 10, 0.5, 10),
                         loop_degrade_amount.linlin(0, 10, 0.0, 350));
            cas_fc   = (loop_degrade_amount.linlin(0, 10, 2800, 1400) + cas_wow + cas_wonk).clip(200, 8000);
            cas_rq   = loop_degrade_amount.linlin(0, 10, 3.0, 0.5);
            cas_sig  = BPF.ar(loop_preserve, cas_fc, cas_rq);
            cas_crinkle = (LFNoise0.kr(loop_degrade_amount.linlin(0, 10, 0.5, 15)) * loop_degrade_amount.linlin(0, 10, 0.0, 0.4) + 1.0).clip(0.2, 1.5);
            cas_sig  = cas_sig * cas_crinkle;

            // Select degraded type per channel, then crossfade with dry
            type_r            = loop_degrade_type.round(1);
            loop_preserve_deg = [
                Select.ar(type_r, [bbd_sig[0], cas_sig[0], dig_sig[0], tape_sig[0]]),
                Select.ar(type_r, [bbd_sig[1], cas_sig[1], dig_sig[1], tape_sig[1]])
            ];
            deg_mix           = loop_degrade_amount.linlin(0, 10, 0.0, 1.0);
            loop_preserve_out = (loop_preserve * (1.0 - deg_mix)) + (loop_preserve_deg * deg_mix);

            // Stereo looper: write and read both channels
            write_sig =
                (loop_preserve_out                                                               * (1 - (loop_rec + loop_dub).min(1)))
              + (trem_out                                                                          * loop_rec)
              + ((trem_out * dub_level + loop_rd * loop_level * (1 - dub_style.round(1)))        * loop_dub);

            BufWr.ar(write_sig, loop_buf_num, loop_phase);

            loop_out  = loop_rd * fade_gain * loop_level * (loop_play + loop_dub).min(1);

            loop_mix = trem_out + loop_out;

            // ── Spring reverb ─────────────────────────────────────────────────
            rev_decay = reverb.linlin(0, 10, 0.8, 3.5);
            rev_send  = (reverb * 0.85 / 10.0).sqrt * 0.25 * (1 - reverb_mute);

            // Reverb takes mono input (mix of stereo loop_mix), outputs stereo via allpass diffuser
            spring_in = (loop_mix[0] + loop_mix[1]) * 0.5 * rev_send;
            preDel    = DelayN.ar(spring_in, 0.02, 0.008);

            twang = BPF.ar(preDel, 1350 + LFNoise1.kr(0.5, 100), 3.0);
            twang = twang * rev_decay.linlin(0.8, 3.5, 0.05, 0.22);

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
            // Stereo reverb: two allpass taps produce independent L/R decorrelation
            spring_wet = diff * 0.35;

            wetmix = loop_mix + spring_wet;

            // ── Cabinet ───────────────────────────────────────────────────────
            cab_center = MidEQ.ar(wetmix,     120, 1.4,   3.5);  // Jensen C10R bass resonance
            cab_center = MidEQ.ar(cab_center, 3200, 1.0,  4.0);  // center-mic presence
            cab_center = LPF.ar(HPF.ar(cab_center, 90),  6500);

            cab_mid    = MidEQ.ar(wetmix,  120, 1.4,   3.5);
            cab_mid    = MidEQ.ar(cab_mid, 2000, 1.11,  1.5);
            cab_mid    = LPF.ar(HPF.ar(cab_mid,  95),  5000);

            cab_edge   = MidEQ.ar(wetmix,    120, 1.4,   3.5);
            cab_edge   = MidEQ.ar(cab_edge, 1200, 1.25, -2.0);
            cab_edge   = LPF.ar(HPF.ar(cab_edge, 100), 3800);

            cab = [
                Select.ar(mic.round(1), [cab_center[0], cab_mid[0], cab_edge[0]]),
                Select.ar(mic.round(1), [cab_center[1], cab_mid[1], cab_edge[1]])
            ];
            cab = XFade2.ar(cab, wetmix,    Lag.kr(speaker_bypass.round(1) * 2 - 1, 0.008));  // cab off, full mix
            cab = XFade2.ar(cab, [sig, sig], Lag.kr(amp_bypass.round(1)   * 2 - 1, 0.008));  // full dry bypass

            out_sig   = cab * (master / 10.0).squared * 2.0;
            final_sig = out_sig.softclip * (1.0 - mute);

            Out.ar(out_bus, final_sig);

            // ── fx send buses ────────────────────────────────────────────────
            if(~sendA.notNil) { Out.ar(~sendA, final_sig) };
            if(~sendB.notNil) { Out.ar(~sendB, final_sig) };

        }).add;

        SynthDef(\metro_click, {
            arg out_bus = 0, level = 0.5, pitch = 0;
            var freq = 440 * (2 ** (pitch / 12));
            var env  = EnvGen.ar(Env.perc(0.001, 0.06), doneAction: 2);
            var sig  = SinOsc.ar(freq) * env * level.clip(0, 1);
            Out.ar(out_bus, [sig, sig]);
        }).add;

        context.server.sync;

        synth = Synth(\princeton, [
            \out_bus,      context.out_b.index,
            \in_bus,       context.in_b[0].index,
            \loop_buf_num, loop_buf.bufnum
        ], context.xg);

        this.addCommand("repeat_bypass",    "f", { |msg| synth.set(\repeat_bypass,    msg[1]) });
        this.addCommand("repeat_level",     "f", { |msg| synth.set(\repeat_level,     msg[1]) });
        this.addCommand("repeat_feedback",  "f", { |msg| synth.set(\repeat_feedback,  msg[1]) });
        this.addCommand("repeat_time",      "f", { |msg| synth.set(\repeat_time,      msg[1]) });
        this.addCommand("amp_bypass",       "f", { |msg| synth.set(\amp_bypass,       msg[1]) });
        this.addCommand("amp_bass",              "f", { |msg| synth.set(\bass,             msg[1]) });
        this.addCommand("repeat_characteristic", "f", { |msg| synth.set(\characteristic,   msg[1]) });
        this.addCommand("looper_direction",      "f", { |msg| synth.set(\direction,        msg[1]) });
        this.addCommand("looper_dub_level",      "f", { |msg| synth.set(\dub_level,        msg[1]) });
        this.addCommand("looper_dub_style",      "f", { |msg| synth.set(\dub_style,        msg[1]) });
        this.addCommand("loop_dub",              "f", { |msg| synth.set(\loop_dub,         msg[1]) });
        this.addCommand("loop_frames",           "f", { |msg| synth.set(\loop_frames,      msg[1]) });
        this.addCommand("looper_level",          "f", { |msg| synth.set(\loop_level,       msg[1]) });
        this.addCommand("loop_play",             "f", { |msg| synth.set(\loop_play,        msg[1]) });
        this.addCommand("loop_rec",              "f", { |msg| synth.set(\loop_rec,         msg[1]) });
        this.addCommand("looper_speed",           "f", { |msg| synth.set(\loop_speed,       msg[1]) });
        this.addCommand("looper_play_from",       "f", { |msg| synth.set(\loop_play_from,   msg[1]) });
        this.addCommand("looper_character",      "f", { |msg| synth.set(\loop_degrade_amount, msg[1]) });
        this.addCommand("looper_topology",       "f", { |msg| synth.set(\loop_degrade_type,   msg[1]) });
        this.addCommand("amp_master",            "f", { |msg| synth.set(\master,           msg[1]) });
        this.addCommand("mic_position",          "f", { |msg| synth.set(\mic,              msg[1]) });
        this.addCommand("mute",                  "f", { |msg| synth.set(\mute,             msg[1]) });
        this.addCommand("distort_bypass",        "f", { |msg| synth.set(\distort_bypass,  msg[1]) });
        this.addCommand("distort_gain",          "f", { |msg| synth.set(\distort_gain,    msg[1]) });
        this.addCommand("distort_level",         "f", { |msg| synth.set(\distort_level,   msg[1]) });
        this.addCommand("distort_lowcut",        "f", { |msg| synth.set(\distort_lowcut,  msg[1]) });
        this.addCommand("distort_tone",          "f", { |msg| synth.set(\distort_tone,    msg[1]) });
        this.addCommand("reverb_amount",         "f", { |msg| synth.set(\reverb,           msg[1]) });
        this.addCommand("amp_treble",            "f", { |msg| synth.set(\treble,           msg[1]) });
        this.addCommand("tremolo_intensity",     "f", { |msg| synth.set(\trem_intensity,   msg[1]) });
        this.addCommand("tremolo_speed",         "f", { |msg| synth.set(\trem_speed,       msg[1]) });
        this.addCommand("push_bypass",           "f", { |msg| synth.set(\push_bypass,      msg[1]) });
        this.addCommand("push_gain",             "f", { |msg| synth.set(\push_gain,        msg[1]) });
        this.addCommand("push_level",            "f", { |msg| synth.set(\push_level,       msg[1]) });
        this.addCommand("push_mix",              "f", { |msg| synth.set(\push_mix,         msg[1]) });
        this.addCommand("push_tone",             "f", { |msg| synth.set(\push_tone,        msg[1]) });
        this.addCommand("warp_bypass",           "f", { |msg| synth.set(\warp_bypass,      msg[1]) });
        this.addCommand("warp_depth",            "f", { |msg| synth.set(\warp_depth,       msg[1]) });
        this.addCommand("warp_mix",              "f", { |msg| synth.set(\warp_mix,         msg[1]) });
        this.addCommand("warp_rate",             "f", { |msg| synth.set(\warp_rate,        msg[1]) });
        this.addCommand("warp_rise",             "f", { |msg| synth.set(\warp_rise,        msg[1]) });
        this.addCommand("reverb_mute",           "f", { |msg| synth.set(\reverb_mute,      msg[1]) });
        this.addCommand("speaker_bypass",        "f", { |msg| synth.set(\speaker_bypass,   msg[1]) });
        this.addCommand("amp_volume",            "f", { |msg| synth.set(\volume,           msg[1]) });
        this.addCommand("metro_tick",       "ff", { |msg|
            Synth(\metro_click, [
                \out_bus, context.out_b.index,
                \level,   msg[1],
                \pitch,   msg[2]
            ], context.xg);
        });
        this.addCommand("loop_clear",       "",  {
            loop_buf.zero;
            synth.set(\loop_rec, 0, \loop_dub, 0, \loop_play, 0);
        });
    }

    free {
        synth.free;
        loop_buf.free;
    }
}
