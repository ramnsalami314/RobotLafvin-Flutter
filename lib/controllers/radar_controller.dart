import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/serial_service.dart';

enum RadarRenderMode {
  raw,
  processed,
}

class RadarController extends ChangeNotifier {
  RadarController()
      : serial = SerialService();

  final SerialService serial;

  // ==========================================================
  // RADAR CONFIG
  // ==========================================================

  static const double maxRadarDistance = 220;
  static const double minimumVisibleDistance = 40;
  static const double zoomStep = 20;

  // Arduino sends odd radar angles:
  // 5, 7, 9 ... 175
  static const int minimumRadarAngle = 5;
  static const int maximumRadarAngle = 175;
  static const int angleStep = 2;

  // Processed map uses the latest 3 completed sweeps.
  static const int processedSweepTarget = 3;

  // ==========================================================
  // SERIAL / CONNECTION
  // ==========================================================

  StreamSubscription<String>? _lineSubscription;

  Timer? _driveHeartbeatTimer;
  Timer? _odometryTimer;

  bool isConnected = false;

  String connectionMessage =
      'Not connected';

  List<String> availablePorts = [];

  String? selectedPort;

  // USB Arduino:
  // 115200
  //
  // HC-05:
  // 9600
  int selectedBaud = 115200;

  // ==========================================================
  // UART MESSAGE FORMAT
  // ==========================================================

  final RegExp _radarPattern =
      RegExp(
    r'ServoAngle:\s*(\d+)\s*,\s*RadarAngle:\s*(\d+)\s*,\s*Distance:\s*(-?[\d.]+)',
  );

  // ==========================================================
  // CURRENT RADAR STATE
  // ==========================================================

  int currentServoAngle = 90;
  int currentRadarAngle = 90;

  double currentDistance = -1;

  double visibleDistance =
      maxRadarDistance;

  // ==========================================================
  // DISPLAY MODE
  // ==========================================================

  RadarRenderMode renderMode =
      RadarRenderMode.raw;

  bool get processedMode =>
      renderMode ==
      RadarRenderMode.processed;

  // ==========================================================
  // MANUAL RADAR
  // ==========================================================

  bool manualRadar = false;

  double manualServoAngle = 90;

  // ==========================================================
  // DRIVE
  // ==========================================================

  String activeDriveCommand = 'X';

  String driveStatus =
      'STOPPED';

  // ==========================================================
  // RAW RADAR
  // ==========================================================

  final Map<int, double> rawReadings =
      {};

  // ==========================================================
  // PROCESSED RADAR
  // ==========================================================

  final Map<int, double>
      processedReadings = {};

  // Unknown = not enough reliable information.
  final Set<int> unknownAngles = {};

  // angle -> distance where blocked area begins.
  final Map<int, double>
      occludedAngles = {};

  Map<int, double>
      get displayedReadings {
    if (processedMode) {
      return processedReadings;
    }

    return rawReadings;
  }

  // ==========================================================
  // SWEEP HISTORY
  // ==========================================================

  final Map<int, double>
      _currentSweep = {};

  final List<Map<int, double>>
      _completedSweeps = [];

  int? _previousRadarAngle;

  int _previousDirection = 0;

  int get completedSweepCount =>
      _completedSweeps.length;

  bool get processedReady =>
      completedSweepCount >=
      processedSweepTarget;

  String get processedProgressLabel {
    if (processedReady) {
      return 'Processed map ready';
    }

    return 'Building map: '
        '$completedSweepCount/'
        '$processedSweepTarget sweeps';
  }

  // ==========================================================
  // ROBOT PATH ESTIMATION
  // ==========================================================

  static const double
      forwardSpeedCmPerSecond = 18;

  static const double
      reverseSpeedCmPerSecond = 14;

  static const double
      turnDegreesPerSecond = 95;

  double _robotXcm = 0;
  double _robotYcm = 0;

  double _robotHeadingRadians = 0;

  double totalPathCm = 0;

  DateTime? _lastOdometryUpdate;

  final List<Offset> _globalRobotPath = [
    Offset.zero,
  ];

  List<Offset> get robotPath =>
      List<Offset>.unmodifiable(
        _globalRobotPath,
      );

