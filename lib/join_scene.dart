import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/udp_service.dart';

class JoinPage extends StatefulWidget {
  const JoinPage({Key? key}) : super(key: key);

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
  String? _winnerMsg;
  bool _isWinner = false;
  bool _connected = false;
  bool _confirmed = false;
  bool _connecting = false;
  Timer? _timeoutTimer;
  StreamSubscription? _sub;

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

    }
    final port = int.tryParse(portStr);
    if (port == null || port < 20000 || port > 29999) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('端口号需在20000-29999之间')));
      // do not proceed
    }else{
    setState(() {
      _connecting = true;
      _roomInfo = null;
      _prizesInfo = null;
      _confirmed = false;
      _connected = false;
    });
    await _initUuid();
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
      } else if (data.startsWith('winner:')) {
        // 解析中奖信息 winner:uuid|name|prize
        final winnerData = data.replaceFirst('winner:', '').split('|');
        if (winnerData.length == 3) {
          final winnerUuid = winnerData[0];
          final winnerName = winnerData[1];
          final prize = winnerData[2];
          setState(() {
            _winnerMsg = '恭喜 $winnerName 获得 $prize';
            _isWinner = (winnerUuid == _uuid);
          });
        }
      }
    });
    // 发送参与者广播
    _udpService!.send(Uint8List.fromList('${_uuid}|$name'.codeUnits));
    // 3秒超时
    _timeoutTimer = Timer(const Duration(seconds: 3), () {
      if (!_connected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('连接超时，未收到房主回复')));
        Navigator.of(context).pop();
      }
    });}
  }

  void _confirmJoin() {
    if (_udpService != null && _uuid != null) {
      _udpService!.send(Uint8List.fromList('${_uuid}|confirm'.codeUnits));
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
                  Text('房间：${_roomInfo ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('奖品：${_prizesInfo ?? ''}'),
                  const SizedBox(height: 24),
                  if (!_confirmed)
                    ElevatedButton(
                      onPressed: _confirmJoin,
                      child: const Text('确认加入'),
                    ),
                  if (_confirmed)
                    const Text('已确认加入，等待开奖...', style: TextStyle(color: Colors.green)),
                  if (_winnerMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Text(
                        _winnerMsg!,
                        style: TextStyle(
                          color: _isWinner ? Colors.red : Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
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
                    child: _connecting ? const CircularProgressIndicator() : const Text('连接房间'),
                  ),
                ],
              ),
      ),
    );
  }
}
