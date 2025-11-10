import 'dart:async';
import 'dart:convert';

import 'package:ahnc/message.dart';
import 'package:ahnc/widgets/debug_console.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

class DeviceUuid {
    final String uuid;

    DeviceUuid(): uuid = Uuid().v4();

    DeviceUuid.fromString(this.uuid);
    
    @override
    String toString() => uuid;
    
    @override
    bool operator ==(Object other) =>
        identical(this, other) 
        || other is DeviceUuid 
        && runtimeType == other.runtimeType 
        && uuid == other.uuid;

    @override
    int get hashCode => uuid.hashCode;
}

enum DeviceStatus { 
    connected,
    connecting, 
    discovered, 
    blocked,
}
int _statusToNumber(DeviceStatus status) {
    switch (status) {
        case DeviceStatus.connected: return 0;
        case DeviceStatus.connecting: return 1;
        case DeviceStatus.discovered: return 2;
        case DeviceStatus.blocked: return 3;
    }
}

class NearbyDevice {
    final DeviceUuid uuid;
    String? name;
    String connectionId;
    DeviceStatus status;
    List<FarawayDevice> table = [];

    NearbyDevice({
        required this.uuid,
        required this.connectionId,
        required this.status
    });

    @override
    String toString() {
        return 'NearbyDevice {\n'
            '    uuid: "${uuid}",\n'
            '    name: "${name}",\n'
            '    connection_id: "${connectionId}",\n'
            '    status: ${status.name},\n'
           '}';
    }
}

class FarawayDevice {
    final DeviceUuid uuid;
    final String deviceName;
    int cost;
    
    FarawayDevice(this.uuid, this.deviceName, this.cost);

    factory FarawayDevice.fromJson(Map<String, dynamic> json) {
        return FarawayDevice(
            DeviceUuid.fromString(json['uuid'] as String), 
            json['deviceName'] as String,
            json['cost'] as int
        );
    }
    
    Map<String, dynamic> toJson() => {
        'uuid': uuid.toString(),
        'deviceName': deviceName,
        'cost': cost
    };
}

class NearbyManager extends ChangeNotifier {
    static final NearbyManager _instance = NearbyManager._internal();
    static final _routingManager = RoutingManager();
    static final _localUuid = DeviceUuid();
    static const _strategy = Strategy.P2P_CLUSTER;

    factory NearbyManager() => _instance;
    NearbyManager._internal() {
        _startAdvertising();
        
        Timer.periodic(const Duration(seconds: 15), (_) async {
            final snapshot = Map<DeviceUuid, NearbyDevice>.from(_devices);

            for (final nearby in snapshot.values) {
                tryLogAsync(DebugMessageType.error, () async {
                    await _onSendMessage(
                        nearby,
                        RouteUpdateMessage(
                            source: _localUuid,
                            destination: nearby.uuid,
                            nodes: _routingManager._prepareRoutingTableToSend(nearby, snapshot),
                        )
                    );                   
                });
            }
        });
    }
    
    final Map<DeviceUuid, NearbyDevice> _devices = {};
    final Map<DeviceUuid, List<TextMessage>> _textMessages = {};
    final _lock = Lock();
    String? _localEndpointName;
    String _serviceId = 'com.ahnc';
    
    List<NearbyDevice> get devices {
        final result = _devices.values.toList();
        
        result.sort((a, b) => _statusToNumber(a.status).compareTo(_statusToNumber(b.status)));
        return result;
    } 
    RoutingManager get routingManager => _routingManager;
    String? get localEndpointName => _localEndpointName;
    String get serviceId => _serviceId;
    DeviceUuid get localUuid => _localUuid;

    List<TextMessage> getTextMessages(DeviceUuid uuid) {
        return (_textMessages[uuid] ?? []).toList();
    } 
    
    void addTextMessage(DeviceUuid chatUuid, TextMessage message) {
        _textMessages.putIfAbsent(chatUuid, () => []).add(message);
    }

    void blockDevice(DeviceUuid uuid) {
        final device = _devices[uuid];
        if (device == null) return;

        device.status = DeviceStatus.blocked;
        Nearby().disconnectFromEndpoint(device.connectionId);
        notifyListeners();
    }
    
    void unblockDevice(DeviceUuid uuid) {
        final device = _devices[uuid];
        if (device == null) return;

        device.status = DeviceStatus.discovered;
        notifyListeners();
    }
    
