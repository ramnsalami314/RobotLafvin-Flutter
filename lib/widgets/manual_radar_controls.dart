import 'package:flutter/material.dart';

import '../controllers/radar_controller.dart';

class ManualRadarControls
    extends StatelessWidget {
  const ManualRadarControls({
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
          const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color:
            const Color(
          0xFF0D1713,
        ),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: controller.manualRadar
              ? Colors.orangeAccent
              : Colors.green.withValues(
                  alpha: 0.4,
                ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.radar,
              ),
              const SizedBox(
                width: 8,
              ),
              const Expanded(
                child: Text(
                  'Manual radar aiming',
                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
              Switch(
                value:
                    controller.manualRadar,
                onChanged:
                    controller.isConnected
                        ? (value) {
                            controller
                                .setManualRadar(
                              value,
                            );

                            onInteractionComplete();
                          }
                        : null,
              ),
            ],
          ),
          if (controller.manualRadar)
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    controller
                        .nudgeManualServo(
                      -2,
                    );

                    onInteractionComplete();
                  },
                  icon: const Icon(
                    Icons.chevron_left,
                  ),
                ),
                Expanded(
                  child: Slider(
                    min: 5,
                    max: 175,
                    divisions: 85,
                    value: controller
                        .manualServoAngle,
                    label:
                        '${controller.manualServoAngle.round()}°',
                    onChanged: controller
                        .setManualServoAngle,
                    onChangeEnd: (_) {
                      controller
                          .sendManualServoAngle();

                      onInteractionComplete();
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    controller
                        .nudgeManualServo(
                      2,
                    );

                    onInteractionComplete();
                  },
                  icon: const Icon(
                    Icons.chevron_right,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${controller.manualServoAngle.round()}°',
                    textAlign:
                        TextAlign.center,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}