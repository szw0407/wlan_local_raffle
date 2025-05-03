import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:udp/udp.dart';
import '../models/message.dart';

// 网络通信服务
class NetworkService {
  // 默认的组播地址范围(224.0.0.0 ~ 239.255.255.255)，这里我们使用224.x.x.x
  static const String _baseMulticastAddress = '224';
  // 端口范围（避免使用系统保留端口）
  static const int _minPort = 10000;
  static const int _maxPort = 65535;
  
  UDP? _udpSender;
  UDP? _udpReceiver;
  StreamController<Message>? _messageStreamController;
  Stream<Message>? _messageStream;
  
  String? _multicastAddress;
  int? _port;
  bool _isListening = false;

  // 获取消息流
  Stream<Message> get messageStream {
    if (_messageStream == null) {
      _messageStreamController = StreamController<Message>.broadcast();
      _messageStream = _messageStreamController!.stream;
    }
    return _messageStream!;
  }
  
  // 生成一个随机的组播地址
  String _generateMulticastAddress() {
    final random = Random();
    final part2 = random.nextInt(256);
    final part3 = random.nextInt(256);
    final part4 = random.nextInt(256);
    return '$_baseMulticastAddress.$part2.$part3.$part4';
  }
  
  // 生成一个随机端口
  int _generatePort() {
    return _minPort + Random().nextInt(_maxPort - _minPort);
  }
  
  // 初始化网络服务（创建新的房间）
  Future<Map<String, dynamic>> initHost() async {
    // 如果已经在监听，先关闭
    if (_isListening) {
      await close();
    }
    
    // 生成组播地址和端口
    _multicastAddress = _generateMulticastAddress();
    _port = _generatePort();
    
    // 初始化UDP接收器
    await _initializeReceiver(_multicastAddress!, _port!);
    
    return {
      'multicastAddress': _multicastAddress!,
      'port': _port!,
    };
  }
  
  // 初始化网络服务（加入现有房间）
  Future<void> initClient(String multicastAddress, int port) async {
    // 如果已经在监听，先关闭
    if (_isListening) {
      await close();
    }
    
    _multicastAddress = multicastAddress;
    _port = port;
    
    // 初始化UDP接收器
    await _initializeReceiver(_multicastAddress!, _port!);
  }
  
  // 初始化UDP接收器
  Future<void> _initializeReceiver(String multicastAddress, int port) async {
    try {
      // 创建UDP接收器
      _udpReceiver = await UDP.bind(Endpoint.any(port: Port(port)));
      
      // 开始监听消息
      _udpReceiver!.asStream().listen((datagram) {
        if (datagram != null && datagram.data.isNotEmpty) {
          try {
            final String messageData = String.fromCharCodes(datagram.data);
            final message = Message.deserialize(messageData);
            _messageStreamController?.add(message);
          } catch (e) {
            print('解析消息失败: $e');
          }
        }
      });
      
      // 创建UDP发送器（用于发送消息）
      _udpSender = await UDP.bind(Endpoint.any());
      
      _isListening = true;
      print('UDP监听已启动 - 地址: $multicastAddress, 端口: $port');
    } catch (e) {
      print('初始化UDP接收器失败: $e');
      throw e;
    }
  }
  
  // 发送消息
  Future<void> sendMessage(Message message) async {
    if (_multicastAddress == null || _port == null || _udpSender == null) {
      throw Exception('网络服务未初始化');
    }
    
    try {
      final data = message.serialize();
      final dataBytes = Uint8List.fromList(data.codeUnits);
      
      final endpoint = Endpoint.multicast(
        InternetAddress(_multicastAddress!),
        port: Port(_port!),
      );
      
      await _udpSender!.send(dataBytes, endpoint);
    } catch (e) {
      print('发送消息失败: $e');
      throw e;
    }
  }
  
  // 关闭网络服务
  Future<void> close() async {
    _isListening = false;
    
    // 关闭UDP接收器
    if (_udpReceiver != null) {
      _udpReceiver!.close();
      _udpReceiver = null;
    }
    
    // 关闭UDP发送器
    if (_udpSender != null) {
      _udpSender!.close();
      _udpSender = null;
    }
    
    // 关闭消息流
    await _messageStreamController?.close();
    _messageStreamController = null;
    _messageStream = null;
    
    _multicastAddress = null;
    _port = null;
    
    print('网络服务已关闭');
  }
}