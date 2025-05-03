import 'package:flutter/material.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../services/raffle_service.dart';

class ParticipantRoomScreen extends StatefulWidget {
  const ParticipantRoomScreen({Key? key}) : super(key: key);

  @override
  State<ParticipantRoomScreen> createState() => _ParticipantRoomScreenState();
}

class _ParticipantRoomScreenState extends State<ParticipantRoomScreen> {
  final RaffleService _raffleService = RaffleService();
  Room? _room;
  String? _winnerInfo;
  bool _hasJoined = false;
  bool _drawFinished = false;
  bool _isDrawing = false;

  @override
  void initState() {
    super.initState();
    _listenRoomUpdates();
  }

  void _listenRoomUpdates() {
    _raffleService.roomStream.listen((room) {
      setState(() {
        _room = room;
        _drawFinished = room.status == RoomStatus.closed;
        if (room.winners.isNotEmpty) {
          _winnerInfo = room.winners.entries.map((e) =>
            '${room.participants.firstWhere((u) => u.id == e.key, orElse: () => User(id: '', name: '未知', isHost: false)).name} 获得奖品ID: ${e.value}'
          ).join('\n');
        }
      });
    });
  }

  Future<void> _joinDraw() async {
    setState(() {
      _isDrawing = true;
    });
    await _raffleService.sendRaffleRequest();
    setState(() {
      _hasJoined = true;
      _isDrawing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      appBar: AppBar(title: const Text('参与抽奖')),
      body: room == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('房间名: ${room.name}'),
                  Text('房主: ${room.host.name}'),
                  Text('多播地址: ${room.multicastAddress}'),
                  Text('端口: ${room.port}'),
                  const SizedBox(height: 16),
                  Text('奖品列表:', style: Theme.of(context).textTheme.titleMedium),
                  ...room.prizes.map((p) => Text('${p.name} × ${p.quantity}')),
                  const SizedBox(height: 16),
                  if (_winnerInfo != null) ...[
                    Text('中奖结果: $_winnerInfo', style: const TextStyle(color: Colors.green)),
                  ] else if (_drawFinished) ...[
                    const Text('抽奖已结束，未中奖。', style: TextStyle(color: Colors.red)),
                  ] else if (!_hasJoined) ...[
                    Center(
                      child: ElevatedButton(
                        onPressed: _isDrawing ? null : _joinDraw,
                        child: _isDrawing ? const CircularProgressIndicator() : const Text('参与抽奖'),
                      ),
                    ),
                  ] else ...[
                    const Center(child: Text('已参与抽奖，等待开奖...')),
                  ],
                ],
              ),
            ),
    );
  }
}
