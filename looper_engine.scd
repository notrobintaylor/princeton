// looper_engine: looper + imprint SynthDefs (per medium), shared by princeton and media.
// Loaded at runtime and applied via .value(engine, ctx). ctx provides:
//   ctx[\mediaNames]   -- medium symbol list ([\bbd, \cas, \cd, \chip, \tape, \vinyl])
//   ctx[\mediumBlend]  -- medium-DSP blend closure
//   ctx[\mediumRead]   -- medium-DSP read closure
{ |engine, ctx|
    var mediaNames  = ctx[\mediaNames];
    var mediumBlend = ctx[\mediumBlend];
    var mediumRead  = ctx[\mediumRead];
    var server = ctx[\server], mainSynth = ctx[\mainSynth];
    var looperInBus = ctx[\looperInBus], looperOutBus = ctx[\looperOutBus], loopBuf = ctx[\loopBuf];
    var imprint_in_bus, imprint_out_bus, looper_synth, imprint_synth;
    var imp_amt_v = 50, imp_bbd_tone_v = 0, imp_medium_v = 3;

    imprint_in_bus  = Bus.audio(server, 2);
    imprint_out_bus = Bus.audio(server, 2);

        // ── Imprint sub-synths ───────────────────────────────────────
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

        // ── Looper sub-synths ────────────────────────────────────────
        mediaNames.do { |med|
        SynthDef(("princeton_looper_" ++ med).asSymbol, {
            arg looper_in_bus = 0, looper_out_bus = 0,
                imprint_in_bus_num = 0, imprint_out_bus_num = 0, loop_buf_num = 0,
                loop_rec = 0, loop_dub = 0, loop_play = 0,
                loop_frames = 2880000, loop_level = 0.75, loop_dub_level = 0.75, loop_fade = 0.75,
                loop_direction = 0, loop_speed = 1, loop_dub_style = 0,
                loop_wear_amt = 5,
                loop_play_from = 0, loop_sample_retrig = 0,
                loop_wow_tape = 5, loop_wow_cas = 5,
                loop_bbd_tone = 0, loop_chip_crush = 0, loop_cd_errors = 0, loop_vinyl_noise = 10;
            var input, trem_imprinted, loop_preserve_out;
            var frames, rec_span, rec_phase, rec_end, fade_samps, speed_rate, dub_style_r, is_resample;
            var loop_reset, retrig_kr, start_trig, write_rate, fill_gate, loop_phase, play_phase;
            var direction_r, pend_phase, pend_read, wrap_trig, pend_wrap_trig, oneshot_trig, in_sample_mode, oneshot_done, sample_gate, out_gate, rand_dir, rand_read;
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

            rec_span   = loop_frames.max(2);
            speed_rate = loop_speed.clip(0.5, 2.0);

            dub_style_r = loop_dub_style.round(1);
            is_resample = dub_style_r > 2.5;

            loop_reset = Changed.kr(loop_rec)  * loop_rec;
            write_rate = Select.kr(loop_rec.round(1), [Select.kr(is_resample * loop_dub.round(1), [speed_rate, 1]), speed_rate]);

            // Loop length comes from the recorder's own write head, not from a wall-clock
            // estimate in Lua. Lua cannot know when the engine actually began writing (OSC
            // plus block latency), so its figure ran a few milliseconds long: the loop point
            // then sat PAST the end of the recorded material, and every pass crossed a raw
            // splice into stale buffer content shortly before the seam - outside the fade,
            // which is centred on the seam itself. Hence a click once per pass, on any
            // medium and worst on short loops, where it recurs most often.
            // A dedicated phasor does the measuring: it runs from the start of recording at
            // the write rate and wraps at the capacity Lua asked for, so latching it when
            // recording ends yields exactly the span that was written, speed included.
            // Bounded by the buffer, NOT by rec_span. rec_span is Lua's estimate and Lua
            // sends loop_frames BEFORE loop_rec(0) when committing: if that estimate landed
            // even one sample below the real write position, this phasor would wrap on the
            // spot and the latch a block later would freeze a loop of a few hundred samples,
            // i.e. an almost silent loop. Whether that happened came down to the difference
            // between two OSC latencies, so it was a coin toss. A fixed bound removes the
            // dependency entirely.
            rec_phase  = Phasor.ar(loop_reset, write_rate, 0, BufFrames.kr(loop_buf_num), 0);
            rec_end    = Latch.kr(A2K.kr(rec_phase), Changed.kr(loop_rec) * (1 - loop_rec));
            // While recording, and before anything has been recorded, fall back to Lua's value.
            frames     = Select.kr((loop_rec.round(1) + (rec_end < 2)).min(1),
                                   [rec_end, rec_span]).max(2);
            // The seam crossfade has to fit inside the loop. At a fixed 512 samples any loop
            // shorter than 1024 never reaches full gain anywhere, because the fade-in from one
            // end still overlaps the fade-out into the other, and a really short one is held
            // down near silence over its whole length. A quarter of the loop keeps the fade
            // proportional, so a short loop plays at level and only its seam is smoothed.
            fade_samps = (frames * 0.25).min(512).max(1);
            retrig_kr  = Changed.kr(loop_sample_retrig);
            start_trig = Changed.kr(loop_play) * loop_play * (1 - loop_play_from.round(1))
                       + retrig_kr             *             (1 - loop_play_from.round(1));
            loop_phase = Phasor.ar(loop_reset + start_trig, write_rate, 0, frames, 0);
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
            // Output gate, smoothed. loop_play, loop_dub and sample_gate are hard 0/1 steps:
            // ungated they cut the output mid-waveform on start, stop and at the end of a
            // one-shot, which is a splice with no fade and clicks accordingly. loop_level is
            // already lagged, these were not. Kept separate from wrap_trig above, which must
            // stay hard because it is a trigger.
            out_gate = Lag.ar(K2A.ar((loop_play + loop_dub).min(1)) * sample_gate, 0.004);
            rand_dir  = TRand.ar(0.0, 1.0, wrap_trig).round(1);
            rand_read = Select.ar(rand_dir, [play_phase, frames - 1 - play_phase]);

            read_pos   = Select.ar(direction_r, [
                play_phase,
                frames - 1 - play_phase,
                pend_read,
                rand_read
            ]);

            fade_norm  = (play_phase.min(frames - play_phase) / fade_samps).clip(0, 1);
            // Pendulum gets no fade. The other directions cross a real splice at the seam -
            // the read position jumps from one end of the buffer to the other - and the fade
            // is what hides it. Pendulum folds instead of jumping: it turns around at the
            // ends, so the read position stays continuous and there is nothing to hide.
            // Fading anyway just punched a hole in the level at both turning points, twice
            // per cycle, right where the pendulum lingers longest.
            fade_norm  = Select.ar(direction_r, [
                fade_norm,
                fade_norm,
                DC.ar(1),
                fade_norm
            ]);
            fade_gain  = (fade_norm * 0.5 * pi).sin;
            fade_gain  = fade_gain * fade_gain;

            loop_rd    = BufRd.ar(2, loop_buf_num, read_pos,   loop: 1, interpolation: 2);

            loop_preserve = BufRd.ar(2, loop_buf_num, loop_phase, loop: 1, interpolation: 1);

            bbd_tone_fc = SelectX.kr(loop_bbd_tone, [5000, 2500]);

            loop_preserve_out = mediumBlend.(med, loop_preserve, loop_wear_amt, bbd_tone_fc);

            ReplaceOut.ar(imprint_in_bus_num, input);
            trem_imprinted    = InFeedback.ar(imprint_out_bus_num, 2);
            trem_imprinted    = LPF.ar(trem_imprinted, (speed_rate * 21600).clip(2000, 22000));

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
            // At write rates above 1 (live record / dub at Speed > 100%) the write head skips
            // buffer positions, leaving unwritten holes that playback interpolates as silence.
            // Fill the position behind the head so reads never land in a gap.
            // Gated on rec/dub as well as on the rate: while merely playing back, the same
            // path only copies the buffer through the medium onto itself, and doubling those
            // writes would overwrite every second sample with its neighbour, smearing the
            // recording a little more on every pass. Resample writes at rate 1 regardless.
            fill_gate = (write_rate > 1) * (loop_rec + loop_dub).min(1);
            BufWr.ar(write_sig, loop_buf_num,
                Select.ar(K2A.ar(fill_gate), [loop_phase, (loop_phase - 1).wrap(0, frames)]));

            // The seam fade is applied BEFORE mediumRead, not after. Cassette, Tape and Vinyl
            // run the read through a wow-modulated DelayC of up to 25-30 ms; applying the fade
            // afterwards closed it while the seam was still inside that delay line, so the
            // splice came out later at full gain - an unfaded cut through the material, once
            // per loop pass and therefore most obvious on short loops. Feeding the faded
            // signal into the delay makes fade and seam travel together, per channel, since
            // left and right are delayed by different amounts.
            loop_rd_wow = mediumRead.(med, loop_rd * fade_gain, bbd_tone_fc, loop_wow_tape, loop_wow_cas, loop_chip_crush, speed_rate);

            loop_out  = (loop_rd_wow * (1 - cd_skip_env) * (1 - cd_stutter_env)
                         + cd_skip_out + cd_stutter_out)
                        * (1 - cd_scratch_env)
                        * loop_level * out_gate;

            if(med == \vinyl, {
                var vinyl_noise_amt, vinyl_noise_sig;
                vinyl_noise_amt = loop_vinyl_noise / 100.0;
                vinyl_noise_sig = [
                    HPF.ar(Dust2.ar(vinyl_noise_amt.pow(1.5) * 20.0, vinyl_noise_amt * 0.5), 2000)
                      + LPF.ar(PinkNoise.ar(vinyl_noise_amt.pow(1.3) * 0.010), 8000),
                    HPF.ar(Dust2.ar(vinyl_noise_amt.pow(1.5) * 20.0, vinyl_noise_amt * 0.5), 2000)
                      + LPF.ar(PinkNoise.ar(vinyl_noise_amt.pow(1.3) * 0.010), 8000)
                ];
                loop_out = loop_out + (vinyl_noise_sig * loop_level * out_gate);
            });

            ReplaceOut.ar(looper_out_bus, loop_out);
        }).add;
        };

        // The looper synth is freed outright, with no release envelope, so the last block it
        // wrote stays on the output bus - and the main synth reads that bus every block
        // whether a looper exists or not. Left alone the final block repeats forever as a
        // steady buzz at loop level. This wipes the bus once after the free; it self-frees,
        // and must, since a permanent writer here would erase the looper's own output.
        SynthDef(\princeton_looper_silence, {
            arg out_bus = 0;
            ReplaceOut.ar(out_bus, DC.ar(0) ! 2);
            Line.kr(0, 0, 0.02, doneAction: 2);
        }).add;

// ── Looper param commands ────────────────────────────────────
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
            engine.addCommand(pair[0], "f", { |msg| if(looper_synth.notNil) { looper_synth.set(pair[1], msg[1]) } });
        };

