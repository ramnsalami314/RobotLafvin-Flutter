import 'dart:async';
import 'dart:math' as math;
import '../services/port_discovery_service.dart';

import 'package:flutter/material.dart';

import '../services/serial_service.dart';

enum RadarRenderMode {
  raw,
  processed,
}

class RadarController extends ChangeNotifier {
  RadarController()
    : serial = SerialService(
        portName: 'COM3',
        baudRate: 9600,
      );

  final SerialService serial;

  // ==========================================================
  // RADAR CONFIG
  // ==========================================================

  static const double maxRadarDistance = 220;
  static const double minimumVisibleDistance = 40;
  static const double zoomStep = 20;

  /*
   * IMPORTANT:
   *
   * Arduino scans servo:
   *
   * 5, 7, 9 ... 175
   *
   * RadarAngle = 180 - servoAngle
   *
   * Therefore Flutter receives:
   *
   * 175, 173, 171 ... 5
   *
   * These are ODD angles.
   */
  static const int minimumRadarAngle = 5;
  static const int maximumRadarAngle = 175;
  static const int angleStep = 2;

  /*
   * Process three complete sweeps.
   */
  static const int processedSweepTarget = 3;

  // ==========================================================
  // FILTER CONFIG
  // ==========================================================

  static const double minimumNeighborTolerance = 8;

  static const double neighborTolerancePercent = 0.12;

  static const double majorJumpCm = 25;

  static const double severeJumpCm = 45;

  // ==========================================================
  // CONNECTION
  // ==========================================================

  StreamSubscription<String>? _lineSubscription;
  Timer? _driveHeartbeatTimer;
  Timer? _odometryTimer;

  bool isConnected = false;

  String connectionMessage = 'Connecting...';

  // ==========================================================
  // UART FORMAT
  // ==========================================================

  final RegExp _radarPattern = RegExp(
    r'ServoAngle:\s*(\d+)\s*,\s*RadarAngle:\s*(\d+)\s*,\s*Distance:\s*(-?[\d.]+)',
  );

  // ==========================================================
  // CURRENT RADAR VALUES
  // ==========================================================

  int currentServoAngle = 90;
  int currentRadarAngle = 90;

  double currentDistance = -1;

  double visibleDistance = maxRadarDistance;

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

  String driveStatus = 'STOPPED';

  // ==========================================================
  // RAW DATA
  // ==========================================================

  final Map<int, double> rawReadings = {};

  // ==========================================================
  // PROCESSED DATA
  // ==========================================================

  final Map<int, double> processedReadings = {};

  /*
   * Unknown sector:
   *
   * We simply do not have enough information to know
   * what exists there.
   */
  final Set<int> unknownAngles = {};

  /*
   * Occluded sector:
   *
   * angle -> distance where blocked region starts.
   *
   * Example:
   *
   * 90° -> 52 cm
   *
   * means:
   *
   * visibility exists until about 52 cm,
   * then the environment behind that object is hidden.
   */
  final Map<int, double> occludedAngles = {};

  Map<int, double> get displayedReadings {
    if (processedMode) {
      return processedReadings;
    }

    return rawReadings;
  }

  // ==========================================================
  // SWEEP HISTORY
  // ==========================================================

  final Map<int, double> _currentSweep = {};

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
  // ROBOT PATH / DEAD RECKONING
  // ==========================================================

  static const double forwardSpeedCmPerSecond =
      18;

  static const double reverseSpeedCmPerSecond =
      14;

  static const double turnDegreesPerSecond =
      95;

  double _robotXcm = 0;
  double _robotYcm = 0;

  double _robotHeadingRadians = 0;

  double totalPathCm = 0;

  DateTime? _lastOdometryUpdate;

  final List<Offset> _globalRobotPath = [
    Offset.zero,
  ];

  List<Offset> get localRobotPath {
    final List<Offset> result = [];

    final double cosHeading =
        math.cos(_robotHeadingRadians);

    final double sinHeading =
        math.sin(_robotHeadingRadians);

    for (final point in _globalRobotPath) {
      final double dx =
          point.dx - _robotXcm;

      final double dy =
          point.dy - _robotYcm;

      /*
       * Convert world position into robot-local
       * coordinates.
       */
      final double lateral =
          dx * cosHeading -
          dy * sinHeading;

      final double forward =
          dx * sinHeading +
          dy * cosHeading;

      result.add(
        Offset(
          lateral,
          forward,
        ),
      );
    }

    return result;
  }

  // ==========================================================
  // CONNECT
  // ==========================================================

