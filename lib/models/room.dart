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
  final String id;
  final User host;
  final List<Prize> prizes;
  final List<User> participants;
  final String multicastAddress;
  final int port;
  bool isLotteryStarted;
  bool isLotteryFinished;

  Room({
    required this.id,
    required this.host,
    required this.prizes,
    required this.participants,
    required this.multicastAddress,
    required this.port,
    this.isLotteryStarted = false,
    this.isLotteryFinished = false,
  });

  factory Room.create({
    required String name,
    required User host,
    required String multicastAddress,
    required int port,
    required List<User> participants,
    List<Prize> prizes = const [],
  }) {
    final uuid = Uuid();
    return Room(
      id: uuid.v4(),
      host: host,
      prizes: prizes,
      participants: [],
      multicastAddress: multicastAddress,
      port: port,
    );
  }

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'],
        host: User.fromJson(json['host']),
        prizes: (json['prizes'] as List).map((e) => Prize.fromJson(e)).toList(),
        participants: (json['participants'] as List).map((e) => User.fromJson(e)).toList(),
        multicastAddress: json['multicastAddress'],
        port: json['port'],
        isLotteryStarted: json['isLotteryStarted'] ?? false,
        isLotteryFinished: json['isLotteryFinished'] ?? false,
      );


  Map<String, dynamic> toJson() => {
        'id': id,
        'host': host.toJson(),
        'prizes': prizes.map((e) => e.toJson()).toList(),
        'participants': participants.map((e) => e.toJson()).toList(),
        'multicastAddress': multicastAddress,
        'port': port,
        'isLotteryStarted': isLotteryStarted,
        'isLotteryFinished': isLotteryFinished,
      };

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
    isLotteryStarted = true;
  }

  // 设置中奖结果
  void setWinners(Map<String, String> winnerMap) {
    isLotteryFinished = true;
  }

  Room? copyWith({required List<User> participants, required bool isLotteryFinished}) {
    return Room(
      id: id,
      host: host,
      prizes: prizes,
      participants: participants,
      multicastAddress: multicastAddress,
      port: port,
      isLotteryStarted: isLotteryStarted,
      isLotteryFinished: isLotteryFinished,
    );
  }
}