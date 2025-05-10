// 抽奖结果模型
class RaffleResult {
  Map<String, String?> userPrizePairs; // 用户uuid到奖品id的映射，null表示未中奖

  RaffleResult({required this.userPrizePairs});

  Map<String, dynamic> toJson() {
    return {
      'results': userPrizePairs,
    };
  }

  factory RaffleResult.fromJson(Map<String, dynamic> json) {
    Map<String, String?> pairs = {};
    
    if (json['results'] is Map) {
      json['results'].forEach((key, value) {
        pairs[key] = value as String?;
      });
    }

    return RaffleResult(userPrizePairs: pairs);
  }
}
