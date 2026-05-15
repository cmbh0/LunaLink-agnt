import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../services/app_state.dart';
import '../theme/moon_theme.dart';

class FileViewerScreen extends StatefulWidget {
  final AppState state;
  final String path;
  const FileViewerScreen({super.key, required this.state, required this.path});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  String? text;
  bool editable = false;
  late final TextEditingController controller;
  File? localMedia;
  AudioPlayer? audio;
  VideoPlayerController? video;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    controller.dispose();
    audio?.dispose();
    video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bytes = await widget.state.ssh.readFile(widget.path);
    final name = widget.path.toLowerCase();
    if (_isImage(name)) {
      setState(() => text = '__IMAGE__${base64Encode(bytes)}');
    } else if (_isAudio(name)) {
      localMedia = await _cache(bytes);
      audio = AudioPlayer();
      setState(() => text = '__AUDIO__');
    } else if (_isVideo(name)) {
      localMedia = await _cache(bytes);
      video = VideoPlayerController.file(localMedia!);
      await video!.initialize();
      setState(() => text = '__VIDEO__');
    } else {
      controller.text = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        text = controller.text;
        editable = true;
      });
    }
  }

  Future<File> _cache(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, p.basename(widget.path)));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _save() async {
    await widget.state.ssh.writeFile(widget.path, utf8.encode(controller.text));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final value = text;
    return Scaffold(
      appBar: AppBar(title: Text(widget.path.split('/').last), actions: [if (editable) IconButton(onPressed: _save, icon: const Icon(Icons.save_rounded))]),
      body: value == null ? const Center(child: CircularProgressIndicator()) : Padding(padding: const EdgeInsets.all(12), child: _body(value)),
    );
  }

  Widget _body(String value) {
    if (value.startsWith('__IMAGE__')) {
      return InteractiveViewer(child: Center(child: Image.memory(base64Decode(value.substring(9)))));
    }
    if (value == '__AUDIO__') {
      return Center(child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.music_note_rounded, size: 72, color: MoonColors.accent),
        Text(p.basename(widget.path)),
        const SizedBox(height: 14),
        Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.icon(onPressed: () => audio?.play(DeviceFileSource(localMedia!.path)), icon: const Icon(Icons.play_arrow_rounded), label: const Text('播放')),
          const SizedBox(width: 10),
          OutlinedButton.icon(onPressed: () => audio?.pause(), icon: const Icon(Icons.pause_rounded), label: const Text('暂停')),
        ]),
      ]))));
    }
    if (value == '__VIDEO__') {
      return Column(children: [
        Expanded(child: Center(child: AspectRatio(aspectRatio: video!.value.aspectRatio, child: VideoPlayer(video!)))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          FilledButton.icon(onPressed: () { video!.value.isPlaying ? video!.pause() : video!.play(); setState(() {}); }, icon: Icon(video!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded), label: Text(video!.value.isPlaying ? '暂停' : '播放')),
        ]),
      ]);
    }
    return TextField(controller: controller, readOnly: !editable, maxLines: null, style: const TextStyle(fontFamily: 'monospace', color: MoonColors.text), decoration: const InputDecoration(border: InputBorder.none));
  }
}

bool _isImage(String n) => n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg') || n.endsWith('.webp') || n.endsWith('.gif');
bool _isAudio(String n) => n.endsWith('.mp3') || n.endsWith('.wav') || n.endsWith('.m4a') || n.endsWith('.flac');
bool _isVideo(String n) => n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.mkv') || n.endsWith('.webm');
