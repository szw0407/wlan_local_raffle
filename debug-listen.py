import socket
import struct

MULTICAST_IP = "224.1.0.115"
PORT = 11362

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('', PORT))

mreq = struct.pack("4sl", socket.inet_aton(MULTICAST_IP), socket.INADDR_ANY)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

print(f"Listening on {MULTICAST_IP}:{PORT} ... (Ctrl+C to stop)")
while True:
    data, addr = sock.recvfrom(4096)
    print(f"[{addr[0]}:{addr[1]}] {data.decode('utf-8', errors='replace')}")
