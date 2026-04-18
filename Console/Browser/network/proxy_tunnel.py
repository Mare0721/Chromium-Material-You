import asyncio
import struct
import socket

class AsyncProxyTunnel:
    def __init__(self, proxy_config):
        self.proxy_config = proxy_config
        self.server = None
        self.local_port = 0
        self.active_clients = set()
        self.total_connections = 0

    async def _handshake_socks5(self, reader, writer):
        """Perform SOCKS5 handshake with upstream proxy"""
        try:
            # 1. Connect
            remote_reader, remote_writer = await asyncio.open_connection(
                self.proxy_config['ip'], self.proxy_config['port']
            )

            # 2. Auth negotiation
            # Methods: NoAuth(0x00), UserPass(0x02)
            auth_methods = [0x00]
            if self.proxy_config.get('user'):
                auth_methods.append(0x02)
            
            remote_writer.write(bytes([0x05, len(auth_methods)] + auth_methods))
            await remote_writer.drain()

            ver, method = struct.unpack('BB', await remote_reader.read(2))

            # 3. Auth sub-negotiation
            if method == 0x02: # User/Pass
                u = self.proxy_config['user'].encode()
                p = self.proxy_config['pass'].encode()
                remote_writer.write(b"\x01" + bytes([len(u)]) + u + bytes([len(p)]) + p)
                await remote_writer.drain()
                
                resp = await remote_reader.read(2)
                if resp[1] != 0:
                    raise Exception("Auth failed")

            return remote_reader, remote_writer
        except Exception as e:
            # print(f"Upstream connect failed: {e}")
            return None, None

    async def _pipe(self, reader, writer):
        try:
            while True:
                data = await reader.read(4096)
                if not data: break
                writer.write(data)
                await writer.drain()
        except: pass
        finally:
            writer.close()

    async def handle_client(self, client_reader, client_writer):
        remote_writer = None
        self.total_connections += 1
        self.active_clients.add(client_writer)
        try:
            # 1. Basic HTTP CONNECT handling (for Chrome)
            # Chrome sends: CONNECT target:port HTTP/1.1
            headers = b""
            while b"\r\n\r\n" not in headers:
                chunk = await client_reader.read(4096)
                if not chunk: return
                headers += chunk
            
            lines = headers.split(b"\r\n")
            request_line = lines[0].decode()
            method, target, _ = request_line.split()

            if method != 'CONNECT':
                # Only support CONNECT for HTTPS tunneling (which Chrome uses for everything over proxy)
                client_writer.close()
                return

            host, port = target.split(":")
            
            # 2. Connect to Upstream SOCKS5
            remote_reader, remote_writer = await self._handshake_socks5(client_reader, client_writer)
            if not remote_writer:
                client_writer.close()
                return

            # 3. Request Upstream Connection
            # CMD=0x01 (Connect), ATYP=0x03 (Domain)
            host_bytes = host.encode()
            req = b"\x05\x01\x00\x03" + bytes([len(host_bytes)]) + host_bytes + struct.pack(">H", int(port))
            remote_writer.write(req)
            await remote_writer.drain()

            # 4. Check Upstream Response
            # VER | REP | RSV | ATYP | ADDR | PORT
            resp = await remote_reader.read(4)
            if resp[1] != 0:
                client_writer.close()
                remote_writer.close()
                return
            
            # Skip addr/port
            atyp = resp[3]
            if atyp == 1: await remote_reader.read(6) # IPv4 + Port
            elif atyp == 3: await remote_reader.read(1 + (await remote_reader.read(1))[0] + 2) # Domain + Port
            elif atyp == 4: await remote_reader.read(18) # IPv6 + Port

            # 5. Send 200 OK to Chrome
            client_writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await client_writer.drain()

            # 6. Start full duplex piping
            task1 = asyncio.create_task(self._pipe(client_reader, remote_writer))
            task2 = asyncio.create_task(self._pipe(remote_reader, client_writer))
            await asyncio.gather(task1, task2)

        except Exception as e:
            # print(f"Tunnel Error: {e}")
            pass
        finally:
            self.active_clients.discard(client_writer)
            try: client_writer.close()
            except: pass
            if remote_writer:
                try: remote_writer.close()
                except: pass

    async def start(self):
        self.server = await asyncio.start_server(
            self.handle_client, '127.0.0.1', 0
        )
        self.local_port = self.server.sockets[0].getsockname()[1]
        return self.local_port

    async def serve_forever(self):
        async with self.server:
            await self.server.serve_forever()

    def stop(self):
        if self.server:
            self.server.close()
        for writer in list(self.active_clients):
            try:
                writer.close()
            except Exception:
                pass
        self.active_clients.clear()

    def get_stats(self):
        return {
            "local_port": self.local_port,
            "total_connections": self.total_connections,
            "active_clients": len(self.active_clients),
        }
