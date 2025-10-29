import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ahnc/message.dart';
import 'package:ahnc/widgets/debug_console.dart';
import 'package:flutter/widgets.dart';
import 'package:nearby_connections/nearby_connections.dart';

class NodeInfo {
    final String deviceName;
    int cost;
    
    NodeInfo({required this.deviceName, required this.cost});
}

class DeviceInfo {
    final String id;
    final String name;
    
    DeviceInfo({required this.id, required this.name});
}

class DeviceRoutingTable {
    final DeviceInfo info;
    List<NodeInfo> nodes = [];

    DeviceRoutingTable({required this.info});
}

class RoutingManager {
    final String localDeviceName;
    final List<DeviceRoutingTable> directConnections = [];
    final List<DeviceInfo> stagedConnections = [];
    /// String: id
    final Future<void> Function(String, Message) onSendMessage;
    
    RoutingManager({required this.localDeviceName, required this.onSendMessage}) {
        Timer.periodic(const Duration(seconds: 15), (_) {
            logInfo("Preparing for update.");
            for (DeviceRoutingTable table in directConnections) {
                logInfo("Sending update to: ${table.info.name}.");
                final nodes = _prepareRoutingTableToSend(table.info);
                onSendMessage(table.info.id, RouteUpdateMessage(
                    destination: table.info.name,
                    nodes: nodes
                ));
            }
        });
    }

    void stageConnection(String connectionId, String deviceName) {
        stagedConnections.add(DeviceInfo(id: connectionId, name: deviceName));
    }
    
    DeviceInfo? unstageConnection(String connectionId) {
        for (DeviceInfo info in stagedConnections) {
            if (info.id == connectionId) return info;
        }
        
        return null;
    }
    
    void addConnection(String connectionId) {
        for (DeviceInfo info in stagedConnections) {
            if (info.id == connectionId) {
                directConnections.add(DeviceRoutingTable(info: info));
                unstageConnection(connectionId);
                break;
            }
        }
    
        return null;
    }

    DeviceInfo? removeConnection(String connectionId) {
        DeviceRoutingTable? removed;
        for (var i = 0; i < directConnections.length; i++) {
            if (directConnections[i].info.id == connectionId) {
                removed = directConnections.removeAt(i);
                break;
            }
        }
        
        if (removed != null) return removed.info;
        else return null;
    }
    
    bool isConnectedTo(String connectionId) {
        for (DeviceRoutingTable table in directConnections) {
            if (table.info.id == connectionId) return true;
        }
    
        return false;
    }

    void onMessageReceived(String connectionId, Message msg) {
        DeviceInfo? sender;

        for (DeviceRoutingTable table in directConnections) {
            if (table.info.id == connectionId) {
                sender = table.info;
                break;
            }
        }

        if (sender == null) {
            logError("Received message from unknown device. ($connectionId)");
            return;
        }

        switch (msg) {
            case TextMessage():
                _handleTextMessage(sender, msg);
                break;
            case RouteUpdateMessage():
                _handleRouteUpdateMessage(sender, msg);
                break;
            case AckMessage():
                logInfo("AckMessage: from ${sender.name}.");
            case ErrorMessage():
                logError("ErrorMessage: from ${sender.name}.");
        }
    }
    
    void _handleTextMessage(DeviceInfo sender, TextMessage msg) {
        if (msg.destination == localDeviceName) {
            onSendMessage(
                sender.id, 
                AckMessage(destination: sender.name, messageId: msg.id)
            );

            return;
        }
    
        _forwardMessage(msg);
    }
    
    void _handleRouteUpdateMessage(DeviceInfo sender, RouteUpdateMessage msg) {
        // We do not expect to receive route updates not meant for us.
        if (msg.destination != localDeviceName) {
            logWarn("Received route update from a non neighbor: ${msg.destination}");
            return;
        }     

        _updateRoutingTableIncoming(sender, msg.nodes);

        onSendMessage(sender.id, AckMessage(
            destination: sender.name, 
            messageId: msg.id
        ));
    }
    
    void _forwardMessage(Message msg) {
        for (DeviceRoutingTable table in directConnections) {
            if (table.info.name == msg.destination) {
                onSendMessage(table.info.id, msg);
                return;
            }

            for (NodeInfo tableEntry in table.nodes) {
                if (tableEntry.deviceName == msg.destination) {
                    onSendMessage(table.info.id, msg);
                    return;
                }
            }
        }
    }

    void _updateRoutingTableIncoming(DeviceInfo sender, List<NodeInfo> incomingTable) {
        // Removing ineficient.
        final List<int> toRemoveIncoming = [];
        int? tableIndex;
        for (int i = 0; i < incomingTable.length; i++) {
            // Updating hop count.
            incomingTable[i].cost += 1;

            for (DeviceRoutingTable table in directConnections) {
                // The same table we're updating later.
                if (table.info == sender) {
                    // For use later.
                    tableIndex = i;
                    continue;
                };
                
                // This means that one of the incoming table node is a direct connection.
                // Or we are in the table.
                if (incomingTable[i] == table.info.name || incomingTable[i].deviceName == localDeviceName) {
                    toRemoveIncoming.add(i);
                    continue;
                }

                final List<int> toRemoveInternal = [];
                for (int j = 0; j < table.nodes.length; j++) {
                    if (incomingTable[i].deviceName == table.nodes[j].deviceName) {
                        // Incoming is worse than others.
                        if (incomingTable[i].cost > table.nodes[j].cost) {
                            toRemoveIncoming.add(i);
                        } else {
                            toRemoveInternal.add(j);
                        }
                    }
                }
                
                // Removing this one's.
                for (int toRemove in toRemoveInternal) {
                    table.nodes.removeAt(toRemove);
                }
            }
        }
        
        // Removing incoming.
        for (int toRemove in toRemoveIncoming) {
            incomingTable.removeAt(toRemove);
        }

        // Swapping.
        directConnections[tableIndex!].nodes = incomingTable;
    }

