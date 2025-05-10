// 奖品模型
class Prize {
  String id;
  String name;
  String description;
  int quantity; // 奖品数量

  Prize({
    required this.id,
    required this.name,
    this.description = '',
    this.quantity = 1, // 默认数量为1
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'quantity': quantity,
    };
  }

  factory Prize.fromJson(Map<String, dynamic> json) {
    return Prize(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      quantity: json['quantity'] ?? 1,
    );
  }
}
