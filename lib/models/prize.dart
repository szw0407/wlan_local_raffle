// 奖品模型类
class Prize {
  String id; // 奖品ID
  String name; // 奖品名称
  int quantity; // 奖品数量
  
  Prize({
    required this.id,
    required this.name,
    required this.quantity,
  });
  
  // 从JSON创建奖品对象
  factory Prize.fromJson(Map<String, dynamic> json) {
    return Prize(
      id: json['id'],
      name: json['name'],
      quantity: json['quantity'],
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
    };
  }
  
  // 创建奖品的副本
  Prize copy({
    String? id,
    String? name,
    int? quantity,
  }) {
    return Prize(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
    );
  }
}