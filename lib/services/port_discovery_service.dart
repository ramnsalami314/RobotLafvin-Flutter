import 'dart:io';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:serial_port_win32/serial_port_win32.dart'
    as win_serial;

class DiscoveredPort {
  const DiscoveredPort({
    required this.portName,
    required this.friendlyName,
    required this.hardwareId,
    required this.isBluetooth,
  });

  final String portName;
  final String friendlyName;
  final String hardwareId;
  final bool isBluetooth;

  @override
  String toString() {
    if (friendlyName.isEmpty) {
      return portName;
    }

    return '$friendlyName — $portName';
  }
}

class PortDiscoveryService {
  static List<DiscoveredPort> findPorts() {
    if (Platform.isWindows) {
      return _findWindowsPorts();
    }

    return SerialPort.availablePorts
        .map(
          (name) => DiscoveredPort(
            portName: name,
            friendlyName: name,
            hardwareId: '',
            isBluetooth: false,
          ),
        )
        .toList();
  }

  static List<DiscoveredPort> _findWindowsPorts() {
    final List<DiscoveredPort> result = [];

    try {
      final ports =
          win_serial.SerialPort.getPortsWithFullMessages();

      for (final info in ports) {
        final String friendly =
            info.friendlyName.toLowerCase();

        final String hardware =
            info.hardwareID.toLowerCase();

        final String manufacturer =
            info.manufactureName.toLowerCase();

        final bool bluetooth =
            hardware.contains('bthenum') ||
                hardware.contains('bluetooth') ||
                friendly.contains('bluetooth') ||
                friendly.contains(
                  'standard serial over bluetooth',
                ) ||
                manufacturer.contains('bluetooth');

        result.add(
          DiscoveredPort(
            portName: info.portName,
            friendlyName: info.friendlyName,
            hardwareId: info.hardwareID,
            isBluetooth: bluetooth,
          ),
        );
      }
    } catch (_) {
      for (final name in SerialPort.availablePorts) {
        result.add(
          DiscoveredPort(
            portName: name,
            friendlyName: name,
            hardwareId: '',
            isBluetooth: false,
          ),
        );
      }
    }

    result.sort((a, b) {
      if (a.isBluetooth && !b.isBluetooth) {
        return -1;
      }

      if (!a.isBluetooth && b.isBluetooth) {
        return 1;
      }

      return a.portName.compareTo(b.portName);
    });

    return result;
  }

  static DiscoveredPort? findLikelyBluetoothPort() {
    final ports = findPorts();

    for (final port in ports) {
      if (port.isBluetooth) {
        return port;
      }
    }

    return null;
  }
}