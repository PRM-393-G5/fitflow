import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/app_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/openai_service.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/workout_stats.dart';
import '../domain/adaptive_inference_scheduler.dart';
import '../domain/form_feedback.dart';
import '../domain/plank_analyzer.dart';
import '../domain/pose_frame.dart';
import '../domain/pushup_analyzer.dart';
import '../domain/squat_analyzer.dart';
import 'form_voice.dart';
import 'pose_overlay.dart';
import 'pose_render_model.dart';

class SquatFormCheckPage extends StatefulWidget {
  const SquatFormCheckPage({
    required this.controller,
    this.forSet,
    this.voice,
    super.key,
  });

  final AppController controller;

  /// Spoken cues; defaults to device text-to-speech.
  final FormVoice? voice;

  /// Set mode: opened from an active workout to count one set of this
  /// exercise. The exercise can't be switched, nothing is saved as a
  /// session, and the page pops with the counted reps (or hold seconds),
  /// or null when nothing was counted.
  final FormExercise? forSet;

  @override
  State<SquatFormCheckPage> createState() => _SquatFormCheckPageState();
}

/// What one exercise produced, captured in a single step so the saved
/// count always matches the reviewed reps.
typedef _FormResult = ({
  FormExercise exercise,
  int amount,
  List<RepRecord> records,
  HoldSummary? hold,
  DateTime? startedAt,
});

const _voicePreferenceKey = 'form_check_voice';

