import 'package:flutter/material.dart';
import '../models/room.dart';
import '../models/user.dart';
import '../services/network_service.dart';
import '../services/raffle_service.dart';

class HostRoomScreen extends StatefulWidget {
  const HostRoomScreen({Key? key}) : super(key: key);

  @override
  State<HostRoomScreen> createState() => _HostRoomScreenState();
}

class _HostRoomScreenState extends State<HostRoomScreen> {
  late Room _room;
  final RaffleService _raffleService = RaffleService();
  bool _isDrawing = false;
  String? _winnerInfo;
  bool _drawFinished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Room) {
      _room = args;
    } else {
      _room = _raffleService.currentRoom!;
    }
  }

  Future<void> _drawLottery() async {
    setState(() {
      _isDrawing = true;
    });
    await _raffleService.generateDrawResult();
    final winners = _room.winners;
    String winnerInfo = '';
    if (winners.isNotEmpty) {
      winnerInfo = winners.entries.map((e) =>
        '${_room.participants.firstWhere((u) => u.id == e.key, orElse: () => User(id: '', name: '未知', isHost: false)).name} 获得奖品ID: ${e.value}'
      ).join('\n');
    } else {
      winnerInfo = '无人中奖';
    }
    setState(() {
      _winnerInfo = winnerInfo;
      _drawFinished = true;
      _isDrawing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('房主房间控制台')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('房间名: ${_room.name}'),
            Text('房主: ${_room.host.name}'),
            Text('多播地址: ${_room.multicastAddress}'),
            Text('端口: ${_room.port}'),
            const SizedBox(height: 16),
            // 大字体展示房间号
            Center(
              child: Text(
                '房间号: ' + NetworkService.encodeRoomCode(_room.multicastAddress, _room.port),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 16),
            Text('奖品列表:', style: Theme.of(context).textTheme.titleMedium),
            ..._room.prizes.map((p) => Text('${p.name} × ${p.quantity}')).toList(),
            const SizedBox(height: 16),
            Text('参与者:', style: Theme.of(context).textTheme.titleMedium),
            Expanded(
              child: ListView(
                children: _room.participants.isEmpty
                    ? [const Text('暂无参与者')] 
                    : _room.participants.map((u) => Text(u.name)).toList(),
              ),
            ),
            if (_winnerInfo != null) ...[
              const SizedBox(height: 16),
              Text('中奖结果: $_winnerInfo', style: const TextStyle(color: Colors.green)),
            ],
            const SizedBox(height: 16),
            if (!_drawFinished)
              Center(
                child: ElevatedButton(
                  onPressed: _isDrawing ? null : _drawLottery,
                  child: _isDrawing ? const CircularProgressIndicator() : const Text('开奖'),
                ),
              )
            else
              const Center(child: Text('抽奖已结束，不再接受新参与者。', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
