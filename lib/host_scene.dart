import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models/prize.dart';
import 'models/raffle_result.dart';
import 'models/user.dart';
import 'services/message_service.dart';
import 'services/raffle_service.dart';
import 'services/udp_service.dart';

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> {
  final UdpService _udpService = UdpService();
  final String _multicastAddress = "224.15.0.15";
  final List<int> _availablePorts = List.generate(5, (index) => 8000 + index);

  late final String _hostName;
  late final String _userUuid;
  late int _selectedPort;

  final List<Prize> _prizes = [];
  final List<User> _users = [];
  bool _isRaffling = false;
  bool _isServerRunning = false;
  bool _includeHostInRaffle = false; // 是否将房主加入抽奖
  RaffleResult? _raffleResult;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController(text: "1"); // 添加数量控制器

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _stopServer();
    _nameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose(); // 释放数量控制器
    super.dispose();
  }

  // 加载用户信息
  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _hostName = prefs.getString('user_name') ?? '未命名房主';
    _userUuid = prefs.getString('user_uuid') ?? const Uuid().v4();
    _selectedPort = _availablePorts.first;

    setState(() {});
  }

  // 启动服务器
  Future<void> _startServer() async {
    // 如果房主加入了抽奖，则将房主信息添加到参与者列表

    try {
      await _udpService.bind(
        multicastAddress: _multicastAddress,
        port: _selectedPort,
      );

      _udpService.onData.listen(_handleIncomingMessage);
      if (_includeHostInRaffle) {
        _users.add(User(uuid: _userUuid, name: _hostName));
        _users.firstWhere((user) => user.uuid == _userUuid).confirmed = true;
      }

      setState(() {
        _isServerRunning = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('抽奖房间已开启，端口：$_selectedPort')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动服务器失败：$e')),
      );
    }
  }

  // 停止服务器
  void _stopServer() {
    _udpService.close();
    setState(() {
      _isServerRunning = false;
      _users.clear();
      _raffleResult = null;
    });
  }

  // 处理接收到的消息
  void _handleIncomingMessage(dynamic datagram) {
    try {
      final data = datagram.data as Uint8List;
      final message = MessageService.parseMessage(data);
      final messageType = MessageService.getMessageType(message);

      switch (messageType) {
        case MessageType.userJoin:
          _handleUserJoin(message);
          break;
        case MessageType.userConfirm:
          _handleUserConfirm(message);
          break;
        default:
          // 忽略其他类型的消息
          break;
      }
    } catch (e) {
      print('处理消息出错：$e');
    }
  }

  // 处理用户加入请求
  void _handleUserJoin(Map<String, dynamic> message) {
    final user = User.fromJson(message['user']);

    // 检查是否已经有该UUID的用户
    final existingUserIndex = _users.indexWhere((u) => u.uuid == user.uuid);

    if (existingUserIndex >= 0) {
      // 更新现有用户
      setState(() {
        _users[existingUserIndex] = user;
      });
    } else {
      // 添加新用户
      setState(() {
        _users.add(user);
      });
    }

    // 回复房间信息
    _sendRoomInfo(user.uuid);
  }

  // 处理用户确认加入
  void _handleUserConfirm(Map<String, dynamic> message) {
    final user = User.fromJson(message['user']);

    // 更新用户确认状态
    final index = _users.indexWhere((u) => u.uuid == user.uuid);
    if (index >= 0) {
      setState(() {
        _users[index].confirmed = true;
      });
    }
  }

  // 发送房间信息给指定用户
  void _sendRoomInfo(String userUuid) {
    final message = MessageService.buildHostBroadcastMessage(
      _hostName,
      _prizes,
      userUuid,
    );
    _udpService.send(message);
  }

  // 执行抽奖
  void _startRaffle() {
    if (_prizes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加至少一个奖品')),
      );
      return;
    }

    // 获取已确认的参与者
    final confirmedUsers = _users.where((user) => user.confirmed).toList();

    if (confirmedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无已确认的参与者')),
      );
      return;
    }

    setState(() {
      _isRaffling = true;
    });

    // 模拟抽奖过程
    Future.delayed(const Duration(seconds: 2), () {
      final result = RaffleService.drawRaffle(confirmedUsers, _prizes);

      setState(() {
        _raffleResult = result;
        _isRaffling = false;
      });

      // 广播抽奖结果
      final message = MessageService.buildRaffleResultsMessage(result);
      _udpService.send(message);
    });
  }

  // 添加奖品
  void _addPrize() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('奖品名称不能为空')),
      );
      return;
    }

    // 验证数量
    int quantity = 1;
    try {
      quantity = int.parse(_quantityController.text.trim());
      if (quantity <= 0) throw FormatException('数量必须大于0');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('奖品数量必须是大于0的整数')),
      );
      return;
    }

    setState(() {
      _prizes.add(Prize(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        quantity: quantity, // 添加数量
      ));
      _nameController.clear();
      _descriptionController.clear();
      _quantityController.text = "1"; // 重置为默认值
    });
  }

  // 删除奖品
  void _removePrize(String id) {
    setState(() {
      _prizes.removeWhere((prize) => prize.id == id);
    });
  }

  // 显示全部抽奖结果的对话框
  void _showAllRaffleResults() {
    if (_raffleResult == null) return;

    // 获取所有确认的用户和他们的中奖情况
    final List<Widget> resultWidgets = [];

    // 处理普通参与者的抽奖结果
    for (final user in _users.where((u) => u.confirmed)) {
      final prizeId = _raffleResult!.userPrizePairs[user.uuid];
      String resultText;

      if (prizeId != null) {
        final prize = _prizes.firstWhere(
          (p) => p.id == prizeId,
          orElse: () => Prize(id: '', name: '未知奖品'),
        );
        resultText = '${user.name}: 中奖 - ${prize.name}';
      } else {
        resultText = '${user.name}: 未中奖';
      }

      resultWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            resultText,
            style: TextStyle(
              fontSize: 16,
              color: prizeId != null ? Colors.green : Colors.grey,
            ),
          ),
        ),
      );
    }

    // 如果房主参与了抽奖，显示房主的抽奖结果
    if (_includeHostInRaffle) {
      final prizeId = _raffleResult!.userPrizePairs[_userUuid];

      if (prizeId != null) {
        final prize = _prizes.firstWhere(
          (p) => p.id == prizeId,
          orElse: () => Prize(id: '', name: '未知奖品'),
        );
        final resultText = '$_hostName(房主): 中奖 - ${prize.name}';

        resultWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              resultText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ),
        );
      } else if (_raffleResult!.userPrizePairs.containsKey(_userUuid)) {
        // 房主参与但未中奖
        resultWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              '$_hostName(房主): 未中奖',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        );
      }
    }

    // 显示对话框
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('抽奖结果一览'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: resultWidgets.isEmpty
                ? [const Text('暂无用户参与抽奖')]
                : resultWidgets,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建抽奖房间'),
        actions: [
          if (_isServerRunning)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: _stopServer,
              tooltip: '停止抽奖房间',
            ),
        ],
      ),
      body: _isServerRunning ? _buildServerRunningView() : _buildSetupView(),
    );
  }

  // 服务器运行中的视图
  Widget _buildServerRunningView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('房间名称: $_hostName的抽奖',
                      style: const TextStyle(fontSize: 18)),
                  Text('房间端口: $_selectedPort',
                      style: const TextStyle(fontSize: 16)),
                  Text(
                      '参与人数: ${_users.length}人 (已确认: ${_users.where((u) => u.confirmed).length}人)',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 奖品列表
          const Text('奖品列表:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Expanded(
            flex: 2,
            child: _prizes.isEmpty
                ? const Center(child: Text('暂无奖品，请添加'))
                : ListView.builder(
                    itemCount: _prizes.length,
                    itemBuilder: (context, index) {
                      final prize = _prizes[index];
                      return ListTile(
                        title: Text('${prize.name} (${prize.quantity}个)'),
                        subtitle: prize.description.isNotEmpty
                            ? Text(prize.description)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: _raffleResult == null
                              ? () => _removePrize(prize.id)
                              : null,
                        ),
                      );
                    },
                  ),
          ),

          // 参与者列表
          const SizedBox(height: 8),
          const Text('参与者列表:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Expanded(
            flex: 3,
            child: _users.isEmpty
                ? const Center(child: Text('等待参与者加入...'))
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      String? prizeInfo;
                      // 只有确认的用户才显示中奖情况
                      if (_raffleResult != null && user.confirmed) {
                        final prizeId =
                            _raffleResult!.userPrizePairs[user.uuid];
                        final prize = _prizes.firstWhere((p) => p.id == prizeId,
                            orElse: () => Prize(id: '', name: ''));
                        prizeInfo =
                            prize.name.isNotEmpty ? '中奖: ${prize.name}' : '未中奖';
                      }

                      return ListTile(
                        leading: Icon(
                          user.confirmed
                              ? Icons.check_circle
                              : (_raffleResult != null ? Icons.error : Icons.hourglass_empty),
                          color: user.confirmed 
                              ? Colors.green 
                              : (_raffleResult != null ? Colors.red : Colors.amber),
                        ),
                        title: Text(user.name),
                        subtitle: prizeInfo != null ? Text(prizeInfo) : null,
                      );
                    },
                  ),
          ),
          // 操作按钮
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _raffleResult == null && !_isRaffling
                        ? _startRaffle
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                    child: _isRaffling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_raffleResult == null ? '开始抽奖' : '抽奖已完成'),
                  ),
                  if (_raffleResult != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0),
                      child: ElevatedButton(
                        onPressed: _showAllRaffleResults,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          backgroundColor: Colors.blue,
                        ),
                        child: const Text('查看完整抽奖结果',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 设置视图（添加奖品、设置端口等）
  Widget _buildSetupView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 端口选择
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择房间端口:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButton<int>(
                    value: _selectedPort,
                    items: _availablePorts
                        .map((port) => DropdownMenuItem(
                              value: port,
                              child: Text('端口 $port'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPort = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 添加奖品
          const Text('添加奖品:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '奖品名称',
              border: OutlineInputBorder(),
              hintText: '输入奖品名称',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: '奖品描述 (可选)',
              border: OutlineInputBorder(),
              hintText: '输入奖品描述',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _quantityController,
            decoration: const InputDecoration(
              labelText: '奖品数量',
              border: OutlineInputBorder(),
              hintText: '输入奖品数量',
            ),
            keyboardType: TextInputType.number, // 使用数字键盘
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton(
                onPressed: _addPrize,
                child: const Text('添加奖品'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 奖品列表
          const Text('已添加的奖品:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Expanded(
            child: _prizes.isEmpty
                ? const Center(child: Text('暂无奖品，请添加'))
                : ListView.builder(
                    itemCount: _prizes.length,
                    itemBuilder: (context, index) {
                      final prize = _prizes[index];
                      return ListTile(
                        title: Text('${prize.name} (${prize.quantity}个)'),
                        subtitle: prize.description.isNotEmpty
                            ? Text(prize.description)
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _removePrize(prize.id),
                        ),
                      );
                    },
                  ),
          ),
          // 添加"将自己加入抽奖"的选项
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Checkbox(
                  value: _includeHostInRaffle,
                  onChanged: (value) {
                    setState(() {
                      _includeHostInRaffle = value ?? false;
                    });
                  },
                ),
                const Text('将自己也加入抽奖'),
              ],
            ),
          ),

          // 启动服务器按钮
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: ElevatedButton(
                onPressed: _prizes.isNotEmpty ? _startServer : null,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.green,
                ),
                child:
                    const Text('开始抽奖', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
