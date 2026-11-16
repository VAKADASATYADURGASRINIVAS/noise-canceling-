import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ai_noise_processor.dart';

void main() {
  runApp(const PureVoiceApp());
}

class PureVoiceApp extends StatelessWidget {
  const PureVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PureVoice AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090E),
        fontFamily: 'Roboto',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RecorderController _recorderController;
  late final AudioPlayer _audioPlayer;
  late final AiNoiseProcessor _aiProcessor;
  
  int _currentIndex = 1; 
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isProcessing = false;
  
  String? _noisyFilePath;
  String? _pureFilePath;
  String _selectedFormat = '.wav';
  final List<String> _exportFormats = ['.wav', '.mp3', '.m4a'];
  
  List<FileSystemEntity> _historyFiles = [];
  String? _currentlyPlayingHistoryPath;

  Timer? _timer;
  int _recordDuration = 0;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _aiProcessor = AiNoiseProcessor();
    _recorderController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 44100;

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentlyPlayingHistoryPath = null;
        });
      }
    });

    _aiProcessor.loadModel();
    _loadHistory();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorderController.dispose();
    _audioPlayer.dispose();
    _aiProcessor.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final directory = await getApplicationDocumentsDirectory();
    setState(() {
      _historyFiles = directory.listSync().where((file) => file.path.contains('Cleaned_Voice_')).toList();
      _historyFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    });
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorderController.checkPermission();
    if (!hasPermission) {
      await Permission.microphone.request();
      return; 
    }

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/recorded_noisy.m4a';
    
    await _recorderController.record(path: path);
    
    setState(() {
      _isRecording = true;
      _recordDuration = 0;
      _noisyFilePath = null;
      _pureFilePath = null;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (mounted) setState(() => _recordDuration++);
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorderController.stop();
    
    setState(() {
      _isRecording = false;
      _noisyFilePath = path;
    });

    if (path != null) {
      _processAudio();
    }
  }

  String get _formattedTime {
    final minutes = (_recordDuration ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordDuration % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _uploadAudio() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _noisyFilePath = result.files.single.path;
        _pureFilePath = null;
      });
      _processAudio();
    }
  }

  Future<void> _processAudio() async {
    if (_noisyFilePath == null) return;
    setState(() => _isProcessing = true);

    String? cleanedPath = await _aiProcessor.removeNoise(_noisyFilePath!);

    setState(() {
      _pureFilePath = cleanedPath;
      _isProcessing = false;
    });
    
    _loadHistory();
  }

  Future<void> _togglePlay() async {
    if (_pureFilePath == null) return;

    if (_isPlaying && _currentlyPlayingHistoryPath == null) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(_pureFilePath!));
      setState(() {
        _isPlaying = true;
        _currentlyPlayingHistoryPath = null;
      });
    }
  }

  Future<void> _playHistoryFile(String path) async {
    if (_isPlaying && _currentlyPlayingHistoryPath == path) {
      await _audioPlayer.stop();
      setState(() {
        _isPlaying = false;
        _currentlyPlayingHistoryPath = null;
      });
    } else {
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(path));
      setState(() {
        _isPlaying = true;
        _currentlyPlayingHistoryPath = path;
      });
    }
  }

  Future<void> _saveAudioFile(String sourcePath, {String? customFormat}) async {
    try {
      Directory? downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) downloadsDir = await getExternalStorageDirectory();

      final extension = customFormat ?? '.m4a'; 
      final fileName = 'PureVoice_Cleaned_${DateTime.now().millisecondsSinceEpoch}$extension';
      final savePath = '${downloadsDir!.path}/$fileName';
      
      await File(sourcePath).copy(savePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to Downloads:\n$fileName'), backgroundColor: const Color(0xFF10B981)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save file.'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PureVoice AI', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2, color: Colors.white, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF11111A),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.grey.shade600,
        elevation: 20,
        currentIndex: _currentIndex,
        onTap: (index) {
          if (!_isRecording && !_isProcessing) {
            setState(() => _currentIndex = index);
            if (index == 2) _loadHistory();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.cloud_upload_outlined), activeIcon: Icon(Icons.cloud_upload), label: 'Upload'),
          BottomNavigationBarItem(icon: Icon(Icons.mic_none), activeIcon: Icon(Icons.mic), label: 'Record'),
          BottomNavigationBarItem(icon: Icon(Icons.history), activeIcon: Icon(Icons.history_toggle_off), label: 'History'),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: _isProcessing
                    ? _buildProcessingView()
                    : _currentIndex == 0
                        ? _buildUploadView()
                        : _currentIndex == 1
                            ? _buildRecordView()
                            : _buildHistoryView(),
              ),
            ),
            if (_pureFilePath != null && !_isProcessing && _currentIndex != 2) _buildResultCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _formattedTime,
          style: TextStyle(
            fontSize: 84,
            fontWeight: FontWeight.w200,
            color: _isRecording ? const Color(0xFFF43F5E) : Colors.white, 
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          height: 100,
          child: _isRecording 
            ? AudioWaveforms(
                size: Size(MediaQuery.of(context).size.width * 0.8, 100),
                recorderController: _recorderController,
                enableGesture: false,
                waveStyle: WaveStyle(
                  waveColor: const Color(0xFF00E5FF),
                  showDurationLabel: false,
                  spacing: 8.0,
                  showBottom: false,
                  extendWaveform: false,
                  showMiddleLine: false,
                  gradient: ui.Gradient.linear(
                    const Offset(0, 0),
                    const Offset(200, 0),
                    [const Color(0xFF00E5FF), const Color(0xFF6366F1)],
                  ),
                ),
              )
            : const Center(child: Text("Ready to record", style: TextStyle(color: Colors.white38, fontSize: 16))),
        ),
        const SizedBox(height: 60),
        GestureDetector(
          onTap: _isRecording ? _stopRecording : _startRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 90,
            width: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording ? const Color(0xFFF43F5E).withOpacity(0.1) : const Color(0xFF00E5FF).withOpacity(0.05),
              border: Border.all(
                color: _isRecording ? const Color(0xFFF43F5E) : const Color(0xFF00E5FF), 
                width: 2,
              ),
              boxShadow: [
                if (_isRecording)
                  BoxShadow(color: const Color(0xFFF43F5E).withOpacity(0.3), blurRadius: 40, spreadRadius: 5)
              ]
            ),
            child: Icon(
              _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 40,
              color: _isRecording ? const Color(0xFFF43F5E) : const Color(0xFF00E5FF),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        CircularProgressIndicator(color: Color(0xFF00E5FF), strokeWidth: 2),
        SizedBox(height: 30),
        Text("Isolating Voice...", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        Text("Running advanced FFT filters", style: TextStyle(fontSize: 14, color: Colors.white54)),
      ],
    );
  }

  Widget _buildUploadView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.audio_file_outlined, size: 80, color: const Color(0xFF00E5FF).withOpacity(0.7)),
          const SizedBox(height: 30),
          const Text("Clean Existing Audio", style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          const Text("Select a noisy voice recording from your files to digitally isolate the vocals.", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.white54, height: 1.5)),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            ),
            onPressed: _uploadAudio,
            child: const Text("Select File", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    if (_historyFiles.isEmpty) {
      return const Center(child: Text("No recordings saved yet.", style: TextStyle(color: Colors.white38, fontSize: 16)));
    }
    return ListView.builder(
      itemCount: _historyFiles.length,
      padding: const EdgeInsets.all(20),
      itemBuilder: (context, index) {
        final file = _historyFiles[index];
        final isPlayingThis = _isPlaying && _currentlyPlayingHistoryPath == file.path;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF151520),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: IconButton(
              icon: Icon(isPlayingThis ? Icons.pause_circle_filled : Icons.play_circle_fill, color: const Color(0xFF00E5FF), size: 36),
              onPressed: () => _playHistoryFile(file.path),
            ),
            title: Text(file.path.split('/').last, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.download_rounded, color: Colors.white54), onPressed: () => _saveAudioFile(file.path)),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white38),
                  onPressed: () { file.deleteSync(); _loadHistory(); },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResultCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF151520),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const Text("Cleaned Audio Ready", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: Colors.white54)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 42,
                icon: Icon(_isPlaying && _currentlyPlayingHistoryPath == null ? Icons.pause_circle_filled : Icons.play_circle_fill, color: const Color(0xFF00E5FF)),
                onPressed: _togglePlay,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedFormat,
                    dropdownColor: const Color(0xFF151520),
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    items: _exportFormats.map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase()))).toList(),
                    onChanged: (val) => setState(() => _selectedFormat = val!),
                  ),
                ),
              ),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.save_alt_rounded, color: Color(0xFF10B981)),
                onPressed: () => _saveAudioFile(_pureFilePath!, customFormat: _selectedFormat),
              ),
            ],
          ),
        ],
      ),
    );
  }
}