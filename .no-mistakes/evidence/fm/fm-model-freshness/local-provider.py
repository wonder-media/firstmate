import http.server,json,pathlib
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_POST(self):
  data=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  with open('.h/requests.jsonl','a') as f:f.write(json.dumps({'path':self.path,'model':data.get('model')})+'\n')
  msg={'id':'msg_lab','type':'message','role':'assistant','status':'completed','phase':'final_answer','content':[{'type':'output_text','text':'Local validation response. No tools executed.','annotations':[]}]}
  events=[{'type':'response.created','response':{'id':'resp_lab','status':'in_progress','output':[]}}, {'type':'response.output_item.added','output_index':0,'item':dict(msg,status='in_progress',content=[])},{'type':'response.output_item.done','output_index':0,'item':msg},{'type':'response.completed','response':{'id':'resp_lab','status':'completed','output':[msg],'usage':{'input_tokens':1,'output_tokens':1,'total_tokens':2}}}]
  body=''.join('event: '+e['type']+'\ndata: '+json.dumps(e)+'\n\n' for e in events).encode()
  self.send_response(200); self.send_header('Content-Type','text/event-stream');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
s=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
pathlib.Path('.h/codex/config.toml').write_text(f'''model_provider="fixture"
[model_providers.fixture]
name="Local validation"
base_url="http://127.0.0.1:{s.server_port}/v1"
wire_api="responses"
requires_openai_auth=false
[features]
shell_snapshot=false
[analytics]
enabled=false
''')
print('Local provider listening on',s.server_port,flush=True)
try:s.serve_forever()
finally:s.server_close()
