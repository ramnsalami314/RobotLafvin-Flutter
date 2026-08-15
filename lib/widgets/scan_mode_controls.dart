import 'package:flutter/material.dart';

import '../../controllers/radar_controller.dart';

class ScanModeControls extends StatelessWidget {
  const ScanModeControls({
    super.key,
    required this.controller,
  });

  final RadarController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1713),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'SCAN MODE',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Raw'),
                  selected:
                      controller.renderMode ==
                          RadarRenderMode.raw,
                  onSelected: (_) {
                    controller.setRenderMode(
                      RadarRenderMode.raw,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Processed'),
                  selected:
                      controller.renderMode ==
                          RadarRenderMode.processed,
                  onSelected: (_) {
                    controller.setRenderMode(
                      RadarRenderMode.processed,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            controller.renderMode ==
                    RadarRenderMode.raw
                ? 'Raw mode: immediate points, no lines.'
                : controller.processedProgressLabel,
            style: TextStyle(
              color:
                  controller.processedReady
                      ? Colors.orangeAccent
                      : Colors.grey.shade300,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}