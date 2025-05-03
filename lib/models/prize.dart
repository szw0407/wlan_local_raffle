// 奖品模型类
class Prize {
  final String id; // 奖品ID
  String name; // 奖品名称
  int count; // 奖品数量

  Prize({
    required this.id,
    required this.name,
    required this.count,
  });

  // 从JSON创建奖品对象
  factory Prize.fromJson(Map<String, dynamic> json) {
    return Prize(
      id: json['id'],
      name: json['name'],
      count: json['count'],
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'count': count,
    };
  }
}