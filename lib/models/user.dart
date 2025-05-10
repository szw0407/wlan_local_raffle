// 用户模型
class User {
  final String uuid;
  final String name;
  bool confirmed = false;

  User({required this.uuid, required this.name});

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'confirmed': confirmed,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      uuid: json['uuid'],
      name: json['name'],
    )..confirmed = json['confirmed'] ?? false;
  }
}
