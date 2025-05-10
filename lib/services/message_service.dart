import 'dart:convert';
import 'dart:typed_data';

import '../models/prize.dart';
import '../models/raffle_result.dart';
import '../models/user.dart';

enum MessageType {
  userJoin,         // 用户加入请求
  hostBroadcast,    // 房主广播房间信息
  userConfirm,      // 用户确认加入
  raffleResults,    // 抽奖结果
}

/// 消息处理服务，用于处理UDP通信中的消息
class MessageService {
  // 构建用户加入消息
  static Uint8List buildUserJoinMessage(User user) {
    Map<String, dynamic> message = {
      'type': MessageType.userJoin.index,
      'user': user.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(message)));
  }

  // 构建房主广播消息
  static Uint8List buildHostBroadcastMessage(String hostName, List<Prize> prizes, String userUuid) {
    Map<String, dynamic> message = {
      'type': MessageType.hostBroadcast.index,
      'hostName': hostName,
      'prizes': prizes.map((p) => p.toJson()).toList(),
      'targetUserUuid': userUuid, // 指定目标用户UUID
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(message)));
  }

  // 构建用户确认消息
  static Uint8List buildUserConfirmMessage(User user) {
    Map<String, dynamic> message = {
      'type': MessageType.userConfirm.index,
      'user': user.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(message)));
  }

  // 构建抽奖结果消息
  static Uint8List buildRaffleResultsMessage(RaffleResult result) {
    Map<String, dynamic> message = {
      'type': MessageType.raffleResults.index,
      'result': result.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(message)));
  }

  // 解析接收到的消息
  static Map<String, dynamic> parseMessage(Uint8List data) {
    String message = utf8.decode(data);
    return jsonDecode(message);
  }

  // 获取消息类型
  static MessageType getMessageType(Map<String, dynamic> message) {
    int typeIndex = message['type'];
    return MessageType.values[typeIndex];
  }
}
