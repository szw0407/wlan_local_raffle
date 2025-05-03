import 'dart:convert';
import 'dart:io';
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
  Multicast? _multicast;
  Room? _room;
  String _multicastAddress = '224.1.0.1'; // Default address
  int _port = 10012; // Default port
  List<User> _participants = [];
  String? _lotteryResult;
  String? _roomCode;
  List<User> _currentParticipants = [];
  bool _lotteryDone = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _multicast?.dispose(); // Use dispose for cleanup
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

  void _handleMessage(String data, String address) {
    try {
      final msg = Message.fromString(data);
      print('Host received message: ${msg.type} from $address'); // Debug log

      if (msg.type == MessageType.joinRequest) {
        final user = User.fromJson(msg.data['user']);
        // Prevent duplicates and adding self if host sends join somehow
        if (_currentParticipants.any((u) => u.id == user.id) || user.id == _room?.host.id) {
          return;
        }
        setState(() {
          _currentParticipants.add(user);
        });
        // Optionally send updated room info immediately upon join
        _broadcastRoomInfo();
      }
      // Handle other message types if needed
    } catch (e) {
      print('Error handling message in host: $e');
    }
  }

  // Renamed from _listenMulticast for clarity
  Future<void> _startNetworkServices() async {
    if (_multicast != null) return; // Already started

    try {
      _multicast = Multicast(
        mDnsAddressIPv4: InternetAddress(_multicastAddress),
        port: _port,
      );
      await _multicast!.startListening();
      _multicast!.addListener(_handleMessage);

      // Start periodic broadcast of room info
      await _multicast!.startPeriodicBroadcast([
        _buildRoomInfoMessage() // Initial room info
      ], duration: const Duration(seconds: 3)); // Adjust interval as needed

      print('Host network services started.');
    } catch (e) {
      print("Error starting host network services: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('启动网络服务失败: $e')));
      setState(() {
        _started = false; // Revert state
        _multicast?.dispose();
        _multicast = null;
      });
      throw e; // Rethrow to stop lottery start process
    }
  }

  String _buildRoomInfoMessage() {
    if (_room == null) return ''; // Should not happen if called correctly
    // Update room participants before sending
    _room = _room!.copyWith(participants: _currentParticipants, isLotteryFinished: _lotteryDone);
    final message = Message(
      type: MessageType.roomInfo,
      data: _room!.toJson(),
    );
    return message.toString();
  }

  // Send current room info once
  void _broadcastRoomInfo() {
    if (_multicast == null || _room == null) return;
    final messageString = _buildRoomInfoMessage();
    if (messageString.isNotEmpty) {
      _multicast!.sendOnce(messageString);
    }
  }

  void _startLottery() async { // Make async
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
      _lotteryResult = null; // Reset result
    });

    _roomCode = RoomCodeUtil.encode(_multicastAddress, _port);
    final hostUser = User(id: const Uuid().v4(), name: _usernameController.text.trim(), isHost: true);
    _room = Room.create(
      name: '抽奖房间',
      host: hostUser,
      multicastAddress: _multicastAddress,
      port: _port,
      prizes: List<Prize>.from(_prizes),
      participants: [hostUser], // Start with host
    );
    _currentParticipants = [hostUser];

    try {
      await _startNetworkServices(); // Start listening and broadcasting

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('房间信息'),
          content: SelectableText('房间号: $_roomCode\n地址: $_multicastAddress:$_port'), // Show address too
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
        ),
      );
    } catch (e) {
      // Error already handled in _startNetworkServices
      print("Failed to start lottery due to network error.");
    }
  }

  void _drawLottery() async { // Keep async
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

    // Stop periodic room info broadcast
    _multicast?.stopPeriodicBroadcast();

    // Send lottery result message
    final resultMessage = Message(
      type: MessageType.lotteryResult,
      data: {
        'result': result,
        'roomCode': _roomCode, // Include room code for potential filtering on client
        'prizes': _prizes.map((p) => p.toJson()).toList(), // Send final prize list
        'winners': winners, // Send winner map
      },
    ).toString();

    await _multicast?.sendOnce(resultMessage);
    print('Lottery result sent.');

    // Send final room info indicating lottery finished
    _broadcastRoomInfo(); // This will now include isLotteryFinished = true
    // Optionally send it a few times to increase delivery chance
    await Future.delayed(Duration(milliseconds: 100));
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
                // Use SelectableText for easy copying
                child: SelectableText('房间号: ${_roomCode ?? ''}\n地址: $_multicastAddress:$_port', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                crossAxisAlignment: CrossAxisAlignment.start, // Align text left
                children: [
                  const Center(child: Text('抽奖已开始，等待抽奖者加入...')),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: _drawLottery,
                      child: const Text('开奖'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('当前参与者 (${_currentParticipants.length}):'), // Show count
                  // Display participants in a scrollable view if list gets long
                  Container(
                    constraints: BoxConstraints(maxHeight: 100), // Limit height
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _currentParticipants.map((u) => Text(u.name)).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            if (_lotteryResult != null)
              Center(
                child: Column(
                  children: [
                    const Text('开奖结果', style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText(_lotteryResult!, style: const TextStyle(fontSize: 18, color: Colors.green)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
