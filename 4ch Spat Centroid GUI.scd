s.options.numOutputBusChannels = 4;
s.options.numInputBusChannels = 4;
Server.local.options.memSize = 131072*10;
Server.internal.options.memSize = 131072*10;
s.options.device = "Yamaha 01V96i";
s.reboot;

// Definición de estado global
(
~soloedTrack = nil;
~globalPanRate = 1;
~lagTime = 3;
~originalRates = [];
~originalPanRates = [];
)

(
SynthDef(\trackPlayer, {
    |out=0, buf, rate=1, panRate=1, direction=1, type=0, mute=0, volume=1, gate=1,
    delayActive=0, delayTime=0.3, feedback=0.6, wet=0.5|
    var sig, pan, panned, playRate;
    var drySig, wetSig;

    playRate = Lag.kr(rate, ~lagTime) * BufRateScale.kr(buf);
    sig = PlayBuf.ar(1, buf, playRate, loop: 0);

    pan = Select.kr(Lag.kr(type, ~lagTime), [
        LFSaw.kr(Lag.kr(panRate * ~globalPanRate, ~lagTime), iphase: 0)
            .range(0, 4) * direction,
        LFNoise1.kr(Lag.kr(panRate * ~globalPanRate, ~lagTime)).range(0, 4)
    ]);

    panned = PanAz.ar(4, sig, pan);

    // Procesamiento de delay condicional por canal
    drySig = panned;
    wetSig = CombL.ar(
        in: panned,
        maxdelaytime: 2.0,
        delaytime: delayTime,
        decaytime: feedback * 4
    );

    // Mezclar señales wet/dry según activación
    panned = XFade2.ar(drySig, wetSig, (delayActive * 2 - 1) * wet);

    // Aplicar volumen, mute y envelope
    panned = panned * Lag.kr(volume, ~lagTime) * (1 - Lag.kr(mute, ~lagTime)) * EnvGen.kr(Env.asr(0.01, 1, 0.1), gate, doneAction: 2);

    Out.ar(out, panned);
}).add;

// Sistema de espacialización espectral ping-pong delay y envolventes para efectos globales
SynthDef(\pingPongCentroideDelay, {
    |inBus = 0, outBus = 0, fftSize = 1024, rate = 3, amp = 0.5,
    delayTime = 0.3, feedback = 0.8, centroidScale = 15, lagTime = 0.1, wet = 0.5|

    var in, chain, centroid, mod, delayed, spatialSignal;
    var window, dry, pos;

    window = LocalBuf(fftSize);
    in = In.ar(inBus, 4);

    // Análisis espectral
    chain = FFT(window, Mix(in) / 4);
    centroid = SpecCentroid.kr(chain).lag(lagTime);

    // Modulación dinámica basada en brillo espectral
    mod = SinOsc.kr(
        freq: rate + (centroid / 15000 * centroidScale),  // Rango adaptativo
        phase: Rand(0, 2pi)
    ).range(-1, 1);

    dry = in * amp;

    // Modular el tiempo de delay con el centroide espectral
    delayed = CombL.ar(
        in: dry,
        maxdelaytime: 2.0,
        // Modular el tiempo de delay con un rango de ±15% basado en el mod
        delaytime: delayTime * (1 + (mod * 0.15)),
        decaytime: feedback * 4
    );

    // Aplicar la modulación a la espacialización de la señal procesada
    pos = (0..3) * 0.25 + (mod * 0.2); // Offset basado en la modulación

    // Rotar espacialmente la señal de delay según la modulación espectral
    delayed = PanAz.ar(
        numChans: 4,
        in: Mix(delayed) / 4,  // Mezclar a mono para re-espacializar
        pos: Lag.kr(LFSaw.kr(rate * 0.25).range(0, 4) + (mod * 2)), // Movimiento circular + mod
        level: 1
    );

    spatialSignal = XFade2.ar(dry, delayed, wet * 2 - 1);

    // Salida final
    Out.ar(outBus, spatialSignal);
}).add;
)

