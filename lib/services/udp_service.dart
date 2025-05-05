import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// UDP 广播服务，支持多播地址的发送与监听
class UdpService {
  RawDatagramSocket? _socket;
  StreamController<Datagram> _controller = StreamController.broadcast();
  InternetAddress? _multicastAddress;
  int? _port;

  /// 初始化并监听指定端口和多播地址
  Future<void> bind({
    required String multicastAddress,
    required int port,
  }) async {
    _multicastAddress = InternetAddress(multicastAddress);
    _port = port;
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true, reusePort: true);
    _socket!.joinMulticast(_multicastAddress!);
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          _controller.add(datagram);
        }
      }
    });
  }

  /// 发送广播消息
  void send(Uint8List data) {
    if (_socket != null && _multicastAddress != null && _port != null) {
      _socket!.send(data, _multicastAddress!, _port!);
    }
  }

  /// 监听收到的消息
  Stream<Datagram> get onData => _controller.stream;

  /// 关闭 socket
  void close() {
    _socket?.close();
    _controller.close();
  }
}
