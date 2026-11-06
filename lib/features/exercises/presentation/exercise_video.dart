import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/exercise.dart';

/// Bundled asset path for an exercise demo (`asset:videos/x.mp4` → `assets/videos/x.mp4`), or null.
String? demoAssetPath(Exercise e) {
  final url = e.mediaUrl;
  if (url == null || !url.startsWith('asset:')) return null;
  return 'assets/${url.substring(6)}';
}

/// Looping, muted exercise demonstration. Tap to pause/play.
class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({super.key, required this.assetPath, this.maxHeight = 560});
  final String assetPath;
  final double maxHeight;

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.asset(widget.assetPath, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c.initialize().then((_) async {
      await _c.setLooping(true);
      await _c.setVolume(0);
      await _c.play();
      if (mounted) setState(() => _ready = true);
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ratio = 720 / 1280;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Gaps.radius),
            child: ColoredBox(
              color: AppColors.surface,
              child: _failed
                  ? const Center(child: Text('Demo unavailable', style: TextStyle(color: AppColors.textMuted)))
                  : !_ready
                      ? const Center(child: CircularProgressIndicator())
                      : GestureDetector(
                          onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
                          child: Stack(fit: StackFit.expand, children: [
                            VideoPlayer(_c),
                            if (!_c.value.isPlaying)
                              const Center(
                                child: CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
                                ),
                              ),
                          ]),
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the demo, used from the workout logger.
Future<void> showExerciseDemo(BuildContext context, Exercise e) {
  final path = demoAssetPath(e);
  if (path == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(e.name, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: Gaps.md),
          ExerciseVideo(assetPath: path, maxHeight: MediaQuery.sizeOf(ctx).height * 0.72),
        ]),
      ),
    ),
  );
}
