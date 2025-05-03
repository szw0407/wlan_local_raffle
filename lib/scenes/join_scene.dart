import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../models/room.dart';
import '../models/message.dart';
import '../services/multicast_service.dart';
import '../utils/room_code.dart';

class JoinPage extends StatefulWidget {
  const JoinPage({Key? key}) : super(key: key);

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();
  MulticastService? _multicastService;
  Room? _room;
  bool _joined = false;
  bool _waiting = false;
  String? _error;
  String? _winnerInfo;
  Room? _latestRoom;
  bool _lotteryDone = false;
  List<User> _currentParticipants = [];

  @override
  void dispose() {
    _usernameController.dispose();
    _roomCodeController.dispose();
    _multicastService?.close();
    super.dispose();
  }

  void _startMulticastListener() {
    _multicastService?.onMessage.listen((msg) {
      if (msg.type == MessageType.roomInfo) {
        final room = Room.fromJson(msg.data);
        setState(() {
          _latestRoom = room;
          _currentParticipants = List<User>.from(room.participants);
          _waiting = false;
          _lotteryDone = room.isLotteryFinished;
        });
        if (!_joined) {
          _showJoinConfirm(room);
        }
      } else if (msg.type == MessageType.lotteryResult) {
        setState(() {
          _winnerInfo = msg.data['result'] ?? '未知';
          _lotteryDone = true;
        });
      }
    });
  }

  void _tryJoin() async {
    setState(() {
      _error = null;
      _waiting = true;
    });
    final code = _roomCodeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _error = '请输入房间号';
        _waiting = false;
      });
      return;
    }
    try {
      final (address, port) = RoomCodeUtil.decode(code);
      _multicastService = MulticastService(multicastAddress: address, port: port);
      await _multicastService!.start();
      _startMulticastListener();
      bool received = false;
      // 启动5秒超时
      Future.delayed(const Duration(seconds: 5), () {
        if (!received && mounted && _waiting) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('连接超时'),
              content: const Text('5秒内未收到房间信息，请检查房间号或网络后重试。'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _waiting = false;
                      _room = null;
                      _joined = false;
                    });
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      });
      _multicastService!.send(Message(type: MessageType.joinRequest, data: {
        'user': {
          'id': const Uuid().v4(),
          'name': _usernameController.text.trim(),
          'isHost': false,
        }
      }));
    } catch (e) {
      setState(() {
        _error = '房间号无效';
        _waiting = false;
      });
    }
  }

  void _showJoinConfirm(Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('加入房间'),
        content: Text('是否加入${room.host.name}的房间？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('加入')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _joined = true;
      });
    } else {
      setState(() {
        _room = null;
        _joined = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入抽奖房间')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _joined && _room != null
            ? _buildRoomView()
            : _buildJoinForm(),
      ),
    );
  }

  Widget _buildJoinForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(labelText: '用户名'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _roomCodeController,
          decoration: const InputDecoration(labelText: '房间号'),
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (_waiting)
          const Center(child: CircularProgressIndicator()),
        if (!_waiting)
          Center(
            child: ElevatedButton(
              onPressed: _tryJoin,
              child: const Text('加入房间'),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_latestRoom != null)
          Text('房主：${_latestRoom!.host.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('奖品列表：'),
        if (_latestRoom != null)
          ..._latestRoom!.prizes.map((p) => Text('${p.name} (${p.count}份)')),
        const SizedBox(height: 16),
        const Text('当前参与者：'),
        ..._currentParticipants.map((u) => Text(u.name)),
        const SizedBox(height: 24),
        if (_winnerInfo == null && !_lotteryDone)
          const Center(child: Text('等待开奖...')),
        if (_winnerInfo != null)
          Center(child: Text('开奖结果：$_winnerInfo', style: const TextStyle(fontSize: 18, color: Colors.green))),
        if (_lotteryDone && _winnerInfo == null)
          const Center(child: Text('未中奖')),
      ],
    );
  }
}
