module adaptor;
import ft;
import ft.adaptors;
import std.string;
import std.algorithm.comparison: max;
import inochi2d;
import core.exception;
import std.stdio: writeln;
import inochi2d.core.automation.sine;
import std.math;

enum TrackingMode {
    VMC = "vmc",
    VTS = "vts",
    OSF = "osf",
    JML = "jml",
    None = ""
}

private {
    Adaptor[TrackingMode] adaptors;
    TrackingMode defaultMode = TrackingMode.None;
    TrackingMode[string] modeMap;

    Puppet puppet;
    float time;
    Parameter[string] params;
    string[string] options;

    void applyToAxis(TrackingMode mode, string name, int axis, float val, bool inverse = false) {
        try {
            TrackingMode usedMode = (name in modeMap)? modeMap[name]: defaultMode;
            if (mode != usedMode){
                return;
            }
            Parameter param = params[name];
            auto delta = deltaTime();
            float speed = 4;
            if (axis == 0) param.value.x = dampen(param.value.x, clamp(inverse? -val:val, param.min.x, param.max.x), delta, speed);
            if (axis == 1) param.value.y = dampen(param.value.y, clamp(inverse? -val:val, param.min.y, param.max.y), delta, speed);
        } catch (RangeError e) {};
    }
}

void invStartAdaptor(TrackingMode mode, string[string] newOptions) {
    time = 0;

    // Stop old adaptor before switching

    if (mode in adaptors && adaptors[mode].isRunning) adaptors[mode].stop();
    
    switch(mode) {
        case TrackingMode.VMC:
            adaptors[mode] = new VMCAdaptor();
            break;
        case TrackingMode.VTS:
            adaptors[mode] = new VTSAdaptor();
            break;
        case TrackingMode.OSF:
            adaptors[mode] = new OSFAdaptor();
            break;
        case TrackingMode.JML:
            adaptors[mode] = new JMLAdaptor();
            break;
        default: 
            break;
    }

    options = newOptions;
    if (mode in adaptors) {
        try {
            adaptors[mode].start(options);
        } catch(Exception ex) {
            if (adaptors[mode].isRunning) adaptors[mode].stop();
            adaptors.remove(mode);
        }
    }
}

void invSetDefaultMode(TrackingMode mode) {
    if (mode in adaptors)
        defaultMode = mode;
}

void invSetTrackingModeMap(TrackingMode[string] map) {
    foreach (name, mode; map) {
        if (mode in adaptors)
            modeMap[name] = mode;
        else
            modeMap[name] = defaultMode;
    }
}

void invStopAdaptor(TrackingMode mode) {
    if (mode in adaptors && adaptors[mode].isRunning)
        adaptors[mode].stop();
}

void invStopAdaptors() {
    foreach (mode, adaptor; adaptors) {
        invStopAdaptor(mode);
    }
}

void invSetPuppet(Puppet newPuppet) {
    puppet = newPuppet;
    foreach (param; puppet.parameters) {
        params[param.name] = param;
    }
}

void invSetAutomator() {
	foreach (param; puppet.parameters) {
		if (param.name == "Breath") {
			auto automator = new SineAutomation(puppet);
			automator.speed = 2;
			automator.phase = 0;
			auto binding   = AutomationBinding();
			binding.paramId = param.name;
			binding.param   = param;
			binding.axis    = 0;
			binding.range   = vec2(0, 1);
			automator.bind(binding);
			puppet.automation ~= automator;
		} else if (param.name == "Arm R Move") {
			auto automator = new SineAutomation(puppet);
			automator.speed = 1;
			automator.phase = 0;
			auto binding   = AutomationBinding();
			binding.paramId = param.name;
			binding.param   = param;
			binding.axis    = 0;
			binding.range   = vec2(0, 0.05);
			automator.bind(binding);
			puppet.automation ~= automator;

			auto automator_x = new SineAutomation(puppet);
            automator_x.sineType = SineType.Cos;
			automator_x.speed = 0.9;
			automator_x.phase = 0;
			binding   = AutomationBinding();
			binding.paramId = param.name;
			binding.param   = param;
			binding.axis    = 1;
			binding.range   = vec2(0, 0.05);
			automator_x.bind(binding);
			puppet.automation ~= automator_x;
        }
	}
}

void invUpdate() {

    foreach (mode, adaptor; adaptors) {
        if (adaptor && adaptor.isRunning) {
            adaptor.poll();
        }

        float[string] blendShapes = adaptor.getBlendshapes();
        Bone[string] bones = adaptor.getBones();

        writeln(format("[%s]", mode));
        foreach (name, value; blendShapes) {
            writeln(format("%20s: %0.5f", name, value));
        }
        foreach (name, value; bones) {
            writeln(format("%20s: %s, %s", name, value.position, value.rotation));
        }

        switch (mode) {
            case TrackingMode.VTS:
                invUpdateVTS(blendShapes, bones);
                break;
            case TrackingMode.OSF:
                invUpdateOSF(blendShapes, bones);
                break;
            case TrackingMode.JML:
                invUpdateJML(blendShapes, bones);
                break;
            default:
                break;
        }
    }

}
 

