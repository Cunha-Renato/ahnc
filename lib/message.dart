import 'package:ahnc/nearby_manager.dart';
import 'package:uuid/uuid.dart';

const jsonMessageType = 'messageType';
const jsonMessageId = 'id';
const jsonMessageDestination = 'destination';
const jsonMessageSource = 'source';
const jsonMessageContents = 'contents';

sealed class Message {
    String id = Uuid().v4();
    final DeviceUuid source;
    final DeviceUuid destination;

    Message({required this.source, required this.destination});
    Message.withId({required this.id, required this.source, required this.destination});
    
    Map<String, dynamic> toJson();
    static Message? fromJson(Map<String, dynamic> json) => null;
}

class TextMessage extends Message {
    final String text;

    TextMessage({required super.source, required super.destination, required this.text});
    TextMessage.withId(String id, {required super.source, required super.destination, required this.text}): super.withId(id: id);
    
    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'Text',
        jsonMessageId: id,
        jsonMessageDestination: destination.toString(),
        jsonMessageContents: text,
    };
    
    static TextMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'Text') return null;
            
            return TextMessage.withId(
                json[jsonMessageId]! as String,
                destination: DeviceUuid.fromString(json[jsonMessageDestination]! as String),
                source: DeviceUuid.fromString(json[jsonMessageSource]! as String),
                text: json[jsonMessageContents]! as String
            );
        } catch(_) {
            return null;
        }
    }
}

class NameUpdateMessage extends Message {
    final String newName;

    NameUpdateMessage({required super.source, required super.destination, required this.newName});
    NameUpdateMessage.withId(String id, {required super.source, required super.destination, required this.newName}): super.withId(id: id);
    
    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'NameUpdate',
        jsonMessageId: id,
        jsonMessageDestination: destination.toString(),
        jsonMessageContents: newName,
    };
    
    static NameUpdateMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'NameUpdate') return null;
            
            return NameUpdateMessage.withId(
                json[jsonMessageId]! as String,
                destination: DeviceUuid.fromString(json[jsonMessageDestination]! as String),
                source: DeviceUuid.fromString(json[jsonMessageSource]! as String),
                newName: json[jsonMessageContents]! as String
            );
        } catch(_) {
            return null;
        }
    }
}

class RouteUpdateMessage extends Message {
    final List<FarawayDevice> nodes;

    RouteUpdateMessage({required super.source, required super.destination, required this.nodes});
    RouteUpdateMessage.withId(String id, {required super.source, required super.destination, required this.nodes}): super.withId(id: id);

    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'RouteUpdate',
        jsonMessageId: id,
        jsonMessageDestination: destination.toString(),
        jsonMessageContents: nodes.map((n) => n.toJson()).toList(),
    };
    
    static RouteUpdateMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'RouteUpdate') return null;

            return RouteUpdateMessage.withId(
                json[jsonMessageId]! as String,
                destination: DeviceUuid.fromString(json[jsonMessageDestination]! as String),
                source: DeviceUuid.fromString(json[jsonMessageSource]! as String),
                nodes: List<dynamic>.from(json[jsonMessageContents]!)
                    .map((d) => FarawayDevice.fromJson(Map<String, dynamic>.from(d)))
                    .toList(),
            );
        } catch(_) {
            return null;
        }
    }
}

class AckMessage extends Message {
    final String messageId;

    AckMessage({required super.source, required super.destination, required this.messageId});
    AckMessage.withId(String id, {required super.source, required super.destination, required this.messageId}): super.withId(id: id);

    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'Ack',
        jsonMessageId: id,
        jsonMessageDestination: destination.toString(),
        jsonMessageContents: messageId,
    };

    static AckMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'Ack') return null;

            return AckMessage.withId(
                json[jsonMessageId]! as String,
                destination: DeviceUuid.fromString(json[jsonMessageDestination]! as String),
                source: DeviceUuid.fromString(json[jsonMessageSource]! as String),
                messageId: json[jsonMessageContents]! as String
            );
        } catch(_) {
            return null;
        }
    }
}

class ErrorMessage extends Message {
    final String messageId;
    final String error;

    ErrorMessage({
        required super.source,
        required super.destination,
        required this.messageId,
        required this.error
    });

    ErrorMessage.withId(String id, {
        required super.source,
        required super.destination,
        required this.messageId,
        required this.error
    });

    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'Error',
        jsonMessageId: id,
        jsonMessageDestination: destination.toString(),
        jsonMessageContents: [messageId, error],
    };

    static ErrorMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! != 'Text') return null;
            
            final contents = List<String>.from(json[jsonMessageContents]!);

            return ErrorMessage.withId(
                json[jsonMessageId]! as String,
                destination: DeviceUuid.fromString(json[jsonMessageDestination]! as String),
                source: DeviceUuid.fromString(json[jsonMessageSource]! as String),
                messageId: contents[0],
                error: contents[1],
            );
        } catch(_) {
            return null;
        }
    }
}

