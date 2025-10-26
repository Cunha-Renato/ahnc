import 'package:ahnc/device_info.dart';
import 'package:ahnc/widgets/debug_console.dart';
import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';

class ConnectionManagerPage extends StatefulWidget {
    const ConnectionManagerPage({super.key});

    @override
    State<ConnectionManagerPage> createState() => _ConnectionManagerPageState();
}

class _ConnectionManagerPageState extends State<ConnectionManagerPage> {
    @override
    void initState() {
        super.initState();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_ConnectionManager().isInitialized()) {
                _showPrompt();
            }
        });
    }

    Future<void> _showPrompt() async {
        final controller = TextEditingController();

        final result = await showDialog<String>(
            context: context, 
            builder: (context) {
                return StatefulBuilder(
                    builder: (context, setState) {
                        return AlertDialog(
                            title: const Text('Enter Connection Name'),
                            content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(hintText: 'Connection Name'),
                                onChanged: (_) => setState(() {}),
                            ),
                            actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                ),
                                if (controller.text.isNotEmpty)
                                    TextButton(
                                        onPressed: () => Navigator.of(context).pop(controller.text),
                                        child: const Text('OK'),
                                    ),
                            ],
                        );
                    },
                );
            },
        );
        
        if (result != null && result.isNotEmpty) {
            setState(() {
                _ConnectionManager().init(result);
            });
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: const Text('Connections'),
                backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            ),
            body: Container(
                padding: const EdgeInsets.all(5.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        _ConnectionManager().isInitialized()
                            ? Text("Connection name: ${_ConnectionManager().deviceName}")
                            : ElevatedButton(
                                onPressed: () {
                                    _showPrompt();
                                }, 
                                child: const Text('Set Connection Name')
                            ),
                        ValueListenableBuilder(
                            valueListenable: _ConnectionManager().isRunning, 
                            builder: (context, isRunning, _) {
                                return TextButton(
                                    onPressed: () async {
                                        if (isRunning) {
                                            await _ConnectionManager()._end();
                                        } else {
                                            await _ConnectionManager()._begin();
                                        }
                                    }, 
                                    child: isRunning
                                        ? const Text('Stop')
                                        : const Text('Start')
                                );
                            }
                        ),
                    ],
                )
            ),
        );
    }
}

// This is a singleton because I don't know how to keep state between pages.
class _ConnectionManager {
    static final _ConnectionManager _instancee = _ConnectionManager._();
    final String serviceId = 'com.ahnc';
    final strategy = Strategy.P2P_CLUSTER;
    final nearby = Nearby();
    final connectedDevices = <String, DeviceInfo>{};
    final devicesAboutToConnect = <String, DeviceInfo>{};
    ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);

    String? deviceName;

    _ConnectionManager._();
    factory _ConnectionManager() => _instancee;

    void init(String name) {
        if (deviceName != null) return;
        deviceName = name;
    }

    bool isInitialized() {
        return deviceName != null;
    }

    bool isConnectedTo(String id) {
        return connectedDevices.containsKey(id);
    }
    
    bool isConnectingTo(String id) {
        return devicesAboutToConnect.containsKey(id) || isConnectedTo(id);
    }

    Future<void> _begin() async {
        await _startAdvertising();
        await _startDiscovery();
        isRunning.value = true;
    }
    
    Future<void> _end() async {
        await nearby.stopAdvertising();
        await nearby.stopAllEndpoints();
        await nearby.stopDiscovery();
        isRunning.value = false;
    }

    Future<void> _startAdvertising() async {
        if (!isInitialized()) {
            logError("ConnectionManager is not initialized.");
        }

        tryLogAsync(DebugMessageType.error, () async {
            await nearby.startAdvertising(
                deviceName!,
                serviceId: serviceId,
                Strategy.P2P_CLUSTER,
                onConnectionInitiated: onConnectionInitiated,
                onConnectionResult: onConnectionResult,
                onDisconnected: onDisconnected,
            );

            DebugConsole.log(DebugMessageType.info, 'Started advertising');
        });
    }

    Future<void> _startDiscovery() async {
        if (!isInitialized()) {
            logError("ConnectionManager is not initialized.");
        }
        
        tryLogAsync(DebugMessageType.error, () async {
            await nearby.startDiscovery(
                deviceName!, 
                strategy, 
                serviceId: serviceId,
                onEndpointFound: onEndpointFound,
                onEndpointLost: onEndpointLost,
            );

            DebugConsole.log(DebugMessageType.info, 'Started discovery');
        });
    }
    
    void onConnectionInitiated(String id, ConnectionInfo info) {
        DebugConsole.log(DebugMessageType.info, 'Connection initiated from ${info.endpointName} ($id).');

        tryLogAsync(DebugMessageType.error, () async {
            if (!isConnectingTo(id)) return;

            await nearby.acceptConnection(
                id, 
                onPayLoadRecieved: (_, _) {}
            );
        });
    }
    
    void onConnectionResult(String id, Status status) {
        DebugConsole.log(DebugMessageType.info, 'Connection result from $id: $status');
        DeviceInfo? deviceInfo = devicesAboutToConnect.remove(id);

        tryLog(DebugMessageType.error, () {
            switch (status) {
                case Status.CONNECTED:
                    connectedDevices[id] = deviceInfo!;
                    break;
                default:
                    break;
            }
        });
    }
    
    void onDisconnected(String id) {
        devicesAboutToConnect.remove(id);
        DeviceInfo? deviceInfo = connectedDevices.remove(id);
        String deviceName = deviceInfo?.name ?? "Unknown Device";
        DebugConsole.log(DebugMessageType.info, 'Disconnected from $deviceName ($id)');
    }
    
    void onEndpointFound(String id, String name, String serviceId) {
        DebugConsole.log(DebugMessageType.info, 'Endpoint found: $name ($id)');
        tryLogAsync(DebugMessageType.error, () async {
            if (!isConnectingTo(id)) {
                devicesAboutToConnect[id] = DeviceInfo(name);

                await nearby.requestConnection(
                    deviceName!,
                    id, 
                    onConnectionInitiated: onConnectionInitiated, 
                    onConnectionResult: onConnectionResult, 
                    onDisconnected: onDisconnected
                );
            }
        });
    }
    
    void onEndpointLost(String? id) {
        if (id == null) return;

        devicesAboutToConnect.remove(id);
        DebugConsole.log(DebugMessageType.info, 'Endpoint lost: $id');
    }
}