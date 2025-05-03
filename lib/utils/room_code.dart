import 'dart:math';

class RoomCodeUtil {
  // 编码：将多播地址后三段和端口拼接后Base36编码
  static String encode(String multicastAddress, int port) {
    final parts = multicastAddress.split('.');
    if (parts.length != 4) throw ArgumentError('非法IP');
    final b = int.parse(parts[1]);
    final c = int.parse(parts[2]);
    final d = int.parse(parts[3]);
    final raw = (b << 24) | (c << 16) | (d << 8) | (port & 0xFF);
    final portHigh = (port >> 8) & 0xFF;
    final codeNum = (raw << 8) | portHigh;
    return codeNum.toRadixString(36).toUpperCase();
  }

  // 解码：将Base36解码为b.c.d和端口
  static (String address, int port) decode(String code) {
    final codeNum = int.parse(code, radix: 36);
    final raw = codeNum >> 8;
    final portHigh = codeNum & 0xFF;
    final b = (raw >> 24) & 0xFF;
    final c = (raw >> 16) & 0xFF;
    final d = (raw >> 8) & 0xFF;
    final portLow = raw & 0xFF;
    final port = (portHigh << 8) | portLow;
    final address = '224.$b.$c.$d';
    return (address, port);
  }
}
