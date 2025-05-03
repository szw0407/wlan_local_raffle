import 'package:flutter/material.dart';
import '../services/raffle_service.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({Key? key}) : super(key: key);

  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final _nameController = TextEditingController();
  final _raffleService = RaffleService();
  bool _isLoading = false;
  String? _errorMessage;
  String? _role;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _role = args != null ? args['role'] as String? : null;
  }

  @override
  void initState() {
    super.initState();
    final currentUser = _raffleService.currentUser;
    if (currentUser != null) {
      _nameController.text = currentUser.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = '请输入用户名';
      });
      return;
    }
    if (_role == null) {
      setState(() {
        _errorMessage = '页面参数错误，请重新进入';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final isHost = _role == 'host';
      await _raffleService.setUser(name, isHost: isHost);
      if (isHost) {
        Navigator.pushReplacementNamed(context, '/create_room');
      } else {
        Navigator.pushReplacementNamed(context, '/join_room');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '保存用户信息失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHost = _role == 'host';
    return Scaffold(
      appBar: AppBar(
        title: Text(isHost ? '创建抽奖房间' : '加入抽奖'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '请输入您的用户名',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveUsername(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveUsername,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }
}