void invUpdateVTS(float[string] blendShapes, Bone[string] bones) {
    TrackingMode mode = TrackingMode.VTS;
    float headYaw = 0;
    float headPitch = 0;
    float headRoll = 0;
    try {
        headYaw    = bones["Head"].rotation.pitch();
        headPitch  = -bones["Head"].rotation.roll();
        headRoll   = -bones["Head"].rotation.yaw() * 2;

        float browEmotion = -(blendShapes["browDown_L"] + blendShapes["browDown_R"]) / 2 * 3 + 
            (blendShapes["browOuterUp_L"] + blendShapes["browOuterUp_R"]) / 2;
//            (blendShapes["browOuterUp_L"] + blendShapes["browOuterUp_R"] - blendShapes["browInnerUp_L"] - blendShapes["browInnerUp_R"]) * 3;
        float mouthEmotion = browEmotion > 0 ? max(browEmotion, (blendShapes["mouthSmile_L"] + blendShapes["mouthSmile_R"])/2 - blendShapes["mouthPucker"]) : 
                                               min(browEmotion,  (blendShapes["mouthSmile_L"] + blendShapes["mouthSmile_R"])/2 - blendShapes["mouthPucker"]);

        applyToAxis(mode, "Head Yaw-Pitch", 0, headYaw);
        applyToAxis(mode, "Head Yaw-Pitch", 1, headPitch);
        applyToAxis(mode, "Eye L Blink", 0, blendShapes["EyeBlinkRight"]);
        applyToAxis(mode, "Eye R Blink", 0, blendShapes["EyeBlinkLeft"]);
        applyToAxis(mode, "Mouth Shape", 1, max(blendShapes["jawOpen"], blendShapes["mouthPucker"] * 0.01));

        applyToAxis(mode, "Head Roll", 0, headRoll);
        applyToAxis(mode, "Body Yaw-Pitch", 0, headYaw);
        applyToAxis(mode, "Body Yaw-Pitch", 1, headPitch * 3);
        applyToAxis(mode, "Eyebrow L Emotion", 0, browEmotion);
        applyToAxis(mode, "Eyebrow R Emotion", 0, browEmotion);
        applyToAxis(mode, "Mouth Shape", 0, (mouthEmotion + 1) / 2);
    } catch (RangeError e) {

    }
}


void invUpdateOSF(float[string] blendShapes, Bone[string] bones) {
    TrackingMode mode = TrackingMode.OSF;
    float headYaw = 0;
    float headPitch = 0;
    float headRoll = 0;
    try {
        headYaw    = (bones["Head"].rotation.yaw() / PI) * 3;
        headPitch  = (bones["Head"].rotation.pitch() / PI) * 3;
        headRoll   = (bones["Head"].rotation.roll()  / PI - .5) * 6;

        float lEyePitch = bones["LeftGaze"].rotation.pitch() / PI;
        float lEyeRoll  = bones["LeftGaze"].rotation.roll() / PI;
        float rEyePitch = bones["RightGaze"].rotation.pitch() / PI;
        float rEyeRoll  = bones["RightGaze"].rotation.roll() / PI;
//        writeln(format("L/ %0.5f, %0.5f   R/ %0.5f, %0.5f", lEyePitch, lEyeRoll, rEyePitch, rEyeRoll));

        float browEmotion = -(blendShapes["eyebrowSteppnessRight"] + blendShapes["eyebrowSteppnessLeft"]) / 2;
        float mouthEmotion = (blendShapes["mouthCornerUpDownLeft"] + blendShapes["mouthCornerUpDownRight"]) / 2;

//        applyToAxis("Eyeball R Movement", 0, sign(rEyeRoll) == sign(headYaw) ? rEyeRoll * 20: rEyeRoll * 3);
//        applyToAxis("Eyeball R Movement", 1, rEyePitch * 100);
//        applyToAxis("Eyeball L Movement", 0, sign(lEyeRoll) == sign(headYaw) ? lEyeRoll * 20: lEyeRoll * 3);
//        applyToAxis("Eyeball L Movement", 1, lEyePitch * 100);

        applyToAxis(mode, "Head Yaw-Pitch", 0, headYaw);
        applyToAxis(mode, "Head Yaw-Pitch", 1, headPitch);

        applyToAxis(mode, "Eye L Blink", 0, (0.9 - blendShapes["EyeOpenLeft"]) / 0.5);
        applyToAxis(mode, "Eye R Blink", 0, (0.9 - blendShapes["EyeOpenRight"]) / 0.5);
        applyToAxis(mode, "Mouth Shape", 1, blendShapes["mouthOpen"] * 0.1);

        applyToAxis(mode, "Head Roll", 0, headRoll);
        applyToAxis(mode, "Body Yaw-Pitch", 0, headYaw);
        applyToAxis(mode, "Body Yaw-Pitch", 1, headPitch > 0? headPitch * 3: headPitch);
        applyToAxis(mode, "Eyebrow L Emotion", 0, browEmotion);
        applyToAxis(mode, "Eyebrow R Emotion", 0, browEmotion);
        applyToAxis(mode, "Mouth Shape", 0, (mouthEmotion + 1) / 2);
    } catch (RangeError e) {}
}


