import 'package:uuid/uuid.dart';
import 'prize.dart';
import 'user.dart';

// 抽奖房间状态枚举
enum RoomStatus {
  created, // 已创建
  active,  // 正在进行抽奖
  drawing, // 开奖中
  closed,  // 已关闭
}

// 房间模型类
class Room {
  String id; // 房间ID
  String name; // 房间名称
  User host; // 房主信息
  String multicastAddress; // 多播地址
  int port; // 端口
  List<Prize> prizes; // 奖品列表
  List<User> participants; // 参与者列表
  Map<String, String> winners; // 中奖名单: 用户ID -> 奖品ID
  RoomStatus status; // 房间状态
  
  Room({
    required this.id,
    required this.name,
    required this.host,
    required this.multicastAddress,
    required this.port,
    required this.prizes,
    List<User>? participants,
    Map<String, String>? winners,
    this.status = RoomStatus.created,
  }) : 
    this.participants = participants ?? [],
    this.winners = winners ?? {};
  
  // 创建新的房间
  factory Room.create({
    required String name,
    required User host,
    required String multicastAddress,
    required int port,
    List<Prize> prizes = const [],
  }) {
    final uuid = Uuid();
    return Room(
      id: uuid.v4(),
      name: name,
      host: host,
      multicastAddress: multicastAddress,
      port: port,
      prizes: prizes,
    );
  }
  
  // 从JSON创建房间对象
  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      name: json['name'],
      host: User.fromJson(json['host']),
      multicastAddress: json['multicastAddress'],
      port: json['port'],
      prizes: (json['prizes'] as List).map((p) => Prize.fromJson(p)).toList(),
      participants: (json['participants'] as List?)?.map((u) => User.fromJson(u)).toList() ?? [],
      winners: Map<String, String>.from(json['winners'] ?? {}),
      status: RoomStatus.values.firstWhere((e) => e.toString() == json['status'], 
          orElse: () => RoomStatus.created),
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host.toJson(),
      'multicastAddress': multicastAddress,
      'port': port,
      'prizes': prizes.map((p) => p.toJson()).toList(),
      'participants': participants.map((u) => u.toJson()).toList(),
      'winners': winners,
      'status': status.toString(),
    };
  }
  
  // 添加参与者
  void addParticipant(User user) {
    if (!participants.any((u) => u.id == user.id)) {
      participants.add(user);
    }
  }
  
  // 添加奖品
  void addPrize(Prize prize) {
    prizes.add(prize);
  }
  
  // 删除奖品
  void removePrize(String prizeId) {
    prizes.removeWhere((p) => p.id == prizeId);
  }
  
  // 更新奖品
  void updatePrize(Prize prize) {
    final index = prizes.indexWhere((p) => p.id == prize.id);
    if (index != -1) {
      prizes[index] = prize;
    }
  }
  
  // 抽奖
  void draw() {
    // 房间状态设为抽奖中
    status = RoomStatus.drawing;
  }
  
  // 设置中奖结果
  void setWinners(Map<String, String> winnerMap) {
    winners = winnerMap;
    status = RoomStatus.closed;
  }
}