  // ==========================================================
  // PORT DISCOVERY
  // ==========================================================

  void refreshPorts() {
    availablePorts =
        serial.getAvailablePorts();

    if (availablePorts.isEmpty) {
      selectedPort = null;

      connectionMessage =
          'No COM ports found';

      notifyListeners();
      return;
    }

    // Keep selected port if Windows still reports it.
    if (selectedPort != null &&
        availablePorts.contains(
          selectedPort,
        )) {
      connectionMessage =
          '${availablePorts.length} COM port(s) found';

      notifyListeners();
      return;
    }

    // Otherwise select the first available port.
    selectedPort =
        availablePorts.first;

    connectionMessage =
        '${availablePorts.length} COM port(s) found';

    notifyListeners();
  }

  void selectPort(
    String? port,
  ) {
    if (isConnected) {
      return;
    }

    selectedPort = port;

    notifyListeners();
  }

  void selectBaud(
    int baud,
  ) {
    if (isConnected) {
      return;
    }

    selectedBaud = baud;

    notifyListeners();
  }

  // ==========================================================
  // CONNECT
  // ==========================================================

  void connectSelectedPort() {
    final String? port =
        selectedPort;

    if (port == null) {
      connectionMessage =
          'Select a COM port first';

      notifyListeners();
      return;
    }

    disconnect();

    _lineSubscription =
        serial.lines.listen(
      _processLine,
    );

    final bool success =
        serial.connect(
      port: port,
      baud: selectedBaud,
    );

    if (!success) {
      isConnected = false;

      connectionMessage =
          'Failed to open '
          '$port @ $selectedBaud';

      notifyListeners();
      return;
    }

    isConnected = true;

    connectionMessage =
        'Connected: '
        '$port @ $selectedBaud';

    // Safety first.
    serial.sendLine(
      'DRIVE:X',
    );

    // Automatic scan is default.
    serial.sendLine(
      'RADAR:AUTO',
    );

    // --------------------------------------------------------
    // Drive heartbeat
    // --------------------------------------------------------

    _driveHeartbeatTimer =
        Timer.periodic(
      const Duration(
        milliseconds: 120,
      ),
      (_) {
        if (activeDriveCommand !=
            'X') {
          serial.sendLine(
            'DRIVE:$activeDriveCommand',
          );
        }
      },
    );

    // --------------------------------------------------------
    // Estimated path timer
    // --------------------------------------------------------

    _lastOdometryUpdate =
        DateTime.now();

    _odometryTimer =
        Timer.periodic(
      const Duration(
        milliseconds: 50,
      ),
      (_) {
        _updateOdometry();
      },
    );

    notifyListeners();
  }

  // ==========================================================
  // DISCONNECT
  // ==========================================================

  void disconnect() {
    if (isConnected) {
      serial.sendLine(
        'DRIVE:X',
      );
    }

    _driveHeartbeatTimer
        ?.cancel();

    _driveHeartbeatTimer =
        null;

    _odometryTimer
        ?.cancel();

    _odometryTimer =
        null;

    _lineSubscription
        ?.cancel();

    _lineSubscription =
        null;

    serial.disconnect();

    isConnected = false;

    activeDriveCommand = 'X';

    driveStatus = 'STOPPED';

    connectionMessage =
        'Disconnected';

    notifyListeners();
  }

  // ==========================================================
  // RECEIVE UART DATA
  // ==========================================================

