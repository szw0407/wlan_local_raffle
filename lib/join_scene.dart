import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/prize.dart';
import 'models/raffle_result.dart';
import 'models/user.dart';
import 'services/message_service.dart';
import 'services/udp_service.dart';

class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final UdpService _udpService = UdpService();
  final String _multicastAddress = "224.15.0.15";
  
  final TextEditingController _portController = TextEditingController(text: '8000');
  
  String _userName = '';
  String _userUuid = '';
  String? _hostName;
  List<Prize> _prizes = [];
  bool _isConnected = false;
  bool _isConfirmed = false;
  String? _myPrizeResult;

  late User _user;
  Timer? _joinTimer;
  
  // 连接状态
  ConnectionState _connectionState = ConnectionState.none;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }
  
  @override
  void dispose() {
    _stopClient();
    _portController.dispose();
    super.dispose();
  }
  
  // 加载用户信息
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? '未命名参与者';
      _userUuid = prefs.getString('user_uuid') ?? const Uuid().v4();
      _user = User(uuid: _userUuid, name: _userName);
    });
  }
  
  // 启动客户端
  Future<void> _startClient() async {
    if (_portController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入端口号')),
      );
      return;
    }
    
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('端口号无效，请输入1-65535之间的数字')),
      );
      return;
    }
    
    setState(() {
      _connectionState = ConnectionState.waiting;
      _errorMessage = null;
    });
    
    try {
      // 绑定UDP服务
      await _udpService.bind(
        multicastAddress: _multicastAddress,
        port: port,
      );
      
      // 监听消息
      _udpService.onData.listen(_handleIncomingMessage);
      
      // 开始重复发送加入请求，直到收到回应
      _joinTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        if (!_isConnected) {
          _sendJoinRequest();
        } else {
          timer.cancel();
        }
      });
      
      // 立即发送第一次请求
      _sendJoinRequest();
      
    } catch (e) {
      setState(() {
        _connectionState = ConnectionState.none;
        _errorMessage = '连接失败: $e';
      });
    }
  }
  
  // 停止客户端
  void _stopClient() {
    _joinTimer?.cancel();
    _udpService.close();
    setState(() {
      _isConnected = false;
      _isConfirmed = false;
      _connectionState = ConnectionState.none;
      _hostName = null;
      _prizes = [];
      _myPrizeResult = null;
    });
  }
  
  // 发送加入请求
  void _sendJoinRequest() {
    final message = MessageService.buildUserJoinMessage(_user);
    _udpService.send(message);
  }
  
  // 发送确认加入
  void _sendConfirmation() {
    _user.confirmed = true;
    final message = MessageService.buildUserConfirmMessage(_user);
    _udpService.send(message);
    
    setState(() {
      _isConfirmed = true;
    });
  }
  
  // 处理接收到的消息
  void _handleIncomingMessage(dynamic datagram) {
    try {
      final data = datagram.data as Uint8List;
      final message = MessageService.parseMessage(data);
      final messageType = MessageService.getMessageType(message);
      
      switch (messageType) {
        case MessageType.hostBroadcast:
          _handleHostBroadcast(message);
          break;
        case MessageType.raffleResults:
          _handleRaffleResults(message);
          break;
        default:
          // 忽略其他类型的消息
          break;
      }
    } catch (e) {
      print('处理消息出错：$e');
    }
  }
  
  // 处理房主广播
  void _handleHostBroadcast(Map<String, dynamic> message) {
    // 检查是否是发给当前用户的消息
    if (message['targetUserUuid'] != _userUuid) {
      return;
    }
    
    final hostName = message['hostName'] as String;
    final prizes = (message['prizes'] as List)
        .map((e) => Prize.fromJson(e))
        .toList();
    
    setState(() {
      _hostName = hostName;
      _prizes = prizes;
      _isConnected = true;
      _connectionState = ConnectionState.done;
    });
  }
    // 处理抽奖结果
  void _handleRaffleResults(Map<String, dynamic> message) {
    final result = RaffleResult.fromJson(message['result']);
    final myPrizeId = result.userPrizePairs[_userUuid];
    
    String? prizeName;
    if (myPrizeId != null) {
      final prize = _prizes.firstWhere(
        (p) => p.id == myPrizeId,
        orElse: () => Prize(id: '', name: '未知奖品'),
      );
      prizeName = prize.name;
    }
    
    setState(() {
      _myPrizeResult = prizeName;
    });
    
    // 显示抽奖结果
    _showResultDialog(prizeName);
  }
  
  // 显示抽奖结果对话框
  void _showResultDialog(String? prizeName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('抽奖结果'),
        content: prizeName != null
            ? Text('恭喜您获得了: $prizeName')
            : const Text('很遗憾，您未能中奖'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('参与抽奖'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _stopClient,
              tooltip: '断开连接',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _isConnected ? _buildConnectedView() : _buildConnectView(),
        ),
      ),
    );
  }
  
  // 已连接视图
  List<Widget> _buildConnectedView() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('房间名称: $_hostName', style: const TextStyle(fontSize: 18)),
              Text('您的名称: $_userName', style: const TextStyle(fontSize: 16)),
              Text('状态: ${_isConfirmed ? '已确认参与' : '等待确认参与'}', 
                style: TextStyle(
                  fontSize: 16, 
                  color: _isConfirmed ? Colors.green : Colors.orange
                )),
              if (_myPrizeResult != null)
                Text(
                  '抽奖结果: ${_myPrizeResult != null ? '恭喜获得 $_myPrizeResult' : '未中奖'}',
                  style: TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: _myPrizeResult != null ? Colors.red : Colors.grey,
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
        if (!_isConfirmed)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('奖品列表:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _prizes.length,
                    itemBuilder: (context, index) {                    
                      final prize = _prizes[index];
                      return ListTile(
                        title: Text('${prize.name} (${prize.quantity}个)'),
                        subtitle: prize.description.isNotEmpty ? Text(prize.description) : null,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: _sendConfirmation,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('确认参与抽奖', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        )
      else
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                const SizedBox(height: 16),
                const Text('已确认参与抽奖', style: TextStyle(fontSize: 20)),
                const SizedBox(height: 8),
                const Text('请等待房主开奖...', style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          ),
        ),
    ];
  }
  
  // 连接视图
  List<Widget> _buildConnectView() {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('欢迎 $_userName', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              const Text('请输入抽奖房间的端口号:'),
              const SizedBox(height: 8),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口号',
                  hintText: '例如: 8000',
                  border: OutlineInputBorder(),
                ),
                enabled: _connectionState != ConnectionState.waiting,
              ),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton(
                  onPressed: _connectionState != ConnectionState.waiting ? _startClient : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: _connectionState == ConnectionState.waiting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('连接房间'),
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
      const Expanded(
        child: Center(
          child: Text('连接后将看到房间信息和奖品列表'),
        ),
      ),
    ];
  }
}
