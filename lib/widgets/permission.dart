import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionDialog {
    final ValueNotifier<bool> showDialog = ValueNotifier(false);
    final ValueNotifier<bool> launchAppSettings = ValueNotifier(false);
    
    void setShowDialog(bool value) => showDialog.value = value;
    void setLaunchAppSettings(bool value) => launchAppSettings.value = value;
    
    void dispose() {
        showDialog.dispose();
        launchAppSettings.dispose();
    }
}

class HandlePermissions extends StatefulWidget {
    final PermissionDialog dialog = PermissionDialog();
    
    HandlePermissions({super.key});
    
    @override
    State<HandlePermissions> createState() => _HandlePermissionsState();
}

class _HandlePermissionsState extends State<HandlePermissions> {
    @override
    void initState() {
        super.initState();
        _checkAndRequestPermissions();
    }
    
    Future<List<Permission>> _getRequiredPermissions() async {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        List<Permission> permissions = [];


        if (sdkInt >= 31) { // Android 12 and above
            permissions.addAll([
                Permission.bluetoothAdvertise,
                Permission.bluetoothConnect,
                Permission.bluetoothScan,
            ]);
        }

        if (sdkInt >= 33) { 
            permissions.add(Permission.nearbyWifiDevices);
        }

        if (sdkInt >= 29) { // Android 10 and above
            permissions.add(Permission.location);
        }

        return permissions;
    }

    Future<void> _checkAndRequestPermissions() async {
        final permissions = await _getRequiredPermissions();
        await permissions.request();

        for (final permission in permissions) {
            final status = await permission.status;
            debugPrint("Permission: $permission, $status");
            
            if (status.isDenied || status.isPermanentlyDenied) {
                widget.dialog.setShowDialog(true);
                
                if (status.isPermanentlyDenied) {
                    widget.dialog.setLaunchAppSettings(true);
                }
            }
        }
    }
    
    @override
    Widget build(BuildContext context) {
        return ValueListenableBuilder(
            valueListenable: widget.dialog.showDialog,
            builder: (context, show, _) {
                if (show) {
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                        await showDialog<void>(
                            context: context,
                            barrierDismissible: false, 
                            builder: (context) {
                                final launchAppSettings = widget.dialog.launchAppSettings.value;

                                return AlertDialog(
                                    title: const Text(
                                        "Permissions are Needed.",
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    content: const Text(
                                        "This app cannot function without the permissions.",
                                    ),
                                    actions: [
                                        TextButton(
                                            onPressed: () async {
                                                Navigator.of(context).pop(); 
                                                widget.dialog.setShowDialog(false);

                                                if (launchAppSettings) {
                                                    await openAppSettings();
                                                    widget.dialog.setLaunchAppSettings(false);
                                                    SystemNavigator.pop();
                                                } else {
                                                    await _checkAndRequestPermissions();
                                                }
                                            },
                                            child: const Text("Confirm"),
                                        ),
                                    ],
                                );
                            },
                        );
                    });
                }

                // Keep an empty placeholder in the widget tree
                return const SizedBox.shrink();
            },
        );
    }

}