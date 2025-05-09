import 'dart:async';
import 'dart:typed_data';
import 'dart:convert'; // 添加JSON支持
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/udp_service.dart';

class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  UdpService? _udpService;
  String? _uuid;
  String? _roomInfo;
  String? _prizesInfo;
  String? _myPrize;
  bool _isWinner = false;
  bool _connected = false;
  bool _confirmed = false;
  bool _connecting = false;
  Timer? _timeoutTimer;
  StreamSubscription? _sub;

  // 获奖者列表
  final List<Map<String, dynamic>> _winnersList = [];

  Future<void> _initUuid() async {
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString('user_uuid');
    if (uuid == null) {
      uuid = const Uuid().v4();
      await prefs.setString('user_uuid', uuid);
    }
    _uuid = uuid;
  }

  @override
  void initState() {
    super.initState();
    _initUuid();
  }

  @override
  void dispose() {
    _udpService?.close();
    _nameController.dispose();
    _portController.dispose();
    _timeoutTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _connectRoom() async {
    final name = _nameController.text.trim();
    final portStr = _portController.text.trim();
    if (name.isEmpty || portStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入用户名和端口号')));
      return;
    }
    
    final port = int.tryParse(portStr);
    if (port == null || port < 20000 || port > 29999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('端口号需在20000-29999之间')));
      return;
    }
    
    setState(() {
      _connecting = true;
      _roomInfo = null;
      _prizesInfo = null;
      _confirmed = false;
      _connected = false;
      _winnersList.clear();
      _myPrize = null;
      _isWinner = false;
    });
    
    // 确保UUID已初始化（只在必要时调用）
    if (_uuid == null) {
      await _initUuid();
    }
    
    _udpService = UdpService();
    
    await _udpService!.bind(multicastAddress: '224.1.0.1', port: port);
    
    // 监听房主回复
    _sub = _udpService!.onData.listen((datagram) {
      final data = String.fromCharCodes(datagram.data);
      
      if (data.startsWith('room:')) {
        _timeoutTimer?.cancel();
        final parts = data.split('|');
        final room = parts.firstWhere((e) => e.startsWith('room:'), orElse: () => '');
        final prizes = parts.firstWhere((e) => e.startsWith('prizes:'), orElse: () => '');
        setState(() {
          _roomInfo = room.replaceFirst('room:', '');
          _prizesInfo = prizes.replaceFirst('prizes:', '');
          _connected = true;
          _connecting = false;
        });
      } else if (data.startsWith('prize|')) {
        // 使用新的JSON格式解析获奖信息
        try {
          final jsonStr = data.substring(6); // "prize|"之后的内容
          final winnerData = jsonDecode(jsonStr) as Map<String, dynamic>;
          
          final winnerUuid = winnerData['uuid'] as String;
          final winnerName = winnerData['name'] as String;
          final prize = winnerData['prize'] as String;
          
          // 添加到获奖者列表
          setState(() {
            _winnersList.add({
              'uuid': winnerUuid,
              'name': winnerName,
              'prize': prize
            });
            
            // 检查自己是否中奖
            if (winnerUuid == _uuid) {
              _isWinner = true;
              _myPrize = prize;
            }
          });
        } catch (e) {
          print('获奖信息解析错误: $e');
        }
      } else if (data.startsWith('winner:')) {
        // 为向后兼容保留的旧格式处理代码
        final winnerData = data.replaceFirst('winner:', '').split('|');
        if (winnerData.length == 3) {
          final winnerUuid = winnerData[0];
          final winnerName = winnerData[1];
          final prize = winnerData[2];
          
          // 添加到获奖者列表
          setState(() {
            _winnersList.add({
              'uuid': winnerUuid,
              'name': winnerName,
              'prize': prize
            });
            
            // 检查自己是否中奖
            if (winnerUuid == _uuid) {
              _isWinner = true;
              _myPrize = prize;
            }
          });
        }
      }
    });
    
    // 发送参与者广播
    _udpService!.send(Uint8List.fromList('$_uuid|$name'.codeUnits));
    
    // 3秒超时
    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (!_connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('连接超时，未收到房主回复')));
        setState(() {
          _connecting = false;
        });
      }
    });
  }

  void _confirmJoin() {
    if (_udpService != null && _uuid != null) {
      _udpService!.send(Uint8List.fromList('$_uuid|confirm'.codeUnits));
      setState(() {
        _confirmed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('参与者-加入抽奖')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _connected
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('房间：${_roomInfo ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Text('奖品：${_prizesInfo ?? ''}', style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 24),
                  if (!_confirmed)
                    ElevatedButton(
                      onPressed: _confirmJoin,
                      child: const Text('确认加入'),
                    ),
                  if (_confirmed)
                    const Text('已确认加入，等待开奖...', style: TextStyle(color: Colors.green)),

                  // 显示获奖列表
                  if (_winnersList.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('获奖名单', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _winnersList.length,
                        itemBuilder: (context, index) {
                          final winner = _winnersList[index];
                          final isMe = winner['uuid'] == _uuid;
                          
                          return ListTile(
                            title: Text(winner['name']),
                            subtitle: Text('获得: ${winner['prize']}'),
                            leading: CircleAvatar(
                              backgroundColor: isMe ? Colors.amber : Colors.blue,
                              child: Icon(
                                Icons.emoji_events, 
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            tileColor: isMe ? Colors.amber.withOpacity(0.1) : null,
                          );
                        },
                      ),
                    ),
                  ],
                  
                  // 显示自己的中奖信息
                  if (_isWinner && _myPrize != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.amber, size: 36),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('恭喜你！', 
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  )
                                ),
                                Text('你获得了: $_myPrize', 
                                  style: const TextStyle(fontSize: 16)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_winnersList.isNotEmpty && !_isWinner) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.sentiment_dissatisfied, color: Colors.grey, size: 36),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text('很遗憾，你未能中奖', 
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              )
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '用户名'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: '端口号'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _connecting ? null : _connectRoom,
                    child: _connecting 
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('连接中...'),
                          ],
                        )
                      : const Text('连接房间'),
                  ),
                ],
              ),
      ),
    );
  }
}