  void _processLine(
    String line,
  ) {
    debugPrint(
      'ARDUINO >>> $line',
    );

    final RegExpMatch? match =
        _radarPattern.firstMatch(
      line,
    );

    if (match == null) {
      debugPrint(
        'PARSE FAILED >>> $line',
      );

      return;
    }

    final int? servoAngle =
        int.tryParse(
      match.group(1)!,
    );

    final int? radarAngle =
        int.tryParse(
      match.group(2)!,
    );

    final double? distance =
        double.tryParse(
      match.group(3)!,
    );

    if (servoAngle == null ||
        radarAngle == null ||
        distance == null) {
      return;
    }

    debugPrint(
      'PARSED >>> '
      'servo=$servoAngle '
      'radar=$radarAngle '
      'distance=$distance',
    );

    if (radarAngle <
            minimumRadarAngle ||
        radarAngle >
            maximumRadarAngle) {
      return;
    }

    currentServoAngle =
        servoAngle;

    currentRadarAngle =
        radarAngle;

    currentDistance =
        distance;

    // --------------------------------------------------------
    // RAW DATA
    // --------------------------------------------------------

    if (distance > 0 &&
        distance <=
            maxRadarDistance) {
      rawReadings[
        radarAngle
      ] = distance;

      debugPrint(
        'RAW POINT >>> '
        '$radarAngle° = '
        '${distance.toStringAsFixed(1)} cm '
        '| total=${rawReadings.length}',
      );
    } else {
      rawReadings.remove(
        radarAngle,
      );
    }

    // --------------------------------------------------------
    // RECORD SWEEP FOR PROCESSED MODE
    // --------------------------------------------------------

    _recordSweepPoint(
      radarAngle,
      distance,
    );

    notifyListeners();
  }

  // ==========================================================
  // SWEEP RECORDING
  // ==========================================================

  void _recordSweepPoint(
    int angle,
    double distance,
  ) {
    if (_previousRadarAngle !=
        null) {
      final int delta =
          angle -
          _previousRadarAngle!;

      if (delta != 0) {
        final int newDirection =
            delta > 0
                ? 1
                : -1;

        // Direction changed = one sweep ended.
        if (_previousDirection !=
                0 &&
            newDirection !=
                _previousDirection) {
          _completeCurrentSweep();
        }

        _previousDirection =
            newDirection;
      }
    }

    if (distance > 0 &&
        distance <=
            maxRadarDistance) {
      _currentSweep[
        angle
      ] = distance;
    } else {
      _currentSweep.remove(
        angle,
      );
    }

    _previousRadarAngle =
        angle;
  }

  // ==========================================================
  // COMPLETE SWEEP
  // ==========================================================

  void _completeCurrentSweep() {
    if (_currentSweep.isEmpty) {
      return;
    }

    _completedSweeps.add(
      Map<int, double>.from(
        _currentSweep,
      ),
    );

    while (_completedSweeps.length >
        processedSweepTarget) {
      _completedSweeps.removeAt(
        0,
      );
    }

    debugPrint(
      'SWEEP COMPLETE >>> '
      '${_completedSweeps.length}/'
      '$processedSweepTarget',
    );

    _currentSweep.clear();

    _buildProcessedEnvironment();
  }

  // ==========================================================
  // PROCESSED ENVIRONMENT
  // ==========================================================

