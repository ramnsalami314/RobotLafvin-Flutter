import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/radar_controller.dart';

import '../widgets/connection_panel.dart';
import '../widgets/drive_controls.dart';
import '../widgets/manual_radar_controls.dart';
import '../widgets/radar_view.dart';
import '../widgets/scan_mode_controls.dart';
import '../widgets/status_panel.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({
    super.key,
  });

  @override
  State<RadarScreen> createState() {
    return _RadarScreenState();
  }
}

class _RadarScreenState
    extends State<RadarScreen> {
  late final RadarController controller;

  final FocusNode _keyboardFocusNode =
      FocusNode();

  final Set<LogicalKeyboardKey>
      _pressedKeys = {};

  @override
  void initState() {
    super.initState();

    controller =
        RadarController();

    controller.addListener(
      _refresh,
    );

    /*
     * IMPORTANT:
     *
     * We no longer automatically connect to COM3.
     *
     * Instead:
     * 1. Scan Windows for available COM ports.
     * 2. Let you choose the correct port.
     * 3. Let you choose USB or HC-05 baud.
     */
    controller.refreshPorts();

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        if (mounted) {
          _keyboardFocusNode
              .requestFocus();
        }
      },
    );
  }

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ==========================================================
  // KEYBOARD CONTROL
  // ==========================================================

  KeyEventResult _handleKeyboard(
    FocusNode node,
    KeyEvent event,
  ) {
    final LogicalKeyboardKey key =
        event.logicalKey;

    String? command;

    if (key ==
        LogicalKeyboardKey.keyW) {
      command = 'W';
    }

    else if (key ==
        LogicalKeyboardKey.keyA) {
      command = 'A';
    }

    else if (key ==
        LogicalKeyboardKey.keyS) {
      command = 'S';
    }

    else if (key ==
        LogicalKeyboardKey.keyD) {
      command = 'D';
    }

    if (command == null) {
      return KeyEventResult.ignored;
    }

    // --------------------------------------------------------
    // KEY DOWN
    // --------------------------------------------------------

    if (event is KeyDownEvent) {
      /*
       * Ignore Windows keyboard-repeat events.
       *
       * The controller already sends a periodic heartbeat.
       */
      if (_pressedKeys.contains(
        key,
      )) {
        return KeyEventResult.handled;
      }

      _pressedKeys.add(
        key,
      );

      controller.startDrive(
        command,
      );

      return KeyEventResult.handled;
    }

    // --------------------------------------------------------
    // KEY UP
    // --------------------------------------------------------

    if (event is KeyUpEvent) {
      _pressedKeys.remove(
        key,
      );

      controller.stopDrive();

      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Focus(
      focusNode:
          _keyboardFocusNode,
      autofocus: true,
      onKeyEvent:
          _handleKeyboard,
      child: GestureDetector(
        behavior:
            HitTestBehavior.translucent,
        onTap: () {
          _keyboardFocusNode
              .requestFocus();
        },
        child: Scaffold(
          backgroundColor:
              const Color(
            0xFF040806,
          ),

          // ==================================================
          // APP BAR
          // ==================================================

          appBar: AppBar(
            backgroundColor:
                const Color(
              0xFF09110E,
            ),
            title: const Text(
              'LAFVIN Sonar Robot',
            ),
            actions: [
              // ----------------------------------------------
              // ZOOM IN
              // ----------------------------------------------

              IconButton(
                tooltip:
                    'Zoom in',
                onPressed:
                    controller.visibleDistance >
                            RadarController
                                .minimumVisibleDistance
                        ? controller.zoomIn
                        : null,
                icon: const Icon(
                  Icons.add,
                ),
              ),

              Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 4,
                  ),
                  child: Text(
                    '${controller.visibleDistance.round()} cm',
                    style:
                        const TextStyle(
                      color:
                          Colors.greenAccent,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // ----------------------------------------------
              // ZOOM OUT
              // ----------------------------------------------

              IconButton(
                tooltip:
                    'Zoom out',
                onPressed:
                    controller.visibleDistance <
                            RadarController
                                .maxRadarDistance
                        ? controller.zoomOut
                        : null,
                icon: const Icon(
                  Icons.remove,
                ),
              ),

              // ----------------------------------------------
              // CLEAR RADAR
              // ----------------------------------------------

              IconButton(
                tooltip:
                    'Clear radar data',
                onPressed:
                    controller.clearRadar,
                icon: const Icon(
                  Icons.delete_outline,
                ),
              ),
            ],
          ),

          // ==================================================
          // BODY
          // ==================================================

          body: SafeArea(
            child: Column(
              children: [
                // --------------------------------------------
                // CONNECTION
                // --------------------------------------------

                ConnectionPanel(
                  controller:
                      controller,
                ),

                // --------------------------------------------
                // CURRENT STATUS
                // --------------------------------------------

                StatusPanel(
                  controller:
                      controller,
                ),

                // --------------------------------------------
                // RAW / PROCESSED
                // --------------------------------------------

                ScanModeControls(
                  controller:
                      controller,
                ),

                // --------------------------------------------
                // RADAR
                // --------------------------------------------

                Expanded(
                  child: RadarView(
                    controller:
                        controller,
                  ),
                ),

                // --------------------------------------------
                // MANUAL SERVO
                // --------------------------------------------

                ManualRadarControls(
                  controller:
                      controller,
                  onInteractionComplete:
                      () {
                    _keyboardFocusNode
                        .requestFocus();
                  },
                ),

                // --------------------------------------------
                // WASD
                // --------------------------------------------

                DriveControls(
                  controller:
                      controller,
                  onInteractionComplete:
                      () {
                    _keyboardFocusNode
                        .requestFocus();
                  },
                ),

                const SizedBox(
                  height: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    controller.removeListener(
      _refresh,
    );

    controller.dispose();

    _keyboardFocusNode
        .dispose();

    super.dispose();
  }
}