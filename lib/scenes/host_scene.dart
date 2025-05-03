import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/prize.dart';
import '../models/room.dart';
import '../services/multicast_service.dart';
import 'dart:math';
import '../utils/room_code.dart';

class HostPage extends StatefulWidget {
  const HostPage({Key? key}) : super(key: key);

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final TextEditingController _usernameController = TextEditingController();
  final List<Prize> _prizes = [];
  bool _started = false;
  MulticastService? _multicastService;
  Room? _room;
  String? _multicastAddress;
  int? _port;
  List<User> _participants = [];
  String? _lotteryResult;
  String? _roomCode;
  List<User> _currentParticipants = [];
  bool _lotteryDone = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _multicastService?.close();
    super.dispose();
  }

  void _addPrize() async {
    final nameController = TextEditingController();
    final countController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加奖品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '奖品名称'),
            ),
            TextField(
              controller: countController,
              decoration: const InputDecoration(labelText: '数量'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, {
                'name': nameController.text,
                'count': int.tryParse(countController.text) ?? 1,
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result['name'] != null && result['name'].toString().isNotEmpty) {
      setState(() {
        _prizes.add(Prize(id: const Uuid().v4(), name: result['name'], count: result['count']));
      });
    }
  }

  void _editPrize(int index) async {
    final prize = _prizes[index];
    final nameController = TextEditingController(text: prize.name);
    final countController = TextEditingController(text: prize.count.toString());
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑奖品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '奖品名称'),
            ),
            TextField(
              controller: countController,
              decoration: const InputDecoration(labelText: '数量'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, {
                'name': nameController.text,
                'count': int.tryParse(countController.text) ?? 1,
              });
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result['name'] != null && result['name'].toString().isNotEmpty) {
      setState(() {
        _prizes[index] = Prize(id: prize.id, name: result['name'], count: result['count']);
      });
    }
  }

  void _removePrize(int index) {
    setState(() {
      _prizes.removeAt(index);
    });
  }

  // 固定多播地址和端口，便于调试
  void _allocateMulticastAddressAndPort() {
    _multicastAddress = '224.0.0.1';
    _port = 10012;
  }

  void _handleJoinRequest(Message msg) {
    final user = User.fromJson(msg.data['user']);
    if (_participants.any((u) => u.id == user.id)) return;
    setState(() {
      _participants.add(user);
    });
    // 回复房间信息，便于抽奖者端显示房主和奖品
    _multicastService?.send(Message(type: MessageType.roomInfo, data: _room!.toJson()));
  }

  void _listenMulticast() {
    _participants = [_room!.host]; // 房主自己也参与
    _multicastService!.onMessage.listen((msg) {
      if (msg.type == MessageType.joinRequest) {
        _handleJoinRequest(msg);
      }
    });
  }

  void _startMulticastListener() {
    _multicastService?.onMessage.listen((msg) {
      if (_lotteryDone) return;
      if (msg.type == MessageType.joinRequest) {
        final user = User.fromJson(msg.data['user']);
        // 只允许未开奖时加入
        if (!_currentParticipants.any((u) => u.id == user.id)) {
          setState(() {
            _currentParticipants.add(user);
          });
          // 广播最新roomInfo，带当前参与者
          _broadcastRoomInfo();
        }
      }
    });
  }

  void _broadcastRoomInfo() {
    if (_room == null) return;
    final room = Room(
      id: _room!.id,
      host: _room!.host,
      prizes: List<Prize>.from(_prizes),
      participants: List<User>.from(_currentParticipants),
      multicastAddress: _room!.multicastAddress,
      port: _room!.port,
      isLotteryStarted: _started,
      isLotteryFinished: _lotteryDone,
    );
    _multicastService?.send(Message(type: MessageType.roomInfo, data: room.toJson()));
  }

  void _startLottery() {
    if (_usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入用户名')));
      return;
    }
    if (_prizes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少添加一个奖品')));
      return;
    }
    setState(() {
      _started = true;
      _lotteryDone = false;
    });
    _allocateMulticastAddressAndPort();
    _roomCode = RoomCodeUtil.encode(_multicastAddress!, _port!);
    final hostUser = User(id: const Uuid().v4(), name: _usernameController.text.trim(), isHost: true);
    _room = Room.create(
      name: '抽奖房间',
      host: hostUser,
      multicastAddress: _multicastAddress!,
      port: _port!,
      prizes: List<Prize>.from(_prizes),
    );
    _currentParticipants = [hostUser];
    _multicastService = MulticastService(multicastAddress: _multicastAddress!, port: _port!);
    _multicastService!.start().then((_) {
      _startMulticastListener();
      _broadcastRoomInfo();
    });
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('房间信息'),
        content: Text('房间号: $_roomCode'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
      ),
    );
  }

  void _drawLottery() {
    if (_currentParticipants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有参与者，无法开奖')));
      return;
    }
    final rand = Random();
    final prizePool = <Prize>[];
    for (final p in _prizes) {
      for (int i = 0; i < p.count; i++) {
        prizePool.add(Prize(id: p.id, name: p.name, count: 1));
      }
    }
    final users = List<User>.from(_currentParticipants);
    users.shuffle(rand);
    prizePool.shuffle(rand);
    int n = min(users.length, prizePool.length);
    final winners = <String, String>{};
    for (int i = 0; i < n; i++) {
      winners[users[i].name] = prizePool[i].name;
    }
    String result = winners.entries.map((e) => '${e.key}：${e.value}').join('\n');
    setState(() {
      _lotteryResult = result;
      _lotteryDone = true;
    });
    _multicastService?.send(Message(type: MessageType.lotteryResult, data: {'result': result}));
    // 广播最终roomInfo，标记已开奖
    _broadcastRoomInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('房主设置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '房主用户名'),
              enabled: !_started,
            ),
            const SizedBox(height: 16),
            const Text('奖品列表：', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _prizes.length,
                itemBuilder: (context, index) {
                  final prize = _prizes[index];
                  return ListTile(
                    title: Text('${prize.name} (${prize.count}份)'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: !_started ? () => _editPrize(index) : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: !_started ? () => _removePrize(index) : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_started)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('房间号: ${_roomCode ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            if (!_started)
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _addPrize,
                    child: const Text('添加奖品'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _startLottery,
                    child: const Text('开始抽奖'),
                  ),
                ],
              ),
            if (_started && !_lotteryDone)
              Column(
                children: [
                  const Center(child: Text('抽奖已开始，等待抽奖者加入...')),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _drawLottery,
                    child: const Text('开奖'),
                  ),
                  const SizedBox(height: 8),
                  Text('当前参与者：'),
                  ..._currentParticipants.map((u) => Text(u.name)),
                ],
              ),
            if (_lotteryResult != null)
              Center(
                child: Column(
                  children: [
                    const Text('开奖结果', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_lotteryResult!, style: const TextStyle(fontSize: 18, color: Colors.green)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
