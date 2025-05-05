import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'services/udp_service.dart';

class HostPage extends StatefulWidget {
  const HostPage({Key? key}) : super(key: key);

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final TextEditingController _roomNameController = TextEditingController();

  final List<Map<String, dynamic>> _prizes = [];
  // final List<Map<String, String>> _participants = [];
  final Map<String, String> _query = {}; // uuid to username
  final Map<String, String> _participants = {}; // uuid to username
  UdpService? _udpService;
  int? _port;
  bool _isStarted = false;
  String? _winnerInfo;
  @override
  void dispose() {
    _udpService?.close();
    _roomNameController.dispose();
    super.dispose();
  }

  // 添加奖品时支持输入名称和数量
  void _addPrize() async {
    final nameController = TextEditingController();
    final countController = TextEditingController(text: '1');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加奖品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '奖品名称')),
            TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '数量')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final count = int.tryParse(countController.text.trim()) ?? 1;
              if (name.isNotEmpty && count > 0) {
                Navigator.pop(context, {'name': name, 'count': count});
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _prizes.add(result);
      });
    }
  }

  // 编辑奖品
  void _editPrize(int index) async {
    final prize = _prizes[index];
    final nameController = TextEditingController(text: prize['name']);
    final countController =
        TextEditingController(text: prize['count'].toString());
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑奖品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '奖品名称')),
            TextField(
                controller: countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '数量')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              final count = int.tryParse(countController.text.trim()) ?? 1;
              if (name.isNotEmpty && count > 0) {
                Navigator.pop(context, {'name': name, 'count': count});
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _prizes[index] = result;
      });
    }
  }

  void _removePrize(int index) {
    setState(() {
      _prizes.removeAt(index);
    });
  }

  Future<void> _startRaffle() async {
    if (_roomNameController.text.trim().isEmpty || _prizes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写房间名并添加奖品')));
      return;
    }
    final random = Random();
    final port = 20000 + random.nextInt(10000);
    _udpService = UdpService();
    await _udpService!.bind(multicastAddress: '224.1.0.1', port: port);
    setState(() {
      _port = port;
      _isStarted = true;
    });
    _udpService!.onData.listen((datagram) {
      // TODO
    });
  }

  void _drawWinner() {
    // 只从数量大于0的奖品中抽取
    // final availablePrizes = _prizes.where((p) => p['count'] > 0).toList();
    // if (_participants.isEmpty || availablePrizes.isEmpty) return;
    // final random = Random();
    // final winner = _participants[random.nextInt(_participants.length)];
    // final prizeIndex = _prizes
    //     .indexOf(availablePrizes[random.nextInt(availablePrizes.length)]);
    // final prize = _prizes[prizeIndex];
    // final msg =
    //     'winner:${winner['uuid']}|${winner['name']}|${prize['name']}(${prize['count']})';
    // _udpService?.send(Uint8List.fromList(msg.codeUnits));
    // setState(() {
    //   _winnerInfo = '${winner['name']} 获得 ${prize['name']}(${prize['count']})';
    //   _prizes[prizeIndex]['count'] = prize['count'] - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('房主-局域网抽奖')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(labelText: '房间名称'),
              enabled: !_isStarted,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('奖品列表',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (!_isStarted)
                  IconButton(onPressed: _addPrize, icon: const Icon(Icons.add)),
              ],
            ),
            ..._prizes.asMap().entries.map((e) => ListTile(
                  title: Text('${e.value['name']} (${e.value['count']})'),
                  trailing: !_isStarted
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editPrize(e.key),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _removePrize(e.key),
                            ),
                          ],
                        )
                      : null,
                )),
            const SizedBox(height: 16),
            if (!_isStarted)
              ElevatedButton(
                onPressed: _startRaffle,
                child: const Text('开始抽奖'),
              ),
            if (_isStarted && _port != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已开始，端口: $_port',
                      style: const TextStyle(color: Colors.green)),
                  const SizedBox(height: 16),
                  const Text('已加入参与者：'),
                  SizedBox(
                    height: 200, // 可根据需要调整高度
                    child: ListView.builder(
                      itemCount: _participants.length,
                      itemBuilder: (context, index) {
                        final p = _participants[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(p['name'] ?? ''),
                          subtitle: Text(p['uuid'] ?? ''),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_participants.isNotEmpty && _prizes.isNotEmpty)
                    ElevatedButton(
                      onPressed: _drawWinner,
                      child: const Text('开奖'),
                    ),
                  if (_winnerInfo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text('中奖：$_winnerInfo',
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
