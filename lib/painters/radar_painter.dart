import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadarPainter extends CustomPainter {
  RadarPainter({
    required this.currentAngle,
    required this.readings,
    required this.unknownAngles,
    required this.occludedAngles,
    required this.pathPoints,
    required this.maxDistance,
    required this.processedMode,
  });

  final double currentAngle;

  final Map<int, double> readings;

  final Set<int> unknownAngles;

  /*
   * angle -> distance where occlusion begins
   */
  final Map<int, double> occludedAngles;

  /*
   * Robot path in local robot coordinates.
   *
   * dx = left/right cm
   * dy = forward/backward cm
   */
  final List<Offset> pathPoints;

  final double maxDistance;

  final bool processedMode;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final double horizontalRadius =
        size.width * 0.46;

    final double verticalRadius =
        size.height * 0.80;

    final double radius = math.min(
      horizontalRadius,
      verticalRadius,
    );

    final Offset center = Offset(
      size.width / 2,
      size.height * 0.90,
    );

    _drawBackground(
      canvas,
      center,
      radius,
    );

    if (processedMode) {
      _drawUnknownSpace(
        canvas,
        center,
        radius,
      );

      _drawOccludedSpace(
        canvas,
        center,
        radius,
      );
    }

    _drawGrid(
      canvas,
      center,
      radius,
    );

    if (processedMode) {
      _drawRobotPath(
        canvas,
        center,
        radius,
      );

      _drawProcessedReadings(
        canvas,
        center,
        radius,
      );
    } else {
      _drawRawReadings(
        canvas,
        center,
        radius,
      );
    }

    _drawSweep(
      canvas,
      center,
      radius,
    );

    _drawSensor(
      canvas,
      center,
    );
  }

  // ==========================================================
  // BACKGROUND
  // ==========================================================

  void _drawBackground(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final Rect radarRect = Rect.fromCircle(
      center: center,
      radius: radius,
    );

    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.green.withOpacity(0.11),
          Colors.green.withOpacity(0.04),
          Colors.transparent,
        ],
      ).createShader(radarRect);

    final Path radarArea = Path()
      ..moveTo(
        center.dx - radius,
        center.dy,
      )
      ..arcTo(
        radarRect,
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(
        center.dx,
        center.dy,
      )
      ..close();

    canvas.drawPath(
      radarArea,
      paint,
    );
  }

  // ==========================================================
  // UNKNOWN SPACE
  //
  // Light gray:
  // sensor did not establish enough information here.
  // ==========================================================

  void _drawUnknownSpace(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final Paint unknownPaint = Paint()
      ..color = Colors.grey.withOpacity(
        0.14,
      )
      ..style = PaintingStyle.fill;

    final List<int> angles =
        unknownAngles.toList()
          ..sort();

    for (final int angle in angles) {
      _drawSector(
        canvas: canvas,
        center: center,
        innerRadius: 0,
        outerRadius: radius,
        startAngle: angle - 1,
        endAngle: angle + 1,
        paint: unknownPaint,
      );
    }
  }

  // ==========================================================
  // OCCLUDED SPACE
  //
  // Dark gray:
  // an object blocks visibility behind it.
  // ==========================================================

  void _drawOccludedSpace(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final Paint occlusionPaint = Paint()
      ..color = Colors.grey.shade900.withOpacity(
        0.58,
      )
      ..style = PaintingStyle.fill;

    final List<MapEntry<int, double>> entries =
        occludedAngles.entries.toList()
          ..sort(
            (a, b) => a.key.compareTo(
              b.key,
            ),
          );

    for (final entry in entries) {
      final int angle = entry.key;

      final double blockedFromCm =
          entry.value.clamp(
        0,
        maxDistance,
      );

      final double innerRadius =
          radius *
              blockedFromCm /
              maxDistance;

      _drawSector(
        canvas: canvas,
        center: center,
        innerRadius: innerRadius,
        outerRadius: radius,
        startAngle: angle - 1,
        endAngle: angle + 1,
        paint: occlusionPaint,
      );
    }
  }

  // ==========================================================
  // SECTOR HELPER
  // ==========================================================

  void _drawSector({
    required Canvas canvas,
    required Offset center,
    required double innerRadius,
    required double outerRadius,
    required double startAngle,
    required double endAngle,
    required Paint paint,
  }) {
    final Offset innerStart =
        _polarToCanvas(
      center: center,
      radius: innerRadius,
      angle: startAngle,
    );

    final Offset outerStart =
        _polarToCanvas(
      center: center,
      radius: outerRadius,
      angle: startAngle,
    );

    final Offset outerEnd =
        _polarToCanvas(
      center: center,
      radius: outerRadius,
      angle: endAngle,
    );

    final Offset innerEnd =
        _polarToCanvas(
      center: center,
      radius: innerRadius,
      angle: endAngle,
    );

    final Path path = Path()
      ..moveTo(
        innerStart.dx,
        innerStart.dy,
      )
      ..lineTo(
        outerStart.dx,
        outerStart.dy,
      )
      ..lineTo(
        outerEnd.dx,
        outerEnd.dy,
      )
      ..lineTo(
        innerEnd.dx,
        innerEnd.dy,
      )
      ..close();

    canvas.drawPath(
      path,
      paint,
    );
  }

  // ==========================================================
  // GRID
  // ==========================================================

  void _drawGrid(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final Paint gridPaint = Paint()
      ..color = Colors.green.withOpacity(
        0.38,
      )
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    const int rangeSections = 4;

    for (
      int section = 1;
      section <= rangeSections;
      section++
    ) {
      final double sectionRadius =
          radius *
              section /
              rangeSections;

      final Rect arcRect =
          Rect.fromCircle(
        center: center,
        radius: sectionRadius,
      );

      canvas.drawArc(
        arcRect,
        math.pi,
        math.pi,
        false,
        gridPaint,
      );

      final double distance =
          maxDistance *
              section /
              rangeSections;

      final TextPainter label =
          TextPainter(
        text: TextSpan(
          text:
              '${distance.round()} cm',
          style: TextStyle(
            color: Colors.green.withOpacity(
              0.80,
            ),
            fontSize: 11,
          ),
        ),
        textDirection:
            TextDirection.ltr,
      )..layout();

      label.paint(
        canvas,
        Offset(
          center.dx + 5,
          center.dy -
              sectionRadius -
              14,
        ),
      );
    }

    canvas.drawLine(
      Offset(
        center.dx - radius,
        center.dy,
      ),
      Offset(
        center.dx + radius,
        center.dy,
      ),
      gridPaint,
    );

    for (
      int angle = 0;
      angle <= 180;
      angle += 30
    ) {
      final Offset endpoint =
          _polarToCanvas(
        center: center,
        radius: radius,
        angle:
            angle.toDouble(),
      );

      canvas.drawLine(
        center,
        endpoint,
        gridPaint,
      );

      final Offset labelPosition =
          _polarToCanvas(
        center: center,
        radius: radius + 20,
        angle:
            angle.toDouble(),
      );

      final TextPainter angleLabel =
          TextPainter(
        text: TextSpan(
          text: '$angle°',
          style: TextStyle(
            color: Colors.green.withOpacity(
              0.82,
            ),
            fontSize: 11,
          ),
        ),
        textDirection:
            TextDirection.ltr,
      )..layout();

      angleLabel.paint(
        canvas,
        Offset(
          labelPosition.dx -
              angleLabel.width /
                  2,
          labelPosition.dy -
              angleLabel.height /
                  2,
        ),
      );
    }
  }

  // ==========================================================
  // RAW READINGS
  //
  // NO LINES.
  // ==========================================================

  void _drawRawReadings(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final List<MapEntry<int, double>> entries =
        readings.entries.toList()
          ..sort(
            (a, b) => a.key.compareTo(
              b.key,
            ),
          );

    for (final entry in entries) {
      final double distance =
          entry.value;

      if (distance <= 0 ||
          distance > maxDistance) {
        continue;
      }

      final Offset point =
          _polarToCanvas(
        center: center,
        radius:
            radius *
                distance /
                maxDistance,
        angle:
            entry.key.toDouble(),
      );

      final Color color =
          _distanceColor(
        distance,
      );

      canvas.drawCircle(
        point,
        8,
        Paint()
          ..color =
              color.withOpacity(
            0.18,
          ),
      );

      canvas.drawCircle(
        point,
        3.5,
        Paint()
          ..color = color,
      );
    }
  }

  // ==========================================================
  // PROCESSED READINGS
  //
  // Lines are intentionally conservative.
  // ==========================================================

  void _drawProcessedReadings(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final List<MapEntry<int, double>> entries =
        readings.entries.toList()
          ..sort(
            (a, b) => a.key.compareTo(
              b.key,
            ),
          );

    Offset? previousPoint;
    int? previousAngle;
    double? previousDistance;

    for (final entry in entries) {
      final int angle =
          entry.key;

      final double distance =
          entry.value;

      if (distance <= 0 ||
          distance > maxDistance) {
        previousPoint = null;
        previousAngle = null;
        previousDistance = null;
        continue;
      }

      final Offset point =
          _polarToCanvas(
        center: center,
        radius:
            radius *
                distance /
                maxDistance,
        angle:
            angle.toDouble(),
      );

      final Color color =
          _distanceColor(
        distance,
      );

      bool connectToPrevious = false;

      if (previousPoint != null &&
          previousAngle != null &&
          previousDistance != null) {
        final int angleDifference =
            (angle -
                    previousAngle)
                .abs();

        final double distanceDifference =
            (distance -
                    previousDistance)
                .abs();

        /*
         * Very conservative connection rule.
         *
         * Since processed points are spaced about
         * 2 degrees apart, only directly adjacent
         * samples should normally connect.
         */
        final double allowedJump =
            math.max(
          6.0,
          math.min(
                distance,
                previousDistance,
              ) *
              0.10,
        );

        if (angleDifference <= 2 &&
            distanceDifference <=
                allowedJump) {
          connectToPrevious = true;
        }

        /*
         * Extremely close objects can change depth
         * quickly across adjacent angles.
         */
        else if (angleDifference <= 2 &&
            distance < 35 &&
            previousDistance < 35 &&
            distanceDifference <= 10) {
          connectToPrevious = true;
        }

        /*
         * Do NOT bridge large distance changes.
         */
        else {
          connectToPrevious = false;
        }
      }

      if (connectToPrevious &&
          previousPoint != null) {
        canvas.drawLine(
          previousPoint,
          point,
          Paint()
            ..color =
                color.withOpacity(
              0.85,
            )
            ..strokeWidth = 3
            ..strokeCap =
                StrokeCap.round,
        );
      }

      canvas.drawCircle(
        point,
        8,
        Paint()
          ..color =
              color.withOpacity(
            0.20,
          ),
      );

      canvas.drawCircle(
        point,
        3.5,
        Paint()
          ..color = color,
      );

      previousPoint = point;
      previousAngle = angle;
      previousDistance = distance;
    }
  }

  // ==========================================================
  // ROBOT PATH
  // ==========================================================

  void _drawRobotPath(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    if (pathPoints.isEmpty) {
      return;
    }

    final Paint trailPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(
        0.82,
      )
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final Paint trailPointPaint = Paint()
      ..color = Colors.cyanAccent;

    final List<Offset> canvasPoints =
        [];

    for (final Offset point in pathPoints) {
      final double x =
          point.dx;

      final double y =
          point.dy;

      /*
       * Convert centimeters into radar pixels.
       *
       * maxDistance cm corresponds to radar radius.
       */
      final Offset canvasPoint =
          Offset(
        center.dx +
            (
              x /
              maxDistance
            ) *
                radius,
        center.dy -
            (
              y /
              maxDistance
            ) *
                radius,
      );

      canvasPoints.add(
        canvasPoint,
      );
    }

    if (canvasPoints.length >= 2) {
      final Path path =
          Path()
            ..moveTo(
              canvasPoints.first.dx,
              canvasPoints.first.dy,
            );

      for (
        int i = 1;
        i < canvasPoints.length;
        i++
      ) {
        path.lineTo(
          canvasPoints[i].dx,
          canvasPoints[i].dy,
        );
      }

      canvas.drawPath(
        path,
        trailPaint,
      );
    }

    for (final Offset point
        in canvasPoints) {
      canvas.drawCircle(
        point,
        2.5,
        trailPointPaint,
      );
    }
  }

  // ==========================================================
  // SWEEP
  // ==========================================================

  void _drawSweep(
    Canvas canvas,
    Offset center,
    double radius,
  ) {
    final Offset endpoint =
        _polarToCanvas(
      center: center,
      radius: radius,
      angle: currentAngle,
    );

    final Paint glowPaint = Paint()
      ..color =
          Colors.greenAccent.withOpacity(
        0.18,
      )
      ..strokeWidth = 10
      ..strokeCap =
          StrokeCap.round;

    final Paint linePaint = Paint()
      ..color =
          Colors.greenAccent
      ..strokeWidth = 2
      ..strokeCap =
          StrokeCap.round;

    canvas.drawLine(
      center,
      endpoint,
      glowPaint,
    );

    canvas.drawLine(
      center,
      endpoint,
      linePaint,
    );
  }

  // ==========================================================
  // SENSOR
  // ==========================================================

  void _drawSensor(
    Canvas canvas,
    Offset center,
  ) {
    canvas.drawCircle(
      center,
      16,
      Paint()
        ..color =
            Colors.greenAccent.withOpacity(
          0.20,
        ),
    );

    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color =
            Colors.greenAccent,
    );
  }

  // ==========================================================
  // POLAR -> CANVAS
  // ==========================================================

  Offset _polarToCanvas({
    required Offset center,
    required double radius,
    required double angle,
  }) {
    final double radians =
        math.pi -
        (
          angle *
          math.pi /
          180.0
        );

    return Offset(
      center.dx +
          radius *
              math.cos(
                radians,
              ),
      center.dy -
          radius *
              math.sin(
                radians,
              ),
    );
  }

  // ==========================================================
  // DISTANCE COLORS
  // ==========================================================

  Color _distanceColor(
    double distance,
  ) {
    if (distance < 40) {
      return Colors.red;
    }

    if (distance < 90) {
      return Colors.orange;
    }

    if (distance < 150) {
      return Colors.yellow;
    }

    return Colors.green;
  }

  // ==========================================================
  // REPAINT
  // ==========================================================

  @override
  bool shouldRepaint(
    covariant RadarPainter oldDelegate,
  ) {
    return oldDelegate.currentAngle !=
            currentAngle ||
        oldDelegate.readings !=
            readings ||
        oldDelegate.unknownAngles !=
            unknownAngles ||
        oldDelegate.occludedAngles !=
            occludedAngles ||
        oldDelegate.pathPoints !=
            pathPoints ||
        oldDelegate.maxDistance !=
            maxDistance ||
        oldDelegate.processedMode !=
            processedMode;
  }
}