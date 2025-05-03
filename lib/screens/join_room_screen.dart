import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/network_service.dart';
import '../services/raffle_service.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({Key? key}) : super(key: key);

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _roomCodeController = TextEditingController();
  final _raffleService = RaffleService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  // 连接到房间
  Future<void> _joinRoom() async {
    final code = _roomCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorMessage = '请输入房间号';
      });
      return;
    }
    String address;
    int port;
    try {
      final decoded = NetworkService.decodeRoomCode(code);
      address = decoded['ip'];
      port = decoded['port'];
    } catch (e) {
      setState(() {
        _errorMessage = '房间号格式错误';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _raffleService.joinRoom(address, port);
      if (mounted) {
        _showConnectingDialog();
      }
      final roomStream = _raffleService.roomStream;
      final room = await roomStream.first.timeout(
        const Duration(seconds:8),
        onTimeout: () => throw Exception('连接超时，请检查房间号'),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      if (mounted) {
        final confirmed = await _showJoinConfirmationDialog(room.name, room.host.name);
        if (confirmed == true) {
          Navigator.pushReplacementNamed(
            context, 
            '/participant_room',
          );
        } else {
          await _raffleService.leaveRoom();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      setState(() {
        _errorMessage = '加入房间失败: $e';
      });
      await _raffleService.leaveRoom();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 显示连接中对话框
  void _showConnectingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text('连接中'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接到房间...'),
          ],
        ),
      ),
    );
  }

  // 显示确认加入对话框
  Future<bool?> _showJoinConfirmationDialog(String roomName, String hostName) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认加入'),
        content: Text('是否加入 $hostName 的房间"$roomName"？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('加入'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('加入抽奖房间'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '请输入房间号',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _roomCodeController,
              decoration: const InputDecoration(
                labelText: '房间号',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
                hintText: '如 77-9IX',
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _joinRoom,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('加入房间'),
            ),
          ],
        ),
      ),
    );
  }
}