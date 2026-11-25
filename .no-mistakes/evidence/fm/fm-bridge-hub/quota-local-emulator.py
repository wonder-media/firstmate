import socketserver,ssl,json,pathlib,time
lab=pathlib.Path(__file__).resolve().parent
ev=pathlib.Path('~/.no-mistakes/evidence/01M8A0X6STT0FN1DFD4X64E35R')
class Handler(socketserver.BaseRequestHandler):
 def handle(self):
  self.request.settimeout(8)
  data=b''
  while b'\r\n\r\n' not in data:data+=self.request.recv(4096)
  assert data.startswith(b'CONNECT api.z.ai:443 '),data[:100]
  self.request.sendall(b'HTTP/1.1 200 Connection Established\r\n\r\n')
  ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(lab/'proxy.crt',lab/'proxy.key')
  with ctx.wrap_socket(self.request,server_side=True) as s:
   data=b''
   while b'\r\n\r\n' not in data:data+=s.recv(4096)
   assert data.startswith(b'GET /api/monitor/usage/quota/limit '),data[:100]
   response={'data':{'level':'lab-plan','limits':[{'type':'TOKENS_LIMIT','unit':3,'number':5,'percentage':25,'nextResetTime':int((time.time()+3600)*1000)},{'type':'TOKENS_LIMIT','unit':6,'number':1,'percentage':88,'nextResetTime':int((time.time()+86400)*1000)}]}}
   body=json.dumps(response).encode()
   with (ev/'quota-local-http.jsonl').open('a') as f:f.write(json.dumps({'request':data.split(b'\r\n')[0].decode(),'response':response,'scope':'localhost TLS emulator; synthetic token only'})+'\n')
   s.sendall(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body)
class Server(socketserver.ThreadingTCPServer):allow_reuse_address=True;daemon_threads=True
with Server(('127.0.0.1',0),Handler) as server:
 (lab/'proxy-port').write_text(str(server.server_address[1]));server.timeout=.2
 while not (lab/'proxy-stop').exists():server.handle_request()
