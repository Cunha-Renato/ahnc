import 'package:ahnc/network_manager.dart';
import 'package:uuid/uuid.dart';

const jsonMessageType = 'messageType';
const jsonMessageId = 'id';
const jsonMessageDestination = 'destination';
const jsonMessageContents = 'contents';

sealed class Message {
    String id = Uuid().v4();
    final String destination;

    Message({required this.destination});
    Message.withId({required this.id, required this.destination});
    
    Map<String, dynamic> toJson();
    static Message? fromJson(Map<String, dynamic> json) => null;
}

class TextMessage extends Message {
    final String text;

    TextMessage({required super.destination, required this.text});
    TextMessage.withId(String id, {required super.destination, required this.text}): super.withId(id: id);
    
    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'Text',
        jsonMessageId: id,
        jsonMessageDestination: destination,
        jsonMessageContents: text,
    };
    
    static TextMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'Text') return null;
            
            return TextMessage.withId(
                json[jsonMessageId]! as String,
                destination: json[jsonMessageDestination]! as String,
                text: json[jsonMessageContents]! as String
            );
        } catch(_) {
            return null;
        }
    }
}

class RouteUpdateMessage extends Message {
    final List<NodeInfo> nodes;

    RouteUpdateMessage({required super.destination, required this.nodes});
    RouteUpdateMessage.withId(String id, {required super.destination, required this.nodes}): super.withId(id: id);

    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'RouteUpdate',
        jsonMessageId: id,
        jsonMessageDestination: destination,
        jsonMessageContents: nodes,
    };
    
    static RouteUpdateMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'RouteUpdate') return null;

            return RouteUpdateMessage.withId(
                json[jsonMessageId]! as String,
                destination: json[jsonMessageDestination]! as String,
                nodes: List<NodeInfo>.from(json[jsonMessageContents]!),
            );
        } catch(_) {
            return null;
        }
    }
}

class AckMessage extends Message {
    final String messageId;

    AckMessage({required super.destination, required this.messageId});
    AckMessage.withId(String id, {required super.destination, required this.messageId}): super.withId(id: id);

    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'Ack',
        jsonMessageId: id,
        jsonMessageDestination: destination,
        jsonMessageContents: messageId,
    };

    static AckMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! as String != 'Ack') return null;

            return AckMessage.withId(
                json[jsonMessageId]! as String,
                destination: json[jsonMessageDestination]! as String,
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
        required super.destination,
        required this.messageId,
        required this.error
    });

    ErrorMessage.withId(String id, {
        required super.destination,
        required this.messageId,
        required this.error
    });

    @override
    Map<String, dynamic> toJson() => {
        jsonMessageType: 'Error',
        jsonMessageId: id,
        jsonMessageDestination: destination,
        jsonMessageContents: [messageId, error],
    };

    static ErrorMessage? fromJson(Map<String, dynamic> json) {
        try {
            if (json[jsonMessageType]! != 'Text') return null;
            
            final contents = List<String>.from(json[jsonMessageContents]!);

            return ErrorMessage.withId(
                json[jsonMessageId]! as String,
                destination: json[jsonMessageDestination]! as String,
                messageId: contents[0],
                error: contents[1],
            );
        } catch(_) {
            return null;
        }
    }
}

