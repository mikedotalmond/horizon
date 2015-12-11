package flock;

import flock.FlockSprites;
import js.html.audio.AudioBuffer;
import js.html.audio.AudioContext;
import js.html.audio.ConvolverNode;
import js.html.audio.GainNode;
import js.html.Float32Array;
import motion.Actuate;
import tones.AudioBase;
import tones.Samples;
import tones.utils.NoteFrequencyUtil;

import motion.actuators.PropertyDetails;
import motion.actuators.SimpleActuator;
import motion.easing.Sine;

import util.MathUtil;
import worker.FlockData;

/**
 * ...
 * @author Mike Almond - https://github.com/mikedotalmond
 */

class SoundControl {
	
	static inline var MAX_POLYPHONY			:Int = 8;
	static inline var SOUND_BEGIN			:Float = 0.9;
	static inline var SOUND_END				:Float = 2.1;
	static inline var SOUND_RANGE			:Float = SOUND_END - SOUND_BEGIN;
	static inline var AUDIO_TYPE			:String = 'ogg';
	// need to add mp3/aac here to support IE... but meh.

	var noteIDs:Array<String>;
	
	var playTime:Float = .0;
	var triggerTime:Float = .25;
	var noteWeights:Float32Array;
	var volumeWeights:Float32Array;
	
	var t:PositionAccessActuator;
	var noteBuffers:Array<AudioBuffer>;
	var loadCount:Int=0;
	var paused:Bool=true;
	var context:AudioContext;
	var outGain:GainNode;
	var samples:Samples;
	
	public function new(flock:FlockSprites) {
		
		noteWeights = new Float32Array([for(c in 0...FlockData.Y_DATA_POINTS) .0]);
		volumeWeights = new Float32Array([for (c in 0...FlockData.X_DATA_POINTS) .0]);
		
		context = AudioBase.createContext();
		outGain = context.createGain();
		outGain.connect(context.destination);
		
		var outComp = context.createDynamicsCompressor();
		outComp.connect(outGain);
		//threshold - The decibel value above which the compression will start taking effect. Its default value is -24, with a nominal range of -100 to 0.
		//knee - A decibel value representing the range above the threshold where the curve smoothly transitions to the "ratio" portion. Its default value is 30, with a nominal range of 0 to 40.
		//ratio - The amount of dB change in input for a 1 dB change in output. Its default value is 12, with a nominal range of 1 to 20.	
		//reduction - A read-only decibel value for metering purposes, representing the current amount of gain reduction that the compressor is applying to the signal. If fed no signal the value will be 0 (no gain reduction). The nominal range is -20 to 0.
		//attack - The amount of time (in seconds) to reduce the gain by 10dB. Its default value is 0.003, with a nominal range of 0 to 1.		
		//release - The amount of time (in seconds) to increase the gain by 10dB. Its default value is 0.250, with a nominal range of 0 to 1.
		
		var samplesOutput = context.createGain();
		var drySignal = context.createGain();
		var wetSignal = context.createGain();
		var reverb = context.createConvolver();
		
		samples = new Samples(context, samplesOutput);
		samplesOutput.connect(wetSignal);
		samplesOutput.connect(drySignal);
		
		outGain.gain.setValueAtTime(.5, context.currentTime);
		drySignal.gain.setValueAtTime(.75, context.currentTime);
		wetSignal.gain.setValueAtTime(.25, context.currentTime);
		
		wetSignal.connect(reverb);
		
		reverb.connect(outComp);
		drySignal.connect(outComp);
		
		//samples.loadBuffer('audio/impulses/Lexicon 300 - Glossy Plate - Preset 302_dc.wav', function(buffer) {
		samples.loadBuffer('audio/impulses/hall.wav', function(buffer) {
		//samples.loadBuffer('audio/impulses/Hall 5_dc.wav', function(buffer) {
			trace('reverb impulse loaded');
			reverb.normalize = true;
			reverb.buffer = buffer;
		});
		
		var notes = '';
		for (octave in 2...6) notes += 'C$octave,C_$octave,D$octave,D_$octave,E$octave,F$octave,F_$octave,G$octave,G_$octave,A$octave,A_$octave,B$octave${octave==5?"":","}';
		noteIDs = notes.split(',');
		
		loadCount = 0;
		noteBuffers = [];
		
		for (i in 0...noteIDs.length) {
			samples.loadBuffer('audio/notes/note_${noteIDs[i]}.${AUDIO_TYPE}', audioDecoded.bind(_, i));
		}
	}
	
	
	function audioDecoded(buffer:AudioBuffer, index:Int) {
		noteBuffers[index] = buffer;
		loadCount++;
		if (loadCount == noteIDs.length) {
			trace('all loaded');
			// start
			noteTimeUpdate();
			paused = false;
		}
	}
	
