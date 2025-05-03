import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'room.dart';
import 'user.dart';

// 消息类型枚举
enum MessageType {
  roomInfo,
  joinRequest,
  joinConfirm,
  lotteryRequest,
  lotteryResult,
  error,
}

// 消息模型类
class Message {
  final MessageType type;
  final Map<String, dynamic> data;

  Message({required this.type, required this.data});

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        type: MessageType.values.firstWhere((e) => e.toString() == 'MessageType.' + (json['type'] ?? 'error')),
        data: Map<String, dynamic>.from(json['data'] ?? {}),
      );
  Map<String, dynamic> toJson() => {
        'type': type.toString().split('.').last,
        'data': data,
      };
}