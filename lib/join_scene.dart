import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class JoinPage extends StatefulWidget {
  const JoinPage({Key? key}) : super(key: key);

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  RawDatagramSocket? _socket;
  String? _uuid;
  bool _connected = false;
  String? _roomName;
  List<dynamic> _prizes = [];
  List<dynamic> _users = [];
  String? _result;
  StreamSubscription? _socketSub;
  bool _waitingForReply = false;
  bool _waitTimeout = false;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    _addressController.text = '224.1.0.1';
    _nameController.addListener(_onTextChanged);
    _addressController.addListener(_onTextChanged);
    _portController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _socket?.close();
    _socketSub?.cancel();
    _nameController.removeListener(_onTextChanged);
    _addressController.removeListener(_onTextChanged);
    _portController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _tryConnect() async {
    final address = '224.1.0.1';
    final port = int.tryParse(_portController.text.trim());
    final name = _nameController.text.trim();
    if (port == null || name.isEmpty) return;
    _uuid = const Uuid().v4();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.joinMulticast(InternetAddress(address));
    _socketSub = _socket!.listen((event) => _onSocketData(event, address, port));
    // 发送join_request
    final joinMsg = jsonEncode({
      'type': 'join_request',
      'user_name': name,
      'uuid': _uuid,
    });
    _socket!.send(utf8.encode(joinMsg), InternetAddress(address), port);
    setState(() {
      _connected = false;
      _roomName = null;
      _prizes = [];
      _users = [];
      _result = null;
      _waitingForReply = true;
      _waitTimeout = false;
    });
    _waitTimer?.cancel();
    _waitTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_connected) {
        setState(() {
          _waitTimeout = true;
          _waitingForReply = false;
        });
      }
    });
  }

  void _onSocketData(RawSocketEvent event, String address, int port) {
    if (event == RawSocketEvent.read) {
      final datagram = _socket!.receive();
      if (datagram == null) return;
      final msg = utf8.decode(datagram.data);
      try {
        final data = jsonDecode(msg);
        if (data['type'] == 'host_announce') {
          setState(() {
            _connected = true;
            _roomName = data['room_name'] ?? '';
            _prizes = data['prizes'] ?? [];
            if (_waitingForReply) {
              _waitingForReply = false;
              _waitTimeout = false;
              _waitTimer?.cancel();
            }
          });
        } else if (data['type'] == 'user_list') {
          setState(() {
            _users = data['users'] ?? [];
          });
        } else if (data['type'] == 'raffle_result') {
          // 查找自己是否中奖
          final results = data['results'] as List<dynamic>;
          final me = results.firstWhere(
            (r) => r['uuid'] == _uuid,
            orElse: () => null,
          );
          setState(() {
            _result = me != null ? me['prize'] : '未中奖';
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_waitingForReply) {
      return Scaffold(
        appBar: AppBar(title: const Text('参与抽奖')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 24),
              Text('正在等待房主回复...', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }
    if (_waitTimeout) {
      return Scaffold(
        appBar: AppBar(title: const Text('参与抽奖')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 24),
              const Text('等待超时，未收到房主回复', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _waitTimeout = false;
                    _waitingForReply = false;
                    _connected = false;
                    _roomName = null;
                    _prizes = [];
                    _users = [];
                    _result = null;
                  });
                },
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('参与抽奖')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '你的名称', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addressController,
              
              enabled: false,
              decoration: const InputDecoration(labelText: '组播地址', border: OutlineInputBorder(), hintText: '224.1.0.1'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(labelText: '端口', border: OutlineInputBorder(), hintText: '如 8888'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _nameController.text.isNotEmpty && _addressController.text.isNotEmpty && _portController.text.isNotEmpty ? _tryConnect : null,
              child: const Text('连接房间'),
            ),
            const SizedBox(height: 24),
            if (_connected)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已连接房间：$_roomName', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('奖品细则：'),
                  ..._prizes.map((p) => Text('${p['name']} x${p['count']}')),
                  const SizedBox(height: 8),
                  const Text('当前参与者：'),
                  ..._users.map((u) => Text(u['name'] ?? '')),
                  const SizedBox(height: 16),
                  if (_result != null)
                    Text('开奖结果：$_result', style: const TextStyle(fontSize: 18, color: Colors.red)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
