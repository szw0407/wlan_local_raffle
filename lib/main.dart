import 'package:flutter/material.dart';
import 'screens/host_room_screen.dart';
import 'screens/create_room_screen.dart';
import 'screens/participant_room_screen.dart';
import 'screens/username_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WLAN局域网抽奖',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const MyHomePage(title: 'WLAN局域网抽奖'),
        '/username': (context) => UsernameScreen(),
        '/create_room': (context) => CreateRoomScreen(),
        '/host_room': (context) => HostRoomScreen(),
        '/participant_room': (context) => ParticipantRoomScreen(),
      },
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('请选择您的身份'),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/username',
                  arguments: {'role': 'host'},
                );
              },
              child: const Text('房主'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/username',
                  arguments: {'role': 'participant'},
                );
              },
              child: const Text('抽奖者'),
            ),
          ],
        ),
      ),
    );
  }
}
