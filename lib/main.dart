import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'host_scene.dart';
import 'join_scene.dart';

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
        useMaterial3: true,
      ),
      home: const HomePage(),
      routes: {
        '/host': (context) => const HostPage(),
        '/join': (context) => const JoinPage(),
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _nameController = TextEditingController();
  bool _isNameValid = false;

  @override
  void initState() {
    super.initState();
    _loadSavedName();
  }

  // 加载保存的用户名
  Future<void> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('user_name');
    if (savedName != null && savedName.isNotEmpty) {
      setState(() {
        _nameController.text = savedName;
        _isNameValid = true;
      });
    }
  }

  // 保存用户名和UUID
  Future<void> _saveName(String name) async {
    if (name.trim().isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    
    // 如果还没有UUID，则生成一个
    if (prefs.getString('user_uuid') == null) {
      final uuid = const Uuid().v4();
      await prefs.setString('user_uuid', uuid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WLAN局域网抽奖系统')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '欢迎使用WLAN局域网抽奖系统',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '请输入您的名称',
                  border: OutlineInputBorder(),
                  hintText: '您的名称将显示给其他人',
                ),
                onChanged: (value) {
                  setState(() {
                    _isNameValid = value.trim().isNotEmpty;
                  });
                },
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isNameValid 
                      ? () {
                          _saveName(_nameController.text);
                          Navigator.pushNamed(context, '/host');
                        } 
                      : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: const Text('我是房主'),
                  ),
                  ElevatedButton(
                    onPressed: _isNameValid 
                      ? () {
                          _saveName(_nameController.text);
                          Navigator.pushNamed(context, '/join');
                        } 
                      : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: const Text('我是抽奖者'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