    Future<void> configure(String endpointName, String? serviceId) async {
        final shouldBroadcast = _localEndpointName != endpointName;
        _localEndpointName = endpointName;

        if (serviceId != null && serviceId != _serviceId) {
            _serviceId = serviceId;
            return;
        }

        if (shouldBroadcast) {
            for (NearbyDevice device in _devices.values) {
                if (device.status == DeviceStatus.connected) {
                    await _onSendMessage(
                        device,
                        NameUpdateMessage(
                            source: _localUuid,
                            destination: device.uuid, 
                            newName: endpointName
                        )
                    );
                }
            }
        }
    }

    Future<void> _startAdvertising() async {
        await tryLogAsync(DebugMessageType.error, () async {
            await Nearby().startAdvertising(
                _localUuid.toString(), 
                _strategy, 
                onConnectionInitiated: _onConnectionInitiated, 
                onConnectionResult: _onConnectionResult, 
                onDisconnected: _onDisconnected,
                serviceId: _serviceId,
            );
        });
    }

    Future<void> _stopAdvertising() async {
        await tryLogAsync(DebugMessageType.error, () async {
            await Nearby().stopAdvertising();
        });
    }
    
    Future<void> restartAdvertising() async {
        await _stopAdvertising();
        await _startAdvertising();
    }
    
    Future<void> startDiscovery() async {
        await tryLogAsync(DebugMessageType.error, () async {
            await Nearby().startDiscovery(
                _localUuid.toString(),
                _strategy,
                serviceId: _serviceId,
                onEndpointFound: (id, name, serviceId) async {
                    final endpointUuid = DeviceUuid.fromString(name);

                    final device = await _lock.synchronized(() =>
                        _devices.putIfAbsent(
                            endpointUuid, 
                            () => NearbyDevice(
                                uuid: endpointUuid,
                                connectionId: id,
                                status: DeviceStatus.discovered
                            )
                        )
                    );
                    device.connectionId = id;

                    notifyListeners();
                    
                    logDebug("Endpoint found: $device");

                    if (device.status == DeviceStatus.connected || device.status == DeviceStatus.connecting) {
                        logDebug("Endpoint is alwready connected or connecting: returning from onEndpointFound.");
                        return;
                    } else if (device.status == DeviceStatus.blocked) {
                        return;
                    }

                    try {
                        await Nearby().requestConnection(
                            _localUuid.toString(), 
                            id, 
                            onConnectionInitiated: _onConnectionInitiated, 
                            onConnectionResult: _onConnectionResult, 
                            onDisconnected: _onDisconnected
                        );
                    } on PlatformException catch (pe) {
                        if (pe.message == "8003: STATUS_ALREADY_CONNECTED_TO_ENDPOINT") device.status = DeviceStatus.connected;
                    } catch (e) {
                        logError(e.toString());
                    }
                },
                onEndpointLost: (id) async {
                    await _lock.synchronized(() {
                        logDebug("Endpoint lost: $id.");
                        _devices.removeWhere((_, value) => 
                            value.connectionId == id
                            && value.status == DeviceStatus.discovered
                        );
                    });
                    
                    await restartDiscovery();

                    notifyListeners();
                },
              );
        });
    }
    
    Future<void> stopDiscovery() async {
        await Nearby().stopDiscovery();
    }
    
    Future<void> restartDiscovery() async {
        await stopDiscovery();
        await startDiscovery();
    }

    Future<void> disconnectAll() async {
        await Nearby().stopAllEndpoints();
        await _lock.synchronized(() => _devices.clear());
        notifyListeners();
    }
    
    Future<void> _onConnectionInitiated(String id, ConnectionInfo info) async {
        final blocked = await _lock.synchronized(() { 
            final endpointUuid = DeviceUuid.fromString(info.endpointName);
            NearbyDevice device = _devices.putIfAbsent(
                endpointUuid,
                () => NearbyDevice(
                    uuid: endpointUuid,
                    connectionId: id,
                    status: DeviceStatus.connecting
                )
            );
            
            logDebug("Connection Initiated - preview: $device");
            
            device.connectionId = id;
            if (device.status == DeviceStatus.discovered) device.status = DeviceStatus.connecting; 
            
            if (device.status == DeviceStatus.blocked) return true;
            logDebug("Connection Initiated - final: $device");
            
            return false;
        });

        if (blocked) {
            await Nearby().rejectConnection(id);

            return;
        }

        notifyListeners();
        
        await Nearby().acceptConnection(
            id, 
            onPayLoadRecieved: _onPayloadReceived,
        );
    }
    
