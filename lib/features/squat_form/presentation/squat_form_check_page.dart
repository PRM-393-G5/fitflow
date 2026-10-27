import 'dart:async';
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
import '../../../core/widgets/app_sheet.dart';
import '../../../data/openai_service.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/workout_stats.dart';
import '../../../domain/models/form_result.dart';
import '../domain/adaptive_inference_scheduler.dart';
import '../domain/form_feedback.dart';
import '../domain/form_record.dart';
import '../domain/hands_free_session.dart';
import '../domain/plank_analyzer.dart';
import '../domain/pose_frame.dart';
import '../domain/pushup_analyzer.dart';
import '../domain/shoulder_press_analyzer.dart';
import '../domain/curl_analyzer.dart';
import '../domain/dip_analyzer.dart';
import '../domain/triceps_extension_analyzer.dart';
import '../domain/squat_analyzer.dart';
import 'form_review_view.dart';
import 'form_voice.dart';
import 'pose_overlay.dart';
import 'pose_render_model.dart';

class SquatFormCheckPage extends StatefulWidget {
  const SquatFormCheckPage({
    required this.controller,
    this.forSet,
    this.plan,
    this.voice,
    super.key,
  }) : assert(forSet == null || plan == null);

  final AppController controller;

  /// Spoken cues; defaults to device text-to-speech.
  final FormVoice? voice;

  /// Set mode: opened from an active workout to count one set of this
  /// exercise. The exercise can't be switched, nothing is saved as a
  /// session, and the page pops with a [FormSetOutcome] (the counted reps
  /// or hold seconds, and the form verdict to log with the set), or null
  /// when nothing was counted.
  final FormExercise? forSet;

  /// Hands-free mode: runs these sets back to back without a tap (see
  /// [HandsFreeSession]), resting and switching exercise in between.
  /// Nothing is saved as a session; the page pops with the
  /// [FormSetOutcome] of each finished set, in plan order (fewer than
  /// planned when the user stops early).
  final List<PlannedSet>? plan;

  @override
  State<SquatFormCheckPage> createState() => _SquatFormCheckPageState();
}

/// What set mode hands back to the workout.
typedef FormSetOutcome = ({int amount, FormResult? form});

/// What one exercise produced, captured in a single step so the saved
/// count always matches the reviewed reps.
typedef _SetSnapshot = ({
  FormExercise exercise,
  int amount,
  List<RepRecord> records,
  HoldSummary? hold,

  /// The verdict shown in the review and saved with the set; null when too
  /// little was judged to review (no reps, or a hold under 3 s).
  FormResult? form,
  DateTime? startedAt,
});

const _voicePreferenceKey = 'form_check_voice';