  void _buildProcessedEnvironment() {
    processedReadings.clear();

    unknownAngles.clear();

    occludedAngles.clear();

    if (_completedSweeps.isEmpty) {
      return;
    }

    final Map<int, double>
        consensusReadings = {};

    final Map<int, int>
        confidence = {};

    // ========================================================
    // PASS 1
    // Compare each angle over repeated sweeps.
    // ========================================================

    for (
      int angle =
          minimumRadarAngle;
      angle <=
          maximumRadarAngle;
      angle += angleStep
    ) {
      final List<double> samples =
          [];

      for (final sweep
          in _completedSweeps) {
        final double? value =
            sweep[angle];

        if (value != null &&
            value > 0 &&
            value <=
                maxRadarDistance) {
          samples.add(
            value,
          );
        }
      }

      final _ConsensusResult? result =
          _findConsensus(
        samples,
      );

      if (result == null) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      consensusReadings[
        angle
      ] = result.distance;

      confidence[
        angle
      ] = result.confidence;
    }

    // ========================================================
    // PASS 2
    // Neighborhood validation.
    // ========================================================

    for (
      int angle =
          minimumRadarAngle;
      angle <=
          maximumRadarAngle;
      angle += angleStep
    ) {
      final double? current =
          consensusReadings[
        angle
      ];

      final double? left =
          consensusReadings[
        angle - 2
      ];

      final double? right =
          consensusReadings[
        angle + 2
      ];

      final double? left2 =
          consensusReadings[
        angle - 4
      ];

      final double? right2 =
          consensusReadings[
        angle + 4
      ];

      // ------------------------------------------------------
      // No reading at this angle.
      // ------------------------------------------------------

      if (current == null) {
        // Fill tiny gaps only if neighbors agree strongly.
        if (left != null &&
            right != null &&
            _similar(
              left,
              right,
            )) {
          processedReadings[
            angle
          ] =
              (
                left +
                right
              ) /
              2.0;

          unknownAngles.remove(
            angle,
          );
        } else {
          unknownAngles.add(
            angle,
          );
        }

        continue;
      }

      final int confidenceLevel =
          confidence[
            angle
          ] ??
          0;

      final bool leftSupport =
          left != null &&
              _similar(
                current,
                left,
              );

      final bool rightSupport =
          right != null &&
              _similar(
                current,
                right,
              );

      // ------------------------------------------------------
      // Strong repeated reading.
      // ------------------------------------------------------

      if (confidenceLevel >= 3) {
        processedReadings[
          angle
        ] = current;

        continue;
      }

      // ------------------------------------------------------
      // Both sides agree.
      // ------------------------------------------------------

      if (leftSupport &&
          rightSupport) {
        processedReadings[
          angle
        ] = current;

        continue;
      }

      // ------------------------------------------------------
      // Edge detection
      // ------------------------------------------------------

      if (leftSupport &&
          (
            right == null ||
            (
                  current -
                  right
                ).abs() >
                25
          )) {
        processedReadings[
          angle
        ] = current;

        continue;
      }

      if (rightSupport &&
          (
            left == null ||
            (
                  current -
                  left
                ).abs() >
                25
          )) {
        processedReadings[
          angle
        ] = current;

        continue;
      }

      // ------------------------------------------------------
      // Isolated spike
      // ------------------------------------------------------

      if (left != null &&
          right != null &&
          _similar(
            left,
            right,
          ) &&
          (
                current -
                left
              ).abs() >
              25 &&
          (
                current -
                right
              ).abs() >
              25) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      // ------------------------------------------------------
      // Wide neighborhood says current is wrong.
      // ------------------------------------------------------

      if (left2 != null &&
          right2 != null &&
          _similar(
            left2,
            right2,
          ) &&
          !_similar(
            current,
            left2,
          )) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      // ------------------------------------------------------
      // Weak isolated reading.
      // ------------------------------------------------------

      if (!leftSupport &&
          !rightSupport &&
          confidenceLevel <
              2) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      processedReadings[
        angle
      ] = current;
    }

    // ========================================================
    // PASS 3
    // Remove isolated islands.
    // ========================================================

    final Map<int, double> cleaned =
        {};

    for (final entry
        in processedReadings.entries) {
      final int angle =
          entry.key;

      final bool supported =
          processedReadings
                  .containsKey(
                angle - 2,
              ) ||
              processedReadings
                  .containsKey(
                angle + 2,
              ) ||
              processedReadings
                  .containsKey(
                angle - 4,
              ) ||
              processedReadings
                  .containsKey(
                angle + 4,
              );

      if (!supported) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      cleaned[
        angle
      ] = entry.value;
    }

    processedReadings
      ..clear()
      ..addAll(
        cleaned,
      );

    // ========================================================
    // PASS 4
    // Estimate blocked / occluded space.
    // ========================================================

    for (final entry
        in processedReadings.entries) {
      final int angle =
          entry.key;

      final double distance =
          entry.value;

      if (distance >
          visibleDistance *
              0.85) {
        continue;
      }

      final int shadowWidth;

      if (distance < 25) {
        shadowWidth = 12;
      } else if (distance < 45) {
        shadowWidth = 10;
      } else if (distance < 75) {
        shadowWidth = 8;
      } else if (distance < 120) {
        shadowWidth = 6;
      } else {
        shadowWidth = 4;
      }

      final double blockedStart =
          math.min(
        visibleDistance,
        distance + 5,
      );

      for (
        int shadowAngle =
            angle -
            shadowWidth;
        shadowAngle <=
            angle +
            shadowWidth;
        shadowAngle +=
            angleStep
      ) {
        if (shadowAngle <
                minimumRadarAngle ||
            shadowAngle >
                maximumRadarAngle) {
          continue;
        }

        final double? visibleObject =
            processedReadings[
          shadowAngle
        ];

        if (visibleObject != null &&
            visibleObject <=
                distance + 8) {
          continue;
        }

        final double? existing =
            occludedAngles[
          shadowAngle
        ];

        if (existing == null ||
            blockedStart <
                existing) {
          occludedAngles[
            shadowAngle
          ] = blockedStart;
        }
      }
    }

    // Occlusion is more specific than unknown.
    for (final int angle
        in occludedAngles.keys) {
      unknownAngles.remove(
        angle,
      );
    }

    debugPrint(
      'PROCESSED >>> '
      '${processedReadings.length} surfaces | '
      '${unknownAngles.length} unknown | '
      '${occludedAngles.length} blocked',
    );
  }