void invUpdateJML(float[string] blendShapes, Bone[string] bones) {
    TrackingMode mode = TrackingMode.JML;
    float headYaw = 0;
    float headPitch = 0;
    float headRoll = 0;
    static float cumEyeUD = 0;
    static float initSequenceNumber = -1;
    static float initYaw = 0;
    static int   numInitYaw = 0;
    static bool  yawFixed = false;

    try {
        if (initSequenceNumber == -1)
            initSequenceNumber = blendShapes["sequenceNumber"];

        if (!yawFixed) {
            float sequenceNumber = blendShapes["sequenceNumber"] - initSequenceNumber;
            sequenceNumber = sequenceNumber < 0 ? sequenceNumber + 256 : sequenceNumber;
            if (sequenceNumber < 60) {
                initYaw += blendShapes["yaw"];
                numInitYaw ++;
            } else {
                initYaw = initYaw / numInitYaw / 360.0;
                yawFixed = true;
                writeln("Yaw base is determined");
            }
        } else {
            headYaw    = fmodf(blendShapes["yaw"] / 360 - initYaw, 1);
            headYaw    = headYaw > 0.5? 1 - headYaw: headYaw;
            headYaw    *= 3;
        }
        headPitch  = -(blendShapes["pitch"] / 180) * 3;
        headRoll   = -(blendShapes["roll"] / 180) * 3;
        cumEyeUD   += (blendShapes["eyeMoveUp"] > 0 ? 1: 0) - (blendShapes["eyeMoveDown"] > 0 ? 1: 0);
        writeln(format("%0.5f(%0.5f), %0.5f, %0.5f", headYaw, initYaw, headPitch, headRoll));

        float lEyePitch = 0;
        float lEyeRoll  = 0;
        float rEyePitch = 0;
        float rEyeRoll  = 0;
//        writeln(format("L/ %0.5f, %0.5f   R/ %0.5f, %0.5f", lEyePitch, lEyeRoll, rEyePitch, rEyeRoll));

//        float browEmotion = -(blendShapes["eyebrowSteppnessRight"] + blendShapes["eyebrowSteppnessLeft"]) / 2;
//        float mouthEmotion = (blendShapes["mouthCornerUpDownLeft"] + blendShapes["mouthCornerUpDownRight"]) / 2;

//        applyToAxis("Eyeball R Movement", 0, sign(rEyeRoll) == sign(headYaw) ? rEyeRoll * 20: rEyeRoll * 3);
//        applyToAxis("Eyeball R Movement", 1, rEyePitch * 100);
//        applyToAxis("Eyeball L Movement", 0, sign(lEyeRoll) == sign(headYaw) ? lEyeRoll * 20: lEyeRoll * 3);
//        applyToAxis("Eyeball L Movement", 1, lEyePitch * 100);

        applyToAxis(mode, "Head Yaw-Pitch", 0, headYaw);
        applyToAxis(mode, "Head Yaw-Pitch", 1, headPitch);

        applyToAxis(mode, "Eye L Blink", 0, cumEyeUD + blendShapes["blinkStrength"] > 0 ? 1:0);
        applyToAxis(mode, "Eye R Blink", 0, cumEyeUD + blendShapes["blinkStrength"] > 0 ? 1:0);

        applyToAxis(mode, "Head Roll", 0, headRoll);
        applyToAxis(mode, "Body Yaw-Pitch", 0, headYaw);
        applyToAxis(mode, "Body Yaw-Pitch", 1, headPitch > 0? headPitch: headPitch / 3);
//        applyToAxis(mode, "Eyebrow L Emotion", 0, browEmotion);
//        applyToAxis(mode, "Eyebrow R Emotion", 0, browEmotion);
//        applyToAxis(mode, "Mouth Shape", 0, (mouthEmotion + 1) / 2);
    } catch (RangeError e) {}
}