class _SquatFormCheckPageState extends State<SquatFormCheckPage>
    with WidgetsBindingObserver {
  late FormExercise _exercise = widget.forSet ?? FormExercise.squat;
  late RepAnalyzer _analyzer = _analyzerFor(_exercise);

  static RepAnalyzer _analyzerFor(FormExercise exercise) => switch (exercise) {
    FormExercise.squat => SquatAnalyzer(),
    FormExercise.pushup => PushupAnalyzer(),
    FormExercise.plank => PlankAnalyzer(),
  };
  final _detector = PoseDetector(
    options: PoseDetectorOptions(
      model: PoseDetectionModel.base,
      mode: PoseDetectionMode.stream,
    ),
  );
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  CameraDescription? _description;
  final _clock = Stopwatch()..start();
  final _scheduler = AdaptiveInferenceScheduler();
  final _poseModel = PoseRenderModel();
  late LiveFeedback _feedback = _feedbackFor(_exercise);

  static LiveFeedback _feedbackFor(FormExercise exercise) =>
      LiveFeedback(timed: exercise == FormExercise.plank);
  late final FormVoice _voice = widget.voice ?? TtsFormVoice();
  late bool _voiceOn =
      widget.controller.preferences.getBool(_voicePreferenceKey) ?? true;

  /// Set once the body is first tracked; hides the camera setup guide.
  bool _tracked = false;
  bool _setupDismissed = false;
  DateTime? _startedAt;
  bool _processing = false;
  int _droppedFrames = 0;
  int _inferenceCount = 0;
  int _telemetryStartedUs = 0;
  double _inferenceFps = 0;
  bool _showTelemetry = false;
  bool _paused = false;
  bool _reviewing = false;
  bool _switchingCamera = false;
  bool _initializing = true;
  bool _saving = false;
  bool _disposed = false;

  /// Set after a failed save so the next close leaves without saving
  /// instead of trapping the user behind `PopScope(canPop: false)`.
  bool _discardOnClose = false;

  /// The detector call in flight, so [dispose] can close the detector only
  /// once it has returned.
  Future<List<Pose>>? _inference;
  PermissionStatus? _permission;
  String? _error;

  /// Tail of the camera operation queue — see [_serialized].
  Future<void> _cameraQueue = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Landmark rotation and the cover-fit overlay assume an upright phone;
    // ML Kit's iOS rotation is derived from the sensor alone.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initialize();
  }

  Future<void> _initialize() async {
    final permission = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _permission = permission);
    if (!permission.isGranted) {
      setState(() => _initializing = false);
      return;
    }
    await _ensureCamera();
    if (mounted && _initializing) setState(() => _initializing = false);
  }

  void _retry() {
    setState(() {
      _error = null;
      _initializing = true;
    });
    _initialize();
  }

  /// Runs camera (re)configuration one at a time: a double tap on switch or
  /// a lifecycle resume overlapping a switch would otherwise open two
  /// controllers on one device. A failure releases the camera and shows a
  /// retryable error instead of an endless spinner.
  Future<void> _serialized(Future<void> Function() task) =>
      _cameraQueue = _cameraQueue.then((_) async {
        if (!mounted) return;
        try {
          await task();
        } catch (error) {
          try {
            await _closeCamera();
          } catch (_) {
            // Already broken; the error below is what the user needs.
          }
          if (mounted) {
            setState(() {
              _error = 'Không thể mở camera: $error';
              _initializing = false;
            });
          }
        }
      });

  /// Opens the camera unless one is already open, discovering cameras first
  /// when the page started without permission.
  Future<void> _ensureCamera() => _serialized(() async {
    if (_camera != null) return;
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('Không tìm thấy camera');
    }
    await _openCamera(
      _description ??
          _cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first,
          ),
    );
  });

  /// Only call inside [_serialized].
  Future<void> _closeCamera() async {
    final camera = _camera;
    if (camera == null) return;
    _camera = null;
    // Rebuild first so no CameraPreview holds the disposed controller.
    if (mounted) setState(() {});
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } finally {
      await camera.dispose();
    }
  }

  /// Only call inside [_serialized].
  Future<void> _openCamera(CameraDescription description) async {
    await _closeCamera();
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _description = description;
    _camera = controller;
    _startedAt ??= DateTime.now();
    _analyzer.pauseTiming();
    _poseModel.clear();
    // A pause (or open review) survives reopening after background/resume.
    if (!_paused && !_reviewing) {
      await controller.startImageStream(_processFrame);
    }
    if (mounted) {
      setState(() {
        _initializing = false;
        _error = null;
      });
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    // The stream can still deliver frames between dispose and the queued
    // camera teardown; the detector may already be closing by then.
    if (_disposed) return;
    final nowUs = _clock.elapsedMicroseconds;
    if (_paused ||
        _reviewing ||
        _processing ||
        !_scheduler.shouldStart(nowUs)) {
      _droppedFrames++;
      return;
    }
    final description = _description;
    final controller = _camera;
    if (description == null || controller == null) return;
    final input = _inputImage(
      image,
      description,
      controller.value.deviceOrientation,
    );
    if (input == null) return;
    _processing = true;
    _scheduler.markStarted(nowUs);
    final inferenceStartUs = _clock.elapsedMicroseconds;
    try {
      final inference = _detector.processImage(input);
      _inference = inference;
      final poses = await inference;
      if (_disposed || !mounted || _paused || _reviewing) return;
      final pose = poses.isEmpty ? null : poses.first;
      final frame = _poseFrame(input.metadata!);
      final points = pose == null
          ? <SquatJoint, SquatPoint>{}
          : _toAnalyzerPoints(pose, frame);
      final completedUs = _clock.elapsedMicroseconds;
      _scheduler.recordLatency(
        Duration(microseconds: completedUs - inferenceStartUs),
      );
      if (points.isEmpty) {
        _poseModel.clear();
      } else {
        _poseModel.update(points, completedUs, imageAspect: frame.aspectRatio);
      }
      _inferenceCount++;
      final telemetryWindowUs = completedUs - _telemetryStartedUs;
      if (telemetryWindowUs >= 1000000) {
        _inferenceFps = _inferenceCount * 1000000 / telemetryWindowUs;
        _inferenceCount = 0;
        _telemetryStartedUs = completedUs;
      }
      final next = _analyzer.analyze(points, timestampUs: completedUs);
      // Always fed, so turning voice on mid-set doesn't replay counts.
      final feedback = _feedback.update(next, completedUs);
      _poseModel.highlight = _feedback.shown!.faultJoints;
      if (feedback.say != null && _voiceOn) _voice.speak(feedback.say!);
      final tracked =
          _tracked ||
          (next.bodyVisible && next.phase != SquatPhase.findingBody);
      if (feedback.changed ||
          tracked != _tracked ||
          (_showTelemetry && telemetryWindowUs >= 1000000)) {
        setState(() => _tracked = tracked);
      }
    } catch (_) {
      // A transient native detector error drops this frame; never log hot-loop.
    } finally {
      _processing = false;
      _inference = null;
    }
  }

  InputImage? _inputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    const orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final sensor = camera.sensorOrientation;
    int rotationDegrees;
    if (Platform.isIOS) {
      // camera_avfoundation sets the stream connection's videoOrientation
      // to the (portrait-locked, see initState) device orientation, so BGRA
      // buffers arrive upright, and ML Kit's iOS bytes path ignores
      // `rotation` anyway (it builds an `.up` image from the raw buffer).
      // Landmarks are therefore in raw buffer space: pass 0 so [_poseFrame]
      // derives the upright size from what ML Kit actually used.
      rotationDegrees = 0;
    } else {
      final compensation = orientations[orientation];
      if (compensation == null) return null;
      rotationDegrees = camera.lensDirection == CameraLensDirection.front
          ? (sensor + compensation) % 360
          : (sensor - compensation + 360) % 360;
    }
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null || image.planes.length != 1) {
      return null;
    }
    if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
    if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// The upright image ML Kit reports landmarks in: the buffer rotated by
  /// the rotation passed to ML Kit (always 0 on iOS, see [_inputImage]).
  PoseFrame _poseFrame(InputImageMetadata metadata) {
    final rotated =
        metadata.rotation == InputImageRotation.rotation90deg ||
        metadata.rotation == InputImageRotation.rotation270deg;
    return PoseFrame(
      width: rotated ? metadata.size.height : metadata.size.width,
      height: rotated ? metadata.size.width : metadata.size.height,
    );
  }

  Map<SquatJoint, SquatPoint> _toAnalyzerPoints(Pose pose, PoseFrame frame) {
    const mapping = {
      SquatJoint.leftShoulder: PoseLandmarkType.leftShoulder,
      SquatJoint.rightShoulder: PoseLandmarkType.rightShoulder,
      SquatJoint.leftElbow: PoseLandmarkType.leftElbow,
      SquatJoint.rightElbow: PoseLandmarkType.rightElbow,
      SquatJoint.leftWrist: PoseLandmarkType.leftWrist,
      SquatJoint.rightWrist: PoseLandmarkType.rightWrist,
      SquatJoint.leftHip: PoseLandmarkType.leftHip,
      SquatJoint.rightHip: PoseLandmarkType.rightHip,
      SquatJoint.leftKnee: PoseLandmarkType.leftKnee,
      SquatJoint.rightKnee: PoseLandmarkType.rightKnee,
      SquatJoint.leftAnkle: PoseLandmarkType.leftAnkle,
      SquatJoint.rightAnkle: PoseLandmarkType.rightAnkle,
      SquatJoint.leftFoot: PoseLandmarkType.leftFootIndex,
      SquatJoint.rightFoot: PoseLandmarkType.rightFootIndex,
      SquatJoint.leftHeel: PoseLandmarkType.leftHeel,
      SquatJoint.rightHeel: PoseLandmarkType.rightHeel,
    };
    return {
      for (final entry in mapping.entries)
        if (pose.landmarks[entry.value] case final landmark?)
          entry.key: frame.point(
            landmark.x,
            landmark.y,
            confidence: landmark.likelihood,
          ),
    };
  }

  Future<void> _togglePause() => _serialized(() async {
    final paused = !_paused;
    final camera = _camera;
    _analyzer.pauseTiming();
    if (paused) {
      // Flag first so frames already in flight are ignored.
      setState(() => _paused = true);
      _voice.stop();
      if (camera != null && camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } else {
      if (camera != null && !camera.value.isStreamingImages) {
        await camera.startImageStream(_processFrame);
      }
      if (mounted) setState(() => _paused = false);
    }
  });

  Future<void> _switchCamera() async {
    if (_switchingCamera || _cameras.length < 2) return;
    setState(() => _switchingCamera = true);
    await _serialized(() async {
      final current = _description;
      if (current == null) return;
      final index = _cameras.indexOf(current);
      await _openCamera(_cameras[(index + 1) % _cameras.length]);
    });
    if (mounted) setState(() => _switchingCamera = false);
  }

  _FormResult _snapshot() {
    final analyzer = _analyzer;
    return (
      exercise: _exercise,
      amount: analyzer.repetitions,
      records: List.of(analyzer.repRecords),
      hold: analyzer is PlankAnalyzer ? analyzer.summary : null,
      startedAt: _startedAt,
    );
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    if (!_voiceOn) _voice.stop();
    widget.controller.preferences.setBool(_voicePreferenceKey, _voiceOn);
  }

  /// Persists [result] as a one-set session; empty results are dropped.
  Future<void> _saveSession(_FormResult result) async {
    final started = result.startedAt;
    if (started == null || result.amount == 0) return;
    final completed = DateTime.now();
    final exercise = result.exercise;
    final timed = exercise == FormExercise.plank;
    await widget.controller.addSession(
      WorkoutSession(
        id: 'form-${completed.microsecondsSinceEpoch}',
        workoutId: WorkoutStats.formCheckId,
        workoutName:
            '${exercise.label} Form Check (${result.amount}${timed ? 's' : ' reps'})',
        startedAt: started,
        completedAt: completed,
        // One tracked set; its reps (or hold seconds) live on the exercise.
        completedSets: 1,
        volumeKg: 0,
        exercises: [
          Exercise(
            id: exercise.name,
            name: exercise.label,
            muscleGroup: switch (exercise) {
              FormExercise.squat => 'Legs',
              FormExercise.pushup => 'Chest',
              FormExercise.plank => 'Core',
            },
            sets: 1,
            reps: timed ? 0 : result.amount,
            durationSeconds: timed ? result.amount : 0,
            performedSets: [SetEntry(amount: result.amount)],
          ),
        ],
      ),
    );
  }

  Future<void> _selectExercise(FormExercise exercise) async {
    if (exercise == _exercise || _saving) return;
    // Bank the current exercise as its own session instead of silently
    // discarding it; the new exercise starts counting from now.
    final result = _snapshot();
    setState(() {
      _exercise = exercise;
      _analyzer = _analyzerFor(exercise);
      _feedback = _feedbackFor(exercise);
      if (_startedAt != null) _startedAt = DateTime.now();
      _poseModel.clear();
      _tracked = _setupDismissed = false;
    });
    _voice.stop();
    if (result.amount == 0) return;
    try {
      await _saveSession(result);
    } catch (error) {
      if (!mounted) return;
      showFToast(
        context: context,
        title: Text('Không thể lưu ${result.exercise.label}: $error'),
      );
      return;
    }
    if (!mounted) return;
    final unit = result.exercise == FormExercise.plank ? 'giây' : 'rep';
    showFToast(
      context: context,
      title: Text('Đã lưu ${result.exercise.label}: ${result.amount} $unit'),
    );
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    if (_discardOnClose) {
      Navigator.of(context).pop();
      return;
    }
    // _saving must gate before the sheet: a second back/close tap while
    // the review is open would re-enter and double-pop the page.
    // _reviewing stops pose processing so the count can't move behind the
    // sheet after the snapshot.
    setState(() {
      _saving = true;
      _reviewing = true;
    });
    var saved = false;
    var amount = 0;
    try {
      _analyzer.pauseTiming();
      final result = _snapshot();
      _voice.stop();
      if (result.records.isNotEmpty || (result.hold?.trackedMs ?? 0) >= 3000) {
        await showFSheet<void>(
          context: context,
          side: .btt,
          mainAxisMaxRatio: .infinity,
          builder: (_) => _FormReviewSheet(
            exercise: result.exercise,
            records: result.records,
            hold: result.hold,
          ),
        );
        if (!mounted) return;
      }
      // In set mode the workout logs the count; no session of its own.
      if (widget.forSet == null) await _saveSession(result);
      amount = result.amount;
      saved = true;
    } catch (error) {
      if (!mounted) return;
      // Never trap the user: the next close leaves without saving.
      _discardOnClose = true;
      showFToast(
        context: context,
        title: Text('Không thể lưu buổi tập: $error'),
        description: const Text('Nhấn đóng lần nữa để thoát mà không lưu.'),
      );
    } finally {
      if (mounted && !saved) {
        setState(() {
          _saving = false;
          _reviewing = false;
        });
      }
    }
    if (saved && mounted) {
      Navigator.of(context)
          .pop(widget.forSet != null && amount > 0 ? amount : null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _analyzer.pauseTiming();
      _voice.stop();
      _serialized(_closeCamera);
    } else if (state == AppLifecycleState.resumed) {
      _resume();
    }
  }

  Future<void> _resume() async {
    // Re-query: the user may have granted the permission in Settings, which
    // a cached denied status would never notice.
    final permission = await Permission.camera.status;
    if (!mounted) return;
    setState(() => _permission = permission);
    if (permission.isGranted) await _ensureCamera();
  }

  /// Releases the camera, then the detector. Stopping the stream before
  /// disposing, and closing the detector only after any in-flight inference
  /// returns, guarantees no frame reaches a closed detector.
  Future<void> _teardown() async {
    final camera = _camera;
    _camera = null;
    try {
      if (camera != null) {
        try {
          if (camera.value.isStreamingImages) {
            await camera.stopImageStream();
          }
        } finally {
          await camera.dispose();
        }
      }
    } catch (_) {
      // The page is gone; nothing left to report the failure to.
    } finally {
      await _inference?.catchError((_) => <Pose>[]);
      await _detector.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    // Queued behind any in-flight open so that controller is released too.
    _cameraQueue.then((_) => _teardown());
    _voice.stop();
    _poseModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _saveAndClose();
    },
    child: FScaffold(
      childPad: false,
      child: ColoredBox(color: Colors.black, child: _buildBody()),
    ),
  );

  Widget _buildBody() {
    if (_initializing) return const Center(child: FCircularProgress.loader());
    final permission = _permission;
    if (permission != null && !permission.isGranted) {
      return _PermissionView(
        permanent: permission.isPermanentlyDenied || permission.isRestricted,
        retry: _initialize,
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FButton(onPress: _retry, child: const Text('Thử lại')),
              const SizedBox(height: 8),
              FButton(
                variant: .outline,
                onPress: _saveAndClose,
                child: const Text('Đóng'),
              ),
            ],
          ),
        ),
      );
    }
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: FCircularProgress.loader());
    }
    final analysis = _feedback.shown;
    final cue = _feedback.cue;
    // Android streams unmirrored frames under a mirrored front preview;
    // camera_avfoundation mirrors the front buffers themselves (preview and
    // stream alike), so iOS landmarks already match the preview.
    final mirrored =
        Platform.isAndroid &&
        _description?.lensDirection == CameraLensDirection.front;
    final previewSize = camera.value.previewSize!;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(camera),
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: PoseOverlay(
              model: _poseModel,
              mirrored: mirrored,
              // Same portrait box the preview is cover-fitted from above.
              previewAspect: previewSize.height / previewSize.width,
            ),
          ),
        ),
        SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: 8,
                right: 8,
                top: 4,
                child: Row(
                  children: [
                    _CamButton(
                      icon: widget.forSet == null
                          ? FLucideIcons.x
                          : FLucideIcons.check,
                      tooltip: widget.forSet == null ? 'Close' : 'Done',
                      onPress: _saveAndClose,
                    ),
                    const Spacer(),
                    FPopoverMenu.tiles(
                      menuBuilder: (context, controller, menu) => [
                        FTileGroup(
                          children: [
                            for (final mode in SquatPerformanceMode.values)
                              FTile(
                                title: Text(mode.name),
                                onPress: () {
                                  setState(() {
                                    _scheduler.mode = mode;
                                    _scheduler.reset();
                                  });
                                  controller.hide();
                                },
                              ),
                          ],
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          FLucideIcons.ellipsisVertical,
                          color: Colors.white,
                          semanticLabel: 'Chế độ hiệu năng',
                        ),
                      ),
                    ),
                    if (kDebugMode)
                      _CamButton(
                        icon: FLucideIcons.gauge,
                        tooltip: 'Telemetry',
                        onPress: () =>
                            setState(() => _showTelemetry = !_showTelemetry),
                      ),
                    _CamButton(
                      icon: _voiceOn
                          ? FLucideIcons.volume2
                          : FLucideIcons.volumeOff,
                      tooltip: _voiceOn ? 'Tắt giọng nói' : 'Bật giọng nói',
                      onPress: _toggleVoice,
                    ),
                    _CamButton(
                      icon: _paused ? FLucideIcons.play : FLucideIcons.pause,
                      tooltip: _paused ? 'Tiếp tục' : 'Tạm dừng',
                      onPress: _togglePause,
                    ),
                    if (_cameras.length > 1)
                      _CamButton(
                        icon: FLucideIcons.switchCamera,
                        tooltip: 'Đổi camera',
                        onPress: _switchingCamera ? null : _switchCamera,
                      ),
                  ],
                ),
              ),
              if (kDebugMode && _showTelemetry)
                Positioned(
                  top: 60,
                  left: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Preview 30 target  |  inference ${_inferenceFps.toStringAsFixed(1)} fps\n'
                        'latency ${_scheduler.latencyMs.toStringAsFixed(1)} ms  |  dropped $_droppedFrames',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC151515),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      children: [
                        if (widget.forSet != null)
                          Text(
                            _exercise.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          FPopoverMenu.tiles(
                            menuBuilder: (context, controller, menu) => [
                              FTileGroup(
                                children: [
                                  for (final item in FormExercise.values)
                                    FTile(
                                      title: Text(item.label),
                                      onPress: () {
                                        _selectExercise(item);
                                        controller.hide();
                                      },
                                    ),
                                ],
                              ),
                            ],
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _exercise.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Icon(
                                  FLucideIcons.chevronDown,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _Metric(
                              label: _analyzer.countLabel,
                              value: '${analysis?.repetitions ?? 0}',
                            ),
                            _Metric(
                              label: 'TRẠNG THÁI',
                              value: analysis?.phaseLabel ?? 'Khởi động',
                            ),
                            _Metric(
                              label: 'FORM',
                              value: analysis?.bodyVisible == true
                                  ? '${analysis!.score}'
                                  : '--',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          cue.cue ?? 'Đặt điện thoại để thấy toàn thân',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: switch (cue.tone) {
                              CueTone.warn => formWarningColor,
                              CueTone.good => const Color(0xFF62E6A5),
                              CueTone.info => Colors.white,
                            },
                            // Big enough to read from where the user
                            // trains, metres from the phone.
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_tracked && !_setupDismissed && !_paused)
                Positioned(
                  left: 20,
                  right: 20,
                  top: 72,
                  child: _SetupGuide(
                    exercise: _exercise,
                    onDismiss: () => setState(() => _setupDismissed = true),
                  ),
                ),
              if (_paused)
                const Center(
                  child: Text(
                    'Đã tạm dừng',
                    style: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.permanent, required this.retry});

  final bool permanent;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FLucideIcons.cameraOff, color: Colors.white, size: 64),
          const SizedBox(height: 16),
          const Text(
            'FitFlow cần quyền camera để phân tích tư thế ngay trên thiết bị.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          const SizedBox(height: 20),
          FButton(
            onPress: permanent ? openAppSettings : retry,
            child: Text(permanent ? 'Mở cài đặt' : 'Cho phép camera'),
          ),
        ],
      ),
    ),
  );
}