  // ==========================================================
  // MULTI-SWEEP CONSENSUS
  // ==========================================================

  _ConsensusResult? _findConsensus(
    List<double> input,
  ) {
    final List<double> values =
        List<double>.from(
      input,
    )..sort();

    if (values.isEmpty) {
      return null;
    }

    // One sweep only.
    if (values.length == 1) {
      return _ConsensusResult(
        distance:
            values.first,
        confidence:
            1,
      );
    }

    // Two sweeps.
    if (values.length == 2) {
      if (_similar(
        values[0],
        values[1],
      )) {
        return _ConsensusResult(
          distance:
              (
                values[0] +
                values[1]
              ) /
              2.0,
          confidence:
              2,
        );
      }

      return null;
    }

    // Three sweeps.
    final double a =
        values[0];

    final double b =
        values[1];

    final double c =
        values[2];

    final bool ab =
        _similar(
      a,
      b,
    );

    final bool bc =
        _similar(
      b,
      c,
    );

    final bool ac =
        _similar(
      a,
      c,
    );

    if (ab && bc) {
      return _ConsensusResult(
        distance:
            b,
        confidence:
            3,
      );
    }

    if (ab) {
      return _ConsensusResult(
        distance:
            (
              a +
              b
            ) /
            2.0,
        confidence:
            2,
      );
    }

    if (bc) {
      return _ConsensusResult(
        distance:
            (
              b +
              c
            ) /
            2.0,
        confidence:
            2,
      );
    }

    if (ac) {
      return _ConsensusResult(
        distance:
            (
              a +
              c
            ) /
            2.0,
        confidence:
            2,
      );
    }

    return null;
  }

  // ==========================================================
  // DISTANCE COMPARISON
  // ==========================================================

  bool _similar(
    double a,
    double b,
  ) {
    final double reference =
        math.min(
      a,
      b,
    );

    final double tolerance =
        math.max(
      8.0,
      reference *
          0.12,
    );

    return (
          a -
          b
        ).abs() <=
        tolerance;
  }

  // ==========================================================
  // DISPLAY MODE
  // ==========================================================

  void setRenderMode(
    RadarRenderMode mode,
  ) {
    renderMode = mode;

    notifyListeners();
  }

  // ==========================================================
  // DRIVE
  // ==========================================================

  void startDrive(
    String command,
  ) {
    if (!isConnected) {
      return;
    }

    activeDriveCommand =
        command;

    switch (command) {
      case 'W':
        driveStatus =
            'FORWARD';
        break;

      case 'S':
        driveStatus =
            'BACKWARD';
        break;

      case 'A':
        driveStatus =
            'LEFT';
        break;

      case 'D':
        driveStatus =
            'RIGHT';
        break;
    }

    serial.sendLine(
      'DRIVE:$command',
    );

    notifyListeners();
  }

  void stopDrive() {
    activeDriveCommand =
        'X';

    driveStatus =
        'STOPPED';

    if (isConnected) {
      serial.sendLine(
        'DRIVE:X',
      );
    }

    notifyListeners();
  }

  // ==========================================================
  // ESTIMATED ROBOT PATH
  // ==========================================================

