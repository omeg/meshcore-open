import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/main.dart';

class _TestConnector extends MeshCoreConnector {
  _TestConnector({
    required MeshCoreConnectionState state,
    required MeshCoreTransportType transport,
  }) : _state = state,
       _transport = transport;

  MeshCoreConnectionState _state;
  final MeshCoreTransportType _transport;
  int disconnectCallCount = 0;
  bool? lastManual;

  @override
  MeshCoreConnectionState get state => _state;

  @override
  MeshCoreTransportType get activeTransport => _transport;

  @override
  Future<void> disconnect({
    bool manual = true,
    bool skipBleDeviceDisconnect = false,
  }) async {
    disconnectCallCount += 1;
    lastManual = manual;
    _state = MeshCoreConnectionState.disconnected;
  }
}

void main() {
  testWidgets(
    'desktop app exit manually disconnects an active BLE connection',
    (tester) async {
      final connector = _TestConnector(
        state: MeshCoreConnectionState.connected,
        transport: MeshCoreTransportType.bluetooth,
      );

      await tester.pumpWidget(
        DesktopBleExitObserver(
          connector: connector,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );

      final response = await tester.binding.handleRequestAppExit();

      expect(response, AppExitResponse.exit);
      expect(connector.disconnectCallCount, 1);
      expect(connector.lastManual, isTrue);
    },
  );

  testWidgets('desktop app exit ignores non-BLE transports', (tester) async {
    final connector = _TestConnector(
      state: MeshCoreConnectionState.connected,
      transport: MeshCoreTransportType.tcp,
    );

    await tester.pumpWidget(
      DesktopBleExitObserver(
        connector: connector,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );

    final response = await tester.binding.handleRequestAppExit();

    expect(response, AppExitResponse.exit);
    expect(connector.disconnectCallCount, 0);
  });

  testWidgets('desktop app exit ignores BLE scans without a session', (
    tester,
  ) async {
    final connector = _TestConnector(
      state: MeshCoreConnectionState.scanning,
      transport: MeshCoreTransportType.bluetooth,
    );

    await tester.pumpWidget(
      DesktopBleExitObserver(
        connector: connector,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );

    final response = await tester.binding.handleRequestAppExit();

    expect(response, AppExitResponse.exit);
    expect(connector.disconnectCallCount, 0);
  });
}
