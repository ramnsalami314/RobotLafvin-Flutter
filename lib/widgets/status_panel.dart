import 'package:flutter/material.dart';

import '../controllers/radar_controller.dart';

class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.controller,
  });

  final RadarController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1713),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              controller.isConnected
                  ? Colors.green
                  : Colors.red,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 15,
        runSpacing: 8,
        children: [
          Text(controller.connectionMessage),
          Text(
            'Mode: ${controller.renderMode == RadarRenderMode.raw ? 'RAW' : 'PROCESSED'}',
          ),
          Text(
            'Servo: ${controller.currentServoAngle}°',
          ),
          Text(
            'Radar: ${controller.currentRadarAngle}°',
          ),
          Text(
            controller.currentDistance > 0
                ? '${controller.currentDistance.toStringAsFixed(1)} cm'
                : 'No echo',
          ),
          Text(
            'Drive: ${controller.driveStatus}',
          ),
          Text(
            'Path: ${controller.totalPathCm.toStringAsFixed(1)} cm',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            controller.manualRadar
                ? 'Radar: MANUAL'
                : 'Radar: AUTO',
            style: TextStyle(
              color:
                  controller.manualRadar
                      ? Colors.orangeAccent
                      : Colors.greenAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}