	public function play(noteIndex:Int = 0, delay:Float = 0, volume:Float = 1) {
		
		if (paused) return;
		//trace(samples.polyphony);
		if(samples.polyphony > MAX_POLYPHONY) {
			//return;
		}
		
		var buffer = noteBuffers[noteIndex];
		
		samples.buffer = buffer;
		samples.attack = .25 + Math.random() * SOUND_RANGE;
		samples.release = SOUND_RANGE - samples.attack;
		samples.volume = volume;
		samples.offset = SOUND_BEGIN;
		samples.duration = SOUND_RANGE;
		samples.playSample(null, delay);
	}
	
	/**
	 * process the flock info data...
	 * @param	data
	 * @param	offset
	 * @param	now
	 */	
	public function update(dt:Float, data:Float32Array, offset:Int) {
		if (paused) return;
		
		playTime += dt;
		
		if (playTime >= triggerTime * (Math.random() * .1 + .9)) {
			playTime = 0;
			
			var w;
			var maxVol = .0;
			var maxNote = .0; 
			
			for(i in 0...FlockData.X_DATA_POINTS) {
				w 		= volumeWeights[i];
				maxVol 	= MathUtil.max(maxVol, w);				
				w 		= noteWeights[i];
				maxNote	= MathUtil.max(maxNote, w);
			}
			
			maxVol = 1 / maxVol;
			maxNote = 1 / maxNote;
			
			var shouldPlay;
			var wVolume, wNote;
			for(i in 0...FlockData.X_DATA_POINTS) {
				
				wVolume	= volumeWeights[i] * maxVol;
				wNote = noteWeights[i] * maxNote;
				shouldPlay = shouldPlayNote(wNote, wVolume);
				
				if (shouldPlay) {
					play(i, triggerTime * wNote * wVolume * 2, wVolume * triggerTime);
					volumeWeights[i] = noteWeights[i] = .0;
				} else {
					volumeWeights[i] *= (1 / 3);
					noteWeights[i] *=  (1 / 3);
				}
			}
		}
		
		var n = data.length;
		var i = offset; 
		var j = 0;
		
		while (i < n) {
			if (j < FlockData.X_DATA_POINTS) {
				volumeWeights[j] += data[i];
			} else {
				noteWeights[j - FlockData.X_DATA_POINTS] += data[i];
			}
			i++; j++;
		}
	}
	
	function noteTimeUpdate() {
		
		var time = .15 + .25 * Math.random();
		var duration = .25 + 180 * Math.random();
		
		t = cast Actuate
			.tween(this, duration, { triggerTime:time }, true, PositionAccessActuator)
			.ease(Sine.easeInOut)
			.onComplete(noteTimeUpdate);
	}
	
	
	function shouldPlayNote(noteWeight, volumeWeight) {
		if (volumeWeight > .0) {
			var p2 = t.position;
			p2 *= p2;
			if (Math.random() > p2) {
				return (noteWeight < .2 && noteWeight > .5) || (volumeWeight > .1 && volumeWeight < .3);
			} else if (Math.random() > p2) {
				return (noteWeight > .8 || noteWeight < .2) && (volumeWeight > .15 && volumeWeight < .25);
			}
		}
		return false;
	}
}


/**
 * Can't read position of a SimpleActuator tween by default... meh.
 */
@:final
class PositionAccessActuator extends SimpleActuator<SoundControl,Float> {
	
	public var position:Float = .0;	
	
	override function update(currentTime:Float):Void {
		position = (currentTime - timeOffset) / duration;
		super.update(currentTime);
	}
}