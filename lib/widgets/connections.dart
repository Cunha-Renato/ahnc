import 'package:ahnc/message.dart';
import 'package:ahnc/nearby_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Connections extends StatefulWidget {
    const Connections({super.key});
    
    @override
    State<StatefulWidget> createState() => _ConnectionsState();
}

class _ConnectionsState extends State<Connections> {
    final Map<DeviceUuid, List<TextMessage>> messages = {};
    bool isPaused = true;
    DeviceUuid? currentChat = null;
    
    @override
    Widget build(BuildContext context) {
        final nearby = context.watch<NearbyManager>();

        return  Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                // crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // LEFT COLUMN
                    Row(
                        children: [
                            SizedBox(
                                width: 100,
                                height: 40,
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueGrey.shade700,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                        ),
                                    ),
                                    onPressed: () async {
                                        await _showConfiguration(nearby);
                                    },
                                    child: const Text(
                                        "Device",
                                        style: TextStyle(
                                            fontSize: 15.0,
                                            fontWeight: FontWeight.bold,
                                        ),
                                    ),
                                ),
                            ),

                            const Spacer(),

                            _iconAction(
                                Icons.refresh, 
                                () {
                                    if (!isPaused) nearby.restartDiscovery();
                                }
                            ),
                            _iconAction(
                                isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause,
                                () async {
                                    setState(() {
                                        if (isPaused) {
                                            nearby.startDiscovery();
                                        } else {
                                            nearby.stopDiscovery();
                                        }
                                        
                                        isPaused = !isPaused;
                                    });
                                }
                            ),
                        ],
                    ),
                    Expanded(
                        child: currentChat == null
                        ? _DeviceList(
                            onTap: (uuid) => setState(() => currentChat = uuid),
                        )
                        : PopScope(
                            canPop: false,
                            onPopInvokedWithResult: (didPop, result) {
                                if (!didPop && currentChat != null) 
                                    setState(() => currentChat = null);
                            },
                            child: _ChatList(currentChat!)
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _iconAction(IconData icon, VoidCallback onTap) {
        return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(icon, size: 32, color: Colors.black87),
            ),
        );
    }

    Future<void> _showConfiguration(NearbyManager nearby) async {
        final nameController = TextEditingController();
        final networkIdController = TextEditingController();
        
        final result = await showDialog<List<String>>(
            context: context, 
            builder: (context) {
                return StatefulBuilder(
                    builder: (context, setState) {
                        return AlertDialog(
                            title: const Text('Device Info'),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    Text("Uuid:\n${nearby.localUuid}"),
                                    TextField(
                                        controller: nameController,
                                        decoration: InputDecoration(hintText: 'Device Name: (${nearby.localEndpointName})'),
                                        onChanged: (_) => setState(() {}),
                                    ),
                                    TextField(
                                        controller: networkIdController,
                                        decoration: InputDecoration(hintText: 'Network ID: (${nearby.serviceId})'),
                                        onChanged: (_) => setState(() {}),
                                    )
                                ],
                            ),
                            actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                ),
                                if (nameController.text.isNotEmpty || nearby.localEndpointName != null)
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
                final localEndpointName = result[0].isNotEmpty
                    ? result[0]
                    : nearby.localEndpointName;

                final serviceId = result.length > 1 && result[1].isNotEmpty
                    ? result[1]
                    : nearby.serviceId;
                
                final changedNetwork = serviceId != nearby.serviceId;

                if (
                    changedNetwork
                    || (
                        localEndpointName != null
                        && localEndpointName != nearby.localEndpointName
                    )
                ) {
                    nearby.configure(localEndpointName!, serviceId);
                }

                // If true then all connected / discovered devices are now outside the network.
                if (changedNetwork) {
                    nearby.restartAdvertising();

                    if (!isPaused) nearby.restartDiscovery();

                    nearby.disconnectAll();
                }
            });
        }
    }
}

class _DeviceList extends StatelessWidget {
    final onTap;
    
    _DeviceList({required void Function(DeviceUuid) this.onTap});

    @override
    Widget build(BuildContext context) {
        final nearby = NearbyManager();
        final devices = nearby.devices;
        final fdevices = [];

        devices.forEach((ndevice) {
            final listTile = ndevice.table.map((fdevice) {
                return ListTile(
                    title: Text("${fdevice.deviceName}, from: (${ndevice.name})"),
                    subtitle: Text(ndevice.status.name),
                    trailing: _statusIcon(ndevice.status),
                    onTap: () => onTap(fdevice.uuid),
                );
            });
            
            fdevices.addAll(listTile);
        });

        return Column(
            children: [
                Text("Nearby"),
                Expanded(child: ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                        final device = devices[index];

                        return ListTile(
                            title: Text("${device.name ?? device.uuid.toString()} (${device.connectionId})"),
                            subtitle: Text(device.status.name),
                            trailing: _statusIcon(device.status),
                            onTap: () => onTap(device.uuid),
                        );
                    },
                )),
                Text("Faraway"),
                Expanded(child: ListView.builder(
                    itemCount: fdevices.length,
                    itemBuilder: (context, index) {
                        return fdevices[index];
                    },
                )),
            ],
        );
    }

    Widget _statusIcon(DeviceStatus status) {
        switch (status) {
            case DeviceStatus.discovered:
                return const Icon(Icons.wifi_find, color: Colors.grey);
            case DeviceStatus.connecting:
                return const Icon(Icons.sync, color: Colors.orange);
            case DeviceStatus.connected:
                return const Icon(Icons.check_circle, color: Colors.green);
        }
    }
}

class _ChatList extends StatefulWidget {
    final DeviceUuid currentChat;

    _ChatList(DeviceUuid this.currentChat);

    @override
    State<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends State<_ChatList> {
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
    void didUpdateWidget(covariant _ChatList oldWidget) {
        super.didUpdateWidget(oldWidget);
        _scrollToEnd();
    }

    @override
    Widget build(BuildContext context) {
        final nearby = context.watch<NearbyManager>();
        final chatMessages = nearby.getTextMessages(widget.currentChat);
        final messageSource = nearby.getUuidName(widget.currentChat);

        return Column(
            children: [
                // Messages
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: ListView.builder(
                            controller: _scrollController,
                            itemCount: chatMessages.length,
                            itemBuilder: (context, index) {
                                final msg = chatMessages[index];
                                final isLocal = msg.destination != NearbyManager().localUuid;

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
                                                    isLocal ? "You" : messageSource,
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
                            onPressed: () async {
                                if (_controller.text.isEmpty) return;

                                final message = TextMessage(
                                    source: nearby.localUuid,
                                    destination: widget.currentChat,
                                    text: _controller.text
                                );

                                await nearby.sendMessage(message);
                                nearby.addTextMessage(widget.currentChat, message);

                                setState(() {
                                    _controller.clear();
                                });

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