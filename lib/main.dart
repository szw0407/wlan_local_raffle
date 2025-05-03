import 'package:flutter/material.dart';
import 'scenes/host_scene.dart';
import 'scenes/join_scene.dart';

void main() {
  runApp(const RaffleApp());
}

class RaffleApp extends StatelessWidget {
  const RaffleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WLAN局域网抽奖',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
      routes: {
        '/host': (context) => const HostPage(),
        '/join': (context) => const JoinPage(),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WLAN局域网抽奖系统')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/host'),
              child: const Text('我是房主'),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/join'),
              child: const Text('我是抽奖者'),
            ),
          ],
        ),
      ),
    );
  }
}


