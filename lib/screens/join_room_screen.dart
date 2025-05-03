import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/raffle_service.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({Key? key}) : super(key: key);

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _addressController = TextEditingController(text: '224.');
  final _portController = TextEditingController();
  final _raffleService = RaffleService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // 连接到房间
  Future<void> _joinRoom() async {
    final address = _addressController.text.trim();
    final portText = _portController.text.trim();

    if (address.isEmpty || !address.startsWith('224.')) {
      setState(() {
        _errorMessage = '请输入有效的组播地址（以224.开头）';
      });
      return;
    }

    int port;
    try {
      port = int.parse(portText);
      if (port < 1024 || port > 65535) {
        throw FormatException('端口必须在1024-65535范围内');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '请输入有效的端口号';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 加入房间
      await _raffleService.joinRoom(address, port);
      
      // 显示连接中对话框
      if (mounted) {
        _showConnectingDialog();
      }
      
      // 等待接收房间信息（最多等待30秒）
      final roomStream = _raffleService.roomStream;
      final room = await roomStream.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('连接超时，请检查地址和端口是否正确'),
      );
      
      // 关闭连接中对话框
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      // 显示确认加入对话框
      if (mounted) {
        final confirmed = await _showJoinConfirmationDialog(room.name, room.host.name);
        
        if (confirmed == true) {
          // 导航到参与者房间界面
          Navigator.pushReplacementNamed(
            context, 
            '/participant_room',
          );
        } else {
          // 用户取消加入，退出房间
          await _raffleService.leaveRoom();
        }
      }
    } catch (e) {
      // 关闭连接中对话框
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      setState(() {
        _errorMessage = '加入房间失败: $e';
      });
      
      // 退出房间
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
              '请输入房间地址和端口',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: '组播地址',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
                hintText: '224.x.x.x',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.router),
                hintText: '10000-65535',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
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