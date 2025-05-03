import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/prize.dart';
import '../services/raffle_service.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({Key? key}) : super(key: key);

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _roomNameController = TextEditingController();
  final _raffleService = RaffleService();
  final List<Prize> _prizes = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  // 添加奖品
  void _addPrize() {
    showDialog(
      context: context,
      builder: (context) => _PrizeDialog(
        onSave: (name, quantity) {
          setState(() {
            _prizes.add(Prize(
              id: const Uuid().v4(),
              name: name,
              quantity: quantity,
            ));
          });
        },
      ),
    );
  }

  // 编辑奖品
  void _editPrize(int index) {
    final prize = _prizes[index];
    showDialog(
      context: context,
      builder: (context) => _PrizeDialog(
        initialName: prize.name,
        initialQuantity: prize.quantity,
        onSave: (name, quantity) {
          setState(() {
            _prizes[index] = Prize(
              id: prize.id,
              name: name,
              quantity: quantity,
            );
          });
        },
      ),
    );
  }

  // 删除奖品
  void _deletePrize(int index) {
    setState(() {
      _prizes.removeAt(index);
    });
  }

  // 创建房间
  Future<void> _createRoom() async {
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) {
      setState(() {
        _errorMessage = '请输入房间名称';
      });
      return;
    }

    if (_prizes.isEmpty) {
      setState(() {
        _errorMessage = '请至少添加一个奖品';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 创建房间
      final room = await _raffleService.createRoom(roomName, _prizes);
      
      // 广播房间信息
      await _raffleService.broadcastRoomInfo();
      
      // 导航到房间界面
      Navigator.pushReplacementNamed(
        context, 
        '/host_room',
        arguments: room,
      );
    } catch (e) {
      setState(() {
        _errorMessage = '创建房间失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建抽奖房间'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: '房间名称',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.meeting_room),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '奖品列表',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                ElevatedButton.icon(
                  onPressed: _addPrize,
                  icon: const Icon(Icons.add),
                  label: const Text('添加奖品'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _prizes.isEmpty
                  ? const Center(child: Text('暂无奖品，请添加'))
                  : ListView.builder(
                      itemCount: _prizes.length,
                      itemBuilder: (context, index) {
                        final prize = _prizes[index];
                        return Card(
                          child: ListTile(
                            title: Text(prize.name),
                            subtitle: Text('数量: ${prize.quantity}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _editPrize(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _deletePrize(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _createRoom,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('创建房间'),
            ),
          ],
        ),
      ),
    );
  }
}

// 添加/编辑奖品对话框
class _PrizeDialog extends StatefulWidget {
  final String? initialName;
  final int? initialQuantity;
  final Function(String name, int quantity) onSave;

  const _PrizeDialog({
    Key? key,
    this.initialName,
    this.initialQuantity,
    required this.onSave,
  }) : super(key: key);

  @override
  State<_PrizeDialog> createState() => _PrizeDialogState();
}

class _PrizeDialogState extends State<_PrizeDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _quantityController = TextEditingController(
        text: widget.initialQuantity?.toString() ?? '1');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  // 保存奖品
  void _savePrize() {
    final name = _nameController.text.trim();
    final quantityText = _quantityController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _errorMessage = '请输入奖品名称';
      });
      return;
    }

    int quantity;
    try {
      quantity = int.parse(quantityText);
      if (quantity <= 0) {
        throw FormatException('数量必须大于0');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '请输入有效的数量';
      });
      return;
    }

    widget.onSave(name, quantity);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialName == null ? '添加奖品' : '编辑奖品'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '奖品名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quantityController,
            decoration: const InputDecoration(
              labelText: '数量',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _savePrize,
          child: const Text('保存'),
        ),
      ],
    );
  }
}