/// Camera placement for each exercise. The analyzers read joint angles in
/// 2D, so the angle to the camera decides whether reps count at all.
class _SetupGuide extends StatelessWidget {
  const _SetupGuide({required this.exercise, required this.onDismiss});

  final FormExercise exercise;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tips = switch (exercise) {
      FormExercise.squat => const [
        (FLucideIcons.smartphone, 'Đặt điện thoại ngang hông, cách 2–3 m'),
        (FLucideIcons.personStanding, 'Đứng nghiêng người về phía camera'),
        (FLucideIcons.scanEye, 'Thấy trọn người từ đầu đến chân'),
      ],
      FormExercise.pushup || FormExercise.plank => [
        (FLucideIcons.smartphone, 'Đặt điện thoại sát sàn, cách 2–3 m'),
        (
          FLucideIcons.personStanding,
          exercise == FormExercise.plank
              ? 'Nằm ngang khung hình, khuỷu tay dưới vai'
              : 'Nằm ngang khung hình, nghiêng về phía camera',
        ),
        (FLucideIcons.scanEye, 'Thấy trọn người từ đầu đến chân'),
      ],
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6151515),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Đặt camera cho ${exercise.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _CamButton(
                  icon: FLucideIcons.x,
                  tooltip: 'Ẩn hướng dẫn',
                  onPress: onDismiss,
                ),
              ],
            ),
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: Row(
                  children: [
                    Icon(icon, color: const Color(0xFF62E6A5), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 10, right: 12),
              child: Text(
                'Tự ẩn khi đã nhận diện được bạn.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _faultLabel(String code) => switch (code) {
  'shallowDepth' => 'Shallow depth',
  'kneeValgus' => 'Knees caved in',
  'forwardLean' => 'Leaning forward',
  'heelsUp' => 'Heels lifted',
  'asymmetry' => 'Uneven sides',
  'fastEccentric' => 'Dropped too fast',
  'hipSag' => 'Hips sagging',
  'hipPike' => 'Hips too high',
  _ => code,
};

String _seconds(int ms) => '${(ms / 1000).round()}s';

/// Post-set review: per-rep telemetry (or a plank's hold breakdown) plus
/// an optional AI coach verdict (gpt-6-luna on the same telemetry).
class _FormReviewSheet extends StatefulWidget {
  const _FormReviewSheet({
    required this.exercise,
    required this.records,
    this.hold,
  });

  final FormExercise exercise;
  final List<RepRecord> records;
  final HoldSummary? hold;

  @override
  State<_FormReviewSheet> createState() => _FormReviewSheetState();
}

class _FormReviewSheetState extends State<_FormReviewSheet> {
  final _service = const OpenAiService();
  String? _summary;
  List<String> _tips = const [];
  bool _loading = false;

  Future<void> _aiReview() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final json = await _service.generateJson(
        system: AiFormReviewPrompt.system,
        user: AiFormReviewPrompt.user(
          exercise: widget.exercise.label,
          reps: widget.records,
          hold: widget.hold?.toJson(),
        ),
        schema: AiFormReviewPrompt.schema,
        schemaName: 'form_review',
      );
      if (!mounted) return;
      setState(() {
        _summary = json['summary'] as String?;
        _tips = [for (final tip in json['tips'] as List? ?? const []) '$tip'];
        _loading = false;
      });
    } on OpenAiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFToast(context: context, title: Text(e.message));
    } catch (_) {
      // Unexpected response shape — strict schema should prevent this.
      if (!mounted) return;
      setState(() => _loading = false);
      showFToast(
        context: context,
        title: const Text('Could not review — try again.'),
      );
    }
  }

  Widget _faults(Iterable<String> labels) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final label in labels)
        FBadge(variant: .destructive, child: Text(label)),
    ],
  );

  List<Widget> _holdBody(BuildContext context, HoldSummary hold) => [
    Text(
      '${_seconds(hold.goodMs)} in good form',
      style: Theme.of(context).textTheme.titleSmall,
    ),
    const SizedBox(height: AppSpacing.xs),
    if (hold.sagMs < 1000 && hold.pikeMs < 1000)
      Text('Clean hold', style: Theme.of(context).textTheme.bodySmall)
    else
      _faults([
        if (hold.sagMs >= 1000)
          '${_faultLabel('hipSag')} · ${_seconds(hold.sagMs)}',
        if (hold.pikeMs >= 1000)
          '${_faultLabel('hipPike')} · ${_seconds(hold.pikeMs)}',
      ]),
    const SizedBox(height: AppSpacing.sm),
  ];

  Widget _rep(BuildContext context, RepRecord rep) {
    final squat = widget.exercise == FormExercise.squat;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              'Rep ${rep.number}',
              // Push-up depth also uses the shoulder drop, so the elbow
              // angle alone would mislead with flared elbows.
              if (squat) '${rep.minKneeAngle.round()}° depth',
              if (rep.descentMs > 0) '↓${rep.descentMs}ms ↑${rep.ascentMs}ms',
            ].join(' · '),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (rep.faults.isEmpty)
            Text('Clean rep', style: Theme.of(context).textTheme.bodySmall)
          else
            _faults(rep.faults.map(_faultLabel)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hold = widget.hold;
    final clean = widget.records.where((rep) => rep.faults.isEmpty).length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.exercise.label} — form review',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    hold != null
                        ? '${_seconds(hold.goodMs)}/${_seconds(hold.trackedMs)} good'
                        : '$clean/${widget.records.length} clean reps',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (hold != null)
                ..._holdBody(context, hold)
              else
                ...widget.records.map((rep) => _rep(context, rep)),
              if (OpenAiService.configured) ...[
                const SizedBox(height: AppSpacing.sm),
                if (_summary == null)
                  FButton(
                    key: const Key('form-review-ai'),
                    variant: .secondary,
                    onPress: _aiReview,
                    prefix: _loading
                        ? const FCircularProgress()
                        : const Icon(FLucideIcons.sparkles),
                    child: Text(_loading ? 'Reviewing…' : 'AI coach review'),
                  )
                else ...[
                  Text(
                    _summary!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  for (final tip in _tips)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text('• $tip'),
                    ),
                ],
              ],
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: FButton(
                  key: const Key('form-review-done'),
                  onPress: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White icon button for the camera overlay — Forui ghost buttons would
/// render with theme foreground, which is unreadable on the black preview.
class _CamButton extends StatelessWidget {
  const _CamButton({
    required this.icon,
    required this.tooltip,
    required this.onPress,
  });

  final IconData icon;
  final String tooltip;

  /// Null disables the button (dimmed).
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) => FTappable(
    onPress: onPress,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(
        icon,
        color: onPress == null ? Colors.white38 : Colors.white,
        semanticLabel: tooltip,
      ),
    ),
  );
}
