module adaptor;
import ft;
import ft.adaptors;
import std.string;
import std.algorithm.comparison: max;
import inochi2d;
import core.exception;
import std.stdio: writeln;
import inochi2d.core.automation.sine;

enum TrackingMode {
    VMC = "vmc",
    VTS = "vts",
    OSF = "osf",
    None = ""
}

private {
    Adaptor adaptor;
    TrackingMode trackingMode = TrackingMode.None;
    Puppet puppet;
    float time;
    Parameter[string] params;
    string[string] options;

    void applyToAxis(string name, int axis, float val, bool inverse = false) {
        try {
            Parameter param = params[name];
            if (axis == 0) param.value.x = clamp(inverse ? val*-1 : val, param.min.x, param.max.x);
            if (axis == 1) param.value.y = clamp(inverse ? val*-1 : val, param.min.y, param.max.y);
        } catch (RangeError e) {};
    }
}

void invStartAdaptor(TrackingMode mode, string[string] newOptions) {
    trackingMode = mode;
    time = 0;

    // Stop old adaptor before switching
    if (adaptor && adaptor.isRunning) adaptor.stop();
    
    switch(trackingMode) {
        case TrackingMode.VMC:
            adaptor = new VMCAdaptor();
            break;
        case TrackingMode.VTS:
            adaptor = new VTSAdaptor();
            break;
        case TrackingMode.OSF:
            adaptor = new OSFAdaptor();
            break;
        default: 
            adaptor = null;
            break;
    }

    options = newOptions;
    if (adaptor) {
        try {
            adaptor.start(options);
        } catch(Exception ex) {
            if (adaptor.isRunning) adaptor.stop();
            adaptor = null;
        }
    }
}

void invStopAdaptor() {
    if (adaptor && adaptor.isRunning)
        adaptor.stop();
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
    if (adaptor && adaptor.isRunning) {
        adaptor.poll();
    }

    float[string] blendShapes = adaptor.getBlendshapes();
    Bone[string] bones = adaptor.getBones();

    time += 1.0;
    writeln();
    foreach (name, value; blendShapes) {
        writeln(format("%20s: %0.5f", name, value));
    }
    foreach (name, value; bones) {
        writeln(format("%20s: %s, %s", name, value.position, value.rotation));
    }

    switch (trackingMode) {
        case TrackingMode.VTS:
            invUpdateVTS(blendShapes, bones);
            break;
        case TrackingMode.OSF:
            invUpdateOSF(blendShapes, bones);
            break;
        default:
            break;
    }
}

void invUpdateVTS(float[string] blendShapes, Bone[string] bones) {
    float headYaw = 0;
    float headPitch = 0;
    float headRoll = 0;
    try {
        headYaw    = bones["Head"].rotation.y * 1.5;
        headPitch  = -bones["Head"].rotation.x * 2;
//        headRoll   = bones["Head"].rotation.z;
//        headYaw =  blendShapes["headLeft"] - blendShapes["headRight"];
//        headPitch =  blendShapes["headUp"] - blendShapes["headDown"];
        headRoll = blendShapes["headRollLeft"] - blendShapes["headRollRight"];

        float browEmotion = -(blendShapes["browDown_L"] + blendShapes["browDown_R"]) / 2 * 3 + 
            (blendShapes["browOuterUp_L"] + blendShapes["browOuterUp_R"]) / 2;
//            (blendShapes["browOuterUp_L"] + blendShapes["browOuterUp_R"] - blendShapes["browInnerUp_L"] - blendShapes["browInnerUp_R"]) * 3;
        float mouthEmotion = browEmotion > 0 ? max(browEmotion, (blendShapes["mouthSmile_L"] + blendShapes["mouthSmile_R"])/2 - blendShapes["mouthPucker"]) : 
                                               min(browEmotion,  (blendShapes["mouthSmile_L"] + blendShapes["mouthSmile_R"])/2 - blendShapes["mouthPucker"]);

        applyToAxis("Head Yaw-Pitch", 0, headYaw);
        applyToAxis("Head Yaw-Pitch", 1, headPitch);
        applyToAxis("Eye L Blink", 0, blendShapes["EyeBlinkRight"]);
        applyToAxis("Eye R Blink", 0, blendShapes["EyeBlinkLeft"]);
        applyToAxis("Mouth Shape", 1, max(blendShapes["jawOpen"], blendShapes["mouthPucker"] * 0.01));

        applyToAxis("Head Roll", 0, headRoll);
        applyToAxis("Body Yaw-Pitch", 0, headYaw);
        applyToAxis("Body Yaw-Pitch", 1, headPitch * 3);
        applyToAxis("Eyebrow L Emotion", 0, browEmotion);
        applyToAxis("Eyebrow R Emotion", 0, browEmotion);
        applyToAxis("Mouth Shape", 0, (mouthEmotion + 1) / 2);
    } catch (RangeError e) {}
}


void invUpdateOSF(float[string] blendShapes, Bone[string] bones) {
    float headYaw = 0;
    float headPitch = 0;
    float headRoll = 0;
    try {

        headYaw    = bones["Head"].rotation.y * 1.5;
        headRoll   = bones["Head"].rotation.z;
        float browEmotion = -(blendShapes["eyebrowSteppnessRight"] + blendShapes["eyebrowSteppnessLeft"]) / 2;
        float mouthEmotion = (blendShapes["mouthCornerUpDownLeft"] + blendShapes["mouthCornerUpDownRight"]) / 2;

        applyToAxis("Head Yaw-Pitch", 0, headYaw);
        applyToAxis("Head Yaw-Pitch", 1, headPitch);

        applyToAxis("Eye L Blink", 0, (1 - blendShapes["EyeOpenLeft"]) / 0.3);
        applyToAxis("Eye R Blink", 0, (1 - blendShapes["EyeOpenRight"]) / 0.3);
        applyToAxis("Mouth Shape", 1, blendShapes["mouthOpen"] * 0.1);

        applyToAxis("Head Roll", 0, headRoll);
        applyToAxis("Body Yaw-Pitch", 0, headYaw);
        applyToAxis("Body Yaw-Pitch", 1, headPitch * 3);
        applyToAxis("Eyebrow L Emotion", 0, browEmotion);
        applyToAxis("Eyebrow R Emotion", 0, browEmotion);
        applyToAxis("Mouth Shape", 0, (mouthEmotion + 1) / 2);
    } catch (RangeError e) {}
}