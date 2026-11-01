// rack_fx holds Tape, Build and Mesmerize, the three rack devices, standing on the post bus from
// the start. They sleep while off rather than being torn down, and switching on wakes them via run.
{ |engine, ctx|
    var server = ctx[\server], postBus = ctx[\postBus], tapeStopBus = ctx[\tapeStopBus];
    var tape_synth, bld_synth, evp_synth, tape_buf, bld_buf, bld_buf2, evp_level_bus, tape_level_bus, bld_level_bus;
    var tape_run_v = 1, bld_spill_v = 0;
    // EVP remembers its settings so that a fresh tank can inherit them
    var evp_vals = IdentityDictionary.new;

        tape_buf = Buffer.alloc(server, (48000 * 6), 2);
        bld_buf = Buffer.alloc(server, 250000, 1);
        bld_buf2 = Buffer.alloc(server, 250000, 1);
        evp_level_bus = Bus.control(server, 1);
        tape_level_bus = Bus.control(server, 4);
        bld_level_bus = Bus.control(server, 2);

        SynthDef(\princeton_tape, {

            arg bus = 0, tape_stop_bus_num = 0, level_bus = 0,
                tape_bypass = 0, tape_speed = 1, tape_drive = 5, tape_bias = 1, tape_hiss = 0.5, tape_wow = 2.5, tape_mag = 2.5,
                tape_azimuth = 2.5, tape_run = 1, tape_down = 2.5, tape_up = 1.0, tape_buf_num = 0, tape_cal = 3.5;

            var final_sig = In.ar(bus, 2);
            var t_spd, t_bias, t_bump, t_hf, t_wowk, t_hissk, t_g, t_off, t_mag, t_sf, t_gm, t_gh, t_sig, t_rate, t_steady, t_reset, t_frames, t_wpos, t_rpos, t_play, t_stop, t_idle, t_in;

            // ── Tape ─────────────────────────────────────────────────────────
            t_in    = final_sig;
            t_spd   = tape_speed.round(1).clip(0, 2);
            t_bias  = tape_bias.round(1).clip(0, 2);
            // Speed and Bias are switches on the tape machine, but the tape itself never jumps: every value
            // they choose glides to its new place over 50 ms instead of arriving with a click.
            t_bump  = Lag.kr(Select.kr(t_spd, [32, 60, 110]), 0.05);
            t_hf    = Lag.kr(Select.kr(t_spd, [8500, 14000, 20000]) * Select.kr(t_bias, [1.2, 1.0, 0.78]), 0.05);
            t_wowk  = Lag.kr(Select.kr(t_spd, [2.0, 1.0, 0.4]), 0.05) * Lag.kr(tape_wow, 0.1) * 0.1;
            t_hissk = Lag.kr(Select.kr(t_spd, [2.0, 1.0, 0.5]), 0.05) * Lag.kr(tape_hiss, 0.1).linlin(0, 10, 0, 0.004);
            t_g     = Lag.kr(tape_drive, 0.1).linexp(0, 10, 0.4, 6) * Lag.kr(Select.kr(t_bias, [1.3, 1.0, 0.8]), 0.05);
            t_mag   = Lag.kr(tape_mag, 0.1) * 0.1;
            t_off   = Lag.kr(Select.kr(t_bias, [0.08, 0.03, 0.0]), 0.05) + (0.06 * t_mag);
            t_sf    = Lag.kr(Select.kr(t_spd, [2.0, 1.0, 0.45]), 0.05);
            t_gm    = t_g * (1 + (1.5 * t_mag));
            t_gh    = t_gm * t_sf * (1 + (2 * t_mag));
            t_sig = final_sig.collect { |x, k|
                var dt, hi, env;
                x   = BHiShelf.ar(x, 3000, 1, 4);
                env = Amplitude.kr(x, 0.01, 0.2);
                hi  = HPF.ar(x, 4000);
                x   = LeakDC.ar((((x - hi) * t_gm) + t_off).tanh - t_off.tanh) / t_gm;
                x   = x + ((hi * t_gh).tanh / t_gh);
                x   = BHiShelf.ar(x, 3000, 1, -4);
                x   = BPeakEQ.ar(HPF.ar(x, t_bump * 0.45), t_bump, 1.2, Select.kr(t_spd, [3.5, 2.5, 1.0]) + (1.5 * t_mag));
                x   = BLowPass.ar(x, (t_hf / (1 + (3 * t_mag * env))).clip(1500, 20000), 0.8);
                dt = 0.006 + (LFNoise2.kr(0.7 + (k * 0.13)) * 0.0035 * t_wowk)
                    + (LFNoise1.kr(9 + k) * 0.00003 * t_wowk) + (k * Lag.kr(tape_azimuth, 0.1) * 0.00006);
                x = DelayC.ar(x, 0.015, dt);
                x + (HPF.ar(PinkNoise.ar, 800) * t_hissk)
            };
            t_sig = [t_sig[0] + (t_sig[1] * 0.02), t_sig[1] + (t_sig[0] * 0.02)] * Lag.kr(Select.kr(t_spd, [-1.35, -0.6, -0.55].dbamp), 0.05) * tape_cal.dbamp;
            final_sig = LinXFade2.ar(t_sig, final_sig, Lag.kr(tape_bypass.round(1) * 2 - 1, 0.008));

            t_rate   = LagUD.ar(Slew.ar(K2A.ar(tape_run.clip(0, 1)), 1000000, 1 / tape_down.max(0.05)), tape_up.max(0.05) * 1.66, 0);
            t_steady = A2K.kr(t_rate) > 0.998;
            t_reset  = ((HPZ1.kr(tape_run.clip(0, 1)) < 0) * (Delay1.kr(A2K.kr(t_rate)) > 0.997)) + ((HPZ1.kr(tape_run.clip(0, 1)) > 0) * (A2K.kr(t_rate) < 0.001)) + Impulse.kr(0);
            t_frames = BufFrames.kr(tape_buf_num);
            t_wpos   = Phasor.ar(0, 1, 0, t_frames);
            BufWr.ar(final_sig, tape_buf_num, t_wpos);
            t_rpos   = Phasor.ar(K2A.ar(t_reset), t_rate, 0, t_frames, (t_wpos - 8).wrap(0, t_frames));
            t_play   = LPF.ar(BufRd.ar(2, tape_buf_num, t_rpos, 1, 4), (A2K.kr(t_rate) * 18000).max(200)) * t_rate;
            final_sig = LinXFade2.ar(final_sig, t_play, LagUD.kr(1 - t_steady, 0.01, 0.08) * 2 - 1);
            t_stop   = (tape_run < 0.5) * (A2K.kr(t_rate) < 0.0001);
            t_stop   = t_stop * (Sweep.kr(t_stop) > 0.05);
            t_idle   = (tape_bypass > 0.5) * t_steady;
            t_idle   = t_idle * (Sweep.kr(t_idle) > 0.15);
            ReplaceOut.kr(tape_stop_bus_num, t_stop);
            ReplaceOut.kr(level_bus, Amplitude.kr(t_in ++ final_sig, 0.005, 0.3));
            ReplaceOut.ar(bus, final_sig);
            PauseSelf.kr(t_stop + t_idle);

        }).add;

        SynthDef(\princeton_bld, {

            arg bus = 0, level_bus = 0,
                bld_bypass = 1, bld_block = 10, bld_time = 10000, bld_ratio_a = 4, bld_ratio_b = -1, bld_fb = 50, bld_mix = 25,
                bld_octave = 10, bld_smear = 10, bld_xfeed = 5,
                bld_freeze = 0, bld_spill = 0, bld_spread = 50, bld_lowcut = 40, bld_highcut = 15000,
                bld_buf = 0, bld_buf2 = 0;

            var final_sig = In.ar(bus, 2);
            var b_ms, b_k, b_short, b_rate, b_m, b_bw, b_frames, b_frz, b_fz, b_byp, b_spill, b_wpos, b_in, b_fbk, b_xf, b_rchg, b_duck, b_ra, b_rb, b_rbs, b_line, b_proc, b_a, b_b, b_fa, b_fb2, b_wet, b_mix, b_idle;

            // ── Build ────────────────────────────────────────────────────────
            b_ms     = Lag3.kr(bld_time.clip(1, 10000), 0.25);
            b_k      = bld_block.round(1).clip(1, 10) - 1;
            b_short  = Lag.kr(b_ms < 40, 0.05);
            b_rate   = Lag.kr(Select.kr(b_k, [1, 1, 1, 1, 1, 0.8, 0.6, 0.45, 0.35, 0.25]).max(0.1), 0.05);
            b_m      = 2 ** (Select.kr(b_k, [16, 16, 16, 16, 12, 12, 11, 10, 9, 8]).max(7) - 1);
            b_bw     = (b_rate * 20000).clip(200, 20000);
            b_frames = BufFrames.kr(bld_buf);
            b_spill  = bld_spill.round(1).clip(0, 1);
            b_byp    = bld_bypass.round(1).clip(0, 1);
            b_frz    = bld_freeze.round(1).clip(0, 1) * (1 - (b_byp * (1 - b_spill)));
            b_fz     = Lag.kr(b_frz, 0.02);
            b_wpos   = Phasor.ar(0, b_rate, 0, b_frames);
            b_in     = (final_sig[0] + final_sig[1]) * 0.5 * (1 - b_fz) * (1 - Lag.kr(b_byp, 0.02));
            b_fbk    = (1 - (1 - (Lag.kr(bld_fb, 0.05) * 0.01).clip(0, 1)).squared) * 0.98;
            b_xf     = Lag.kr(bld_xfeed, 0.05) * 0.01;
            b_rchg   = (Changed.kr(bld_ratio_a) + Changed.kr(bld_ratio_b)) > 0;
            b_duck   = 1 - EnvGen.kr(Env([0, 1, 1, 0], [0.015, 0.006, 0.03], \sin), b_rchg);
            b_ra     = Latch.kr(bld_ratio_a, DelayN.kr(b_rchg, 0.02, 0.016) + Impulse.kr(0)).round(1).clip(1, 8);
            b_rbs    = Latch.kr(bld_ratio_b, DelayN.kr(b_rchg, 0.02, 0.016) + Impulse.kr(0)).round(1);
            b_rb     = b_rbs.abs.clip(1, 8);
            b_line = { |len, ms, rev, buf|
                var tap, ph, heads, out, pass, hit, rise, gu, gd, fb;
                tap   = XFade2.ar(BufRd.ar(1, buf, (b_wpos - len).wrap(0, b_frames), 1, 4), BufRd.ar(1, buf, (b_wpos - len).wrap(0, b_frames), 1, 1), b_fz * 2 - 1);
                ph    = Phasor.ar(0, b_rate, 0, len);
                heads = [ph, (ph + (len * 0.5)).wrap(0, len)].collect { |p|
                    BufRd.ar(1, buf, (b_wpos - (p * 2)).wrap(0, b_frames), 1, 4) * (pi * p / len).sin.squared
                }.sum;
                out   = LPF.ar(XFade2.ar(tap, heads, Lag.kr(rev, 0.03) * 2 - 1), b_bw) * b_duck;
                pass  = Impulse.kr((ms * 0.001).max(0.02).reciprocal);
                hit   = TRand.kr(0, 1, pass) < (bld_octave * 0.01);
                rise  = TRand.kr(0, 1, pass) < 0.5;
                gu    = Lag.kr(hit * rise, 0.02);
                gd    = Lag.kr(hit * (1 - rise), 0.02);
                fb    = (tap * (1 - gu - gd)) + (PitchShift.ar(tap, 0.08, 2, 0, 0.004) * gu) + (PitchShift.ar(tap, 0.12, 0.5, 0, 0.004) * gd);
                [tap, out, fb]
            };
            b_proc = { |sig|
                var sm = Lag.kr(bld_smear, 0.05) * 0.01, g = 1 + (sm * 4), d = sig;
                [0.0071, 0.0113, 0.0179, 0.0267].do { |t| d = AllpassN.ar(d, 0.03, t, sm * 0.4) };
                d = XFade2.ar(sig, LPF.ar(d, 9000), sm * 2 - 1);
                (d * g).tanh / g
            };
            b_a      = b_line.(b_ms * 48 * b_rate * b_ra / b_ra.max(b_rb), b_ms * b_ra / b_ra.max(b_rb), 0, bld_buf);
            b_b      = b_line.(b_ms * 48 * b_rate * b_rb / b_ra.max(b_rb), b_ms * b_rb / b_ra.max(b_rb), b_rbs < 0, bld_buf2);
            b_fa     = b_proc.(b_a[2]);
            b_fb2    = b_proc.(b_b[2]);
            b_wet    = [[b_a, b_fa, b_fb2, bld_buf, b_ms * b_ra / b_ra.max(b_rb), -1, 0], [b_b, b_fb2, b_fa, bld_buf2, b_ms * b_rb / b_ra.max(b_rb), 1, 1]].collect { |e|
                var line = e[0], own = e[1], other = e[2], buf = e[3], ms = e[4], side = e[5], lvl = e[6];
                var x, comb, out;
                x    = LPF.ar((b_in + ((((1 - b_xf) * own) + (b_xf * other)) * b_fbk)).tanh, b_bw * 0.9);
                x    = ((x.abs.max(1e-9).sqrt * b_m).round(1) / b_m).squared * x.sign;
                x    = XFade2.ar(x, line[0], b_fz * 2 - 1);
                BufWr.ar(x, buf, b_wpos);
                comb = CombC.ar(b_in * b_short, 0.05, (ms * 0.001).clip(0.0005, 0.045),
                    Select.kr(b_frz, [(ms * 0.001) * (-6.9078 / b_fbk.max(0.001).log).min(1000), 100000]));
                ReplaceOut.kr(level_bus + lvl, Select.kr(b_short > 0.5, [Amplitude.kr(x, 0.005, 0.1), Amplitude.kr(comb, 0.005, 0.1)]));
                comb = Latch.ar(comb, Impulse.ar(48000 * b_rate));
                out  = (line[1] * (1 - b_short)) + (LPF.ar(comb, b_bw) * b_short * b_duck);
                Pan2.ar(out, (side * Lag.kr(bld_spread, 0.05) * 0.01).clip(-1, 1))
            }.sum;
            b_wet    = HPF.ar(LPF.ar(b_wet, Lag.kr(bld_highcut, 0.05)), Lag.kr(bld_lowcut, 0.05));
            b_mix    = Lag.kr(bld_mix, 0.05) * 0.01;
            final_sig = (final_sig * (((b_mix * 0.5pi).cos * (1 - Lag.kr(b_byp, 0.02))) + Lag.kr(b_byp, 0.02)))
                      + (b_wet * (b_mix * 0.5pi).sin * (1 - Lag.kr(b_byp * (1 - b_spill), 0.02)));
            b_idle   = b_byp * (1 - (b_spill * ((Amplitude.kr((b_wet[0] + b_wet[1]) * 0.5, 0.01, 0.3) > 0.0001) + b_frz).min(1)));
            ReplaceOut.ar(bus, final_sig);
            PauseSelf.kr(b_idle * (Sweep.kr(b_idle) > 0.1));

        }).add;

        SynthDef(\princeton_evp, {

            arg bus = 0, level_bus = 0,
                evp_bypass = 1, evp_freeze = 0, evp_spill = 0, evp_size = 100, evp_predelay = 100, evp_decay = 75, evp_damping = 5,
                evp_tilt = 0, evp_mix = 25, evp_spread = 100, evp_saturation = 0, evp_width = 100, evp_bandwidth = 50,
                evp_diffusion = 25, evp_lowcut = 60;

            var dry = In.ar(bus, 2);
            var dSR = 29761, exMax = 24;
            var gFacT60 = { |delay, gFac| gFac.sign * (-3 * delay / log10(gFac.abs)) };
            var byp, spill, frz, decay, damping, satDrive, bandwidth, size, spread, diff1, diff2, decayDiff2;
            var si, st, modExc, mono, fb, wetL, wetR, tank, tank2, mid, side, tiltAbs, wet, wetLP, wetHP, width, tilt, mix, level, idle;

            byp       = Lag.kr(evp_bypass.round(1).clip(0, 1), 0.02);
            spill     = evp_spill.round(1).clip(0, 1);
            frz       = Lag.kr(evp_freeze.round(1).clip(0, 1) * (1 - (evp_bypass.round(1).clip(0, 1) * (1 - spill))), 0.05);
            decay     = (Lag.kr(evp_decay, 0.1) * 0.01).clip(0, 1);
            decay     = decay + ((1 - decay) * frz);
            damping   = Lag.kr(0.002 + (0.996 * (evp_damping * 0.01).clip(0, 1).squared), 0.05).clip(0.002, 0.998);
            satDrive  = 1 + (Lag.kr(evp_saturation, 0.1) * 0.09);
            bandwidth = Lag.kr(evp_bandwidth * 0.01, 0.05).clip(0, 1);
            size      = Lag.kr(evp_size * 0.01, 0.2).clip(0.1, 3);
            spread    = Lag.kr(evp_spread * 0.01, 0.2).clip(0, 2);
            diff1     = Lag.kr(evp_diffusion * 0.01, 0.2).clip(0, 0.95);
            diff2     = (diff1 * 0.833).clip(0, 0.75);
            decayDiff2 = (decay + 0.15).clip(0.25, 0.5);
            width     = Lag.kr(evp_width * 0.01, 0.05);
            tilt      = Lag.kr(evp_tilt * 0.01, 0.05).clip(-1, 1);
            mix       = Lag.kr(evp_mix * 0.01, 0.05).clip(0, 1);

            si = { |samples| (200 * (samples / 200).pow(spread) / dSR * size).clip(0.00003, 0.1) };
            st = { |samples| (2240 * (samples / 2240).pow(spread) / dSR * size).clip(0.00003, 1) };
            modExc = (exMax / dSR) * size;

            mono = (dry[0] + dry[1]) * 0.5 * 0.25 * (1 - frz) * (1 - byp);
            fb   = LocalIn.ar(1);
            wetL = Silent.ar;
            wetR = Silent.ar;

            // ── Predelay and diffusion ─────────────────────────────────────────────
            mono = DelayN.ar(mono, 0.5, Lag.kr(evp_predelay * 0.001, 0.1).clip(0, 0.5));
            mono = OnePole.ar(mono, 1 - bandwidth);
            mono = AllpassN.ar(mono, 0.1, si.(142), gFacT60.(si.(142), diff1));
            mono = AllpassN.ar(mono, 0.1, si.(107), gFacT60.(si.(107), diff1));
            mono = AllpassN.ar(mono, 0.1, si.(379), gFacT60.(si.(379), diff2));
            mono = AllpassN.ar(mono, 0.1, si.(277), gFacT60.(si.(277), diff2));

            // ── Tank ─────────────────────────────────────────────────────────
            tank = AllpassC.ar(mono + (decay * fb), 1, st.(672) + (modExc * SinOsc.ar(0.25, 0, 0.1)), gFacT60.(st.(672), -0.7));
            wetL = (0.6 * DelayN.ar(tank, 1, st.(1990)).neg) + wetL;
            wetR = (0.6 * tank) + wetR;
            wetR = (0.6 * DelayN.ar(tank, 1, st.(3627))) + wetR;
            tank = DelayN.ar(tank, 1, st.(4453));
            tank = OnePole.ar(tank, damping) * decay;
            wetL = (0.6 * tank).neg + wetL;
            tank = AllpassN.ar(tank, 1, st.(1800), gFacT60.(st.(1800), decayDiff2));
            wetR = (0.6 * tank).neg + wetR;
            tank = DelayN.ar(tank, 1, st.(3720));
            wetR = (0.6 * tank) + wetR;

            tank2 = AllpassC.ar((tank * decay) + mono, 1, st.(908) + (modExc * SinOsc.ar(0.2, pi, 0.1)), gFacT60.(st.(908), -0.7));
            wetL = (0.6 * tank2) + wetL;
            wetL = (0.6 * DelayN.ar(tank2, 1, st.(2974))) + wetL;
            wetR = (0.6 * DelayN.ar(tank2, 1, st.(2111))).neg + wetR;
            tank2 = DelayN.ar(tank2, 1, st.(4217));
            tank2 = OnePole.ar(tank2, damping) * decay;
            tank2 = AllpassN.ar(tank2, 1, st.(2656), gFacT60.(st.(2656), decayDiff2));
            wetL = (0.6 * tank2).neg + wetL;
            wetR = (0.6 * DelayN.ar(tank2, 1, st.(335))).neg + wetR;
            tank2 = DelayN.ar(tank2, 1, st.(3163));
            wetL = (0.6 * tank2) + wetL;

            LocalOut.ar((tank2 * decay * satDrive).tanh);

            // ── Output ────────────────────────────────────────────────────────────
            mid  = (wetL + wetR) * 0.5;
            side = (wetL - wetR) * 0.5;
            wet  = [mid + (side * width), mid - (side * width)];
            tiltAbs = tilt.abs;
            wetLP = OnePole.ar(wet, (-2pi * (1000 / SampleRate.ir)).exp);
            wetHP = wet - wetLP;
            wet = Select.ar(tilt > 0, [
                (wet * (1 - tiltAbs)) + (wetLP * tiltAbs * 2),
                (wet * (1 - tiltAbs)) + (wetHP * tiltAbs * 2)
            ]);
            wet = Limiter.ar(HPF.ar(wet, Lag.kr(evp_lowcut, 0.05).clip(20, 1000)) * 9.dbamp, 1.0, 0.01);

            level = Amplitude.kr((wet[0] + wet[1]) * 0.5, 0.01, 0.3);
            Out.kr(level_bus, level);
            ReplaceOut.ar(bus, (dry * (((mix * 0.5pi).cos * (1 - byp)) + byp)) + (wet * (mix * 0.5pi).sin * (1 - Lag.kr(evp_bypass.round(1).clip(0, 1) * (1 - spill), 0.02))));
            idle = (evp_bypass > 0.5) * (((level < 0.0001) * (frz < 0.01)) + (1 - spill)).min(1);
            PauseSelf.kr(idle * (Sweep.kr(idle) > 0.5));

        }).add;

        // ── Param commands ──────────────────────────────────────────────────────
        [
            ["bld_block",            \bld_block],
            ["bld_time",             \bld_time],
            ["bld_ratio_a",          \bld_ratio_a],
            ["bld_ratio_b",          \bld_ratio_b],
            ["bld_fb",               \bld_fb],
            ["bld_mix",              \bld_mix],
            ["bld_octave",           \bld_octave],
            ["bld_smear",            \bld_smear],
            ["bld_xfeed",            \bld_xfeed],
            ["bld_freeze",           \bld_freeze],
            ["bld_spread",           \bld_spread],
            ["bld_lowcut",           \bld_lowcut],
            ["bld_highcut",          \bld_highcut],
            ["evp_freeze",           \evp_freeze],
            ["evp_spill",            \evp_spill],
            ["evp_size",             \evp_size],
            ["evp_predelay",         \evp_predelay],
            ["evp_decay",            \evp_decay],
            ["evp_damping",          \evp_damping],
            ["evp_tilt",             \evp_tilt],
            ["evp_mix",              \evp_mix],
            ["evp_spread",           \evp_spread],
            ["evp_saturation",       \evp_saturation],
            ["evp_width",            \evp_width],
            ["evp_bandwidth",        \evp_bandwidth],
            ["evp_diffusion",        \evp_diffusion],
            ["evp_lowcut",           \evp_lowcut],
            ["tape_speed",           \tape_speed],
            ["tape_drive",           \tape_drive],
            ["tape_bias",            \tape_bias],
            ["tape_hiss",            \tape_hiss],
            ["tape_wow",             \tape_wow],
            ["tape_mag",             \tape_mag],
            ["tape_azimuth",         \tape_azimuth],
            ["tape_down",            \tape_down],
            ["tape_up",              \tape_up]
        ].do { |pair|
            var target = case
                { pair[0].beginsWith("tape_") } { { tape_synth } }
                { pair[0].beginsWith("bld_") } { { bld_synth } }
                { { evp_synth } };
            engine.addCommand(pair[0], "f", { |msg|
                if(pair[0].beginsWith("evp_")) { evp_vals[pair[1]] = msg[1] };
                target.value.set(pair[1], msg[1]);
            });
        };

        engine.addCommand("tape_bypass", "f", { |msg|
            tape_synth.set(\tape_bypass, msg[1]);
            if((msg[1] < 0.5) and: { tape_run_v > 0.5 }) { tape_synth.run(true) };
        });
        engine.addCommand("tape_run", "f", { |msg|
            tape_run_v = msg[1];
            tape_synth.set(\tape_run, msg[1]);
            tape_synth.run(true);
        });
        // Without Spill, EVP falls asleep mid-reverb with its tank frozen, so re-enabling replaces
        // it with a fresh synth. The level bus is zeroed too, or the meter rings would hold its
        // last value while asleep.
        engine.addCommand("evp_bypass", "f", { |msg|
            var spill = evp_vals[\evp_spill] ? 0;
            evp_vals[\evp_bypass] = msg[1];
            if((msg[1] < 0.5) and: { spill < 0.5 }) {
                evp_synth = Synth.replace(evp_synth, \princeton_evp,
                    evp_vals.asKeyValuePairs ++ [\bus, postBus.index, \level_bus, evp_level_bus.index]);
            } {
                evp_synth.set(\evp_bypass, msg[1]);
                if(msg[1] < 0.5) { evp_synth.run(true) };
            };
            if(msg[1] > 0.5) {
                SystemClock.sched(0.7, {
                    if((evp_vals[\evp_bypass] ? 0) > 0.5) { evp_level_bus.set(0) };
                    nil
                });
            };
        });
        engine.addPoll(\evp_level, { evp_level_bus.getSynchronous });
        [\bld_level_a, \bld_level_b].do { |name, k| engine.addPoll(name, { bld_level_bus.getnSynchronous(2)[k] }) };
        [\tape_in_l, \tape_in_r, \tape_out_l, \tape_out_r].do { |name, k| engine.addPoll(name, { tape_level_bus.getnSynchronous(4)[k] }) };

        engine.addCommand("bld_spill", "f", { |msg| bld_spill_v = msg[1]; bld_synth.set(\bld_spill, msg[1]) });
        engine.addCommand("bld_bypass", "f", { |msg|
            if((msg[1] < 0.5) and: { bld_spill_v < 0.5 }) { bld_buf.zero; bld_buf2.zero };
            bld_synth.set(\bld_bypass, msg[1]);
            if(msg[1] < 0.5) { bld_synth.run(true) };
        });

        (
            start: { |after|
                tape_synth = Synth.after(after, \princeton_tape, [
                    \bus,                 postBus.index,
                    \tape_stop_bus_num,   tapeStopBus.index,
                    \tape_buf_num,        tape_buf.bufnum,
                    \level_bus,           tape_level_bus.index
                ]);
                bld_synth = Synth.after(tape_synth, \princeton_bld, [
                    \bus,                 postBus.index,
                    \bld_buf,             bld_buf.bufnum,
                    \bld_buf2,            bld_buf2.bufnum,
                    \level_bus,           bld_level_bus.index
                ]);
                evp_synth = Synth.after(bld_synth, \princeton_evp, [
                    \bus,                 postBus.index,
                    \level_bus,           evp_level_bus.index
                ]);
                evp_synth
            },
            free: {
                [evp_synth, bld_synth, tape_synth].do { |n| if(n.notNil) { n.free } };
                [tape_buf, bld_buf, bld_buf2, evp_level_bus, tape_level_bus, bld_level_bus].do(_.free);
            }
        )
}
