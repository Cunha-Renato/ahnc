import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ahnc/list_notifier.dart';
import 'package:ahnc/message.dart';
import 'package:ahnc/widgets/debug_console.dart';
import 'package:flutter/material.dart';
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
    final ListNotifier<DeviceRoutingTable> directConnections = ListNotifier();
    final List<DeviceInfo> stagedConnections = [];
    /// String: id
    final Future<void> Function(String, Message) onSendMessage;
    void Function(String, TextMessage)? onLocalReceivedTextMessage;
    bool running = false;
    
    RoutingManager({required this.localDeviceName, required this.onSendMessage}) {
        Timer.periodic(const Duration(seconds: 15), (_) async {
            if (!running) return;

            final snapshot = List<DeviceRoutingTable>.from(directConnections.value);

            for (final table in snapshot) {
                try {
                    logInfo("Sending update to: ${table.info.name}.");
                    await onSendMessage(table.info.id, RouteUpdateMessage(
                        destination: table.info.name,
                        nodes: _prepareRoutingTableToSend(table.info),
                    ));
                } catch (e, st) {
                    logError("Failed to send route update to ${table.info.name}: $e\n$st");
                }
            }
        });
    }


    void clearConnections() {
        directConnections.clear();
        stagedConnections.clear();
    }

    void stageConnection(String connectionId, String deviceName) {
        stagedConnections.add(DeviceInfo(id: connectionId, name: deviceName));
    }
    
    DeviceInfo? unstageConnection(String connectionId) {
        for (int i = 0; i < stagedConnections.length; i++) {
            final info = stagedConnections[i];
            if (info.id == connectionId) {
                return stagedConnections.removeAt(i);
            }
        }

        return null;
    }
    
    void addConnection(String connectionId) {
        for (int i = 0; i < stagedConnections.length; i++) {
            final info = stagedConnections[i];
            if (info.id == connectionId) {
                directConnections.add(DeviceRoutingTable(info: info));
                stagedConnections.removeAt(i);
                break;
            }
        }
    }

    DeviceInfo? removeConnection(String connectionId) {
        DeviceRoutingTable? removed;
        for (var i = 0; i < directConnections.len(); i++) {
            if (directConnections.atRef(i).info.id == connectionId) {
                removed = directConnections.removeAt(i);
                break;
            }
        }
        
        if (removed != null) return removed.info;
        else return null;
    }
    
    bool isConnectedTo(String connectionId) {
        for (int i = 0; i < directConnections.len(); i++) {
            if (directConnections.atRef(i).info.id == connectionId) return true;
        }
    
        return false;
    }

    void onMessageReceived(String connectionId, Message msg) {
        DeviceInfo? sender;

        for (int i = 0; i < directConnections.len(); i++) {
            if (directConnections.atRef(i).info.id == connectionId) {
                sender = directConnections.atRef(i).info;
                break;
            }
        }

        if (sender == null) {
            logError("Received message from unknown device. ($connectionId)");
            return;
        }

        switch (msg) {
            case TextMessage():
                logInfo("TextMessage: from ${sender.name}.");
                _handleTextMessage(sender, msg);
                break;
            case RouteUpdateMessage():
                logInfo("RouteUpdateMessage: from ${sender.name}.");
                _handleRouteUpdateMessage(sender, msg);
                break;
            case AckMessage():
                logInfo("AckMessage: from ${sender.name}.");
                break;
            case ErrorMessage():
                logError("ErrorMessage: from ${sender.name}.");
                break;
        }
    }
    
    void sendTextMessage(TextMessage msg) => _forwardMessage(msg);

    void _handleTextMessage(DeviceInfo sender, TextMessage msg) {
        if (msg.destination == localDeviceName) {
            onSendMessage(
                sender.id, 
                AckMessage(destination: sender.name, messageId: msg.id)
            );

            if (onLocalReceivedTextMessage != null) onLocalReceivedTextMessage!(sender.name, msg);

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
        for (int i = 0; i < directConnections.len(); i++) {
            directConnections.atValue(i, (table) {
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
            });
        }
    }

    void _updateRoutingTableIncoming(DeviceInfo sender, List<NodeInfo> incomingTable) {
        // Defensive copy so we can mutate safely
        final incoming = List<NodeInfo>.from(incomingTable);

        // collect indices to remove from incoming (we'll remove in descending order)
        final List<int> toRemoveIncoming = [];

        int? tableIndex;
        bool addCost = true;

        for (int i = 0; i < directConnections.len(); i++) {
            final table = directConnections.atRef(i);

            if (table.info.id == sender.id) {
                tableIndex = i;
                continue; // don't compare against the table that sent the update
            }

            for (int j = 0; j < incoming.length; j++) {
                final incomingNode = incoming[j];

                if (addCost) incomingNode.cost++;

                // If incoming node is actually a direct neighbor (by name) or is ourselves, skip it
                if (incomingNode.deviceName == table.info.name || incomingNode.deviceName == localDeviceName) {
                    toRemoveIncoming.add(j);
                    continue;
                }

                // Compare incoming entries with existing table nodes
                final List<int> toRemoveInternal = [];
                for (int k = 0; k < table.nodes.length; k++) {
                    final existingNode = table.nodes[k];
                    if (incomingNode.deviceName == existingNode.deviceName) {
                        // If incoming is worse (higher cost) we drop the incoming entry,
                        // otherwise we prefer incoming and remove the old entry
                        if (incomingNode.cost > existingNode.cost) {
                            toRemoveIncoming.add(j);
                        } else {
                            toRemoveInternal.add(k);
                        }
                    }
                }

                // Remove internal entries (descending)
                toRemoveInternal.sort((a, b) => b.compareTo(a));
                for (final rem in toRemoveInternal) {
                    if (rem >= 0 && rem < table.nodes.length) {
                        table.nodes.removeAt(rem);
                    }
                }
            }

            addCost = false; // only first table increments cost once
        }

        // Remove incoming indices in descending order to avoid shifting indices
        toRemoveIncoming.sort((a, b) => b.compareTo(a));
        for (final rem in toRemoveIncoming) {
            if (rem >= 0 && rem < incoming.length) {
                incoming.removeAt(rem);
            }
        }

        // Now swap into the sender's table (if we found it)
        if (tableIndex != null) {
            directConnections.atValue(tableIndex, (table) => table.nodes = incoming);
        } else {
            logError("Was not able to update table from ${sender.name}.");
        }
    }

    List<NodeInfo> _prepareRoutingTableToSend(DeviceInfo destination) {
        final List<NodeInfo> result = [];
        
        for (int i = 0; i < directConnections.len(); i++) {
            final direct = directConnections.atRef(i);
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
        routingManager.running = true;
    }
    
    Future<void> stop() async {
        tryLogAsync(DebugMessageType.error, () async {
            await nearby.stopAdvertising();
            await nearby.stopDiscovery();
            await nearby.stopAllEndpoints();

            DebugConsole.log(DebugMessageType.info, 'Stopped advertising and discovery');
        });

        isRunning.value = false;
        routingManager.running = false;
        routingManager.clearConnections();
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
        if (name == localDeviceName) return;

        DebugConsole.log(DebugMessageType.info, 'Endpoint found: $name ($id)');
        tryLogAsync(DebugMessageType.error, () async {
            if (routingManager.isConnectedTo(id)) {
                DebugConsole.log(DebugMessageType.warn, 'Already connected to $name ($id)');
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

        tryLogAsync(DebugMessageType.error, () async {
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
        routingManager.unstageConnection(id);
        routingManager.removeConnection(id);
    }

    void onEndpointLost(String? id) {
        if (id == null) return;

        routingManager.unstageConnection(id);
        routingManager.removeConnection(id);
    }

    void onPayLoadRecieved(String id, Payload payload) {
        switch (payload.type) {
            case PayloadType.BYTES:
                tryLog(DebugMessageType.error, () {
                    final jsonString = utf8.decode(payload.bytes!);
                    final Map<String, dynamic> data = jsonDecode(jsonString);

                    // This is ugly.
                    Message? message =
                        TextMessage.fromJson(data)
                        ?? RouteUpdateMessage.fromJson(data)
                        ?? AckMessage.fromJson(data)
                        ?? ErrorMessage.fromJson(data);
                    
                    if (message == null) {
                        logWarn("Unknown message format from $id: $data");
                        return;
                    }

                    routingManager.onMessageReceived(id, message);
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