    void _onPayloadReceived(String id, Payload payload) {
        NearbyDevice? sender = null;

        for (var directDevice in _devices.values) {
            if (directDevice.connectionId == id) {
                sender = directDevice;
                break;
            }
        }
        
        if (sender == null) return;
        
        if (payload.type == PayloadType.BYTES) {
            tryLog(DebugMessageType.error, () {
                final jsonString = utf8.decode(payload.bytes!);
                final Map<String, dynamic> data = jsonDecode(jsonString);
                
                Message? message = 
                    TextMessage.fromJson(data)
                    ?? NameUpdateMessage.fromJson(data)
                    ?? RouteUpdateMessage.fromJson(data)
                    ?? AckMessage.fromJson(data)
                    ?? ErrorMessage.fromJson(data);
                    
                if (message == null) {
                    logWarn("Unknown message format from: ${sender!.name}.\n${jsonString}");
                }
                
                _routingManager._onMessageReceived(sender!, message!);
            });
        }
    }

    Future<void> _onConnectionResult(String id, Status status) async {
        await _lock.synchronized(() async {
            NearbyDevice? device = null;

            for (var directDevice in _devices.values) {
                if (directDevice.connectionId == id) {
                    device = directDevice;
                    break;
                }
            }
            
            logDebug("Connection Result - preview: $device\n$status");

            if (device == null) return;
            
            if (status == Status.CONNECTED) {
                device.status = DeviceStatus.connected;
                if (_localEndpointName != null) {
                    await _onSendMessage(device, NameUpdateMessage(
                        source: _localUuid,
                        destination: device.uuid, 
                        newName: _localEndpointName!
                    ));
                }
            } else {
                if (device.status != DeviceStatus.blocked)
                    device.status = DeviceStatus.discovered;
            }
            
            logDebug("Connection Result - final: $device");
        });
        
        notifyListeners();
    }
    
    Future<void> _onDisconnected(String id) async {
        logDebug("Disconnected: $id");
        await _lock.synchronized(() => _devices.values.forEach((device) {
            if (device.connectionId == id && device.status != DeviceStatus.blocked) device.status = DeviceStatus.discovered;
        }));
        
        notifyListeners();
    }

    Future<T> _onModifyNearbyDevices<T>(Future<T> Function(Map<DeviceUuid, NearbyDevice> devices) func) async {
        final result = await _lock.synchronized(() async => await func(_devices));

        notifyListeners();
        return result;
    }

    Future<void> _onSendMessage(NearbyDevice destination, Message message) async {
        await tryLogAsync(DebugMessageType.error, () async {
            final jsonString = jsonEncode(message.toJson());
            final bytes = Uint8List.fromList(utf8.encode(jsonString));
            
            await Nearby().sendBytesPayload(destination.connectionId, bytes);
        });
    }

    Future<void> sendMessage(TextMessage message) async {
        _routingManager._forwardMessage(_devices, message);
    }

    String getUuidName(DeviceUuid uuid) {
        for (var nd in _devices.values) {
            if (nd.uuid == uuid) return nd.name ?? nd.uuid.toString();
            
            for (var fd in nd.table) {
                if (fd.uuid == uuid) return fd.deviceName;
            }
        }
        
        return uuid.toString();
    }
}

class RoutingManager {
    Future<void> _onMessageReceived(NearbyDevice sender, Message message) async {
        final sendAck = await NearbyManager()._onModifyNearbyDevices((devices) async {
            if (sender.status != DeviceStatus.connected) {
                logWarn("Received a message from: ${sender.name}, which is not connected.");
            }

            switch (message) {
                case TextMessage():
                    logInfo("TextMessage from: ${sender.name}.");
                    _handleTextMessage(sender, devices, message);
                    break;

                case NameUpdateMessage():
                    logInfo("NameUpdateMessage from: ${sender.name}.");
                    sender.name = message.newName;
                    break;

                case RouteUpdateMessage():
                    logInfo("RouteUpdateMessage from: ${sender.name}.");
                    logInfo("${message.nodes}");
                    _handleRouteUpdateMessage(sender, devices, message);
                    break;

                case AckMessage():
                    logInfo("AckMessage from: ${sender.name}.");
                    return false;

                case ErrorMessage():
                    logInfo("ErrorMessage from: ${sender.name}.");
                    return false;
            }
            
            return true;
        });
        
        if (!sendAck) return;

        await NearbyManager()._onSendMessage(
            sender,
            AckMessage(
                source: NearbyManager().localUuid,
                destination: sender.uuid, 
                messageId: message.id
            )
        );
    }
    
