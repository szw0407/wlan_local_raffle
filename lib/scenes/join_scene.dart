import 'dart:convert';
import 'dart:io';
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
  Multicast? _multicast;
  Room? _currentRoom;
  bool _joined = false;
  bool _waiting = false;
  String? _error;
  String? _winnerInfo;
  bool _lotteryDone = false;
  List<User> _currentParticipants = [];
  User? _currentUser;
  String? _lotteryResult;

  @override
  void dispose() {
    _usernameController.dispose();
    _roomCodeController.dispose();
    _multicast?.dispose();
    super.dispose();
  }

  void _joinRoom() async {
    if (_usernameController.text.trim().isEmpty) {
      setState(() => _error = '请输入用户名');
      return;
    }
    if (_roomCodeController.text.trim().isEmpty) {
      setState(() => _error = '请输入房间号');
      return;
    }

    setState(() {
      _error = null;
      _waiting = true;
      _joined = false;
      _currentRoom = null;
      _lotteryResult = null;
      _lotteryDone = false;
      _currentParticipants = [];
    });

    final String roomCode = _roomCodeController.text.trim();
    final String username = _usernameController.text.trim();

    try {
      final decoded = RoomCodeUtil.decode(roomCode);
      final String multicastAddress = decoded['address']!;
      final int port = decoded['port']!;
      print('Decoded room code: $multicastAddress:$port');
      _multicast?.dispose();

      _multicast = Multicast(
        mDnsAddressIPv4: InternetAddress(multicastAddress),
        port: port,
      );

      await _multicast!.startListening();
      _multicast!.addListener(_handleMessage);
      print('Listening on $multicastAddress:$port');

      _currentUser = User(id: const Uuid().v4(), name: username, isHost: false);
      final joinMessage = Message(
        type: MessageType.joinRequest,
        data: {'user': _currentUser!.toJson(), 'roomCode': roomCode},
      ).toString();

      await _multicast!.sendOnce(joinMessage);
      print('Join request sent.');

      setState(() {
        _joined = true;
        _waiting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已发送加入请求，等待房间信息...')));

    } catch (e) {
      print('Error joining room: $e');
      setState(() {
        _error = '加入房间失败: $e';
        _waiting = false;
        _multicast?.dispose();
        _multicast = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入房间失败: $e')));
    }
  }

  void _handleMessage(String data, String address) {
    try {
      final msg = Message.fromString(data);
      print('Client received message: ${msg.type} from $address');

      if (msg.type == MessageType.roomInfo) {
        final room = Room.fromJson(msg.data);
        if (room.multicastAddress == _multicast?.mDnsAddressIPv4.address && room.port == _multicast?.port) {
          setState(() {
            _currentRoom = room;
            _currentParticipants = List<User>.from(room.participants);
            _lotteryDone = room.isLotteryFinished;
            if (_lotteryDone && _lotteryResult == null) {
               _winnerInfo = "开奖已结束，等待结果...";
            }
          });
        }
      } else if (msg.type == MessageType.lotteryResult) {
        if (msg.data['roomCode'] == _roomCodeController.text.trim()) {
          setState(() {
            _lotteryResult = msg.data['result'] ?? '无中奖信息';
            _lotteryDone = true;
            final winnersMap = msg.data['winners'] as Map?;
            if (_currentUser != null && winnersMap != null && winnersMap.containsKey(_currentUser!.name)) {
              _winnerInfo = '恭喜你中奖了！奖品：${winnersMap[_currentUser!.name]}';
            } else {
              _winnerInfo = '本次未中奖';
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已收到开奖结果！')));
        }
      }
    } catch (e) {
      print('Error handling message in client: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入抽奖房间')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _joined
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
          enabled: !_waiting && !_joined,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _roomCodeController,
          decoration: const InputDecoration(labelText: '房间号'),
          enabled: !_waiting && !_joined,
        ),
        const SizedBox(height: 24),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (_waiting)
          const Center(child: CircularProgressIndicator()),
        if (!_waiting)
          Center(
            child: ElevatedButton(
              onPressed: _joined ? null : _joinRoom,
              child: Text(_joined ? '已加入' : '加入房间'),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomView() {
    if (_currentRoom == null && !_lotteryDone) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接房间...'),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentRoom != null)
          Text('房间: ${_roomCodeController.text} (房主: ${_currentRoom!.host.name})', style: const TextStyle(fontWeight: FontWeight.bold)),
        if (_currentRoom != null)
           Text('地址: ${_currentRoom!.multicastAddress}:${_currentRoom!.port}'),
        const SizedBox(height: 16),
        const Text('奖品列表：'),
        if (_currentRoom != null)
          ..._currentRoom!.prizes.map((p) => Text('- ${p.name} (${p.count}份)')),
        const SizedBox(height: 16),
        const Text('当前参与者：'),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _currentParticipants.map((u) => Text('- ${u.name}${u.id == _currentUser?.id ? ' (你)' : ''}${u.isHost ? ' (房主)' : ''}')).toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: _lotteryDone
              ? Column(
                  children: [
                    const Text('开奖结果', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    if (_winnerInfo != null)
                       Text(_winnerInfo!, style: const TextStyle(fontSize: 16, color: Colors.blue)),
                    if (_lotteryResult != null && _lotteryResult!.isNotEmpty)
                       Padding(
                         padding: const EdgeInsets.only(top: 8.0),
                         child: SelectableText("详细结果:\n$_lotteryResult", textAlign: TextAlign.center),
                       ),
                    if (_lotteryResult == null && _winnerInfo == null)
                       const Text("正在获取开奖结果..."),
                  ],
                )
              : const Text('等待房主开奖...', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