  void _updateOdometry() {
    final DateTime now =
        DateTime.now();

    final DateTime? previous =
        _lastOdometryUpdate;

    _lastOdometryUpdate =
        now;

    if (previous == null) {
      return;
    }

    final double dt =
        now
                .difference(
                  previous,
                )
                .inMilliseconds /
            1000.0;

    if (dt <= 0 ||
        dt > 0.5) {
      return;
    }

    double movement = 0;

    // --------------------------------------------------------
    // Forward
    // --------------------------------------------------------

    if (activeDriveCommand ==
        'W') {
      movement =
          forwardSpeedCmPerSecond *
          dt;

      _robotXcm +=
          math.sin(
            _robotHeadingRadians,
          ) *
          movement;

      _robotYcm +=
          math.cos(
            _robotHeadingRadians,
          ) *
          movement;
    }

    // --------------------------------------------------------
    // Reverse
    // --------------------------------------------------------

    else if (activeDriveCommand ==
        'S') {
      movement =
          reverseSpeedCmPerSecond *
          dt;

      _robotXcm -=
          math.sin(
            _robotHeadingRadians,
          ) *
          movement;

      _robotYcm -=
          math.cos(
            _robotHeadingRadians,
          ) *
          movement;
    }

    // --------------------------------------------------------
    // Turn left
    // --------------------------------------------------------

    else if (activeDriveCommand ==
        'A') {
      _robotHeadingRadians -=
          turnDegreesPerSecond *
          dt *
          math.pi /
          180.0;
    }

    // --------------------------------------------------------
    // Turn right
    // --------------------------------------------------------

    else if (activeDriveCommand ==
        'D') {
      _robotHeadingRadians +=
          turnDegreesPerSecond *
          dt *
          math.pi /
          180.0;
    }

    if (movement > 0) {
      totalPathCm +=
          movement;

      final Offset position =
          Offset(
        _robotXcm,
        _robotYcm,
      );

      if ((position -
                  _globalRobotPath
                      .last)
              .distance >=
          2) {
        _globalRobotPath.add(
          position,
        );

        // Prevent unbounded memory growth.
        if (_globalRobotPath.length >
            500) {
          _globalRobotPath.removeAt(
            0,
          );
        }
      }

      notifyListeners();
    }
  }

  // ==========================================================
  // MANUAL RADAR
  // ==========================================================

  void setManualRadar(
    bool enabled,
  ) {
    if (!isConnected) {
      return;
    }

    manualRadar =
        enabled;

    if (enabled) {
      manualServoAngle =
          currentServoAngle
              .toDouble();

      serial.sendLine(
        'RADAR:MANUAL',
      );

      sendManualServoAngle();
    } else {
      serial.sendLine(
        'RADAR:AUTO',
      );
    }

    notifyListeners();
  }

  void setManualServoAngle(
    double angle,
  ) {
    manualServoAngle =
        angle.clamp(
      5.0,
      175.0,
    );

    notifyListeners();
  }

  void nudgeManualServo(
    int delta,
  ) {
    setManualServoAngle(
      manualServoAngle +
          delta,
    );

    sendManualServoAngle();
  }

  void sendManualServoAngle() {
    if (!manualRadar ||
        !isConnected) {
      return;
    }

    serial.sendLine(
      'RADAR:ANGLE:'
      '${manualServoAngle.round()}',
    );
  }

  // ==========================================================
  // ZOOM
  // ==========================================================

  void zoomIn() {
    visibleDistance =
        math.max(
      minimumVisibleDistance,
      visibleDistance -
          zoomStep,
    );

    if (processedReady) {
      _buildProcessedEnvironment();
    }

    notifyListeners();
  }

  void zoomOut() {
    visibleDistance =
        math.min(
      maxRadarDistance,
      visibleDistance +
          zoomStep,
    );

    if (processedReady) {
      _buildProcessedEnvironment();
    }

    notifyListeners();
  }

  // ==========================================================
  // CLEAR RADAR
  // ==========================================================

  void clearRadar() {
    rawReadings.clear();

    processedReadings.clear();

    unknownAngles.clear();

    occludedAngles.clear();

    _currentSweep.clear();

    _completedSweeps.clear();

    _previousRadarAngle =
        null;

    _previousDirection =
        0;

    notifyListeners();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    disconnect();

    serial.dispose();

    super.dispose();
  }
}

class _ConsensusResult {
  const _ConsensusResult({
    required this.distance,
    required this.confidence,
  });

  final double distance;

  final int confidence;
}