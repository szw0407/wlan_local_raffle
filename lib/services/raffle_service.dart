import 'dart:math';

import '../models/prize.dart';
import '../models/raffle_result.dart';
import '../models/user.dart';

/// 抽奖服务，用于处理抽奖逻辑
class RaffleService {
  // 随机抽奖，将用户和奖品进行匹配，考虑奖品数量
  static RaffleResult drawRaffle(List<User> confirmedUsers, List<Prize> prizes) {
    // 只考虑已确认的用户
    List<User> eligibleUsers = confirmedUsers.where((user) => user.confirmed).toList();
    eligibleUsers.shuffle(); // 打乱用户列表
    
    // 创建结果映射
    Map<String, String?> userPrizePairs = {};
    
    // 为所有用户设置默认值为null（未中奖）
    for (User user in eligibleUsers) {
      userPrizePairs[user.uuid] = null;
    }
    
    // 根据奖品数量创建展开的奖品池
    List<String> prizePool = [];
    for (Prize prize in prizes) {
      for (int i = 0; i < prize.quantity; i++) {
        prizePool.add(prize.id);
      }
    }
    prizePool.shuffle(); // 打乱奖品池
    
    // 配对用户和奖品
    int minLength = min(eligibleUsers.length, prizePool.length);
    for (int i = 0; i < minLength; i++) {
      userPrizePairs[eligibleUsers[i].uuid] = prizePool[i];
    }
    
    return RaffleResult(userPrizePairs: userPrizePairs);
  }

  // 根据奖品ID获取奖品名称
  static String? getPrizeName(List<Prize> prizes, String? prizeId) {
    if (prizeId == null) return null;
    for (var prize in prizes) {
      if (prize.id == prizeId) {
        return prize.name;
      }
    }
    return null;
  }
}