class _SquatFormCheckPageState extends State<SquatFormCheckPage>
    with WidgetsBindingObserver {
  late final HandsFreeSession? _session = widget.plan == null
      ? null
      : HandsFreeSession(widget.plan!);
  late FormExercise _exercise =
      widget.plan?.first.exercise ?? widget.forSet ?? FormExercise.squat;

  /// Hands-free sets finished so far.
  final _outcomes = <FormSetOutcome>[];
  Timer? _restTimer;
  int _restShown = 0;
  late RepAnalyzer _analyzer = _analyzerFor(_exercise);

  static RepAnalyzer _analyzerFor(FormExercise exercise) => switch (exercise) {
    FormExercise.squat => SquatAnalyzer(),
    FormExercise.pushup => PushupAnalyzer(),
    FormExercise.plank => PlankAnalyzer(),
    FormExercise.shoulderPress => ShoulderPressAnalyzer(),
    FormExercise.curl => CurlAnalyzer(),
    FormExercise.tricepsExtension => TricepsExtensionAnalyzer(),
    FormExercise.dip => DipAnalyzer(),
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
              _error = 'Could not open the camera: $error';
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
      if (_cameras.isEmpty) throw StateError('No camera found');
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
    _session?.pause(_clock.elapsedMicroseconds);
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
      _session?.resume(_clock.elapsedMicroseconds);
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
      final session = _session;
      // Resting (or wrapping up): the skeleton keeps moving, nothing counts.
      if (session != null && session.stage != HandsFreeStage.active) return;
      final next = _analyzer.analyze(points, timestampUs: completedUs);
      // Always fed, so turning voice on mid-set doesn't replay counts.
      final feedback = _feedback.update(next, completedUs);
      _poseModel.highlight = _feedback.shown!.faultJoints;
      final step = session?.onFrame(next, completedUs) ?? HandsFreeStep.none;
      // One utterance: the last count, then what the set end means.
      final say = [feedback.say, step.say].nonNulls.join('. ');
      if (say.isNotEmpty && _voiceOn) _voice.speak(say);
      if (!identical(step, HandsFreeStep.none)) _applyStep(step);
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
      _session?.pause(_clock.elapsedMicroseconds);
      // Flag first so frames already in flight are ignored.
      setState(() => _paused = true);
      _voice.stop();
      if (camera != null && camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
    } else {
      _session?.resume(_clock.elapsedMicroseconds);
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

  /// Acts on what the hands-free session decided (its words are already
  /// said by the caller).
  void _applyStep(HandsFreeStep step) {
    if (step.setEnded) _bankSet();
    if (step.finished) {
      _finishPlan();
      return;
    }
    if (step.nextSet) _startSet();
    if (_session!.stage == HandsFreeStage.resting) _startRestTimer();
    setState(() {});
  }

  void _bankSet() {
    final result = _snapshot();
    if (result.amount > 0) {
      _outcomes.add((amount: result.amount, form: result.form));
    }
  }

  /// A fresh analyzer for the session's current set; a new exercise gets
  /// its camera setup guide again.
  void _startSet() {
    _restTimer?.cancel();
    _restTimer = null;
    final set = _session!.current;
    if (set.exercise != _exercise) _tracked = _setupDismissed = false;
    _exercise = set.exercise;
    _analyzer = _analyzerFor(set.exercise);
    _feedback = _feedbackFor(set.exercise);
    _poseModel.highlight = const {};
  }

  void _startRestTimer() {
    _restTimer?.cancel();
    _restShown = _session!.restLeft(_clock.elapsedMicroseconds);
    _restTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _paused) return;
      final session = _session;
      final step = session.tick(_clock.elapsedMicroseconds);
      if (step.say != null && _voiceOn) _voice.speak(step.say!);
      if (!identical(step, HandsFreeStep.none)) {
        _applyStep(step);
        return;
      }
      final left = session.restLeft(_clock.elapsedMicroseconds);
      if (left != _restShown) setState(() => _restShown = left);
    });
  }

  void _skipRest() {
    final step = _session!.skipRest();
    if (step.say != null && _voiceOn) _voice.speak(step.say!);
    if (!identical(step, HandsFreeStep.none)) _applyStep(step);
  }

  /// Every set done: lets "All done!" be heard, then hands the sets back.
  Future<void> _finishPlan() async {
    if (_saving) return;
    _restTimer?.cancel();
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.of(context).pop(List.of(_outcomes));
  }

  _SetSnapshot _snapshot() {
    final analyzer = _analyzer;
    final records = List.of(analyzer.repRecords);
    final hold = analyzer is PlankAnalyzer ? analyzer.summary : null;
    final judged = records.isNotEmpty || (hold?.trackedMs ?? 0) >= 3000;
    return (
      exercise: _exercise,
      amount: analyzer.repetitions,
      records: records,
      hold: hold,
      form: judged
          ? formResultOf(_exercise, records: records, hold: hold)
          : null,
      startedAt: _startedAt,
    );
  }

  void _toggleVoice() {
    setState(() => _voiceOn = !_voiceOn);
    if (!_voiceOn) _voice.stop();
    widget.controller.preferences.setBool(_voicePreferenceKey, _voiceOn);
  }

  /// Persists [result] as a one-set session; empty results are dropped.
  Future<void> _saveSession(_SetSnapshot result) async {
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
              FormExercise.shoulderPress => 'Shoulders',
              FormExercise.curl ||
              FormExercise.tricepsExtension ||
              FormExercise.dip => 'Arms',
            },
            sets: 1,
            reps: timed ? 0 : result.amount,
            durationSeconds: timed ? result.amount : 0,
            performedSets: [SetEntry(amount: result.amount, form: result.form)],
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
        title: Text('Could not save ${result.exercise.label}: $error'),
      );
      return;
    }
    if (!mounted) return;
    final unit = result.exercise == FormExercise.plank
        ? 'seconds'
        : result.amount == 1
        ? 'rep'
        : 'reps';
    showFToast(
      context: context,
      title: Text('Saved ${result.exercise.label}: ${result.amount} $unit'),
    );
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    if (_session case final session?) {
      // Stopping hands-free keeps every finished set, and the one in
      // progress if it counted anything. No review: each set's verdict
      // is saved with it, to open from the session later.
      _saving = true;
      _restTimer?.cancel();
      final active = session.stage == HandsFreeStage.active;
      final step = session.stop(active ? _analyzer.repetitions : 0);
      if (step.setEnded) _bankSet();
      _voice.stop();
      Navigator.of(context).pop(List.of(_outcomes));
      return;
    }
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
    FormResult? form;
    try {
      _analyzer.pauseTiming();
      final result = _snapshot();
      _voice.stop();
      if (result.form case final reviewed?) {
        await showFSheet<void>(
          context: context,
          side: .btt,
          mainAxisMaxRatio: .infinity,
          builder: (_) => AppSheet(
            child: _FormReviewSheet(
              exercise: result.exercise,
              result: reviewed,
              records: result.records,
              hold: result.hold,
            ),
          ),
        );
        if (!mounted) return;
      }
      // In set mode the workout logs the count; no session of its own.
      if (widget.forSet == null) await _saveSession(result);
      amount = result.amount;
      form = result.form;
      saved = true;
    } catch (error) {
      if (!mounted) return;
      // Never trap the user: the next close leaves without saving.
      _discardOnClose = true;
      showFToast(
        context: context,
        title: Text('Could not save the session: $error'),
        description: const Text('Tap close again to leave without saving.'),
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
      Navigator.of(context).pop<FormSetOutcome>(
        widget.forSet != null && amount > 0
            ? (amount: amount, form: form)
            : null,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _session?.pause(_clock.elapsedMicroseconds);
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
    _restTimer?.cancel();
    _voice.stop();
    _poseModel.dispose();
    super.dispose();
  }

  /// Counting for a workout (one set or hands-free): the close button
  /// finishes rather than discards.
  bool get _counting => widget.forSet != null || widget.plan != null;

  /// "Dumbbell Curl · Set 1/3 · 12 reps". While resting, [next] describes
  /// the set after the current one.
  String _setTitle(PlannedSet current, {bool next = false}) {
    final set = next ? (_session!.upcoming ?? current) : current;
    final unit = set.timed ? 's' : (set.target == 1 ? 'rep' : 'reps');
    return '${set.name} · Set ${set.setNumber}/${set.sets} · '
        '${set.target} $unit';
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
              FButton(onPress: _retry, child: const Text('Try again')),
              const SizedBox(height: 8),
              FButton(
                variant: .outline,
                onPress: _saveAndClose,
                child: const Text('Close'),
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
                      icon: _counting ? FLucideIcons.check : FLucideIcons.x,
                      tooltip: _counting ? 'Done' : 'Close',
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
                          semanticLabel: 'Performance mode',
                        ),
                      ),
                    ),
                    if (!kReleaseMode)
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
                      tooltip: _voiceOn ? 'Mute voice' : 'Unmute voice',
                      onPress: _toggleVoice,
                    ),
                    _CamButton(
                      icon: _paused ? FLucideIcons.play : FLucideIcons.pause,
                      tooltip: _paused ? 'Resume' : 'Pause',
                      onPress: _togglePause,
                    ),
                    if (_cameras.length > 1)
                      _CamButton(
                        icon: FLucideIcons.switchCamera,
                        tooltip: 'Switch camera',
                        onPress: _switchingCamera ? null : _switchCamera,
                      ),
                  ],
                ),
              ),
              if (!kReleaseMode && _showTelemetry)
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
                        if (_session case final session?)
                          Text(
                            _setTitle(session.current),
                            key: const Key('hands-free-set'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else if (widget.forSet != null)
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
                              value: _session == null
                                  ? '${analysis?.repetitions ?? 0}'
                                  : '${analysis?.repetitions ?? 0}'
                                        '/${_session.current.target}',
                            ),
                            _Metric(
                              label: 'PHASE',
                              value: analysis?.phaseLabel ?? 'Starting',
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
                          cue.cue ?? 'Step into the camera view',
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
              if (_session?.stage == HandsFreeStage.resting && !_paused)
                Center(
                  child: _RestCard(
                    seconds: _restShown,
                    next: _setTitle(_session!.current, next: true),
                    onSkip: _skipRest,
                  ),
                ),
              if (_session?.stage == HandsFreeStage.done)
                const Center(
                  child: Text(
                    'All done!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (_paused)
                const Center(
                  child: Text(
                    'Paused',
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

/// The hands-free rest: a countdown readable from across the room, what
/// comes next, and a way to cut it short.
class _RestCard extends StatelessWidget {
  const _RestCard({
    required this.seconds,
    required this.next,
    required this.onSkip,
  });

  final int seconds;
  final String next;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('hands-free-rest'),
    decoration: BoxDecoration(
      color: const Color(0xE6151515),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'REST',
            style: TextStyle(color: Colors.white54, letterSpacing: 2),
          ),
          Text(
            '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Next: $next',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 12),
          FButton(
            key: const Key('hands-free-skip-rest'),
            variant: .outline,
            mainAxisSize: .min,
            onPress: onSkip,
            child: const Text('Skip rest'),
          ),
        ],
      ),
    ),
  );
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
            'FitFlow needs camera access to check your form on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 17),
          ),
          const SizedBox(height: 20),
          FButton(
            onPress: permanent ? openAppSettings : retry,
            child: Text(permanent ? 'Open settings' : 'Allow camera'),
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
        (FLucideIcons.smartphone, 'Phone at hip height, 2–3 m away'),
        (FLucideIcons.personStanding, 'Stand side-on to the camera'),
        (FLucideIcons.scanEye, 'Whole body in view, head to toe'),
      ],
      FormExercise.pushup || FormExercise.plank => [
        (FLucideIcons.smartphone, 'Phone near the floor, 2–3 m away'),
        (
          FLucideIcons.personStanding,
          exercise == FormExercise.plank
              ? 'Lie across the frame, elbows under shoulders'
              : 'Lie across the frame, side-on to the camera',
        ),
        (FLucideIcons.scanEye, 'Whole body in view, head to toe'),
      ],
      FormExercise.shoulderPress => const [
        (FLucideIcons.smartphone, 'Phone at chest height or higher, 2 m away'),
        (FLucideIcons.personStanding, 'Face the camera'),
        (FLucideIcons.scanEye, 'Waist up in view, even with arms overhead'),
      ],
      FormExercise.curl => const [
        (FLucideIcons.smartphone, 'Phone at chest height, 2 m away'),
        (FLucideIcons.personStanding, 'Face the camera or stand side-on'),
        (FLucideIcons.scanEye, 'Knees up in view, both arms included'),
      ],
      FormExercise.tricepsExtension => const [
        (FLucideIcons.smartphone, 'Phone at chest height or higher, 2 m away'),
        (FLucideIcons.personStanding, 'Face the camera'),
        (FLucideIcons.scanEye, 'Waist up in view, even with arms overhead'),
      ],
      FormExercise.dip => const [
        (FLucideIcons.smartphone, 'Phone at bench height, 2–3 m away'),
        (FLucideIcons.personStanding, 'Sit side-on to the camera'),
        (FLucideIcons.scanEye, 'Arms, shoulders and hips clearly in view'),
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
                    'Camera setup for ${exercise.label}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _CamButton(
                  icon: FLucideIcons.x,
                  tooltip: 'Hide tips',
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
                'Hides once you are detected.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Post-set review: per-rep verdicts (or a plank's hold breakdown) plus an
/// optional AI coach verdict (gpt-6-luna on the same telemetry).
class _FormReviewSheet extends StatefulWidget {
  const _FormReviewSheet({
    required this.exercise,
    required this.result,
    required this.records,
    this.hold,
  });

  final FormExercise exercise;

  /// What is shown, and saved with the set.
  final FormResult result;

  /// The analyzer's own telemetry, for the AI coach prompt.
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

  @override
  Widget build(BuildContext context) {
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
                  Text(formSummaryLabel(widget.result)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FormReviewView(result: widget.result),
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
