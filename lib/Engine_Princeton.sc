Engine_Princeton : CroneEngine {

    var synth;
    var loop_buf;
    var ir_buf_l, ir_buf_r;
    var ir_trig_l_val, ir_trig_r_val;
    var tuner_freq_bus;

    alloc {

        loop_buf = Buffer.alloc(context.server, (48000 * 40), 2);
        ir_buf_l = Buffer.alloc(context.server, 2048, 1);
        ir_buf_r = Buffer.alloc(context.server, 2048, 1);
        tuner_freq_bus = Bus.control(context.server, 1);
        ir_trig_l_val = 0;
        ir_trig_r_val = 0;

        context.server.sync;

        ir_buf_l.set(0, 1.0);  // dirac delta: transparent until real IR loaded
        ir_buf_r.set(0, 1.0);

        context.server.sync;

        SynthDef(\princeton, {

            arg out_bus = 0, in_bus = 0,
                volume = 5.0, bass = 5, treble = 5, master = 7.5,
                reverb = 25, reverb_length = 2.5, reverb_low_shelf = 0, reverb_high_shelf = 0,
                trem_speed = 2.5, trem_intensity = 0,
                mic = 1, characteristic = 0,
                push_gain = 5, push_tone = 5, push_level = 5, push_bypass = 1, push_mix = 25,
                distort_gain = 5, distort_tone = 7.5, distort_level = 5, distort_bypass = 1, distort_lowcut = 0,
                warp_rate = 2.5, warp_depth = 5, warp_rise = 2.5, warp_bypass = 1, warp_mix = 0,
                repeat_time = 250, repeat_feedback = 50, repeat_level = 50, repeat_bypass = 1,
                loop_rec = 0, loop_dub = 0, loop_play = 0,
                loop_frames = 1920000, loop_level = 0.75, dub_level = 0.75, loop_fade = 0.75,
                loop_buf_num = 0, direction = 0, loop_speed = 1, dub_style = 0,
                loop_wear_amt = 5, loop_imprint_amt = 50, loop_medium_type = 2,
                loop_play_from = 0, loop_sample_retrig = 0,
                mute = 0, amp_bypass = 0,
                reverb_mute = 0, cab_mode = 1,
                ir_buf_l_num = 0, ir_buf_r_num = 0, ir_trig_l = 0, ir_trig_r = 0,
                loop_wow_tape = 5, loop_wow_cas = 5,
                loop_bbd_tone = 0, loop_dig_glitch = 0,
                cab_level = 1.0,
                ir_level_l = 0.31623, ir_level_r = 0.31623,
                limit_bypass = 1, limit_threshold = 0.31623, limit_ratio = 4.0, limit_gain = 1.0, limit_attack = 10, limit_decay = 50,
                tuner_freq_bus_num = 0;

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
            var dig_glitch_env;
            var dig_skip_rate, dig_skip_out;
            var apply_topology, trem_imprinted, loop_preserve_out;
            var is_digital, medium_lag;
            var bbd_bias_lfo, tape_bias_lfo, cas_bias_lfo, tape_flt_lfo, cas_fm_carrier_lfo;
            var dig_noise_src, dig_jitter_src;
            var write_sig, loop_out, final_sig, loop_mix, dub_style_r, is_resample;
            var repeat_fb_lp, repeat_jitter, repeat_noise, repeat_dt;
            var warp_lfo, warp_sig, warp_depth_env;
            var frames, read_pos, fade_gain, fade_samps, fade_norm, speed_rate, play_phase, start_trig;
            var direction_r, pend_phase, pend_read, wrap_trig, pend_wrap_trig, oneshot_trig, rand_dir, rand_read;
            var retrig_kr, in_sample_mode, oneshot_done, sample_gate;
            var sig_mono;
            var repeat_gate;
            var cab_dsp, cab_mode_r, ir_l, ir_r;
            var loop_rd_wow, rd_wow_depth_tape, rd_wow_depth_cas;
            var delay_time_tape_l, delay_time_tape_r, delay_time_cas_l, delay_time_cas_r;
            var wow_tape_l, wow_tape_r, wow_cas_l, wow_cas_r;
            var wow_tape_hz, wow_cas_hz, wow_tape_jit_hz, wow_cas_jit_hz, wow_tape_jit_amt, wow_cas_jit_amt;
            var limit_ctrl, limit_out;
            var tuner_in, tuner_pitch_freq, tuner_pitch_has;

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
            loop_fade            = Lag.kr(loop_fade,            0.05);
            loop_wear_amt        = Lag.kr(loop_wear_amt,        0.05);
            loop_imprint_amt     = Lag.kr(loop_imprint_amt,     0.05);
            reverb_mute    = Lag.kr(reverb_mute,    0.05);
            mute           = Lag.kr(mute,           0.02);
            loop_wow_tape   = Lag.kr(loop_wow_tape,   0.05);
            loop_wow_cas    = Lag.kr(loop_wow_cas,    0.05);
            loop_dig_glitch = Lag.kr(loop_dig_glitch, 0.05);
            cab_level           = Lag.kr(cab_level,           0.05);
            ir_level_l          = Lag.kr(ir_level_l,          0.05);
            ir_level_r          = Lag.kr(ir_level_r,          0.05);
            limit_threshold      = Lag.kr(limit_threshold,      0.05);
            limit_ratio          = Lag.kr(limit_ratio,          0.05);
            limit_gain           = Lag.kr(limit_gain,           0.05);
            limit_attack         = Lag.kr(limit_attack,         0.10);
            limit_decay          = Lag.kr(limit_decay,          0.10);

            // ── Input ────────────────────────────────────────────────────────
            sig = In.ar(in_bus, 1);
            sig = LeakDC.ar(sig);
            sig = HPF.ar(sig, 40);
            sig = LPF.ar(sig, 7500);

            // ── Tuner pitch detection ────────────────────────────────────────
            tuner_in = sig * 4.0;
            tuner_in = HPF.ar(tuner_in, 70);
            tuner_in = LPF.ar(tuner_in, 2000);
            # tuner_pitch_freq, tuner_pitch_has = Pitch.kr(tuner_in,
                minFreq: 60, maxFreq: 1500,
                ampThreshold: 0.003, median: 7);
            Out.kr(tuner_freq_bus_num, tuner_pitch_freq * tuner_pitch_has);

            // ── Push ─────────────────────────────────────────────────────────
            push_drive = HPF.ar(sig, 100);
            push_drive = LPF.ar(push_drive, 2200);
            push_drive = push_drive * push_gain.linexp(0, 10, 1.0, 100.0);
            push_drive = LPF.ar(push_drive, 2400);
            push_drive = (push_drive.max(0) * 1.02).tanh + (push_drive.min(0) * 0.96).tanh;
            push_drive = LeakDC.ar(push_drive);
            push_drive = HPF.ar(push_drive, push_tone.linexp(0, 10, 100, 750));
            push_drive = LPF.ar(push_drive, 3200);
            push_sig   = push_drive * push_level.linlin(0, 10, 0.0, 1.3);
            sig      = XFade2.ar(push_sig, sig, Lag.kr(Select.kr(push_bypass.round(1), [push_mix.linlin(0, 100, -1, 1), 1]), 0.008));

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
            warp_depth_env = Lag.kr(warp_depth.linlin(0, 100, 0.0, 0.012) * (1 - warp_bypass.round(1)),
                              warp_rise);
            // Mono warp
            warp_lfo = SinOsc.ar(warp_rate + LFNoise2.kr(4, 0.08), 0, warp_depth_env, 0.007);
            warp_sig = DelayC.ar(sig, 0.02, warp_lfo.clip(0.0001, 0.02));
            sig = XFade2.ar(warp_sig, sig, LagUD.kr(Select.kr(warp_bypass.round(1), [warp_mix.linlin(0, 100, -1, 1), 1]), warp_rise, 0.008));

            // ── Repeat ───────────────────────────────────────────────────────
            // Repeat bypass: gate the INPUT only — tail rings out and can self-feedback
            repeat_gate   = Lag.kr(1 - repeat_bypass.round(1), 0.008);
            sig_mono      = sig;
            repeat_jitter = SinOsc.kr(0.3, 0, 0.0003) + LFNoise2.kr(8, 0.0002);
            repeat_dt     = Lag.kr(repeat_time * 0.001, 0.15) + repeat_jitter;
            repeat_fb    = LocalIn.ar(1) * (repeat_feedback / 100.0);
            repeat_fb_lp = Select.kr(characteristic.round(1), [5000, 2500]);
            repeat_fb    = repeat_fb * Select.kr(characteristic.round(1), [1.063, 1.063]);
            repeat_fb    = LPF.ar(repeat_fb, repeat_fb_lp);
            repeat_fb    = (repeat_fb * 1.1).tanh * 0.95;
            // New material enters delay only when active; feedback always circulates
            repeat_delay = DelayL.ar(sig_mono * repeat_gate + repeat_fb, 1.001, repeat_dt.clip(0.001, 1.0));
            // noise goes to LocalOut only — not present in repeat_delay output
            repeat_noise = WhiteNoise.ar(Amplitude.kr(repeat_fb, 0.01, 0.2) * 0.015);
            LocalOut.ar(repeat_delay + repeat_noise);
            // Wet always added — dry sig preserved mono; tail decays naturally after bypass
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

            sag      = Amplitude.ar(pre2, 0.004, 0.12);
            sag_gain = 1.0 / (1.0 + sag * 0.35);
            power    = (pre2 * sag_gain * 2.2).softclip * 0.5;

            // ── Tremolo ───────────────────────────────────────────────────────
            trem_lfo   = SinOsc.kr(trem_speed, 0, 0.5, 0.5);
            trem_dry   = Lag.kr(trem_intensity.linlin(0, 15, 1.0, 0.0).clip(0, 1), 0.05);
            trem_depth = Lag.kr(trem_intensity.linlin(16, 100, 0.0, 0.9).clip(0, 1), 0.05);
            trem_out = [
                power * (trem_dry + (1.0 - trem_dry) * (trem_depth * trem_lfo                              + (1.0 - trem_depth))),
                power * (trem_dry + (1.0 - trem_dry) * (trem_depth * SinOsc.kr(trem_speed, pi * 0.5, 0.5, 0.5) + (1.0 - trem_depth)))
            ];

            // ── Looper ───────────────────────────────────────────────────────
            frames     = loop_frames.max(2);
            fade_samps = 512;
            speed_rate = loop_speed.clip(0.5, 2.0);

            dub_style_r = dub_style.round(1);
            is_resample = dub_style_r > 2.5;

            loop_reset = Changed.kr(loop_rec)  * loop_rec;
            retrig_kr  = Changed.kr(loop_sample_retrig);
            start_trig = Changed.kr(loop_play) * loop_play * (1 - loop_play_from.round(1))
                       + retrig_kr             *             (1 - loop_play_from.round(1));
            loop_phase = Phasor.ar(loop_reset + start_trig, Select.kr(loop_rec.round(1), [Select.kr(is_resample * loop_dub.round(1), [speed_rate, 1]), speed_rate]), 0, frames, 0);
            play_phase = Phasor.ar(loop_reset + start_trig, speed_rate, 0, frames, 0);

            direction_r = direction.round(1);

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

            medium_lag = Lag.kr(loop_medium_type, 0.05);
            is_digital = (1 - (medium_lag - 2).abs).max(0).min(1);
            wow_tape_hz      = 1.1;
            wow_cas_hz       = 0.7;
            wow_tape_jit_hz  = 0.2;
            wow_cas_jit_hz   = 0.3;
            wow_tape_jit_amt = 0.20;
            wow_cas_jit_amt  = 0.25;
            wow_tape_l = SinOsc.kr(wow_tape_hz + LFNoise2.kr(wow_tape_jit_hz, wow_tape_jit_amt), 0,         1.0);
            wow_tape_r = SinOsc.kr(wow_tape_hz + LFNoise2.kr(wow_tape_jit_hz, wow_tape_jit_amt), pi * 0.5,  1.0);
            wow_cas_l  = SinOsc.kr(wow_cas_hz  + LFNoise2.kr(wow_cas_jit_hz,  wow_cas_jit_amt),  0,         1.0);
            wow_cas_r  = SinOsc.kr(wow_cas_hz  + LFNoise2.kr(wow_cas_jit_hz,  wow_cas_jit_amt),  pi * 0.75, 1.0);

            // Shared LFOs (amt-independent; reused across wear + imprint paths)
            bbd_bias_lfo       = LFNoise2.kr(0.1);
            tape_bias_lfo      = LFNoise2.kr(0.12);
            cas_bias_lfo       = LFNoise2.kr(0.15);
            tape_flt_lfo       = SinOsc.kr(7.0 + LFNoise2.kr(1.0, 2.0), 0, 1.0);
            cas_fm_carrier_lfo = LFNoise2.kr(0.1).exprange(120, 400);
            dig_noise_src      = LFNoise0.ar(48000);
            dig_jitter_src     = LFNoise2.ar(200);

            // ── Topology DSP ─────────────────────────────────────────────────
            apply_topology = { |input, amt|
                var amt_fc_bbd, amt_fc_tape, amt_fc_cas, amt_deg_mix;
                var bbd_sig, bbd_drv, bbd_bias;
                var dig_step, dig_sig, dig_drop_rate, dig_drop_env_local, dig_jitter;
                var tape_wow, tape_flt, tape_fc, tape_sig, tape_drv, tape_bias, tape_comp_fc, tape_print;
                var cas_wow, cas_wonk, cas_sig, cas_fc, cas_rq, cas_drv, cas_crinkle, cas_fm_idx, cas_fm_out, cas_bias, cas_comp_fc;
                var wonk_osc;
                var deg_sel;

                amt_fc_bbd  = Select.kr(loop_bbd_tone.round(1), [
                                  amt.linexp(0, 100, 5000, 300),
                                  amt.linexp(0, 100, 2500, 150)
                              ]);
                amt_fc_tape = amt.linlin(0, 100, 16000, 400);
                amt_fc_cas  = amt.linlin(0, 100, 3200, 800);
                amt_deg_mix = amt / 100.0;
                wonk_osc    = LFNoise2.kr(amt.linlin(0, 100, 0.5, 10), 1.0);

                bbd_sig   = HPF.ar(input, 80);
                bbd_sig   = LPF.ar(bbd_sig, amt_fc_bbd);
                bbd_bias  = bbd_bias_lfo * amt.linlin(0, 100, 0.0, 0.04);
                bbd_drv   = 1.1 + amt.linlin(0, 100, 0.0, 3.9);
                bbd_sig   = ((bbd_sig + bbd_bias) * bbd_drv).tanh * (0.95 / bbd_drv);
                bbd_sig   = LeakDC.ar(bbd_sig);
                bbd_sig   = bbd_sig + WhiteNoise.ar(Amplitude.kr(bbd_sig, 0.01, 0.2) * amt.linlin(0, 100, 0.0, 0.03));

                dig_step      = (amt - 67).max(0).linlin(0, 33, 0.00001, 0.04);
                dig_sig       = (input / dig_step).round(1.0) * dig_step;
                dig_sig       = dig_sig + (dig_noise_src * dig_step * amt.linlin(0, 100, 0.0, 0.08));
                dig_jitter    = dig_jitter_src * amt.linlin(0, 100, 0.0, 0.00008);
                dig_sig       = DelayC.ar(dig_sig, 0.001, (0.0005 + dig_jitter.abs).clip(0.0001, 0.001));
                dig_drop_rate = (amt - 68).max(0).linlin(0, 32, 0.0, 8.0);
                dig_drop_env_local = EnvGen.kr(Env.perc(0.002, 0.04, 1, -4), Dust.kr(dig_drop_rate * is_digital));
                dig_sig       = dig_sig * (1.0 - dig_drop_env_local);

                tape_wow      = [wow_tape_l, wow_tape_r] * loop_wow_tape.linlin(0, 100, 0.0, 3000);
                tape_flt      = tape_flt_lfo * loop_wow_tape.linlin(0, 100, 0.0, 1500);
                tape_fc       = (amt_fc_tape + tape_wow + tape_flt).clip(100, 18000);
                tape_sig      = LPF.ar(input, tape_fc);
                tape_print    = DelayN.ar(input, 0.025, 0.019) * amt.linlin(0, 100, 0.0, 0.04);
                tape_drv      = amt.linlin(0, 100, 1.0, 5.0);
                tape_bias     = tape_bias_lfo * amt.linlin(0, 100, 0.0, 0.06);
                tape_sig      = ((tape_sig + tape_bias) * tape_drv).tanh * (1.0 / tape_drv);
                tape_sig      = LeakDC.ar(tape_sig);
                tape_comp_fc  = (Amplitude.kr(tape_sig, 0.005, 0.15) * amt.linlin(0, 100, 0.0, -5000) + 5500).clip(2500, 5500);
                tape_sig      = LPF.ar(tape_sig, tape_comp_fc);
                tape_sig      = tape_sig + tape_print;

                cas_wow  = [wow_cas_l, wow_cas_r] * loop_wow_cas.linlin(0, 100, 0.0, 300);
                cas_wonk = wonk_osc * loop_wow_cas.linlin(0, 100, 0.0, 450);
                cas_fc   = (amt_fc_cas + cas_wow + cas_wonk).clip(200, 8000);
                cas_rq   = amt.linlin(0, 100, 3.0, 1.0);
                cas_sig  = BPF.ar(input, cas_fc, cas_rq);
                cas_drv        = amt.linlin(0, 100, 1.0, 4.5);
                cas_bias       = cas_bias_lfo * amt.linlin(0, 100, 0.0, 0.07);
                cas_sig        = ((cas_sig + cas_bias) * cas_drv).tanh / cas_drv.sqrt;
                cas_sig        = LeakDC.ar(cas_sig);
                cas_comp_fc    = (Amplitude.kr(cas_sig, 0.005, 0.15) * amt.linlin(0, 100, 0.0, -6000) + 5000).clip(2000, 5000);
                cas_sig        = LPF.ar(cas_sig, cas_comp_fc);
                cas_crinkle    = (LFNoise0.kr(amt.linlin(0, 100, 0.5, 15)) * (amt - 68).max(0).linlin(0, 32, 0.0, 0.5) + 1.0).clip(0.2, 1.5);
                cas_sig        = cas_sig * cas_crinkle;
                cas_fm_idx     = amt.linlin(0, 100, 0.0, 0.012);
                cas_fm_out     = SinOsc.ar(cas_fm_carrier_lfo + (cas_sig * cas_fm_carrier_lfo * cas_fm_idx));
                cas_sig        = cas_sig + (cas_fm_out * cas_fm_idx * 0.2);

                deg_sel = [
                    SelectX.ar(medium_lag, [bbd_sig[0], cas_sig[0], dig_sig[0], tape_sig[0]]),
                    SelectX.ar(medium_lag, [bbd_sig[1], cas_sig[1], dig_sig[1], tape_sig[1]])
                ];
                (input * (1.0 - amt_deg_mix)) + (deg_sel * amt_deg_mix)
            };

            loop_preserve_out = apply_topology.(loop_preserve, loop_wear_amt);
            trem_imprinted    = apply_topology.(trem_out,      loop_imprint_amt);

            // ── Read-path glitches ───────────────────────────────────────────
            dig_glitch_env  = { EnvGen.kr(Env.perc(0.002, 0.04, 1, -4), Dust.kr(loop_dig_glitch.linlin(0, 100, 0.0, 8.0) * is_digital)) }.dup(2);
            dig_skip_rate   = loop_dig_glitch.linlin(0, 100, 0.0, 3.0) * is_digital;
            dig_skip_out    = { |ch|
                var trig, pos, phase, rd, env;
                trig  = Dust.kr(dig_skip_rate);
                pos   = TRand.kr(0.0, frames - 1.0, trig);
                phase = Phasor.ar(K2A.ar(trig), speed_rate, 0, frames, pos);
                rd    = BufRd.ar(2, loop_buf_num, phase, loop: 1, interpolation: 2);
                env   = EnvGen.kr(Env.perc(0.001, 0.15, 1, -4), trig);
                rd[ch] * env
            }.dup(2);

            // Stereo looper: write and read both channels
            write_sig =
                (loop_preserve_out * (1 - (loop_rec + loop_dub).min(1)))
              + (trem_imprinted    * loop_rec)
              + (
                  (
                    (
                      ((loop_preserve_out * (1 - is_resample)) + (loop_rd * is_resample))
                      * (1 - dub_style_r.clip(0, 1) + is_resample)
                      * loop_fade
                    )
                    + (trem_imprinted * dub_level)
                  ) * loop_dub
                );

            BufWr.ar(write_sig, loop_buf_num, loop_phase);

            // ── Read-path wow ────────────────────────────────────────────────
            rd_wow_depth_tape = loop_wow_tape.linlin(0, 100, 0.0, 0.025) / speed_rate.max(1.0);
            rd_wow_depth_cas  = loop_wow_cas.linlin(0, 100, 0.0, 0.018) / speed_rate.max(1.0);
            delay_time_tape_l = (rd_wow_depth_tape * 0.5 + wow_tape_l * rd_wow_depth_tape * 0.5).clip(0.0001, 0.030);
            delay_time_tape_r = (rd_wow_depth_tape * 0.5 + wow_tape_r * rd_wow_depth_tape * 0.5).clip(0.0001, 0.030);
            delay_time_cas_l  = (rd_wow_depth_cas  * 0.5 + wow_cas_l  * rd_wow_depth_cas  * 0.5).clip(0.0001, 0.025);
            delay_time_cas_r  = (rd_wow_depth_cas  * 0.5 + wow_cas_r  * rd_wow_depth_cas  * 0.5).clip(0.0001, 0.025);
            loop_rd_wow = [
                SelectX.ar(medium_lag, [loop_rd[0], DelayC.ar(loop_rd[0], 0.030, delay_time_cas_l),  loop_rd[0], DelayC.ar(loop_rd[0], 0.030, delay_time_tape_l)]),
                SelectX.ar(medium_lag, [loop_rd[1], DelayC.ar(loop_rd[1], 0.030, delay_time_cas_r),  loop_rd[1], DelayC.ar(loop_rd[1], 0.030, delay_time_tape_r)])
            ];

            loop_out  = (loop_rd_wow * fade_gain * (1.0 - dig_glitch_env) + dig_skip_out)
                        * loop_level * (loop_play + loop_dub).min(1) * sample_gate;

            loop_mix = trem_out + loop_out;

            // ── Spring reverb ─────────────────────────────────────────────────
            rev_decay = reverb_length;
            rev_send  = (reverb * 0.85 / 100.0).sqrt * 0.25 * (1 - reverb_mute);

            // Reverb takes mono input (mix of stereo loop_mix), outputs stereo via allpass diffuser
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
            // Stereo reverb: two allpass taps produce independent L/R decorrelation
            spring_wet = diff * 0.35;
            spring_wet = BLowShelf.ar(spring_wet, 250,  1.0, reverb_low_shelf);
            spring_wet = BHiShelf.ar(spring_wet,  3500, 1.0, reverb_high_shelf);

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

            cab_dsp = [
                Select.ar(mic.round(1), [cab_center[0], cab_mid[0], cab_edge[0]]) * cab_level,
                Select.ar(mic.round(1), [cab_center[1], cab_mid[1], cab_edge[1]]) * cab_level
            ];
            ir_l = Convolution2.ar(wetmix[0], ir_buf_l_num, K2A.ar(Changed.kr(ir_trig_l)), 2048) * ir_level_l;
            ir_r = Convolution2.ar(wetmix[1], ir_buf_r_num, K2A.ar(Changed.kr(ir_trig_r)), 2048) * ir_level_r;
            cab_mode_r = cab_mode.round(1);
            cab = [
                Select.ar(cab_mode_r, [wetmix[0], cab_dsp[0], ir_l]),
                Select.ar(cab_mode_r, [wetmix[1], cab_dsp[1], ir_r])
            ];
            cab = XFade2.ar(cab, [sig, sig], Lag.kr(amp_bypass.round(1) * 2 - 1, 0.008));  // full dry bypass

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
            arg out_bus = 0, level = 0.5, pitch = 0;
            var freq = 440 * (2 ** (pitch / 12));
            var env  = EnvGen.ar(Env.perc(0.001, 0.06), doneAction: 2);
            var sig  = SinOsc.ar(freq) * env * level.clip(0, 1);
            Out.ar(out_bus, [sig, sig]);
        }).add;

        context.server.sync;

        synth = Synth(\princeton, [
            \out_bus,            context.out_b.index,
            \in_bus,             context.in_b[0].index,
            \loop_buf_num,       loop_buf.bufnum,
            \ir_buf_l_num,       ir_buf_l.bufnum,
            \ir_buf_r_num,       ir_buf_r.bufnum,
            \tuner_freq_bus_num, tuner_freq_bus.index
        ], context.xg);

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
            ["distort_bypass",       \distort_bypass],
            ["distort_gain",         \distort_gain],
            ["distort_level",        \distort_level],
            ["distort_lowcut",       \distort_lowcut],
            ["distort_tone",         \distort_tone],
            ["push_bypass",          \push_bypass],
            ["push_gain",            \push_gain],
            ["push_level",           \push_level],
            ["push_mix",             \push_mix],
            ["push_tone",            \push_tone],
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
            ["loop_rec",             \loop_rec],
            ["loop_dub",             \loop_dub],
            ["loop_play",            \loop_play],
            ["loop_frames",          \loop_frames],
            ["loop_sample_retrig",   \loop_sample_retrig],
            ["looper_wow_tape",      \loop_wow_tape],
            ["looper_wow_cas",       \loop_wow_cas],
            ["looper_bbd_tone",      \loop_bbd_tone],
            ["looper_dig_glitch",    \loop_dig_glitch],
            ["looper_level",         \loop_level],
            ["looper_dub_level",     \dub_level],
            ["looper_fade_level",    \loop_fade],
            ["looper_dub_style",     \dub_style],
            ["looper_direction",     \direction],
            ["looper_speed",         \loop_speed],
            ["looper_play_from",     \loop_play_from],
            ["looper_imprint",       \loop_imprint_amt],
            ["looper_wear",          \loop_wear_amt],
            ["looper_medium",        \loop_medium_type],
            ["cab_mode",             \cab_mode],
            ["cab_level",            \cab_level],
            ["mic_position",         \mic],
            ["ir_level_l",           \ir_level_l],
            ["ir_level_r",           \ir_level_r],
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

        // ── Special commands ─────────────────────────────────────────────
        this.addCommand("metro_tick", "ff", { |msg|
            Synth(\metro_click, [
                \out_bus, context.out_b.index,
                \level,   msg[1],
                \pitch,   msg[2]
            ], context.xg);
        });

        this.addCommand("load_ir_l", "s", { |msg|
            fork {
                var old = ir_buf_l;
                ir_buf_l = Buffer.readChannel(context.server, msg[1], 0, 2048, [0]);
                context.server.sync;
                synth.set(\ir_buf_l_num, ir_buf_l.bufnum);
                0.1.wait;
                ir_trig_l_val = 1 - ir_trig_l_val;
                synth.set(\ir_trig_l, ir_trig_l_val);
                old.free;
            };
        });

        this.addCommand("load_ir_r", "s", { |msg|
            fork {
                var old = ir_buf_r;
                ir_buf_r = Buffer.readChannel(context.server, msg[1], 0, 2048, [0]);
                context.server.sync;
                synth.set(\ir_buf_r_num, ir_buf_r.bufnum);
                0.1.wait;
                ir_trig_r_val = 1 - ir_trig_r_val;
                synth.set(\ir_trig_r, ir_trig_r_val);
                old.free;
            };
        });

        this.addCommand("loop_clear", "", {
            loop_buf.zero;
            synth.set(\loop_rec, 0, \loop_dub, 0, \loop_play, 0);
        });

        this.addPoll("tuner_pitch", {
            tuner_freq_bus.getSynchronous;
        });
    }

    free {
        synth.free;
        loop_buf.free;
        ir_buf_l.free;
        ir_buf_r.free;
        tuner_freq_bus.free;
    }
}
