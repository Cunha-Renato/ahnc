import 'package:ahnc/widgets/debug_console.dart';
import 'package:flutter/widgets.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:uuid/uuid.dart';

class NodeInfo {
    final String deviceName;
    /// This should be a direct connected device.
    final String? imediateNodeName;
    int cost;
    
    NodeInfo({required this.deviceName, required this.imediateNodeName, required this.cost});
}

sealed class Message {
    final String id = Uuid().v4();
    final String destination;

    Message({required this.destination});
}

class TextMessage extends Message {
    final String text;

    TextMessage({required super.destination, required this.text});
}

class RouteUpdateMessage extends Message {
    final List<NodeInfo> nodes;

    RouteUpdateMessage({required super.destination, required this.nodes});
}

class AckMessage extends Message {
    final String messageId;

    AckMessage({required super.destination, required this.messageId});
}

class ErrorMessage extends Message {
    final String messageId;
    final String error;

    ErrorMessage({
        required super.destination,
        required this.messageId,
        required this.error
    });
}

class RoutingManager {
    final String localDeviceName;
    final Map<String, NodeInfo> routingTable = {};
    /// (Connection ID, Device Name)
    final Map<String, String> directConnections = {};
    final Map<String, String> stagedConnections = {};
    
    RoutingManager({required this.localDeviceName});

    void stageConnection(String connectionId, String deviceName) {
        stagedConnections[connectionId] = deviceName;
    }
    
    String? unstageConnection(String connectionId) {
        return stagedConnections.remove(connectionId);
    }
    
    void addConnection(String connectionId) {
        if (stagedConnections.containsKey(connectionId)) {
            directConnections[connectionId] = stagedConnections.remove(connectionId)!;
        }
    }

    String? removeConnection(String connectionId) {
        return directConnections.remove(connectionId);
    }
    
    bool isConnectedTo(String connectionId) {
        return directConnections.containsKey(connectionId);
    }

    void onMessageReceived(Message msg) {
        switch (msg) {
            case TextMessage():
                _handleTextMessage(msg);
                break;
            case RouteUpdateMessage():
                _handleRouteUpdateMessage(msg);
                break;
            case AckMessage():
                throw UnimplementedError();
            case ErrorMessage():
                throw UnimplementedError();
        }
    }
    
    void _handleTextMessage(TextMessage msg) {
        if (msg.destination == localDeviceName) {
            logInfo(msg.text);
            return;
        }
    }
    
    void _handleRouteUpdateMessage(RouteUpdateMessage msg) {
        // We do not expect to receive route updates not meant for us.
        if (msg.destination != localDeviceName) {
            return;
        }
    
        logWarn("Received route update from a non neighbor: ${msg.destination}");
    }
}

class NetworkManager {
    final RoutingManager routingManager;
    final String localDeviceName;
    final String serviceId;
    final Strategy strategy = Strategy.P2P_CLUSTER;
    final nearby = Nearby();
    ValueNotifier<bool> isRunning = ValueNotifier(false);
    
    NetworkManager({required this.localDeviceName, this.serviceId = "com.ahnc"})
        : routingManager = RoutingManager(localDeviceName: localDeviceName);

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
                onPayLoadRecieved: (_, _) {}
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
        String? deviceName = routingManager.removeConnection(id);
        DebugConsole.log(DebugMessageType.info, 'Disconnected from ${deviceName ?? "Unknown Device"} ($id)');
    }

    void onEndpointLost(String? id) {
        if (id == null) return;

        String? deviceName = routingManager.unstageConnection(id);
        DebugConsole.log(DebugMessageType.info, 'Endpoint lost: ${deviceName ?? "Unknown Device"} ($id)');
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