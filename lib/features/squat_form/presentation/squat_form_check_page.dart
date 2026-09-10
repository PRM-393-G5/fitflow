import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/app_controller.dart';
import '../../../domain/models/workout_session.dart';
import '../domain/adaptive_inference_scheduler.dart';
import '../domain/plank_analyzer.dart';
import '../domain/pushup_analyzer.dart';
import '../domain/squat_analyzer.dart';
import 'pose_overlay.dart';
import 'pose_render_model.dart';

class SquatFormCheckPage extends StatefulWidget {
  const SquatFormCheckPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<SquatFormCheckPage> createState() => _SquatFormCheckPageState();
}

class _SquatFormCheckPageState extends State<SquatFormCheckPage>
    with WidgetsBindingObserver {
  FormExercise _exercise = FormExercise.squat;
  RepAnalyzer _analyzer = SquatAnalyzer();
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
  SquatAnalysis? _analysis;
  DateTime? _startedAt;
  bool _processing = false;
  int _droppedFrames = 0;
  int _inferenceCount = 0;
  int _telemetryStartedUs = 0;
  double _inferenceFps = 0;
  bool _showTelemetry = false;
  bool _paused = false;
  bool _initializing = true;
  bool _saving = false;
  PermissionStatus? _permission;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('Không tìm thấy camera');
      final selected = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      await _openCamera(selected);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Không thể mở camera: $error';
          _initializing = false;
        });
      }
    }
  }

  Future<void> _openCamera(CameraDescription description) async {
    final old = _camera;
    _camera = null;
    if (old != null) {
      if (old.value.isStreamingImages) await old.stopImageStream();
      await old.dispose();
    }
    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    _description = description;
    _camera = controller;
    _startedAt ??= DateTime.now();
    await controller.startImageStream(_processFrame);
    if (mounted) {
      setState(() {
        _initializing = false;
        _error = null;
        _paused = false;
      });
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    final nowUs = _clock.elapsedMicroseconds;
    if (_paused || _processing || !_scheduler.shouldStart(nowUs)) {
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
      final poses = await _detector.processImage(input);
      if (!mounted || _paused) return;
      final pose = poses.isEmpty ? null : poses.first;
      final normalized = pose == null
          ? null
          : _normalize(pose, input.metadata!);
      final points = normalized == null
          ? <SquatJoint, SquatPoint>{}
          : _toAnalyzerPoints(normalized);
      final completedUs = _clock.elapsedMicroseconds;
      _scheduler.recordLatency(
        Duration(microseconds: completedUs - inferenceStartUs),
      );
      if (points.isEmpty) {
        _poseModel.clear();
      } else {
        _poseModel.update(points, completedUs);
      }
      _inferenceCount++;
      final telemetryWindowUs = completedUs - _telemetryStartedUs;
      if (telemetryWindowUs >= 1000000) {
        _inferenceFps = _inferenceCount * 1000000 / telemetryWindowUs;
        _inferenceCount = 0;
        _telemetryStartedUs = completedUs;
      }
      final next = _analyzer.analyze(points, timestampUs: completedUs);
      final previous = _analysis;
      if (previous == null ||
          previous.phase != next.phase ||
          previous.repetitions != next.repetitions ||
          previous.cue != next.cue ||
          (previous.score - next.score).abs() >= 5 ||
          (_showTelemetry && telemetryWindowUs >= 1000000)) {
        setState(() => _analysis = next);
      } else {
        _analysis = next;
      }
    } catch (_) {
      // A transient native detector error drops this frame; never log hot-loop.
    } finally {
      _processing = false;
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
      rotationDegrees = sensor;
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

  Pose _normalize(Pose pose, InputImageMetadata metadata) {
    final rotated =
        metadata.rotation == InputImageRotation.rotation90deg ||
        metadata.rotation == InputImageRotation.rotation270deg;
    final width = rotated ? metadata.size.height : metadata.size.width;
    final height = rotated ? metadata.size.width : metadata.size.height;
    return Pose(
      landmarks: pose.landmarks.map(
        (type, point) => MapEntry(
          type,
          PoseLandmark(
            type: type,
            x: point.x / width,
            y: point.y / height,
            z: point.z / width,
            likelihood: point.likelihood,
          ),
        ),
      ),
    );
  }

  Map<SquatJoint, SquatPoint> _toAnalyzerPoints(Pose pose) {
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
    };
    return {
      for (final entry in mapping.entries)
        if (pose.landmarks[entry.value] case final landmark?)
          entry.key: SquatPoint(
            landmark.x,
            landmark.y,
            confidence: landmark.likelihood,
          ),
    };
  }

  Future<void> _togglePause() async {
    final camera = _camera;
    if (camera == null) return;
    if (_paused) {
      await camera.startImageStream(_processFrame);
    } else if (camera.value.isStreamingImages) {
      await camera.stopImageStream();
    }
    if (mounted) setState(() => _paused = !_paused);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _description == null) return;
    final current = _cameras.indexOf(_description!);
    await _openCamera(_cameras[(current + 1) % _cameras.length]);
  }

  void _selectExercise(FormExercise exercise) {
    if (exercise == _exercise) return;
    setState(() {
      _exercise = exercise;
      _analyzer = switch (exercise) {
        FormExercise.squat => SquatAnalyzer(),
        FormExercise.pushup => PushupAnalyzer(),
        FormExercise.plank => PlankAnalyzer(),
      };
      _analysis = null;
      _poseModel.clear();
    });
  }

  Future<void> _saveAndClose() async {
    final started = _startedAt;
    if (started == null || _saving) {
      if (mounted && !_saving) Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final completed = DateTime.now();
    await widget.controller.addSession(
      WorkoutSession(
        id: 'form-${completed.microsecondsSinceEpoch}',
        workoutId: 'form-check',
        workoutName:
            '${_exercise.label} Form Check (${_analyzer.repetitions}${_exercise == FormExercise.plank ? 's' : ' reps'})',
        startedAt: started,
        completedAt: completed,
        completedSets: _analyzer.repetitions,
        volumeKg: 0,
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final camera = _camera;
      _camera = null;
      camera?.dispose();
    } else if (state == AppLifecycleState.resumed &&
        _permission?.isGranted == true) {
      final description = _description;
      if (description != null) _openCamera(description);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _detector.close();
    _poseModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _saveAndClose();
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: _buildBody(),
    ),
  );

  Widget _buildBody() {
    if (_initializing) return const Center(child: CircularProgressIndicator());
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
          child: Text(_error!, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final analysis = _analysis;
    final mirrored = _description?.lensDirection == CameraLensDirection.front;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: camera.value.previewSize!.height,
              height: camera.value.previewSize!.width,
              child: CameraPreview(camera),
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: PoseOverlay(model: _poseModel, mirrored: mirrored),
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
                    IconButton(
                      onPressed: _saveAndClose,
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                    ),
                    const Spacer(),
                    PopupMenuButton<SquatPerformanceMode>(
                      initialValue: _scheduler.mode,
                      tooltip: 'Chế độ hiệu năng',
                      iconColor: Colors.white,
                      onSelected: (mode) => setState(() {
                        _scheduler.mode = mode;
                        _scheduler.reset();
                      }),
                      itemBuilder: (_) => SquatPerformanceMode.values
                          .map(
                            (mode) => PopupMenuItem(
                              value: mode,
                              child: Text(mode.name),
                            ),
                          )
                          .toList(),
                    ),
                    if (kDebugMode)
                      IconButton(
                        tooltip: 'Telemetry',
                        onPressed: () =>
                            setState(() => _showTelemetry = !_showTelemetry),
                        color: Colors.white,
                        icon: const Icon(Icons.speed),
                      ),
                    IconButton(
                      tooltip: _paused ? 'Tiếp tục' : 'Tạm dừng',
                      onPressed: _togglePause,
                      color: Colors.white,
                      icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                    ),
                    if (_cameras.length > 1)
                      IconButton(
                        tooltip: 'Đổi camera',
                        onPressed: _switchCamera,
                        color: Colors.white,
                        icon: const Icon(Icons.cameraswitch),
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
                        PopupMenuButton<FormExercise>(
                          initialValue: _exercise,
                          onSelected: _selectExercise,
                          itemBuilder: (_) => FormExercise.values
                              .map(
                                (item) => PopupMenuItem(
                                  value: item,
                                  child: Text(item.label),
                                ),
                              )
                              .toList(),
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
                                Icons.arrow_drop_down,
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
                          analysis?.cue ?? 'Đặt điện thoại để thấy toàn thân',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF62E6A5),
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'FitFlow cần quyền camera để phân tích tư thế ngay trên thiết bị.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: permanent ? openAppSettings : retry,
            child: Text(permanent ? 'Mở cài đặt' : 'Cho phép camera'),
          ),
        ],
      ),
    ),
  );
}
