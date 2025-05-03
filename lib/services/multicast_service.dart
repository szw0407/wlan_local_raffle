import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

// Default Multicast Address and Port
final InternetAddress _defaultMdnsAddressIPv4 = InternetAddress('224.1.0.1');
const int _defaultPort = 10012;

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

/// 通过组播的方式，让设备能够相互在局域网被发现
class Multicast {
  final InternetAddress mDnsAddressIPv4;
  final int port;

  final List<MessageCall> _callback = [];
  RawDatagramSocket? _socket;
  bool _isListening = false;
  Isolate? _broadcastIsolate;
  bool _isBroadcasting = false;
  final ReceivePort _errorReceivePort = ReceivePort(); // For isolate errors

  // Constructor with defaults
  Multicast({InternetAddress? mDnsAddressIPv4, int? port})
      : mDnsAddressIPv4 = mDnsAddressIPv4 ?? _defaultMdnsAddressIPv4,
        port = port ?? _defaultPort {
     _errorReceivePort.listen((message) {
        print("Error from broadcast isolate: $message");
        // Optionally handle isolate errors, e.g., restart it
        _isBroadcasting = false;
     });
  }

  /// Start listening for multicast messages
  Future<void> startListening() async {
    if (_isListening) {
      return;
    }
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        // a random port for receiving
        0,
        reuseAddress: Platform.isWindows ? false : true, // Reuse address might be needed on non-Windows
        reusePort: Platform.isWindows ? false : true, // Reuse port might be needed on non-Windows
        ttl: 255,
      );
      _socket!.joinMulticast(mDnsAddressIPv4);
      _socket!.broadcastEnabled = false; // Not needed for multicast receive
      _socket!.readEventsEnabled = true;
      _socket!.listen((RawSocketEvent rawSocketEvent) {
        final Datagram? datagram = _socket!.receive();
        if (datagram == null) {
          return;
        }
        // Avoid processing self-sent messages if necessary (check address)
        // Example: if (datagram.address.address == myLocalIp) return;
        String message = utf8.decode(datagram.data);
        _notifyAll(message, datagram.address.address);
      });
      _isListening = true;
      print('Multicast listening started on ${mDnsAddressIPv4.address}:$port');
    } catch (e) {
      print("Error starting multicast listener: $e");
      _isListening = false;
      // Rethrow or handle error appropriately
      rethrow;
    }
  }

  /// Stop listening
  void stopListening() {
    if (!_isListening) {
      return;
    }
    _socket?.leaveMulticast(mDnsAddressIPv4);
    _socket?.close();
    _socket = null;
    _isListening = false;
    _callback.clear(); // Clear listeners when stopping
    print('Multicast listening stopped.');
  }

  void _notifyAll(String data, String address) {
    // Create a copy of the list to avoid concurrent modification issues
    final List<MessageCall> listeners = List.from(_callback);
    for (MessageCall call in listeners) {
      try {
         call(data, address);
      } catch (e) {
         print("Error in message callback: $e");
      }
    }
  }

  /// Add a listener for incoming messages
  void addListener(MessageCall listener) {
    if (!_isListening) {
       print("Warning: Listener added but multicast is not listening. Call startListening() first.");
       // Optionally start listening automatically:
       // await startListening();
       // if (!_isListening) return; // If starting failed
    }
    if (!_callback.contains(listener)) {
       _callback.add(listener);
    }
  }

  /// Remove a listener
  void removeListener(MessageCall listener) {
    _callback.remove(listener);
  }

  /// Start periodically sending messages via multicast in a separate isolate
  Future<void> startPeriodicBroadcast(
    List<String> messages, {
    Duration duration = const Duration(seconds: 1),
  }) async {
    if (_isBroadcasting) {
      print("Periodic broadcast already running.");
      return;
    }
    _isBroadcasting = true;
    try {
       _broadcastIsolate = await Isolate.spawn(
         _multicastBroadcastIsolate,
         _IsolateArgs(
           _errorReceivePort.sendPort, // Pass error port
           port,
           mDnsAddressIPv4,
           messages,
           duration,
         ),
         onError: _errorReceivePort.sendPort,
         onExit: _errorReceivePort.sendPort, // Also notify on exit
       );
       print('Periodic broadcast isolate started.');
    } catch (e) {
       print("Error starting broadcast isolate: $e");
       _isBroadcasting = false;
       rethrow;
    }
  }

  /// Stop the periodic broadcast
  void stopPeriodicBroadcast() {
    if (!_isBroadcasting) {
      return;
    }
    _broadcastIsolate?.kill(priority: Isolate.immediate);
    _broadcastIsolate = null;
    _isBroadcasting = false;
    print('Periodic broadcast stopped.');
  }

  /// Send a single message immediately via multicast
  Future<void> sendOnce(String message) async {
    List<int> dataList = utf8.encode(message);
    RawDatagramSocket? tempSocket;
    try {
      // Use a temporary socket for sending one-off messages
      tempSocket = await RawDatagramSocket.bind(
         InternetAddress.anyIPv4,
         0, // Bind to any available port for sending
         ttl: 255, // Set TTL for multicast
         // reuseAddress: true, // Generally not needed for sending socket
      );
      // No need to join multicast group for sending
      tempSocket.send(dataList, mDnsAddressIPv4, port);
      print('Sent message to ${mDnsAddressIPv4.address}:$port');
      // Add a small delay to allow the packet to be sent before closing
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      print("Error sending multicast message: $e");
      // Handle error appropriately
    } finally {
       tempSocket?.close();
    }
  }

  /// Clean up resources (call when the object is no longer needed)
  void dispose() {
     stopListening();
     stopPeriodicBroadcast();
     _errorReceivePort.close();
  }
}

// Isolate entry point for periodic broadcasting
void _multicastBroadcastIsolate(_IsolateArgs args) {
  RawDatagramSocket? socket;
  Timer? timer;

  Future<void> initializeAndRun() async {
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // Bind to any available port for sending
        ttl: 255,
        // reuseAddress: true,
      );
      // No need to join multicast group for sending

      timer = Timer.periodic(args.duration, (timer) {
        if (socket == null) return; // Socket might have been closed
        for (String data in args.messages) {
          try {
             List<int> dataList = utf8.encode(data);
             socket!.send(dataList, args.mDnsAddress, args.port);
          } catch (e) {
             print("Error sending in isolate: $e");
             // Optionally send error back via SendPort
             // args.errorPort.send("Send error: $e");
             // Consider stopping the timer or isolate on repeated errors
          }
        }
      });
    } catch (e, stacktrace) {
       print("Error in broadcast isolate setup: $e\n$stacktrace");
       args.errorPort.send("Isolate setup error: $e");
       // Ensure resources are cleaned up if setup fails
       timer?.cancel();
       socket?.close();
       Isolate.current.kill(); // Terminate the isolate on setup failure
    }
  }

  // Handle isolate exit message if needed (though kill is more direct)
  // var exitPort = ReceivePort();
  // Isolate.current.addOnExitListener(exitPort.sendPort);
  // exitPort.listen((_) {
  //   timer?.cancel();
  //   socket?.close();
  //   exitPort.close();
  // });

  initializeAndRun();
}

// Arguments for the isolate
class _IsolateArgs {
  _IsolateArgs(
    this.errorPort,
    this.port,
    this.mDnsAddress,
    this.messages,
    this.duration,
  );

  final SendPort errorPort; // For reporting errors back
  final int port;
  final InternetAddress mDnsAddress;
  final List<String> messages;
  final Duration duration;
}
