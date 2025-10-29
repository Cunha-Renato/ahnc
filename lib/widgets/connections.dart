import 'package:ahnc/network_manager.dart';
import 'package:flutter/material.dart';

class ConnectionsPage extends StatefulWidget {
    const ConnectionsPage({super.key});

    @override
    State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
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
                        SNetworkManager().networkManager != null
                            ? Text("Device: ${SNetworkManager().networkManager!.localDeviceName}\nNetwork Id: ${SNetworkManager().networkManager!.serviceId}")
                            : ElevatedButton(
                                onPressed: () {
                                    _showPrompt();
                                }, 
                                child: const Text('Set Info')
                            ),
                        SNetworkManager().networkManager != null
                            ? ValueListenableBuilder(
                                valueListenable: SNetworkManager().networkManager!.isRunning, 
                                builder: (context, isRunning, _) {
                                    return TextButton(
                                        onPressed: () async {
                                            if (isRunning) {
                                                await SNetworkManager().networkManager!.stop();
                                            } else {
                                                await SNetworkManager().networkManager!.start();
                                            }
                                        }, 
                                        child: isRunning
                                            ? const Text('Stop')
                                            : const Text('Start')
                                    );
                                }
                            )
                            : const SizedBox.shrink(),
                    ],
                )
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
            });
        }
    }
}