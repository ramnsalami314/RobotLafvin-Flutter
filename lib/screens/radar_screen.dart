import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/radar_controller.dart';
import '../widgets/drive_controls.dart';
import '../widgets/manual_radar_controls.dart';
import '../widgets/radar_view.dart';
import '../widgets/scan_mode_controls.dart';
import '../widgets/status_panel.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() =>
      _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  late final RadarController controller;

  final FocusNode _keyboardFocusNode =
      FocusNode();

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  @override
  void initState() {
    super.initState();

    controller = RadarController();
    controller.addListener(_refresh);
    controller.connect();

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _keyboardFocusNode.requestFocus(),
    );
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleKeyboard(
    FocusNode node,
    KeyEvent event,
  ) {
    final key = event.logicalKey;

    String? command;

    if (key == LogicalKeyboardKey.keyW) {
      command = 'W';
    } else if (key == LogicalKeyboardKey.keyA) {
      command = 'A';
    } else if (key == LogicalKeyboardKey.keyS) {
      command = 'S';
    } else if (key == LogicalKeyboardKey.keyD) {
      command = 'D';
    }

    if (command == null) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      if (_pressedKeys.contains(key)) {
        return KeyEventResult.handled;
      }

      _pressedKeys.add(key);
      controller.startDrive(command);
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      _pressedKeys.remove(key);
      controller.stopDrive();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyboard,
      child: GestureDetector(
        onTap: () =>
            _keyboardFocusNode.requestFocus(),
        child: Scaffold(
          backgroundColor: const Color(0xFF040806),
          appBar: AppBar(
            backgroundColor: const Color(0xFF09110E),
            title: const Text('LAFVIN Radar'),
            actions: [
              IconButton(
                onPressed: controller.visibleDistance >
                        RadarController
                            .minimumVisibleDistance
                    ? controller.zoomIn
                    : null,
                icon: const Icon(Icons.add),
              ),
              Center(
                child: Text(
                  '${controller.visibleDistance.round()} cm',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                  ),
                ),
              ),
              IconButton(
                onPressed: controller.visibleDistance <
                        RadarController.maxRadarDistance
                    ? controller.zoomOut
                    : null,
                icon: const Icon(Icons.remove),
              ),
              IconButton(
                onPressed: controller.clearRadar,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                StatusPanel(controller: controller),
                ScanModeControls(controller: controller),
                Expanded(
                  child: RadarView(controller: controller),
                ),
                ManualRadarControls(
                  controller: controller,
                  onInteractionComplete: () =>
                      _keyboardFocusNode.requestFocus(),
                ),
                DriveControls(
                  controller: controller,
                  onInteractionComplete: () =>
                      _keyboardFocusNode.requestFocus(),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }
}