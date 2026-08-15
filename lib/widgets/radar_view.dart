import 'package:flutter/material.dart';

import '../controllers/radar_controller.dart';
import '../painters/radar_painter.dart';

class RadarView extends StatelessWidget {
  const RadarView({
    super.key,
    required this.controller,
  });

  final RadarController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF030806),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: controller.processedMode
              ? Colors.orangeAccent.withOpacity(0.45)
              : Colors.greenAccent.withOpacity(0.35),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: RadarPainter(
                  currentAngle:
                      controller.currentRadarAngle.toDouble(),

                  readings:
                      Map<int, double>.from(
                    controller.displayedReadings,
                  ),

                  unknownAngles:
                      controller.processedMode
                          ? Set<int>.from(
                              controller.unknownAngles,
                            )
                          : <int>{},

                  occludedAngles:
                      controller.processedMode
                          ? Map<int, double>.from(
                              controller.occludedAngles,
                            )
                          : <int, double>{},

                  pathPoints:
                      controller.processedMode
                          ? List<Offset>.from(
                              controller.localRobotPath,
                            )
                          : const <Offset>[],

                  maxDistance:
                      controller.visibleDistance,

                  processedMode:
                      controller.processedMode,
                ),
              ),
            ),

            // --------------------------------------------------
            // MODE LABEL
            // --------------------------------------------------

            Positioned(
              top: 10,
              left: 10,
              child: _ModeBadge(
                processedMode:
                    controller.processedMode,
              ),
            ),

            // --------------------------------------------------
            // CURRENT DISTANCE
            // --------------------------------------------------

            Positioned(
              top: 10,
              right: 10,
              child: _InfoBox(
                title: 'DISTANCE',
                value:
                    controller.currentDistance > 0
                        ? '${controller.currentDistance.toStringAsFixed(1)} cm'
                        : 'No echo',
                valueColor:
                    controller.currentDistance > 0
                        ? _distanceColor(
                            controller.currentDistance,
                          )
                        : Colors.grey,
              ),
            ),

            // --------------------------------------------------
            // PROCESSED MODE INFORMATION
            // --------------------------------------------------

            if (controller.processedMode)
              Positioned(
                left: 10,
                bottom: 10,
                child: _ProcessedInfo(
                  controller: controller,
                ),
              ),

            // --------------------------------------------------
            // RAW MODE INFO
            // --------------------------------------------------

            if (!controller.processedMode)
              Positioned(
                left: 10,
                bottom: 10,
                child: _RawInfo(
                  controller: controller,
                ),
              ),

            // --------------------------------------------------
            // PATH DISTANCE
            // --------------------------------------------------

            if (controller.processedMode)
              Positioned(
                right: 10,
                bottom: 10,
                child: _InfoBox(
                  title: 'EST. PATH',
                  value:
                      '${controller.totalPathCm.toStringAsFixed(1)} cm',
                  valueColor:
                      Colors.cyanAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _distanceColor(
    double distance,
  ) {
    if (distance < 40) {
      return Colors.redAccent;
    }

    if (distance < 90) {
      return Colors.orangeAccent;
    }

    if (distance < 150) {
      return Colors.yellowAccent;
    }

    return Colors.greenAccent;
  }
}

// ============================================================
// MODE BADGE
// ============================================================

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({
    required this.processedMode,
  });

  final bool processedMode;

  @override
  Widget build(BuildContext context) {
    final Color color =
        processedMode
            ? Colors.orangeAccent
            : Colors.greenAccent;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            processedMode
                ? Icons.auto_graph
                : Icons.radar,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            processedMode
                ? 'PROCESSED'
                : 'RAW',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GENERAL INFO BOX
// ============================================================

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.title,
    required this.value,
    required this.valueColor,
  });

  final String title;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.shade800,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RAW MODE INFO
// ============================================================

class _RawInfo extends StatelessWidget {
  const _RawInfo({
    required this.controller,
  });

  final RadarController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.greenAccent.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.circle,
            size: 8,
            color: Colors.greenAccent,
          ),
          const SizedBox(width: 6),
          Text(
            '${controller.rawReadings.length} raw points',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PROCESSED MODE INFO
// ============================================================

class _ProcessedInfo extends StatelessWidget {
  const _ProcessedInfo({
    required this.controller,
  });

  final RadarController controller;

  @override
  Widget build(BuildContext context) {
    final bool ready =
        controller.processedReady;

    return Container(
      constraints: const BoxConstraints(
        maxWidth: 260,
      ),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.70),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ready
              ? Colors.orangeAccent.withOpacity(0.45)
              : Colors.grey.shade700,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ready
                    ? Icons.check_circle
                    : Icons.sync,
                size: 14,
                color: ready
                    ? Colors.greenAccent
                    : Colors.orangeAccent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  controller.processedProgressLabel,
                  style: TextStyle(
                    color: ready
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            'Surfaces: '
            '${controller.processedReadings.length}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),

          Text(
            'Unknown: '
            '${controller.unknownAngles.length}',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 10,
            ),
          ),

          Text(
            'Blocked: '
            '${controller.occludedAngles.length}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}