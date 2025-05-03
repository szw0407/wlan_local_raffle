// 用户模型类
class User {
  String id; // 用户ID
  String name; // 用户名
  bool isHost; // 是否是房主
  
  User({
    required this.id,
    required this.name,
    this.isHost = false,
  });
  
  // 从JSON创建用户对象
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      isHost: json['isHost'] ?? false,
    );
  }
  
  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isHost': isHost,
    };
  }
}