// ── Looper on-demand ─────────────────────────────────────────
        engine.addCommand("looper_on", "", {
            if(looper_synth.isNil) {
                var medName = mediaNames.clipAt(imp_medium_v.asInteger);
                looper_synth = Synth.after(mainSynth.value, ("princeton_looper_" ++ medName).asSymbol, [
                    \looper_in_bus,       looperInBus.index,
                    \looper_out_bus,      looperOutBus.index,
                    \imprint_in_bus_num,  imprint_in_bus.index,
                    \imprint_out_bus_num, imprint_out_bus.index,
                    \loop_buf_num,        loopBuf.bufnum
                ]);
            };
        });
        engine.addCommand("looper_off", "", {
            if(looper_synth.notNil) {
                looper_synth.free;
                looper_synth = nil;
                Synth.after(mainSynth.value, \princeton_looper_silence,
                    [\out_bus, looperOutBus.index]);
            };
        });

        // ── Imprint on-demand ────────────────────────────────────────
        engine.addCommand("imprint_on", "", {
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
        engine.addCommand("imprint_off", "", {
            if(imprint_synth.notNil) {
                imprint_synth.set(\gate, 0);
                imprint_synth = nil;
            };
        });

        engine.addCommand("looper_imprint", "f", { |msg|
            imp_amt_v = msg[1];
            if(imprint_synth.notNil) { imprint_synth.set(\amt, msg[1]) };
        });
        engine.addCommand("looper_bbd_tone", "f", { |msg|
            imp_bbd_tone_v = msg[1];
            if(looper_synth.notNil) { looper_synth.set(\loop_bbd_tone, msg[1]) };
            if(imprint_synth.notNil) { imprint_synth.set(\loop_bbd_tone, msg[1]) };
        });
        engine.addCommand("looper_medium", "f", { |msg|
            imp_medium_v = msg[1];
        });

        engine.addCommand("looper_vinyl_noise", "f", { |msg| if(looper_synth.notNil) { looper_synth.set(\loop_vinyl_noise, msg[1]) } });

engine.addCommand("loop_clear", "", {
            loopBuf.zero;
            if(looper_synth.notNil) { looper_synth.set(\loop_rec, 0, \loop_dub, 0, \loop_play, 0) };
        });

        (free: {
            if(imprint_synth.notNil) { imprint_synth.free };
            if(looper_synth.notNil) { looper_synth.free };
            imprint_in_bus.free;
            imprint_out_bus.free;
        })
}
