import 'package:ahnc/widgets/connections.dart';
import 'package:ahnc/widgets/debug_console.dart';
import 'package:ahnc/widgets/permission.dart';
import 'package:flutter/material.dart';

class Routes {
    static const String connections = '/connections';
}

void main() {
    runApp(const App());
}

class App extends StatefulWidget {
    const App({super.key});
    
    final ConnectionsPage connectionManagerPage = const ConnectionsPage();

    @override
    State<App> createState() => AppState();
}

class AppState extends State<App> {
    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            title: 'Ahnc',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.orangeAccent),
            ),
            home: const HomePage(title: 'Ahnc'),
            routes: Map.of({
                Routes.connections: (context) => super.widget.connectionManagerPage,
            }),
        );
    }
}

class HomePage extends StatefulWidget {
    const HomePage({super.key, required this.title});

    final String title;

    @override
    State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(
                title: Text(widget.title),
                backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            ),
            body: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                        HandlePermissions(),
                        ElevatedButton(
                            onPressed: () {
                                Navigator.pushNamed(context, Routes.connections);
                            },
                            child: const Text('Connections'), 
                        ),
                        DebugConsole()
                    ],
                )
            ),
        );
    }
}