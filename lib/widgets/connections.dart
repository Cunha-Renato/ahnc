import 'package:ahnc/message.dart';
import 'package:ahnc/network_manager.dart';
import 'package:flutter/material.dart';

class ConnectionsPage extends StatefulWidget {
    const ConnectionsPage({super.key});

    @override
    State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
    final Map<String, List<TextMessage>> messages = {};
    String? currentChat = null;

    @override
    void initState() {
        super.initState();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (SNetworkManager().networkManager == null) {
                _showPrompt();
            }
        });
    }

    @override
    Widget build(BuildContext context) {
        final networkManager = SNetworkManager().networkManager;

        return Padding(
            padding: const EdgeInsets.all(5.0),
            child: networkManager == null
            ? TextButton(
                onPressed: _showPrompt,
                child: const Text('Set Info'),
            )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Row(
                        children: [
                            // Header
                            TextButton(
                                onPressed: () {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                        return AlertDialog(
                                            title: const Text('Info'),
                                            content: SingleChildScrollView(
                                                child: ListBody(
                                                    children: [
                                                        Text("Name: ${networkManager.localDeviceName}"),
                                                        Text("Service ID: ${networkManager.serviceId}"),
                                                    ]),
                                                ),
                                            actions: [ TextButton(
                                                child: const Text('Ok'),
                                                onPressed: () {
                                                    Navigator.of(context).pop();
                                                },
                                            )],
                                        );
                                    });
                                }, 
                                child: Text(
                                    "Info",
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                )
                            ),

                            // Start/Stop Button
                            ValueListenableBuilder(
                                valueListenable: networkManager.isRunning,
                                builder: (context, isRunning, _) {
                                    return TextButton(
                                        onPressed: () async {
                                            isRunning
                                            ? await networkManager.stop()
                                            : await networkManager.start();
                                        },
                                        child: isRunning
                                            ? const Text('Stop')
                                            : const Text('Start'),
                                    );
                                },
                            ),
                        ]
                    ),

                    // Main content
                    Expanded(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                // Connections Column
                                Expanded(
                                    flex: 2,
                                    child: Builder(builder: (context) {
                                        final controller = TextEditingController();

                                        return SingleChildScrollView(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                                // Connections List
                                                ValueListenableBuilder(
                                                    valueListenable: networkManager.routingManager.directConnections,
                                                    builder: (context, directTables, _) {
                                                        final directWidgets = [];
                                                        final indirectWidgets = [];

                                                        for (var table in directTables) {
                                                            directWidgets.add(TextButton(
                                                                onPressed: () {
                                                                    setState(() {
                                                                        currentChat = table.info.name;
                                                                    });
                                                                },
                                                                child: Text("${table.info.name} -- ${table.info.id}"),
                                                            ));

                                                            for (var node in table.nodes) {
                                                                indirectWidgets.add(TextButton(
                                                                    onPressed: () {
                                                                        setState(() {
                                                                            currentChat = node.deviceName;
                                                                        });
                                                                    },
                                                                    child: Text("${table.info.name}: ${node.deviceName} > ${node.cost}"),
                                                                ));
                                                            }
                                                        }

                                                        return Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                                const Text("Direct Connections", style: TextStyle(fontWeight: FontWeight.bold)),
                                                                ...directWidgets,
                                                                const SizedBox(height: 8),
                                                                const Text("Indirect Connections", style: TextStyle(fontWeight: FontWeight.bold)),
                                                                ...indirectWidgets,
                                                            ],
                                                        );
                                                    },
                                                ),
                                            ],
                                        ));
                                    })
                                ),

                                const SizedBox(width: 8),

                                // Chat Column
                                if (currentChat != null) Expanded(
                                    flex: 3,
                                    child: ChatColumn(
                                        networkManager: networkManager,
                                        chatMessages: messages[currentChat] ?? [],
                                        onSend: (text) {
                                            final message = TextMessage(destination: currentChat!, text: text);
                                            networkManager.routingManager.sendTextMessage(message);

                                            setState(() {
                                                messages.putIfAbsent(currentChat!, () => []).add(message);
                                            });
                                        },
                                    ),
                                ),
                            ],
                        ),
                    ),
                ],
            ),
        );
    }


    Future<void> _showPrompt() async {
        final nameController = TextEditingController();
        final networkIdController = TextEditingController();

        final result = await showDialog<List<String>>(
            context: context, 
            builder: (context) {
                return StatefulBuilder(
                    builder: (context, setState) {
                        return AlertDialog(
                            title: const Text('Enter Info'),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    TextField(
                                        controller: nameController,
                                        decoration: const InputDecoration(hintText: 'Connection Name'),
                                        onChanged: (_) => setState(() {}),
                                    ),
                                    TextField(
                                        controller: networkIdController,
                                        decoration: InputDecoration(hintText: 'Network ID: (optional)'),
                                        onChanged: (_) => setState(() {}),
                                    )
                                ],
                            ),
                            actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                ),
                                if (nameController.text.isNotEmpty)
                                    TextButton(
                                        onPressed: () => Navigator.of(context).pop([nameController.text, networkIdController.text]),
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
                if (result.length > 1 && result[1].isNotEmpty) {
                    SNetworkManager().init(
                        localDeviceName: result[0], 
                        serviceId: result[1]
                    );
                } else {
                    SNetworkManager().init(
                        localDeviceName: result[0], 
                    );
                }
            
                SNetworkManager().networkManager!.routingManager.onLocalReceivedTextMessage = (String sender, TextMessage msg) {
                    setState(() {
                        messages.putIfAbsent(sender, () => []).add(msg);
                    });
                };
            });
        }
    }
}

