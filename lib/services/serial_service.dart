import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialService {
  SerialService({
    this.portName,
    this.baudRate = 115200,
  });

  String? portName;
  int baudRate;

  SerialPort? _port;
  Timer? _readTimer;
  String _buffer = '';

  final StreamController<String> _lineController =
      StreamController<String>.broadcast();

  Stream<String> get lines => _lineController.stream;

  bool get isOpen => _port?.isOpen ?? false;

  List<String> getAvailablePorts() {
    final List<String> ports =
        List<String>.from(
      SerialPort.availablePorts,
    );

    ports.sort();

    return ports;
  }

  bool connect({
    required String port,
    required int baud,
  }) {
    disconnect();

    portName = port;
    baudRate = baud;

    if (!SerialPort.availablePorts.contains(port)) {
      debugPrint(
        'Port not available: $port',
      );

      return false;
    }

    final SerialPort serialPort =
        SerialPort(port);

    if (!serialPort.openReadWrite()) {
      debugPrint(
        'Failed to open $port: '
        '${SerialPort.lastError}',
      );

      serialPort.dispose();

      return false;
    }

    final SerialPortConfig config =
        SerialPortConfig()
          ..baudRate = baud
          ..bits = 8
          ..parity =
              SerialPortParity.none
          ..stopBits = 1
          ..setFlowControl(
            SerialPortFlowControl.none,
          );

    serialPort.config = config;

    config.dispose();

    _port = serialPort;
    _buffer = '';

    _readTimer =
        Timer.periodic(
      const Duration(
        milliseconds: 8,
      ),
      (_) => _readAvailable(),
    );

    debugPrint(
      'Connected to $port @ $baud',
    );

    return true;
  }

  void sendLine(
    String message,
  ) {
    final SerialPort? port =
        _port;

    if (port == null ||
        !port.isOpen) {
      return;
    }

    try {
      final Uint8List bytes =
          Uint8List.fromList(
        utf8.encode(
          '$message\n',
        ),
      );

      port.write(
        bytes,
      );
    } catch (error) {
      debugPrint(
        'Serial write error: $error',
      );
    }
  }

  void _readAvailable() {
    final SerialPort? port =
        _port;

    if (port == null ||
        !port.isOpen) {
      return;
    }

    try {
      final int available =
          port.bytesAvailable;

      if (available <= 0) {
        return;
      }

      final Uint8List bytes =
          port.read(
        available,
        timeout: 0,
      );

      if (bytes.isEmpty) {
        return;
      }

      _buffer += utf8.decode(
        bytes,
        allowMalformed: true,
      );

      _processBuffer();
    } catch (error) {
      debugPrint(
        'Serial read error: $error',
      );
    }
  }

  void _processBuffer() {
    while (_buffer.contains('\n')) {
      final int newlineIndex =
          _buffer.indexOf('\n');

      final String line =
          _buffer
              .substring(
                0,
                newlineIndex,
              )
              .replaceAll(
                '\r',
                '',
              )
              .trim();

      _buffer =
          _buffer.substring(
        newlineIndex + 1,
      );

      if (line.isEmpty) {
        continue;
      }

      debugPrint(
        'SERIAL >>> $line',
      );

      _lineController.add(
        line,
      );
    }
  }

  void disconnect() {
    _readTimer?.cancel();
    _readTimer = null;

    final SerialPort? port =
        _port;

    _port = null;

    if (port == null) {
      return;
    }

    try {
      if (port.isOpen) {
        port.close();
      }
    } catch (_) {}

    try {
      port.dispose();
    } catch (_) {}
  }

  void dispose() {
    disconnect();

    _lineController.close();
  }
}