    List<NodeInfo> _prepareRoutingTableToSend(DeviceInfo destination) {
        final List<NodeInfo> result = [];
        
        for (DeviceRoutingTable direct in directConnections) {
            if (direct.info == destination) continue;
            
            result.addAll(direct.nodes);
        }
        
        return result;
    }
}

class NetworkManager {
    late final RoutingManager routingManager;
    final String localDeviceName;
    final String serviceId;
    final Strategy strategy = Strategy.P2P_CLUSTER;
    final nearby = Nearby();
    ValueNotifier<bool> isRunning = ValueNotifier(false);
    
    NetworkManager({required this.localDeviceName, this.serviceId = "com.ahnc"}) {
        routingManager = RoutingManager(
            localDeviceName: localDeviceName, 
            onSendMessage: onSendMessage
        );
    }

    Future<void> start() async {
        await startAdvertising();
        await startDiscovery();
        isRunning.value = true;
    }
    
    Future<void> stop() async {
        tryLogAsync(DebugMessageType.error, () async {
            await nearby.stopAdvertising();
            await nearby.stopAllEndpoints();
            await nearby.stopDiscovery();

            DebugConsole.log(DebugMessageType.info, 'Stopped advertising and discovery');
        });

        isRunning.value = false;
    }

    Future<void> startAdvertising() async {
        tryLogAsync(DebugMessageType.error, () async {
            await nearby.startAdvertising(
                localDeviceName,
                serviceId: serviceId,
                strategy,
                onConnectionInitiated: onConnectionInitiated,
                onConnectionResult: onConnectionResult,
                onDisconnected: onDisconnected,
            );

            DebugConsole.log(DebugMessageType.info, 'Started advertising');
        });
    }

    Future<void> startDiscovery() async {
        tryLogAsync(DebugMessageType.error, () async {
            await nearby.startDiscovery(
                localDeviceName, 
                strategy, 
                serviceId: serviceId,
                onEndpointFound: onEndpointFound,
                onEndpointLost: onEndpointLost,
            );

            DebugConsole.log(DebugMessageType.info, 'Started discovery');
        });
    }
    
    Future<void> onSendMessage(String id, Message message) async {
        tryLogAsync(DebugMessageType.error, () async {
            final jsonString = jsonEncode(message.toJson());
            final bytes = Uint8List.fromList(utf8.encode(jsonString));

            await nearby.sendBytesPayload(id, bytes);
        });
    }

    void onEndpointFound(String id, String name, String serviceId) {
        DebugConsole.log(DebugMessageType.info, 'Endpoint found: $name ($id)');
        tryLogAsync(DebugMessageType.error, () async {
            if (routingManager.isConnectedTo(id)) {
                DebugConsole.log(DebugMessageType.info, 'Already connected to $name ($id)');
                return;
            }

            await nearby.requestConnection(
                localDeviceName,
                id, 
                onConnectionInitiated: onConnectionInitiated, 
                onConnectionResult: onConnectionResult, 
                onDisconnected: onDisconnected
            );
        });
    }
    
    void onConnectionInitiated(String id, ConnectionInfo info) {
        DebugConsole.log(DebugMessageType.info, 'Connection initiated from ${info.endpointName} ($id).');

        tryLogAsync(DebugMessageType.error, () async {
            if (routingManager.isConnectedTo(id)) return;
            
            routingManager.stageConnection(id, info.endpointName);

            await nearby.acceptConnection(
                id, 
                onPayLoadRecieved: onPayLoadRecieved
            );
        });
    }

    void onConnectionResult(String id, Status status) {
        DebugConsole.log(DebugMessageType.info, 'Connection result from $id: $status');

        tryLog(DebugMessageType.error, () {
            switch (status) {
                case Status.CONNECTED:
                    routingManager.addConnection(id);
                    break;
                default:
                    break;
            }
        });
    }

    void onDisconnected(String id) {
        DeviceInfo info = routingManager.removeConnection(id) ?? DeviceInfo(
            id: id, 
            name: "Unknown Device"
        );
        DebugConsole.log(DebugMessageType.info, 'Disconnected from ${info.name} ($id)');
    }

    void onEndpointLost(String? id) {
        if (id == null) return;

        DeviceInfo info = routingManager.unstageConnection(id) ?? DeviceInfo(
            id: id, 
            name: "Unknown Device"
        );
        DebugConsole.log(DebugMessageType.info, 'Endpoint lost: ${info.name} ($id)');
    }

    void onPayLoadRecieved(String id, Payload payload) {
        switch (payload.type) {
            case PayloadType.BYTES:
                tryLog(DebugMessageType.error, () {
                    final jsonString = utf8.decode(payload.bytes!);
                    final data = jsonDecode(jsonString);

                    // This is ugly.
                    Message? message =
                        TextMessage.fromJson(data)
                        ?? RouteUpdateMessage.fromJson(data)
                        ?? AckMessage.fromJson(data)
                        ?? ErrorMessage.fromJson(data);
                    
                    routingManager.onMessageReceived(id, message!);
                });
                break;
            default: break;
        }
    }
}

class SNetworkManager {
    static final SNetworkManager _instance = SNetworkManager._();
    NetworkManager? networkManager; 

    SNetworkManager._();
    factory SNetworkManager() => _instance;
    
    void init({required String localDeviceName, String serviceId = "com.ahnc"}) {
        networkManager = NetworkManager(
            localDeviceName: localDeviceName, 
            serviceId: serviceId
        );
    }
}