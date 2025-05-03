import 'dart:convert';
import 'dart:math'; // For pow

class RoomCodeUtil {
  static const String _ipPrefix = '224.1.0.';
  static const int _radix = 36; // Use base 36 (0-9, a-z) for shorter codes
  static const int _portMultiplier = 65536; // 2^16, ensures port doesn't overlap with octet

  /// Encodes the last octet of the IP and the port into a short base-36 string.
  /// Assumes the IP address starts with "224.1.0.".
  static String encode(String address, int port) {
    if (!address.startsWith(_ipPrefix)) {
      throw ArgumentError('Address must start with $_ipPrefix');
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError('Port must be between 0 and 65535');
    }

    final parts = address.split('.');
    if (parts.length != 4) {
      throw ArgumentError('Invalid IP address format');
    }

    final int? lastOctet = int.tryParse(parts[3]);
    if (lastOctet == null || lastOctet < 0 || lastOctet > 255) {
      throw ArgumentError('Invalid last octet in IP address');
    }

    // Combine last octet and port into a single integer
    // Ensure lastOctet has enough space (multiply by 2^16)
    final combinedValue = lastOctet * _portMultiplier + port;

    // Convert to base 36
    final code = combinedValue.toRadixString(_radix);

    // Max length is 5 ('zik0z' for 224.1.0.255:65535), well within the 8 char limit.
    return code;
  }

  /// Decodes a base-36 room code back into the IP address (with prefix) and port.
  static Map<String, dynamic> decode(String code) {
    try {
      // Convert base 36 string back to integer
      final combinedValue = int.parse(code.toLowerCase(), radix: _radix); // Ensure lowercase for parsing

      // Extract last octet and port
      final lastOctet = combinedValue ~/ _portMultiplier;
      final port = combinedValue % _portMultiplier;

      if (lastOctet < 0 || lastOctet > 255 || port < 0 || port > 65535) {
        throw const FormatException('Decoded values out of range');
      }

      final address = '$_ipPrefix$lastOctet';
      return {'address': address, 'port': port};
    } catch (e) {
      print("Error decoding room code '$code': $e");
      throw FormatException('Invalid room code format: $e');
    }
  }
}
