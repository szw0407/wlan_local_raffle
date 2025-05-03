import 'dart:convert'; // Add import for utf8
import 'dart:io'; // Add import for InternetAddress and RawDatagramSocket
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
  Room? _latestRoom;
  bool _lotteryDone = false;
  List<User> _currentParticipants = [];

  @override
  void dispose() {
    _usernameController.dispose();
    _roomCodeController.dispose();
    _multicast?.stopSendBoardcast(); // Stop any potential broadcasts
    super.dispose();
  }

  void _joinRoom() async {
    setState(() {
      _error = null;
      _waiting = true;
    });
    final String roomCode = _roomCodeController.text.trim();
    if (roomCode.isEmpty) {
      setState(() {
        _error = '请输入房间号';
        _waiting = false;
      });
      return;
    }

    try {
      final decoded = RoomCodeUtil.decode(roomCode);
      final String multicastAddress = decoded.$1;
      final int port = decoded.$2;

      // Instantiate Multicast for listening
      _multicast = Multicast(
        mDnsAddressIPv4: InternetAddress(multicastAddress),
        port: port,
      );
      _multicast!.addListener(_handleMessage);
      print('Listening on $multicastAddress:$port');

      // Send join request using a temporary socket
      final user = User(id: const Uuid().v4(), name: _usernameController.text.trim(), isHost: false);
      final joinMessage = Message(
        type: MessageType.joinRequest,
        data: {'user': user.toJson(), 'roomCode': roomCode},
      ).toString();
      final List<int> data = utf8.encode(joinMessage);

      try {
        RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket.send(data, InternetAddress(multicastAddress), port);
        // Optionally send to broadcast addresses as well
        final List<String> localAddresses = await _localAddress();
        for (final String addr in localAddresses) {
          final tmp = addr.split('.');
          tmp.removeLast();
          final String addrPrfix = tmp.join('.');
          final InternetAddress broadcastAddress = InternetAddress('$addrPrfix.255');
          try {
             socket.send(data, broadcastAddress, port);
          } catch (e) {
            print("Error sending broadcast join request to $broadcastAddress: $e");
          }
        }
        socket.close();
        print('Join request sent.');
      } catch (e) {
        print('Error sending join request: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送加入请求失败: $e')));
        return; // Stop if sending fails
      }

      setState(() {
        _joined = true;
        _currentParticipants.add(user);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入房间，等待开奖')));

    } catch (e) {
      print('Error joining room: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入房间失败: $e')));
    }
  }

  void _handleMessage(String data, String address) {
    try {
      final msg = Message.fromString(data);
      if (msg.type == MessageType.lotteryResult && msg.data['roomCode'] == _roomCodeController.text.trim()) {
        setState(() {
          _winnerInfo = msg.data['result'];
          _lotteryDone = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已收到开奖结果！')));
      } else if (msg.type == MessageType.roomInfo) {
        // Handle room info updates if needed
        final room = Room.fromJson(msg.data);
        setState(() {
          _currentRoom = room;
          _currentParticipants = List<User>.from(room.participants);
        });
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  Future<List<String>> _localAddress() async {
    List<String> address = [];
    final List<NetworkInterface> interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final NetworkInterface netInterface in interfaces) {
      for (final InternetAddress netAddress in netInterface.addresses) {
        if (netAddress.type == InternetAddressType.IPv4) {
           address.add(netAddress.address);
        }
      }
    }
    return address;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入抽奖房间')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _joined && _currentRoom != null
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
              onPressed: _joinRoom,
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
        if (_currentRoom != null)
          Text('房主：${_currentRoom!.host.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('奖品列表：'),
        if (_currentRoom != null)
          ..._currentRoom!.prizes.map((p) => Text('${p.name} (${p.count}份)')),
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
