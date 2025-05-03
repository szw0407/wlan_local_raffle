import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:isolate';

// InternetAddress _mDnsAddressIPv4 = InternetAddress('224.0.0.251'); // Will be moved into Multicast class
// const int _port = 4545; // Will be moved into Multicast class

typedef MessageCall = void Function(String data, String address);

Future<List<String>> _localAddress() async {
  List<String> address = [];
  final List<NetworkInterface> interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  for (final NetworkInterface netInterface in interfaces) {
    // 遍历网卡
    for (final InternetAddress netAddress in netInterface.addresses) {
      // 遍历网卡的IP地址
      if (netAddress.address.isIPv4) {
        address.add(netAddress.address);
      }
    }
  }
  return address;
}

bool _hasMatch(String? value, String pattern) {
  return (value == null) ? false : RegExp(pattern).hasMatch(value);
}

/// 抄的getx
extension IpString on String {
  bool get isIPv4 =>
      _hasMatch(this, r'^(?:(?:^|\.)(?:2(?:5[0-5]|[0-4]\d)|1?\d?\d)){4}$');
}

extension Boardcast on RawDatagramSocket {
  // Note: This extension uses a global _mDnsAddressIPv4 which will be removed.
  // This part might need further refactoring to work correctly after the change.
  Future<void> boardcast(String msg, int port) async {
    List<int> dataList = utf8.encode(msg);
    // TODO: Replace _mDnsAddressIPv4 with a passed parameter or class member access
    // send(dataList, _mDnsAddressIPv4, port);
    await Future.delayed(const Duration(milliseconds: 10));
    final List<String> address = await _localAddress();
    for (final String addr in address) {
      final tmp = addr.split('.');
      tmp.removeLast();
      final String addrPrfix = tmp.join('.');
      final InternetAddress address = InternetAddress(
        '$addrPrfix.255',
      );
      send(
        dataList,
        address,
        port,
      );
    }
  }
}

/// 通过组播+广播的方式，让设备能够相互在局域网被发现
class Multicast {
  // Moved properties from global scope
  final InternetAddress mDnsAddressIPv4;
  final int port;

  final List<MessageCall> _callback = [];
  bool _isStartSend = false;
  bool _isStartReceive = false;
  final ReceivePort receivePort = ReceivePort();
  Isolate? isolate;

  // Constructor accepting the address and port, with defaults
  Multicast({InternetAddress? mDnsAddressIPv4, int? port})
      : this.mDnsAddressIPv4 =
            mDnsAddressIPv4 ?? InternetAddress('224.0.0.251'),
        this.port = port ?? 4545;

  /// 停止对 udp 发送消息
  void stopSendBoardcast() {
    if (!_isStartSend) {
      return;
    }
    _isStartSend = false;
    isolate?.kill();
  }

  /// 接收udp广播消息
  Future<void> _receiveBoardcast() async {
    // Use the instance member `port`
    RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      this.port, // Use instance member
      reuseAddress: true,
      // reusePort: true, // reusePort is not supported on all platforms
      ttl: 255,
    ).then((RawDatagramSocket socket) {
      // 接收组播消息
      // Use the instance member `mDnsAddressIPv4`
      socket.joinMulticast(this.mDnsAddressIPv4); // Use instance member
      // 开启广播支持
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;
      socket.listen((RawSocketEvent rawSocketEvent) async {
        final Datagram? datagram = socket.receive();
        if (datagram == null) {
          return;
        }

        String message = utf8.decode(datagram.data);
        _notifiAll(message, datagram.address.address);
      });
    });
  }

  void _notifiAll(String data, String address) {
    for (MessageCall call in _callback) {
      call(data, address);
    }
  }

  Future<void> startSendBoardcast(
    // used to send messages
    List<String> messages, {
    Duration duration = const Duration(seconds: 1),
  }) async {
    if (_isStartSend) {
      return;
    }
    _isStartSend = true;
    // Pass the instance members `port` and `mDnsAddressIPv4` to the isolate
    isolate = await Isolate.spawn(
      multicastIsoate,
      _IsolateArgs(
        receivePort.sendPort,
        this.port, // Pass instance member
        this.mDnsAddressIPv4, // Pass instance member
        messages,
        duration,
      ),
    );
  }

  void addListener(MessageCall listener) {
    if (!_isStartReceive) {
      _receiveBoardcast();
      _isStartReceive = true;
    }
    _callback.add(listener);
  }

  void removeListener(MessageCall listener) {
    if (_callback.contains(listener)) {
      _callback.remove(listener);
    }
  }
}

// Isolate entry point needs the multicast address now
void multicastIsoate(_IsolateArgs args) {
  runZonedGuarded(() {
    startSendBoardcast(
      args.messages,
      args.port,
      args.mDnsAddress, // Pass address to the sending function
      args.duration,
      args.sendPort,
    );
  }, (Object error, StackTrace stackTrace) {
    print('multicastIsoate error: $error');
  });
}

// Top-level sending function now needs the multicast address
Future<void> startSendBoardcast(
  List<String> messages,
  int port,
  InternetAddress mDnsAddress, // Added parameter
  Duration duration,
  SendPort sendPort,
) async {
  RawDatagramSocket _socket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    0,
    ttl: 255,
    reuseAddress: true,
  );
  _socket.broadcastEnabled = true;
  _socket.readEventsEnabled = true;
  final Timer timer = Timer.periodic(duration, (timer) async {
    for (String data in messages) {
      // Call the modified boardcast extension method
      // TODO: The extension method needs modification or this needs to be refactored
      // For now, sending directly to multicast address and broadcast
      List<int> dataList = utf8.encode(data);
      _socket.send(dataList, mDnsAddress, port); // Send to multicast group
      // Send to broadcast addresses (similar logic as original extension)
      final List<String> localAddresses = await _localAddress();
      for (final String addr in localAddresses) {
        final tmp = addr.split('.');
        tmp.removeLast();
        final String addrPrfix = tmp.join('.');
        final InternetAddress broadcastAddress =
            InternetAddress('$addrPrfix.255');
        try {
          _socket.send(dataList, broadcastAddress, port);
        } catch (e) {
          // Ignore errors like NetworkUnreachable which can happen
          print("Error sending broadcast to $broadcastAddress: $e");
        }
      }

      // Original call using extension (would need modification)
      // _socket.boardcast(data, port);
      await Future.delayed(Duration(milliseconds: 500));
    }
  });
  // Keep the isolate alive
  // Note: Consider adding a mechanism to stop the timer and close the socket
  // when the isolate is killed or receives a specific message.
}

// Arguments for the isolate, now includes the multicast address
class _IsolateArgs<T> {
  _IsolateArgs(
    this.sendPort,
    this.port,
    this.mDnsAddress, // Added field
    this.messages,
    this.duration,
  );

  final SendPort sendPort;
  final int port;
  final InternetAddress mDnsAddress; // Added field
  final List<String> messages;
  final Duration duration;
}
