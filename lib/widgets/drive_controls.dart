import 'package:flutter/material.dart';

import '../controllers/radar_controller.dart';

class DriveControls extends StatelessWidget {
  const DriveControls({
    super.key,
    required this.controller,
    required this.onInteractionComplete,
  });

  final RadarController controller;
  final VoidCallback onInteractionComplete;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      margin:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      padding:
          const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            const Color(
          0xFF0D1713,
        ),
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Text(
            'WASD DRIVE',
            style: TextStyle(
              fontWeight:
                  FontWeight.bold,
              color:
                  Colors.blueAccent,
            ),
          ),
          _driveButton('W'),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              _driveButton('A'),
              _stopButton(),
              _driveButton('D'),
            ],
          ),
          _driveButton('S'),
        ],
      ),
    );
  }

  Widget _driveButton(
    String command,
  ) {
    final active =
        controller.activeDriveCommand ==
            command;

    return Listener(
      onPointerDown:
          controller.isConnected
              ? (_) {
                  controller.startDrive(
                    command,
                  );
                }
              : null,
      onPointerUp:
          controller.isConnected
              ? (_) {
                  controller.stopDrive();
                  onInteractionComplete();
                }
              : null,
      onPointerCancel:
          controller.isConnected
              ? (_) {
                  controller.stopDrive();
                }
              : null,
      child: Container(
        width: 55,
        height: 42,
        margin:
            const EdgeInsets.all(3),
        alignment:
            Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? Colors.blueAccent
                  .withValues(
                  alpha: 0.4,
                )
              : Colors.blueAccent
                  .withValues(
                  alpha: 0.12,
                ),
          borderRadius:
              BorderRadius.circular(8),
          border: Border.all(
            color:
                Colors.blueAccent,
          ),
        ),
        child: Text(
          command,
          style:
              const TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _stopButton() {
    return SizedBox(
      width: 55,
      height: 42,
      child: ElevatedButton(
        onPressed:
            controller.isConnected
                ? () {
                    controller.stopDrive();
                    onInteractionComplete();
                  }
                : null,
        style:
            ElevatedButton.styleFrom(
          padding:
              EdgeInsets.zero,
          backgroundColor:
              Colors.red.shade800,
        ),
        child: const Text(
          'STOP',
          style:
              TextStyle(
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
