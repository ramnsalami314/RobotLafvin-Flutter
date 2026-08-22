import 'package:flutter/material.dart';

import '../controllers/radar_controller.dart';

class ConnectionPanel extends StatelessWidget {
  const ConnectionPanel({
    super.key,
    required this.controller,
  });

  final RadarController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        12,
        12,
        12,
        4,
      ),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1713),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: controller.isConnected
              ? Colors.green
              : Colors.grey.shade700,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // ------------------------------------------------
              // COM PORT
              // ------------------------------------------------

              Expanded(
                child: DropdownButtonFormField<String>(
                  value:
                      controller.availablePorts.contains(
                    controller.selectedPort,
                  )
                          ? controller.selectedPort
                          : null,
                  decoration: const InputDecoration(
                    labelText: 'COM port',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: controller.availablePorts
                      .map(
                        (String port) {
                          return DropdownMenuItem<String>(
                            value: port,
                            child: Text(port),
                          );
                        },
                      )
                      .toList(),
                  onChanged: controller.isConnected
                      ? null
                      : controller.selectPort,
                ),
              ),

              const SizedBox(width: 10),

              // ------------------------------------------------
              // BAUD RATE
              // ------------------------------------------------

              SizedBox(
                width: 165,
                child: DropdownButtonFormField<int>(
                  value: controller.selectedBaud,
                  decoration: const InputDecoration(
                    labelText: 'Connection type',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem<int>(
                      value: 115200,
                      child: Text(
                        'USB - 115200',
                      ),
                    ),
                    DropdownMenuItem<int>(
                      value: 9600,
                      child: Text(
                        'HC-05 - 9600',
                      ),
                    ),
                    DropdownMenuItem<int>(
                      value: 38400,
                      child: Text(
                        '38400',
                      ),
                    ),
                  ],
                  onChanged: controller.isConnected
                      ? null
                      : (int? value) {
                          if (value == null) {
                            return;
                          }

                          controller.selectBaud(
                            value,
                          );
                        },
                ),
              ),

              const SizedBox(width: 8),

              // ------------------------------------------------
              // REFRESH
              // ------------------------------------------------

              IconButton(
                tooltip: 'Refresh COM ports',
                onPressed: controller.isConnected
                    ? null
                    : controller.refreshPorts,
                icon: const Icon(
                  Icons.refresh,
                ),
              ),

              const SizedBox(width: 4),

              // ------------------------------------------------
              // CONNECT / DISCONNECT
              // ------------------------------------------------

              ElevatedButton.icon(
                onPressed: controller.isConnected
                    ? controller.disconnect
                    : controller.connectSelectedPort,
                icon: Icon(
                  controller.isConnected
                      ? Icons.link_off
                      : Icons.link,
                ),
                label: Text(
                  controller.isConnected
                      ? 'Disconnect'
                      : 'Connect',
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Icon(
                controller.isConnected
                    ? Icons.check_circle
                    : Icons.info_outline,
                size: 16,
                color: controller.isConnected
                    ? Colors.greenAccent
                    : Colors.grey.shade400,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  controller.connectionMessage,
                  style: TextStyle(
                    color: controller.isConnected
                        ? Colors.greenAccent
                        : Colors.grey.shade300,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          if (controller.availablePorts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: 8,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber,
                    color: Colors.orangeAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'No COM ports are currently visible. '
                      'Connect the Arduino or pair the HC-05, then press refresh.',
                      style: TextStyle(
                        color: Colors.orange.shade200,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}