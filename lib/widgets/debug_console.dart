import 'package:flutter/material.dart';

enum DebugMessageType {
    debug,
    info,
    warn,
    error
}

class DebugMessage {
    final DebugMessageType type;
    final String message;
    
    const DebugMessage(this.type, this.message);
}

class DebugConsole extends StatefulWidget {
    static final DebugConsole _instance = DebugConsole._internal();
    factory DebugConsole() => _instance;
    const DebugConsole._internal();

    static _DebugConsoleState? _state;

    static void log(DebugMessageType type, String msg) {
        DebugConsole._state?._log(type, msg);
    }
    
    static void clear() {
        DebugConsole._state?._clear();
    }

    @override
    State<DebugConsole> createState() {
        final state = _DebugConsoleState();
        _state = state;
        return state;
    }
}

class _DebugConsoleState extends State<DebugConsole> {
  final ScrollController _scrollController = ScrollController();
  final List<DebugMessage> _messages = [];

    void _log(DebugMessageType type, String msg) {
        setState(() {
            _messages.add(DebugMessage(type, msg));
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
                _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                );
            }
        });
    }
    
    void _clear() {
        setState(() {
            _messages.clear();
        });
    }

    Color _typeColor(DebugMessageType type) {
        switch (type) {
            case DebugMessageType.debug: return Color(0xff5199f4);
            case DebugMessageType.info: return Color(0xff6aab02);
            case DebugMessageType.warn: return Color(0xfffabd32);
            case DebugMessageType.error: return Color(0xfffb4932);
        }
    }

    String _typeLabel(DebugMessageType type) {
        switch (type) {
            case DebugMessageType.debug: return "Debug: ";
            case DebugMessageType.info: return "Info: ";
            case DebugMessageType.warn: return "Warn: ";
            case DebugMessageType.error: return "Error: ";
        }
    }

    @override
    Widget build(BuildContext context) {
        return Container(
            height: MediaQuery.of(context).size.height * 0.3,
            width: double.infinity,
            color: Color(0xff383838),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _messages.map((msg) {
                        return Container(
                            width: double.infinity,
                            color: Colors.transparent,
                            margin: const EdgeInsets.only(bottom: 2),
                            padding: const EdgeInsets.all(4),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text(
                                        _typeLabel(msg.type),
                                        style: TextStyle(
                                            color: _typeColor(msg.type),
                                            fontWeight: FontWeight.bold
                                        ),
                                    ),
                                    Expanded(
                                        child: Text(
                                            msg.message,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w400
                                            ),
                                        ),
                                    ),
                                ],
                            ),
                        );
                    }).toList(),
                ),
            ),
        );
    }
}

void logDebug(String msg) {
    DebugConsole.log(DebugMessageType.debug, msg);
}

void logInfo(String msg) {
    DebugConsole.log(DebugMessageType.info, msg);
}

void logWarn(String msg) {
    DebugConsole.log(DebugMessageType.warn, msg);
}

void logError(String msg) {
    DebugConsole.log(DebugMessageType.error, msg);
}

void tryLog(DebugMessageType type, void Function() tryFunc) {
    try {
        tryFunc();
    } catch (e) {
        DebugConsole.log(type, e.toString());
    }
}

void tryLogAsync(DebugMessageType type, Future<void> Function() tryFunc) async {
    try {
        await tryFunc();
    } catch (e) {
        DebugConsole.log(type, e.toString());
    }
}