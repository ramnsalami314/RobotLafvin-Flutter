import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialService {
  SerialService({
    required this.portName,
    this.baudRate = 9600,
  });

  String portName;
  int baudRate;

  SerialPort? _port;

  Timer? _readTimer;

  String _buffer = '';

  final StreamController<String> _lineController =
      StreamController<String>.broadcast();

  Stream<String> get lines =>
      _lineController.stream;

  bool get isOpen =>
      _port?.isOpen ?? false;

  bool connect() {
    disconnect();

    if (!SerialPort.availablePorts.contains(portName)) {
      debugPrint(
        'Port not found: $portName',
      );

      return false;
    }

    final SerialPort port =
        SerialPort(portName);

    if (!port.openReadWrite()) {
      debugPrint(
        'Could not open $portName: '
        '${SerialPort.lastError}',
      );

      port.dispose();

      return false;
    }

    final SerialPortConfig config =
        SerialPortConfig()
          ..baudRate = baudRate
          ..bits = 8
          ..parity = SerialPortParity.none
          ..stopBits = 1
          ..setFlowControl(
            SerialPortFlowControl.none,
          );

    port.config = config;

    config.dispose();

    _port = port;

    _readTimer = Timer.periodic(
      const Duration(
        milliseconds: 10,
      ),
      (_) => _readAvailable(),
    );

    debugPrint(
      'Connected to $portName @ $baudRate',
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
        'UART write error: $error',
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
        'UART read error: $error',
      );
    }
  }

  void _processBuffer() {
    while (_buffer.contains('\n')) {
      final int index =
          _buffer.indexOf('\n');

      final String line =
          _buffer
              .substring(
                0,
                index,
              )
              .replaceAll(
                '\r',
                '',
              )
              .trim();

      _buffer =
          _buffer.substring(
        index + 1,
      );

      if (line.isNotEmpty) {
        _lineController.add(
          line,
        );
      }
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