import socket
import struct
import sys
import random
import string
import json

def decode_room_code(code):
    code_num = int(code, 36)
    raw = code_num >> 8
    port_high = code_num & 0xFF
    b = (raw >> 24) & 0xFF
    c = (raw >> 16) & 0xFF
    d = (raw >> 8) & 0xFF
    port_low = raw & 0xFF
    port = (port_high << 8) | port_low
    address = f'224.{b}.{c}.{d}'
    return address, port

def random_username():
    return 'PY_' + ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))

def random_id():
    # 生成一个简单的UUID格式
    return ''.join(random.choices('abcdef' + string.digits, k=8)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=4)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=4)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=4)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=12))

def main():
    # code = input("请输入房间号: ").strip().upper()
    # address, port = decode_room_code(code)
    address = '224.0.0.1'
    port = 10012
    print(f"解码结果: 多播地址={address}, 端口={port}")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(('', port))
    except Exception as e:
        print(f"端口绑定失败: {e}")
        sys.exit(1)

    mreq = struct.pack('4sl', socket.inet_aton(address), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

    # 构造joinRequest消息
    user = {
        'id': random_id(),
        'name': random_username(),
        'isHost': False
    }
    msg = {
        'type': 'joinRequest',
        'data': {
            'user': user
        }
    }
    data = json.dumps(msg).encode('utf-8')
    sock.sendto(data, (address, port))
    print(f"已发送joinRequest: {user}")

    print("监听房间消息（Ctrl+C退出）...")
    while True:
        data, addr = sock.recvfrom(4096)
        try:
            print(f"\n收到消息来自{addr}:")
            print(data.decode('utf-8'))
        except Exception as e:
            print(f"解码失败: {e}")

if __name__ == '__main__':
    main()