    Future<void> _handleTextMessage(
        NearbyDevice sender,
        Map<DeviceUuid, NearbyDevice> devices,
        TextMessage message
    ) async {
        // This means that the message is for this device.
        if (message.destination == NearbyManager().localUuid) {
            NearbyManager()._textMessages.putIfAbsent(
                message.source,
                () => []
            ).add(message);
            return;
        }
        
        await _forwardMessage(devices, message);
    }
    
    Future<void> _handleRouteUpdateMessage(
        NearbyDevice sender,
        Map<DeviceUuid, NearbyDevice> devices,
        RouteUpdateMessage message
    ) async {
        // We do not expect to receive route updates not meant for us.
        if (message.destination != NearbyManager().localUuid) {
            logWarn("Received route update for a non nearby device.");
            return;
        }
        
        _updateRoutingTableIncoming(sender, devices, message.nodes);
    }
    
    void _updateRoutingTableIncoming(
        NearbyDevice sender,
        Map<DeviceUuid, NearbyDevice> devices,
        List<FarawayDevice> farawayDevices
    ) {
        // Increase the cost.
        farawayDevices.forEach((farawayDevice) => farawayDevice.cost++);

        final List<DeviceUuid> toRemoveIncoming = [];
        
        for (NearbyDevice device in devices.values) {
            // We will update this guy in one line latter.
            if (device.uuid == sender.uuid) continue;
        
            for (int i = 0; i < farawayDevices.length; i++) {
                final incomingDevice = farawayDevices[i];

                // If farawayDevice is actually a nearbyDevice.
                // Or localDevice.
                if (
                    devices[incomingDevice.uuid] != null 
                    || incomingDevice.uuid == NearbyManager().localUuid
                ) {
                    // No need to keep this on the table then.
                    toRemoveIncoming.add(incomingDevice.uuid);
                    continue;
                }
                
                final List<DeviceUuid> toRemoveInternal = [];
                for (int j = 0; j < device.table.length; j++) {
                    final tableDevice = device.table[j];
                    
                    if (incomingDevice.uuid == tableDevice.uuid) {
                        if (incomingDevice.cost > tableDevice.cost) {
                            toRemoveIncoming.add(incomingDevice.uuid);
                        } else {
                            toRemoveInternal.add(tableDevice.uuid);
                        }
                    }
                }

                // Removing previous known farawayDevices that are now inefficient.
                device.table = device.table.where((d) => !toRemoveInternal.contains(d.uuid)).toList();
            }
        }
        
        // Removing incoming farawayDevices that are inefficient.
        farawayDevices = farawayDevices.where((fd) => !toRemoveIncoming.contains(fd.uuid)).toList();

        // Updating the table of the sender.
        sender.table = farawayDevices;
    }

    Future<void> _forwardMessage(
        Map<DeviceUuid, NearbyDevice> devices,
        Message message
    ) async {
        // Check if it is a NearbyDevice.
        final destination = devices[message.destination];
        if (destination != null && destination.uuid == message.destination && destination.status == DeviceStatus.connected) {
            await NearbyManager()._onSendMessage(destination, message);
        }
        
        // Check for all possible FarawayDevices.
        for (NearbyDevice nearbyDevice in devices.values) {
            for (FarawayDevice farawayDevice in nearbyDevice.table) {
                // Sending to the nearby that can send to the destination.
                if (farawayDevice.uuid == message.destination && nearbyDevice.status == DeviceStatus.connected) {
                    await NearbyManager()._onSendMessage(nearbyDevice, message);
                    return;
                }
            }
        }
    }
    
    List<FarawayDevice> _prepareRoutingTableToSend(NearbyDevice destination, Map<DeviceUuid, NearbyDevice> devices) {
        final List<FarawayDevice> result = [];
        
        for (NearbyDevice device in devices.values) {
            if (device.uuid == destination.uuid) continue;
            
            result.add(FarawayDevice(device.uuid, device.name ?? device.uuid.toString(), 0));
            result.addAll(device.table);
        }
        
        return result;
    }
}