 void connect() {
  final DiscoveredPort? bluetooth =
      PortDiscoveryService
          .findLikelyBluetoothPort();

  if (bluetooth != null) {
    serial.portName =
        bluetooth.portName;

    serial.baudRate = 9600;

    connectionMessage =
        'Bluetooth found: '
        '${bluetooth.portName}';
  } else {
    /*
     * USB fallback.
     */
    serial.portName = 'COM3';

    serial.baudRate = 115200;

    connectionMessage =
        'Bluetooth not found — trying USB COM3';
  }

  _lineSubscription =
      serial.lines.listen(
    _processLine,
  );

  final bool success =
      serial.connect();

  if (!success) {
    isConnected = false;

    connectionMessage =
        'Could not connect to '
        '${serial.portName}';

    notifyListeners();

    return;
  }

  isConnected = true;

  connectionMessage =
      '${bluetooth != null ? 'Bluetooth' : 'USB'} '
      '${serial.portName}';

  serial.sendLine(
    'DRIVE:X',
  );

  serial.sendLine(
    'RADAR:AUTO',
  );

  _driveHeartbeatTimer =
      Timer.periodic(
    const Duration(
      milliseconds: 120,
    ),
    (_) {
      if (activeDriveCommand != 'X') {
        serial.sendLine(
          'DRIVE:$activeDriveCommand',
        );
      }
    },
  );

  _lastOdometryUpdate =
      DateTime.now();

  _odometryTimer =
      Timer.periodic(
    const Duration(
      milliseconds: 50,
    ),
    (_) => _updateOdometry(),
  );

  notifyListeners();
}

  // ==========================================================
  // MODE
  // ==========================================================

  void setRenderMode(
    RadarRenderMode mode,
  ) {
    renderMode = mode;

    notifyListeners();
  }

  // ==========================================================
  // UART PARSING
  // ==========================================================

