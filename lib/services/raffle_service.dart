import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_service.dart';
import '../models/message.dart';
import '../models/prize.dart';
import '../models/room.dart';
import '../models/user.dart';

// 抽奖服务状态枚举
enum RaffleServiceStatus {
  idle,        // 空闲状态
  hosting,     // 作为房主
  joined,      // 作为参与者
  raffling,    // 正在抽奖
  completed,   // 抽奖完成
}

// 抽奖服务
class RaffleService {
  // 单例实例
  static final RaffleService _instance = RaffleService._internal();
  
  // 工厂构造函数
  factory RaffleService() {
    return _instance;
  }
  
  // 内部构造函数
  RaffleService._internal() {
    _networkService = NetworkService();
    _initializeService();
  }
  
  // 网络服务
  late NetworkService _networkService;
  
  // 用户信息
  User? _currentUser;
  
  // 当前房间
  Room? _currentRoom;
  
  // 当前状态
  RaffleServiceStatus _status = RaffleServiceStatus.idle;
  
  // 状态变化流
  final _statusController = StreamController<RaffleServiceStatus>.broadcast();
  Stream<RaffleServiceStatus> get statusStream => _statusController.stream;
  
  // 房间变化流
  final _roomController = StreamController<Room>.broadcast();
  Stream<Room> get roomStream => _roomController.stream;
  
  // 错误流
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;
  
  // 消息处理订阅
  StreamSubscription? _messageSubscription;
  
  // 已收到的消息ID集合（防止重复处理）
  final Set<String> _processedMessageIds = {};
  
  // 初始化服务
  Future<void> _initializeService() async {
    // 订阅消息流
    _messageSubscription = _networkService.messageStream.listen(_handleMessage);
    
    // 尝试恢复用户信息
    await _loadUserInfo();
  }
  
  // 保存用户信息到本地存储
  Future<void> _saveUserInfo() async {
    if (_currentUser != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user', jsonEncode(_currentUser!.toJson()));
    }
  }
  
  // 从本地存储加载用户信息
  Future<void> _loadUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user');
      
