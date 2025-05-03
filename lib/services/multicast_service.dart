import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/message.dart';

class MulticastService {
  RawDatagramSocket? _socket;
  final String multicastAddress;
  final int port;
  final StreamController<Message> _messageController = StreamController<Message>.broadcast();

  MulticastService({required this.multicastAddress, required this.port});

  Stream<Message> get onMessage => _messageController.stream;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: true);
    _socket!.joinMulticast(InternetAddress(multicastAddress));
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          try {
            final jsonStr = utf8.decode(datagram.data);
            final map = json.decode(jsonStr);
            final msg = Message.fromJson(map);
            _messageController.add(msg);
          } catch (_) {}
        }
      }
    });
  }

  void send(Message message) {
    if (_socket != null) {
      final data = utf8.encode(json.encode(message.toJson()));
      _socket!.send(data, InternetAddress(multicastAddress), port);
    }
  }

  void close() {
    _socket?.close();
    _messageController.close();
  }
}
