import socket
import sys

with socket.socket(socket.AF_INET6, socket.SOCK_DGRAM) as server:
    server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    server.bind(("::", int(sys.argv[1])))
    while True:
        payload, client = server.recvfrom(4096)
        server.sendto(payload, client)