// Extracted ChatColumn for clarity
class ChatColumn extends StatefulWidget {
    final NetworkManager networkManager;
    final List<TextMessage> chatMessages;
    final void Function(String) onSend;

    const ChatColumn({
        required this.networkManager,
        required this.chatMessages,
        required this.onSend,
        super.key,
    });

    @override
    State<ChatColumn> createState() => _ChatColumnState();
}

class _ChatColumnState extends State<ChatColumn> {
    final TextEditingController _controller = TextEditingController();
    final ScrollController _scrollController = ScrollController();

    void _scrollToEnd() {
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

    @override
    void didUpdateWidget(covariant ChatColumn oldWidget) {
        super.didUpdateWidget(oldWidget);
        _scrollToEnd();
    }

    @override
    Widget build(BuildContext context) {
        return Column(
            children: [
                // Messages
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: ListView.builder(
                            controller: _scrollController,
                            itemCount: widget.chatMessages.length,
                            itemBuilder: (context, index) {
                                final msg = widget.chatMessages[index];
                                final isLocal = msg.destination != widget.networkManager.localDeviceName;

                                return Align(
                                    alignment: isLocal
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                                        padding: const EdgeInsets.all(8.0),
                                        decoration: BoxDecoration(
                                            color: isLocal ? const Color(0xff6aab02) : const Color(0xff5199f4),
                                            borderRadius: BorderRadius.circular(8.0),
                                        ),
                                        child: Column(
                                            crossAxisAlignment: isLocal
                                                ? CrossAxisAlignment.end
                                                : CrossAxisAlignment.start,
                                            children: [
                                                Text(
                                                    isLocal ? "You" : msg.destination,
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                    ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                    msg.text,
                                                    softWrap: true,
                                                    style: const TextStyle(color: Colors.white),
                                                ),
                                            ],
                                        ),
                                    ),
                                );
                            },
                        ),
                    ),
                ),

                // Input row
                Row(
                    children: [
                        Expanded(
                            child: TextField(
                                controller: _controller,
                                maxLines: null,
                                decoration: const InputDecoration(
                                    hintText: "Type Message ...",
                                    border: OutlineInputBorder(),
                                ),
                            ),
                        ),
                        TextButton(
                            onPressed: () {
                                if (_controller.text.isEmpty) return;
                                widget.onSend(_controller.text);
                                _controller.clear();
                                _scrollToEnd();
                            },
                            child: const Text("Send"),
                        ),
                    ],
                ),
            ],
        );
    }
}
