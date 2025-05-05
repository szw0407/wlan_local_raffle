import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';

class Prize {
  String name;
  int count;
  Prize({required this.name, required this.count});
}

class HostPage extends StatefulWidget {
  const HostPage({Key? key}) : super(key: key);

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final TextEditingController _hostNameController = TextEditingController();
  List<Prize> _prizes = [];
  String? _multicastAddress;
  int? _multicastPort;
  RawDatagramSocket? _socket;
  List<Map<String, dynamic>> _users = [];
  bool _raffleStarted = false;

  @override
  void initState() {
    super.initState();
    _generateMulticastAddress();
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }

  void _generateMulticastAddress() {
    // 地址固定为224.1.0.1，仅端口可变
    final rand = Random();
    int yy = 8000 + rand.nextInt(1000); // 避免常用端口
    setState(() {
      _multicastAddress = '224.1.0.1';
      _multicastPort = yy;
    });
  }

  void _addPrize() {
    setState(() {
      _prizes.add(Prize(name: '', count: 1));
    });
  }

  void _removePrize(int index) {
    setState(() {
      _prizes.removeAt(index);
    });
  }

  void _updatePrizeName(int index, String name) {
    setState(() {
      _prizes[index].name = name;
    });
  }

  void _updatePrizeCount(int index, int count) {
    setState(() {
      _prizes[index].count = count;
    });
  }

  void _startRaffle() async {
    if (_multicastAddress == null || _multicastPort == null) return;
    setState(() {
      _raffleStarted = true;
    });
    // 创建UDP多播socket并监听
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _multicastPort!);
    _socket!.joinMulticast(InternetAddress(_multicastAddress!));
    _socket!.listen(_onSocketData);
    // 广播房主信息
    _broadcastHostInfo();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('抽奖已开始，等待参与者加入...')),
    );
  }

  void _broadcastHostInfo() {
    if (_socket == null) return;
    final msg = jsonEncode({
      'type': 'host_announce',
      'room_name': _hostNameController.text,
      'prizes': _prizes.map((e) => {'name': e.name, 'count': e.count}).toList(),
      'address': '$_multicastAddress:$_multicastPort',
    });
    _socket!.send(utf8.encode(msg), InternetAddress(_multicastAddress!), _multicastPort!);
  }

  void _onSocketData(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = _socket!.receive();
      if (datagram == null) return;
      final msg = utf8.decode(datagram.data);
      try {
        final data = jsonDecode(msg);
        if (data['type'] == 'join_request') {
          // 新用户请求加入
          final user = {
            'name': data['user_name'] ?? '',
            'uuid': data['uuid'] ?? '',
          };
          if (_users.indexWhere((u) => u['uuid'] == user['uuid']) == -1) {
            setState(() {
              _users.add(user);
            });
            // 广播当前用户列表
            _broadcastUserList();
            // 再次广播房主信息，便于新用户同步
            _broadcastHostInfo();
          }
        }
      } catch (_) {}
    }
  }

  void _broadcastUserList() {
    if (_socket == null) return;
    final msg = jsonEncode({
      'type': 'user_list',
      'users': _users,
    });
    _socket!.send(utf8.encode(msg), InternetAddress(_multicastAddress!), _multicastPort!);
  }

  void _drawRaffle() {
    if (_users.isEmpty || _prizes.isEmpty) return;
    // 生成奖品列表
    final prizeList = <Map<String, String>>[];
    for (var prize in _prizes) {
      for (int i = 0; i < prize.count; i++) {
        prizeList.add({'prize': prize.name});
      }
    }
    // 随机打乱用户和奖品
    final usersShuffled = List<Map<String, String>>.from(_users)..shuffle();
    final prizesShuffled = List<Map<String, String>>.from(prizeList)..shuffle();
    final results = <Map<String, String>>[];
    for (int i = 0; i < usersShuffled.length && i < prizesShuffled.length; i++) {
      results.add({
        'user_name': usersShuffled[i]['name'] ?? '',
        'uuid': usersShuffled[i]['uuid'] ?? '',
        'prize': prizesShuffled[i]['prize'] ?? '',
      });
    }
    // 广播开奖结果
    _broadcastRaffleResult(results);
    // 弹窗显示结果
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开奖结果'),
        content: SizedBox(
          width: 300,
          child: ListView(
            shrinkWrap: true,
            children: results.map((r) => ListTile(
              title: Text(r['user_name'] ?? ''),
              subtitle: Text(r['prize'] ?? ''),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _broadcastRaffleResult(List<Map<String, String>> results) {
    if (_socket == null) return;
    final msg = jsonEncode({
      'type': 'raffle_result',
      'results': results,
    });
    _socket!.send(utf8.encode(msg), InternetAddress(_multicastAddress!), _multicastPort!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('房主设置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _hostNameController,
              decoration: const InputDecoration(
                labelText: '房主名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('奖品设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: _addPrize,
                  child: const Text('添加奖品'),
                ),
              ],
            ),
            ..._prizes.asMap().entries.map((entry) {
              int idx = entry.key;
              Prize prize = entry.value;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(labelText: '奖品名称'),
                          onChanged: (v) => _updatePrizeName(idx, v),
                          controller: TextEditingController(text: prize.name),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          decoration: const InputDecoration(labelText: '数量'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _updatePrizeCount(idx, int.tryParse(v) ?? 1),
                          controller: TextEditingController(text: prize.count.toString()),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removePrize(idx),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            if (_multicastAddress != null && _multicastPort != null)
              Text('组播地址: 224.1.0.1:$_multicastPort', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _prizes.isNotEmpty && _hostNameController.text.isNotEmpty ? _startRaffle : null,
              child: const Text('开始抽奖'),
            ),
            if (_raffleStarted)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text('已加入用户：', style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._users.map((u) => Text('${u['name']} (${u['uuid']})')),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _users.isNotEmpty && _prizes.isNotEmpty ? _drawRaffle : null,
                    child: const Text('开奖'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