// Inicialización del sistema
(
~folder = PathName.new("/.../.../");

~dataBase = [];
~synths = [];
~controlsInitialized = false;

// Variables para efecto global
~effectActive = false;
~effectParams = (
    rate: 1.5,
    amp: 0.6,
    delayTime: 0.25,
    feedback: 0.8,
    centroidScale: 20,
    wet: 0.5
);

~folder.entries.do({ |path, i|
    Buffer.read(s, path.fullPath, action: { |buf|
        var type = if(0.5.coin, 0, 1);
        var baseRate = 1.0;
        var panRate = exprand(0.1, 5);
        var direction = if(type == 0, { [-1, 1].choose }, { 1 });
        var name = path.fileNameWithoutExtension;

        ~dataBase = ~dataBase.add(buf);
        ~originalRates = ~originalRates.add(baseRate);
        ~originalPanRates = ~originalPanRates.add(panRate);

        // Añadir parámetros de delay por canal: [delay activo, tiempo, feedback, wet]
        ~synths = ~synths.add([
            nil, baseRate, panRate, direction, type, name, 0, 0, 1, 0, 0.3, 0.6, 0.5
        ]);

        ~synths[i][0] = Synth(\trackPlayer, [
            \buf, buf,
            \rate, baseRate,
            \panRate, panRate,
            \direction, direction,
            \type, type
        ]);

        if(~synths.size == ~folder.entries.size and: { ~controlsInitialized.not }) {
            AppClock.sched(0, {
                ~createGUI.value;
                ~controlsInitialized = true;
            });
        };
    });
});

~createGUI = {
    var window = Window("Spatial Controller", Rect(100, 100, 1050, 1050), scroll:true)
        .background_(Color.new(0.2, 0.2, 0.25))
        .front;

    var globalControls = View(window, Rect(10, 10, 1030, 90))
        .background_(Color.gray(0.35));

    var effectsSection = View(window, Rect(10, 110, 1030, 120))
        .background_(Color.gray(0.25));

    // ===== CONTROLES GLOBALES =====
    StaticText(globalControls, Rect(10, 10, 100, 30))
        .string_("GLOBAL PAN")
        .font_(Font.default.bold)
        .stringColor_(Color.white);

    ~globalPanRateSlider = Slider(globalControls, Rect(120, 10, 250, 20))
        .value_(0.1)
        .action_({ |s|
            ~globalPanRate = linlin(s.value, 0, 1, 0.1, 5);
            ~updateAllSynths.value;
        });

    Button(globalControls, Rect(390, 10, 120, 20))
        .states_([["RESET RATES", Color.black, Color.white]])
        .action_({
            ~synths.do { |data, i|
                data[1] = ~originalRates[i];
                data[2] = ~originalPanRates[i];
            };
            ~updateAllSynths.value;
        });

    Button(globalControls, Rect(520, 10, 220, 20))
        .states_([["RANDOMIZE SPATIAL", Color.black, Color.yellow(0.7)]])
        .action_({
            ~synths.do { |data, i|
                if(0.3.coin) { data[4] = if(data[4] == 0, 1, 0) };
                data[3] = if(data[4] == 0, { [-1, 1].choose }, { 1 });
            };
            ~updateAllSynths.value;
        });

    Button(globalControls, Rect(750, 10, 140, 20))
        .states_([["RANDOMIZE RATES", Color.black, Color.cyan(0.7)]])
        .action_({
            ~synths.do { |data, i|
                data[1] = rrand(0.89, 1.12);
                data[2] = exprand(0.1, 5);
            };
            ~updateAllSynths.value;
        });

    StaticText(globalControls, Rect(10, 40, 100, 20))
        .string_("LAG TIME")
        .font_(Font.default.bold)
        .stringColor_(Color.white);

    ~lagTimeSlider = Slider(globalControls, Rect(120, 40, 250, 20))
        .value_(~lagTime.linlin(0.1, 5, 0, 1))
        .action_({ |s|
            ~lagTime = linlin(s.value, 0, 1, 0.1, 5);
        });

    // ===== SECCIÓN DE EFECTOS GLOBALES =====
    StaticText(effectsSection, Rect(10, 10, 200, 30))
        .string_("GLOBAL SPECTRAL DELAY")
        .font_(Font("Helvetica", 14).bold)
        .stringColor_(Color.white);

    Button(effectsSection, Rect(10, 40, 100, 25))
        .states_([
            ["GLOBAL OFF", Color.white, Color.red(0.5)],
            ["GLOBAL ON", Color.white, Color.green(0.6)]
        ])
        .action_({ |b|
            ~effectActive = b.value == 1;
            if(~effectActive) {
                ~spatialProcessor = Synth.tail(nil, \pingPongCentroideDelay, [
                    \inBus, 0,
                    \outBus, 0,
                    \fftSize, 2048,
                    \rate, ~effectParams.rate,
                    \amp, ~effectParams.amp,
                    \delayTime, ~effectParams.delayTime,
                    \feedback, ~effectParams.feedback,
                    \centroidScale, ~effectParams.centroidScale,
                    \wet, ~effectParams.wet
                ]);
            } {
                ~spatialProcessor.free;
            };
        });

    // Controles de efectos globales
    StaticText(effectsSection, Rect(120, 40, 70, 20)).string_("RATE").stringColor_(Color.white);
    Slider(effectsSection, Rect(200, 40, 150, 20))
        .value_(~effectParams.rate.linlin(0.1, 5, 0, 1))
        .action_({ |s|
            ~effectParams.rate = s.value.linlin(0, 1, 0.1, 5);
            if(~effectActive) { ~spatialProcessor.set(\rate, ~effectParams.rate) };
        });

    StaticText(effectsSection, Rect(120, 70, 70, 20)).string_("FEEDBACK").stringColor_(Color.white);
    Slider(effectsSection, Rect(200, 70, 150, 20))
        .value_(~effectParams.feedback.linlin(0.1, 2, 0, 1))
        .action_({ |s|
            ~effectParams.feedback = s.value.linlin(0, 1, 0.1, 2);
            if(~effectActive) { ~spatialProcessor.set(\feedback, ~effectParams.feedback) };
        });

    StaticText(effectsSection, Rect(390, 40, 70, 20)).string_("CENTROID").stringColor_(Color.white);
    Slider(effectsSection, Rect(470, 40, 150, 20))
        .value_(~effectParams.centroidScale.linlin(1, 50, 0, 1))
        .action_({ |s|
            ~effectParams.centroidScale = s.value.linlin(0, 1, 1, 50);
            if(~effectActive) { ~spatialProcessor.set(\centroidScale, ~effectParams.centroidScale) };
        });

    StaticText(effectsSection, Rect(390, 70, 70, 20)).string_("WET/DRY").stringColor_(Color.white);
    Slider(effectsSection, Rect(470, 70, 150, 20))
        .value_(~effectParams.wet)
        .action_({ |s|
            ~effectParams.wet = s.value;
            if(~effectActive) { ~spatialProcessor.set(\wet, ~effectParams.wet) };
        });

    StaticText(effectsSection, Rect(650, 40, 70, 20)).string_("AMP").stringColor_(Color.white);
    Slider(effectsSection, Rect(730, 40, 150, 20))
        .value_(~effectParams.amp.linlin(0.1, 1.0, 0, 1))
        .action_({ |s|
            ~effectParams.amp = s.value.linlin(0, 1, 0.1, 1.0);
            if(~effectActive) { ~spatialProcessor.set(\amp, ~effectParams.amp) };
        });

    StaticText(effectsSection, Rect(650, 70, 70, 20)).string_("DELAY").stringColor_(Color.white);
    Slider(effectsSection, Rect(730, 70, 150, 20))
        .value_(~effectParams.delayTime.linlin(0.05, 1.5, 0, 1))
        .action_({ |s|
            ~effectParams.delayTime = s.value.linlin(0, 1, 0.05, 1.5);
            if(~effectActive) { ~spatialProcessor.set(\delayTime, ~effectParams.delayTime) };
        });

/*    Button(effectsSection, Rect(650, 5, 230, 25))
        .states_([["RANDOMIZE EFFECTS", Color.black, Color.magenta(0.7)]])
        .action_({
            ~effectParams.rate = exprand(0.5, 3.5);
            ~effectParams.feedback = rrand(0.4, 1.8);
            ~effectParams.centroidScale = rrand(5, 40);
            ~effectParams.delayTime = rrand(0.1, 0.8);

            if(~effectActive) {
                ~spatialProcessor.set(
                    \rate, ~effectParams.rate,
                    \feedback, ~effectParams.feedback,
                    \centroidScale, ~effectParams.centroidScale,
                    \delayTime, ~effectParams.delayTime
                );
            };
        });*/

    // ===== CONTROLES POR TRACK =====
    ~synths.do { |synthData, i|
        var trackView = View(window, Rect(10, 240 + (i * 75), 1030, 70))
            .background_(Color.rand(0.1, 0.3));

        StaticText(trackView, Rect(5, 5, 150, 20))
            .string_(synthData[5])
            .font_(Font.default.bold);

        Button(trackView, Rect(160, 5, 100, 20))
            .states_([
                ["CIRCULAR", Color.black, Color.green(0.7)],
                ["RANDOM", Color.white, Color.blue(0.7)]
            ])
            .value_(synthData[4])
            .action_({ |b|
                synthData[4] = b.value;
                synthData[3] = if(b.value == 0, { [-1, 1].choose }, { 1 });
                ~updateSynth.value(i);
            });

        Button(trackView, Rect(270, 5, 80, 20))
            .states_([["REVERSE", Color.white, Color.red(0.7)]])
            .action_({ |b|
                synthData[3] = synthData[3] * -1;
                ~updateSynth.value(i);
            });

        Button(trackView, Rect(360, 5, 60, 20))
            .states_([
                ["MUTE", Color.black, Color.gray(0.8)],
                ["MUTE", Color.white, Color.red(0.8)]
            ])
            .value_(synthData[6])
            .action_({ |b|
                synthData[6] = b.value;
                ~updateSynth.value(i);
            });

        Button(trackView, Rect(430, 5, 60, 20))
            .states_([
                ["SOLO", Color.black, Color.gray(0.8)],
                ["SOLO", Color.black, Color.yellow(0.8)]
            ])
            .value_(synthData[7])
            .action_({ |b|
                ~handleSolo.value(i, b.value);
            });

        StaticText(trackView, Rect(500, 5, 70, 20)).string_("FREQ RATE");
        Slider(trackView, Rect(580, 5, 150, 20))
            .value_(linlin(synthData[1], 0.89, 1.12, 0, 1))
            .action_({ |s|
                synthData[1] = linlin(s.value, 0, 1, 0.89, 1.12);
                ~updateSynth.value(i);
            });

        Button(trackView, Rect(780, 5, 80, 20))
            .states_([["RESET", Color.black, Color.white]])
            .action_({
                synthData[1] = ~originalRates[i];
                synthData[2] = ~originalPanRates[i];
                ~updateSynth.value(i);
            });

        StaticText(trackView, Rect(500, 30, 70, 20)).string_("PAN RATE");
        Slider(trackView, Rect(580, 30, 150, 20))
            .value_((synthData[2] - 0.1) / (5 - 0.1))
            .action_({ |s|
                synthData[2] = linlin(s.value, 0, 1, 0.1, 5);
                ~updateSynth.value(i);
            });

        StaticText(trackView, Rect(870, 5, 50, 20)).string_("VOL");
        Slider(trackView, Rect(910, 5, 100, 20))
            .value_(synthData[8])
            .action_({ |s|
                synthData[8] = s.value;
                ~updateSynth.value(i);
            });

        Button(trackView, Rect(780, 40, 80, 20))
            .states_([
                ["DELAY", Color.black, Color.gray(0.8)],
                ["DELAY", Color.white, Color.cyan(0.8)]
            ])
            .value_(synthData[9])
            .action_({ |b|
                synthData[9] = b.value;
                ~updateSynth.value(i);
            });

        StaticText(trackView, Rect(870, 40, 40, 20)).string_("WET");
        Slider(trackView, Rect(910, 40, 50, 20))
            .value_(synthData[12])
            .action_({ |s|
                synthData[12] = s.value;
                ~updateSynth.value(i);
            });

        StaticText(trackView, Rect(980, 40, 30, 20)).string_("T");
        Slider(trackView, Rect(970, 40, 40, 20))
            .value_(synthData[10].linlin(0.05, 1.5, 0, 1))
            .action_({ |s|
                synthData[10] = s.value.linlin(0, 1, 0.05, 1.5);
                ~updateSynth.value(i);
            });
    };
};

// ===== FUNCIONES AUXILIARES =====
~updateSynth = { |i|
    var synthData = ~synths[i];
    var muteValue = if(~soloedTrack.notNil and: { ~soloedTrack != i }, 1, synthData[6]);

    synthData[0].set(
        \rate, synthData[1],
        \panRate, synthData[2] * ~globalPanRate,
        \direction, synthData[3],
        \type, synthData[4],
        \mute, muteValue,
        \volume, synthData[8],
        \delayActive, synthData[9],
        \delayTime, synthData[10],
        \feedback, synthData[11],
        \wet, synthData[12]
    );
};

~updateAllSynths = {
    ~synths.do { |data, i| ~updateSynth.value(i) };
};

~handleSolo = { |i, state|
    ~synths[i][7] = state;

    if(state == 1) {
        ~soloedTrack = i;
        ~synths.do { |data, j|
            data[0].set(\mute, if(j == i, 0, 1));
        };
    } {
        ~soloedTrack = nil;
        ~synths.do { |data, j|
            data[0].set(\mute, data[6]);
        };
    };
};
)