  void _processLine(
    String line,
  ) {
    final RegExpMatch? match =
        _radarPattern.firstMatch(
      line,
    );

    if (match == null) {
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
    // Raw display
    // --------------------------------------------------------

    if (distance > 0 &&
        distance <= maxRadarDistance) {
      rawReadings[
        radarAngle
      ] = distance;
    } else {
      rawReadings.remove(
        radarAngle,
      );
    }

    // --------------------------------------------------------
    // Sweep recording
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
    if (_previousRadarAngle != null) {
      final int delta =
          angle -
          _previousRadarAngle!;

      if (delta != 0) {
        final int newDirection =
            delta > 0
                ? 1
                : -1;

        /*
         * Direction reversal means one sweep ended.
         */
        if (_previousDirection != 0 &&
            newDirection !=
                _previousDirection) {
          _completeCurrentSweep();
        }

        _previousDirection =
            newDirection;
      }
    }

    if (distance > 0 &&
        distance <= maxRadarDistance) {
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

    /*
     * Only retain most recent 3.
     */
    while (_completedSweeps.length >
        processedSweepTarget) {
      _completedSweeps.removeAt(
        0,
      );
    }

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

    final Map<int, double> consensusReadings =
        {};

    final Map<int, int> confidence =
        {};

    // ========================================================
    // PASS 1
    //
    // Compare same angle across multiple sweeps.
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
            value <= maxRadarDistance) {
          samples.add(
            value,
          );
        }
      }

      if (samples.isEmpty) {
        unknownAngles.add(
          angle,
        );

        continue;
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
    //
    // Spatial reasoning.
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

      final double? left1 =
          consensusReadings[
        angle - 2
      ];

      final double? right1 =
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
      // Nothing detected
      // ------------------------------------------------------

      if (current == null) {
        /*
         * Tiny missing hole between two agreeing
         * measurements.
         */
        if (left1 != null &&
            right1 != null &&
            _similar(
              left1,
              right1,
            )) {
          processedReadings[
            angle
          ] =
              (
                left1 +
                right1
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

      final bool leftSupported =
          left1 != null &&
              _similar(
                current,
                left1,
              );

      final bool rightSupported =
          right1 != null &&
              _similar(
                current,
                right1,
              );

      // ------------------------------------------------------
      // Very high confidence
      // ------------------------------------------------------

      if (confidenceLevel >= 3) {
        processedReadings[
          angle
        ] = current;

        continue;
      }

      // ------------------------------------------------------
      // Both immediate neighbors agree
      // ------------------------------------------------------

      if (leftSupported &&
          rightSupported) {
        processedReadings[
          angle
        ] = current;

        continue;
      }

      // ------------------------------------------------------
      // One side supports the point
      // ------------------------------------------------------

      if (leftSupported &&
          !rightSupported) {
        /*
         * Could be right edge of object.
         */
        if (right1 == null) {
          processedReadings[
            angle
          ] = current;

          continue;
        }

        if (_distanceJump(
              current,
              right1,
            ) >
            majorJumpCm) {
          processedReadings[
            angle
          ] = current;

          continue;
        }
      }

      if (rightSupported &&
          !leftSupported) {
        /*
         * Could be left edge of object.
         */
        if (left1 == null) {
          processedReadings[
            angle
          ] = current;

          continue;
        }

        if (_distanceJump(
              current,
              left1,
            ) >
            majorJumpCm) {
          processedReadings[
            angle
          ] = current;

          continue;
        }
      }

      // ------------------------------------------------------
      // Classic spike:
      //
      // left and right agree,
      // middle wildly differs.
      // ------------------------------------------------------

      if (left1 != null &&
          right1 != null &&
          _similar(
            left1,
            right1,
          )) {
        final double jumpLeft =
            _distanceJump(
          current,
          left1,
        );

        final double jumpRight =
            _distanceJump(
          current,
          right1,
        );

        if (jumpLeft >
                majorJumpCm &&
            jumpRight >
                majorJumpCm) {
          unknownAngles.add(
            angle,
          );

          continue;
        }
      }

      // ------------------------------------------------------
      // Wider neighborhood agrees but current does not.
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
      // Severe isolated discontinuity.
      // ------------------------------------------------------

      if (left1 != null &&
          right1 != null) {
        final double jumpLeft =
            _distanceJump(
          current,
          left1,
        );

        final double jumpRight =
            _distanceJump(
          current,
          right1,
        );

        if (jumpLeft >
                severeJumpCm &&
            jumpRight >
                severeJumpCm &&
            confidenceLevel <
                2) {
          unknownAngles.add(
            angle,
          );

          continue;
        }
      }

      // ------------------------------------------------------
      // Weak point with no support.
      // ------------------------------------------------------

      if (!leftSupported &&
          !rightSupported &&
          confidenceLevel <
              2) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      // ------------------------------------------------------
      // Otherwise keep it.
      // ------------------------------------------------------

      processedReadings[
        angle
      ] = current;
    }

    // ========================================================
    // PASS 3
    //
    // Remove tiny isolated islands.
    // ========================================================

    final Map<int, double> cleaned =
        {};

    for (final entry
        in processedReadings.entries) {
      final int angle =
          entry.key;

      final double distance =
          entry.value;

      final bool neighborLeft =
          processedReadings
              .containsKey(
        angle - 2,
      );

      final bool neighborRight =
          processedReadings
              .containsKey(
        angle + 2,
      );

      final bool widerLeft =
          processedReadings
              .containsKey(
        angle - 4,
      );

      final bool widerRight =
          processedReadings
              .containsKey(
        angle + 4,
      );

      if (!neighborLeft &&
          !neighborRight &&
          !widerLeft &&
          !widerRight) {
        unknownAngles.add(
          angle,
        );

        continue;
      }

      cleaned[
        angle
      ] = distance;
    }

    processedReadings
      ..clear()
      ..addAll(
        cleaned,
      );

    // ========================================================
    // PASS 4
    //
    // Determine true occlusion.
    //
    // Nearby objects hide space behind them.
    // ========================================================

    for (final entry
        in processedReadings.entries) {
      final int angle =
          entry.key;

      final double distance =
          entry.value;

      /*
       * A return near maximum range doesn't hide
       * meaningful space behind it.
       */
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

        /*
         * If there is already a nearer or similarly
         * placed measured object at this angle,
         * don't classify the entire angle as hidden.
         */
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

    // ========================================================
    // PASS 5
    //
    // Unknown and occluded are different.
    //
    // Occlusion wins.
    // ========================================================

    for (final int angle
        in occludedAngles.keys) {
      unknownAngles.remove(
        angle,
      );
    }
  }

  // ==========================================================
  // CONSENSUS
  // ==========================================================

  _ConsensusResult? _findConsensus(
    List<double> input,
  ) {
    final List<double> values =
        List<double>.from(input)
          ..sort();

    if (values.isEmpty) {
      return null;
    }

    // --------------------------------------------------------
    // Only one sweep contains this point
    // --------------------------------------------------------

    if (values.length == 1) {
      return _ConsensusResult(
        distance:
            values.first,
        confidence:
            1,
      );
    }

    // --------------------------------------------------------
    // Two samples
    // --------------------------------------------------------

    if (values.length == 2) {
      final double a =
          values[0];

      final double b =
          values[1];

      if (_similar(a, b)) {
        return _ConsensusResult(
          distance:
              (a + b) /
              2.0,
          confidence:
              2,
        );
      }

      return null;
    }

    // --------------------------------------------------------
    // Three samples
    // --------------------------------------------------------

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

    if (ab &&
        bc) {
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
  // FILTER HELPERS
  // ==========================================================

  double _allowedDifference(
    double distance,
  ) {
    return math.max(
      minimumNeighborTolerance,
      distance *
          neighborTolerancePercent,
    );
  }

  bool _similar(
    double a,
    double b,
  ) {
    final double reference =
        math.min(
      a,
      b,
    );

    return (a - b).abs() <=
        _allowedDifference(
          reference,
        );
  }

  double _distanceJump(
    double a,
    double b,
  ) {
    return (a - b).abs();
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

    serial.sendLine(
      'DRIVE:X',
    );

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

    else if (activeDriveCommand ==
        'A') {
      _robotHeadingRadians -=
          turnDegreesPerSecond *
          dt *
          math.pi /
          180.0;
    }

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

      final Offset point =
          Offset(
        _robotXcm,
        _robotYcm,
      );

      if ((point -
                  _globalRobotPath
                      .last)
              .distance >=
          2) {
        _globalRobotPath.add(
          point,
        );

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
    if (!manualRadar) {
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
  // CLEAR
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
    serial.sendLine(
      'DRIVE:X',
    );

    _driveHeartbeatTimer
        ?.cancel();

    _odometryTimer
        ?.cancel();

    _lineSubscription
        ?.cancel();

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