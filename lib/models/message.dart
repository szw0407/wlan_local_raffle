import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'room.dart';
import 'user.dart';

// 消息类型枚举
enum MessageType {
  roomInfo,      // 房间信息
  joinRequest,   // 加入房间请求
  joinAck,       // 加入确认
  raffle,        // 抽奖请求
  drawStart,     // 开始抽奖
  drawResult,    // 抽奖结果
}

// 消息模型类
class Message {
  String id;           // 消息ID
  MessageType type;    // 消息类型
  String roomId;       // 房间ID
  String senderId;     // 发送者ID
  DateTime timestamp;  // 时间戳
  Map<String, dynamic> data;  // 消息数据
  
  Message({
    String? id,
    required this.type,
    required this.roomId,
    required this.senderId,
    DateTime? timestamp,
    required this.data,
  }) : 
    this.id = id ?? const Uuid().v4(),
    this.timestamp = timestamp ?? DateTime.now();
  
  // 创建房间信息消息
  factory Message.roomInfo(Room room) {
    return Message(
      type: MessageType.roomInfo,
      roomId: room.id,
      senderId: room.host.id,
      data: {
        'room': room.toJson(),
      },
    );
  }
  
  // 创建加入请求消息
  factory Message.joinRequest(String roomId, User user) {
    return Message(
      type: MessageType.joinRequest,
      roomId: roomId,
      senderId: user.id,
      data: {
        'user': user.toJson(),
      },
    );
  }
  
  // 创建加入确认消息
  factory Message.joinAck(String roomId, User user) {
    return Message(
      type: MessageType.joinAck,
      roomId: roomId,
      senderId: user.id,
      data: {
        'user': user.toJson(),
        'msg': '${user.name}加入成功',
      },
    );
  }
  
  // 创建抽奖请求消息
  factory Message.raffle(String roomId, User user) {
    return Message(
      type: MessageType.raffle,
      roomId: roomId,
      senderId: user.id,
      data: {
        'user': user.toJson(),
      },
    );
  }
  
  // 创建开始抽奖消息
  factory Message.drawStart(String roomId, User host) {
    return Message(
      type: MessageType.drawStart,
      roomId: roomId,
      senderId: host.id,
      data: {
        'host': host.toJson(),
      },
    );
  }
  
  // 创建抽奖结果消息
  factory Message.drawResult(Room room) {
    return Message(
      type: MessageType.drawResult,
      roomId: room.id,
      senderId: room.host.id,
      data: {
        'winners': room.winners,
        'room': room.toJson(),
      },
    );
  }
  
  // 从JSON创建消息对象
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      type: MessageType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => MessageType.roomInfo,
      ),
      roomId: json['roomId'],
      senderId: json['senderId'],
      timestamp: DateTime.parse(json['timestamp']),
      data: json['data'],
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'roomId': roomId,
      'senderId': senderId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
    };
  }
  
  // 序列化为String
  String serialize() {
    return jsonEncode(toJson());
  }
  
  // 反序列化
  static Message deserialize(String data) {
    final Map<String, dynamic> json = jsonDecode(data);
    return Message.fromJson(json);
  }
}