      if (userJson != null) {
        final userData = jsonDecode(userJson);
        _currentUser = User.fromJson(userData);
      }
    } catch (e) {
      print('加载用户信息失败: $e');
    }
  }
  
  // 设置当前用户
  Future<void> setUser(String name, {bool isHost = false}) async {
    final id = _currentUser?.id ?? const Uuid().v4();
    _currentUser = User(id: id, name: name, isHost: isHost);
    await _saveUserInfo();
  }
  
  // 获取当前用户
  User? get currentUser => _currentUser;
  
  // 获取当前状态
  RaffleServiceStatus get status => _status;
  
  // 获取当前房间
  Room? get currentRoom => _currentRoom;
  
  // 创建房间
  Future<Room> createRoom(String roomName, List<Prize> prizes) async {
    if (_currentUser == null) {
      throw Exception('用户未设置');
    }
    
    try {
      // 初始化网络服务（作为房主）
      final networkInfo = await _networkService.initHost();
      
      // 创建房间
      _currentRoom = Room.create(
        name: roomName,
        host: _currentUser!,
        multicastAddress: networkInfo['multicastAddress'],
        port: networkInfo['port'],
        prizes: prizes,
      );
      
      // 更新状态
      _status = RaffleServiceStatus.hosting;
      _statusController.add(_status);
      _roomController.add(_currentRoom!);
      
      return _currentRoom!;
    } catch (e) {
      _errorController.add('创建房间失败: $e');
      throw Exception('创建房间失败: $e');
    }
  }
  
  // 加入房间
  Future<void> joinRoom(String multicastAddress, int port) async {
    if (_currentUser == null) {
      throw Exception('用户未设置');
    }
    
    try {
      // 初始化网络服务（作为参与者）
      await _networkService.initClient(multicastAddress, port);
      
      // 发送加入请求
      // 这里我们先发送一个空的房间ID，等收到房间信息后再更新
      await _networkService.sendMessage(
        Message.joinRequest('pending', _currentUser!),
      );
      
      // 更新状态
      _status = RaffleServiceStatus.joined;
      _statusController.add(_status);
    } catch (e) {
      _errorController.add('加入房间失败: $e');
      throw Exception('加入房间失败: $e');
    }
  }
  
  // 广播房间信息
  Future<void> broadcastRoomInfo() async {
    if (_currentRoom == null || _status != RaffleServiceStatus.hosting) {
      throw Exception('不是房主或房间未创建');
    }
    
    try {
      await _networkService.sendMessage(
        Message.roomInfo(_currentRoom!),
      );
    } catch (e) {
      _errorController.add('广播房间信息失败: $e');
      throw Exception('广播房间信息失败: $e');
    }
  }
  
  // 发送抽奖请求
  Future<void> sendRaffleRequest() async {
    if (_currentUser == null || _currentRoom == null) {
      throw Exception('用户未设置或未加入房间');
    }
    
    try {
      await _networkService.sendMessage(
        Message.raffle(_currentRoom!.id, _currentUser!),
      );
    } catch (e) {
      _errorController.add('发送抽奖请求失败: $e');
      throw Exception('发送抽奖请求失败: $e');
    }
  }
  
  // 开始抽奖
  Future<void> startDraw() async {
    if (_currentRoom == null || _status != RaffleServiceStatus.hosting) {
      throw Exception('不是房主或房间未创建');
    }
    
    try {
      // 更新房间状态
      _currentRoom!.status = RoomStatus.drawing;
      
      // 发送开始抽奖消息
      await _networkService.sendMessage(
        Message.drawStart(_currentRoom!.id, _currentUser!),
      );
      
      // 更新状态
      _status = RaffleServiceStatus.raffling;
      _statusController.add(_status);
      _roomController.add(_currentRoom!);
    } catch (e) {
      _errorController.add('开始抽奖失败: $e');
      throw Exception('开始抽奖失败: $e');
    }
  }
  
  // 生成抽奖结果
  Future<void> generateDrawResult() async {
    if (_currentRoom == null || _status != RaffleServiceStatus.raffling || !_currentUser!.isHost) {
      throw Exception('无法生成抽奖结果');
    }
    
    try {
      // 创建一个中奖名单
      final Map<String, String> winners = {};
      final List<User> participants = [..._currentRoom!.participants];
      final List<Prize> prizes = [..._currentRoom!.prizes];
      
      // 随机打乱参与者顺序
      participants.shuffle(Random());
      
      // 分配奖品（简单实现：按顺序分配，直到奖品分完或者参与者分完）
      int participantIndex = 0;
      
      for (var prize in prizes) {
        for (var i = 0; i < prize.quantity; i++) {
          if (participantIndex < participants.length) {
            // 分配奖品给参与者
            winners[participants[participantIndex].id] = prize.id;
            participantIndex++;
          } else {
            // 参与者已分配完毕，退出循环
            break;
          }
        }
        
        // 如果参与者已分配完毕，退出循环
        if (participantIndex >= participants.length) {
          break;
        }
      }
      
      // 更新房间状态和中奖名单
      _currentRoom!.winners = winners;
      _currentRoom!.status = RoomStatus.closed;
      
      // 发送抽奖结果
      await _networkService.sendMessage(
        Message.drawResult(_currentRoom!),
      );
      
      // 更新状态
      _status = RaffleServiceStatus.completed;
      _statusController.add(_status);
      _roomController.add(_currentRoom!);
    } catch (e) {
      _errorController.add('生成抽奖结果失败: $e');
      throw Exception('生成抽奖结果失败: $e');
    }
  }
  
  // 处理接收到的消息
  void _handleMessage(Message message) {
    // 检查消息是否已处理过
    if (_processedMessageIds.contains(message.id)) {
      return;
    }
    
    // 将消息ID添加到已处理集合
    _processedMessageIds.add(message.id);
    
    switch (message.type) {
      case MessageType.roomInfo:
        _handleRoomInfoMessage(message);
        break;
      case MessageType.joinRequest:
        _handleJoinRequestMessage(message);
        break;
      case MessageType.raffle:
        _handleRaffleMessage(message);
        break;
      case MessageType.drawStart:
        _handleDrawStartMessage(message);
        break;
      case MessageType.drawResult:
        _handleDrawResultMessage(message);
        break;
    }
  }
  
  // 处理房间信息消息
  void _handleRoomInfoMessage(Message message) {
    final roomData = message.data['room'];
    final room = Room.fromJson(roomData);
    
    // 更新当前房间信息
    _currentRoom = room;
    
    // 如果当前用户不是房主，且房间状态是已创建，则添加自己到参与者列表
    if (!_currentUser!.isHost && room.status == RoomStatus.created && _status == RaffleServiceStatus.joined) {
      _networkService.sendMessage(
        Message.joinRequest(room.id, _currentUser!),
      );
    }
    
    // 更新流
    _roomController.add(room);
  }
  
  // 处理加入请求消息
  void _handleJoinRequestMessage(Message message) {
    // 只有房主处理加入请求
    if (_status != RaffleServiceStatus.hosting || _currentRoom == null) {
      return;
    }
    
    final userData = message.data['user'];
    final user = User.fromJson(userData);
    
    // 将用户添加到参与者列表
    _currentRoom!.addParticipant(user);
    
    // 广播更新后的房间信息
    _networkService.sendMessage(
      Message.roomInfo(_currentRoom!),
    );
    
    // 更新流
    _roomController.add(_currentRoom!);
  }
  
  // 处理抽奖请求消息
  void _handleRaffleMessage(Message message) {
    // 只有房主处理抽奖请求
    if (_status != RaffleServiceStatus.hosting || _currentRoom == null) {
      return;
    }
    
    final userData = message.data['user'];
    final user = User.fromJson(userData);
    
    // 确保用户在参与者列表中
    if (!_currentRoom!.participants.any((p) => p.id == user.id)) {
      _currentRoom!.addParticipant(user);
    }
    
    // 广播更新后的房间信息
    _networkService.sendMessage(
      Message.roomInfo(_currentRoom!),
    );
    
    // 更新流
    _roomController.add(_currentRoom!);
  }
  
  // 处理开始抽奖消息
  void _handleDrawStartMessage(Message message) {
    if (_currentRoom == null) {
      return;
    }
    
    // 更新房间状态
    _currentRoom!.status = RoomStatus.drawing;
    
    // 如果当前用户不是房主，则更新状态为正在抽奖
    if (!_currentUser!.isHost) {
      _status = RaffleServiceStatus.raffling;
      _statusController.add(_status);
    }
    
    // 更新流
    _roomController.add(_currentRoom!);
  }
  
  // 处理抽奖结果消息
  void _handleDrawResultMessage(Message message) {
    final roomData = message.data['room'];
    final winners = Map<String, String>.from(message.data['winners']);
    
    // 更新房间信息和中奖名单
    _currentRoom = Room.fromJson(roomData);
    _currentRoom!.winners = winners;
    
    // 更新状态为已完成
    _status = RaffleServiceStatus.completed;
    _statusController.add(_status);
    
    // 更新流
    _roomController.add(_currentRoom!);
  }
  
  // 退出房间/关闭房间
  Future<void> leaveRoom() async {
    // 关闭网络服务
    await _networkService.close();
    
    // 重置状态
    _status = RaffleServiceStatus.idle;
    _currentRoom = null;
    
    // 清空已处理消息集合
    _processedMessageIds.clear();
    
    // 更新状态流
    _statusController.add(_status);
  }
  
  // 清理资源
  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _networkService.close();
    await _statusController.close();
    await _roomController.close();
    await _errorController.close();
  }
}