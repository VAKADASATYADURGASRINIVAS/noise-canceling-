import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class AiNoiseProcessor {
  
  Future<void> loadModel() async {
    debugPrint('Double-Pass Audio Engine Ready!');
  }

  Future<String?> removeNoise(String inputFilePath) async {
    try {
      debugPrint("Starting Deep Clean Noise Annihilation...");
      
      final directory = await getApplicationDocumentsDirectory();
      final outputPath = '${directory.path}/Cleaned_Voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      if (File(outputPath).existsSync()) {
        File(outputPath).deleteSync();
      }

      // THE DOUBLE-PASS DEEP CLEAN ENGINE:
      // 1. highpass=f=120: Cuts deeper rumbles that mask the voice.
      // 2. lowpass=f=6500: Slices off high-pitched hiss.
      // 3. afftdn (Pass 1): Peels off the first 25dB of background noise smoothly.
      // 4. afftdn (Pass 2): Deep-scrubs another 25dB out of the audio (cleans the noise mixed WITH your voice).
      // 5. agate: Snaps the microphone shut instantly when you stop speaking.
      // 6. dynaudnorm: Smooths and boosts the cleaned voice to studio volume.
      final String ffmpegCommand = '-i "$inputFilePath" -af "highpass=f=120,lowpass=f=6500,afftdn=nr=25:nf=-40,afftdn=nr=25:nf=-40,agate=threshold=0.04:ratio=4:attack=10:release=250,dynaudnorm=p=0.9" -ar 44100 -c:a pcm_s16le "$outputPath"';

      debugPrint("Executing Deep Clean Engine: $ffmpegCommand");

      final session = await FFmpegKit.execute(ffmpegCommand);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint("Audio perfectly isolated and normalized!");
        return outputPath;
      } else {
        final logs = await session.getLogs();
        for (var log in logs) {
          debugPrint("FFmpeg Error: ${log.getMessage()}");
        }
        return null;
      }
    } catch (e) {
      debugPrint("Fatal error processing audio: $e");
      return null;
    }
  }

  void dispose() {}
}