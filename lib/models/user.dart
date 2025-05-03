// 用户模型类
class User {
  final String id; // 用户ID
  final String name; // 用户名
  final bool isHost; // 是否是房主

  User({required this.id, required this.name, this.isHost = false});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'],
        name: json['name'],
        isHost: json['isHost'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isHost': isHost,
      };
}