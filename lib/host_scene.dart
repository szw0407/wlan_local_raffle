import 'dart:math';
import 'dart:typed_data';
import 'dart:convert'; // 添加JSON支持
import 'package:flutter/material.dart';
import 'services/udp_service.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HostPage extends StatefulWidget {
  const HostPage({Key? key}) : super(key: key);

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final TextEditingController _roomNameController = TextEditingController();
  final TextEditingController _hostNameController = TextEditingController(text: '房主'); // 添加房主名称输入

  final List<Map<String, dynamic>> _prizes = [];
  final Map<String, String> _query = {}; // uuid to username
  final Map<String, String> _participants = {}; // uuid to username
  final Map<String, bool> _confirmedParticipants = {}; // uuid to confirmation status
  final List<Map<String, dynamic>> _winners = []; // 获奖者列表
  UdpService? _udpService;
  int? _port;
  bool _isStarted = false;
  bool _isDrawing = false; // 正在抽奖
  bool _hostJoins = false; // 房主是否参与抽奖
  String? _hostUuid; // 房主UUID

  @override
  void initState() {
    super.initState();
    _initUuid(); // 初始化房主UUID
  }

  Future<void> _initUuid() async {
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString('host_uuid');
    if (uuid == null) {
      uuid = const Uuid().v4();
      await prefs.setString('host_uuid', uuid);
    }
    _hostUuid = uuid;
  }

  @override
  void dispose() {
    _udpService?.close();
    _roomNameController.dispose();
    _hostNameController.dispose();
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

  // 获取奖品总数
  int get _totalPrizeCount {
    return _prizes.fold(0, (sum, prize) => sum + (prize['count'] as int));
  }

  // 生成奖品信息字符串
  String _getPrizesInfoString() {
    return _prizes.map((p) => "${p['name']}(${p['count']}份)").join('、');
  }

  Future<void> _startRaffle() async {
    if (_roomNameController.text.trim().isEmpty || _prizes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写房间名并添加奖品')));
      return;
    }
    
    if (_hostJoins && _hostNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('如果房主参与抽奖，请填写房主名称')));
      return;
    }
    
    final random = Random();
    final port = 20000 + random.nextInt(10000);
    _udpService = UdpService();
    await _udpService!.bind(multicastAddress: '224.1.0.1', port: port);
    
    // 如果房主参与抽奖，将房主添加到参与者列表
    if (_hostJoins && _hostUuid != null) {
      _participants[_hostUuid!] = _hostNameController.text.trim();
      _confirmedParticipants[_hostUuid!] = true; // 房主自动确认
    }
    
    setState(() {
      _port = port;
      _isStarted = true;
    });
    
    // 监听参与者加入请求
    _udpService!.onData.listen((datagram) {
      final data = String.fromCharCodes(datagram.data);
      final parts = data.split('|');
      
      if (parts.length >= 2) {
        final uuid = parts[0];
        final action = parts[1];
        
        if (action == 'confirm') {
          // 处理参与者确认加入
          if (_participants.containsKey(uuid)) {
            setState(() {
              _confirmedParticipants[uuid] = true;
            });
          }
        } else {
          // 处理新参与者加入请求
          final username = action; // 第二部分是用户名
          setState(() {
            _query[uuid] = username;
          });
          
          // 立即回复房间信息和奖品信息
          final roomInfo = 'room:${_roomNameController.text}|prizes:${_getPrizesInfoString()}';
          _udpService!.send(Uint8List.fromList(roomInfo.codeUnits));
          
          setState(() {
            _participants[uuid] = username;
          });
        }
      }
    });
  }

  void _drawWinner() async {
    if (_participants.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂无参与者')));
      return;
    }

    // 防止重复抽奖
    if (_isDrawing) return;
    
    setState(() {
      _isDrawing = true;
      _winners.clear();
    });

    // 准备抽奖池：将每个奖品按数量扩展
    final List<Map<String, dynamic>> prizePool = [];
    for (var prize in _prizes) {
      for (var i = 0; i < (prize['count'] as int); i++) {
        prizePool.add({'name': prize['name'], 'original': prize});
      }
    }
    
    // 移除未确认的用户，只保留已确认的参与者
    final confirmedParticipants = <String, String>{};
    _participants.forEach((uuid, username) {
      if (_confirmedParticipants[uuid] == true) {
        confirmedParticipants[uuid] = username;
      }
    });
    
    // 显示移除未确认用户的提示
    final removedCount = _participants.length - confirmedParticipants.length;
    if (removedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移除 $removedCount 名未确认的参与者'))
      );
    }
    
    // 更新参与者列表，移除未确认用户
    setState(() {
      _participants.clear();
      _participants.addAll(confirmedParticipants);
    });
    
    // 如果没有已确认的参与者，则提示并退出
    if (confirmedParticipants.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有已确认的参与者，无法开奖')));
      setState(() {
        _isDrawing = false;
      });
      return;
    }
    
    // 获取已确认的参与者UUID
    final confirmedUuids = confirmedParticipants.keys.toList();
    
    // 决定要抽取的人数（取参与者人数和奖品总数的较小值）
    final int drawCount = min(confirmedUuids.length, prizePool.length);
    
    if (drawCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可发放的奖品或确认的参与者')));
      setState(() {
        _isDrawing = false;
      });
      return;
    }
    
    // 打乱参与者顺序
    confirmedUuids.shuffle();
    
    // 打乱奖品顺序
    prizePool.shuffle();
    
    // 分配奖品
    for (var i = 0; i < drawCount; i++) {
      final uuid = confirmedUuids[i];
      final username = confirmedParticipants[uuid]!;
      final prize = prizePool[i]['name'];
      
      // 添加到获奖者列表
      _winners.add({
        'uuid': uuid,
        'name': username,
        'prize': prize
      });
      
      // 使用prize|JSON格式广播获奖信息
      final winnerData = {
        'uuid': uuid,
        'name': username,
        'prize': prize
      };
      final winnerJson = jsonEncode(winnerData);
      final winnerMsg = 'prize|$winnerJson';
      _udpService!.send(Uint8List.fromList(winnerMsg.codeUnits));
      
      // 添加短暂延迟，确保消息能够分开发送
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    setState(() {
      _isDrawing = false;
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
            
            // 添加房主参与抽奖选项
            if (!_isStarted)
              Column(
                children: [
                  CheckboxListTile(
                    title: const Text('房主参与抽奖'),
                    value: _hostJoins,
                    onChanged: (value) {
                      setState(() {
                        _hostJoins = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_hostJoins)
                    TextField(
                      controller: _hostNameController,
                      decoration: const InputDecoration(labelText: '房主名称'),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
              
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
                  Text('已开始，端口: $_port', style: const TextStyle(color: Colors.green)),
                  const SizedBox(height: 16),
                  const Text('已加入参与者：', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(
                    height: 200,
                    child: _participants.isEmpty 
                      ? const Center(child: Text('暂无参与者'))
                      : ListView.builder(
                          itemCount: _participants.length,
                          itemBuilder: (context, index) {
                            final uuid = _participants.keys.elementAt(index);
                            final name = _participants[uuid]!;
                            final confirmed = _confirmedParticipants[uuid] ?? false;
                            
                            return ListTile(
                              leading: CircleAvatar(child: Text('${index + 1}')),
                              title: Text(name),
                              subtitle: Text(confirmed ? '已确认' : '未确认'),
                              trailing: confirmed 
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : const Icon(Icons.hourglass_empty),
                            );
                          },
                        ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isDrawing ? null : _drawWinner,
                    child: _isDrawing 
                      ? const CircularProgressIndicator() 
                      : const Text('开始抽奖'),
                  ),
                  if (_winners.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('获奖名单：', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...(_winners.map((winner) => ListTile(
                      title: Text('${winner['name']} - ${winner['prize']}'),
                      leading: const Icon(Icons.emoji_events, color: Colors.amber),
                    ))),
                  ]
                ],
              ),
          ],
        ),
      ),
    );
  }
}
