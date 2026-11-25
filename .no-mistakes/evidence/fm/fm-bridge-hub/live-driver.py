import os,pathlib,json,socket,subprocess,time,signal,urllib.request,urllib.error
root=pathlib.Path.cwd(); lab=root/'.test-bridge-live'; home=lab/'home'; ev=pathlib.Path('~/.no-mistakes/evidence/01M8A0X6STT0FN1DFD4X64E35R')
for d in ('config','state','data','tmux','projects'): (home/d).mkdir(parents=True,exist_ok=True)
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
p=port(); closed=port();secret='disposable-bridge-validation-secret'
cfg={'homes':[{'id':'Lab','path':str(home)}],'lan_host':'127.0.0.1','port':p,'secret':secret,'links':[{'title':'Local Bridge','url':f'http://127.0.0.1:{p}/','group':'Local'},{'title':'Stopped dashboard','url':f'http://127.0.0.1:{closed}/','group':'Local'},{'title':'External directory','url':'https://example.invalid/dashboard','group':'External'}]}
(home/'config/board.json').write_text(json.dumps(cfg));(home/'data/backlog.md').write_text('# Backlog\n')
(home/'data/secondmates.md').write_text('- design - Owns design reviews.\n- dormant - Sleeping scope.\n')
(home/'config/crew-dispatch.json').write_text(json.dumps({'rules':[{'when':'design review','why':'Review designs; contact lab@example.com in ~/private','use':[{'harness':'codex','model':'design-model','effort':'high','account':'private-account'}]},{'when':'council architect seat','use':{'harness':'claude','model':'wrong-model'}}],'default':{'harness':'codex','model':'default-model'}}))
(home/'config/council.json').write_text(json.dumps({'seats':{'architect':'design review','critic':'missing rule'},'default_roster':['architect']}))
for name,kind,extra in [('design','secondmate',''),('dormant','secondmate',''),('parked-worker','ship',''),('unknown-worker','ship','backend=unsupported\n')]:
 (home/f'state/{name}.meta').write_text(f'kind={kind}\nharness=codex\nmodel=design-model\neffort=high\nbackend=tmux\nwindow=fm-lab-nonexistent:0\nproject={home}/projects/example\n'+extra)
(home/'state/dormant.dormant').touch()
env={k:v for k,v in os.environ.items() if not k.startswith(('FM_','TASKS_AXI','HERDR','XDG_'))}
env.update(HOME=str(home),FM_HOME=str(home),PATH=str(lab/'tools')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',TMUX_TMPDIR=str(home/'tmux'),TMUX=str(home/'tmux/fm-lab')+',1,0',PYTHONDONTWRITEBYTECODE='1')
log=(ev/'live-daemon.log').open('w'); proc=subprocess.Popen(['/opt/homebrew/bin/python3',str(root/'bin/fm-board.py'),'serve'],env=env,stdout=log,stderr=log,start_new_session=True)
(lab/'connection.json').write_text(json.dumps({'url':f'http://127.0.0.1:{p}/?k={secret}','pid':proc.pid}))
def req(path,auth=True,headers=None):
 h={'Authorization':'Bearer '+secret} if auth else {};h.update(headers or {})
 try:
  with urllib.request.urlopen(urllib.request.Request(f'http://127.0.0.1:{p}'+path,headers=h),timeout=5) as r:return r.status,r.read().decode()
 except urllib.error.HTTPError as e:return e.code,e.read().decode()
try:
 for _ in range(100):
  try:
   if req('/api/fleet')[0]==200:break
  except OSError:pass
  time.sleep(.2)
 time.sleep(6)
 fleet=json.loads(req('/api/fleet')[1]);(ev/'live-fleet.json').write_text(json.dumps(fleet,indent=2))
 checks=[]
 for path in ('/api/fleet','/api/dashboards'):
  for label,auth,headers in [('missing token',False,{}),('wrong token',True,{'Authorization':'Bearer wrong'}),('wrong origin',True,{'Origin':'http://evil.invalid'}),('wrong host',True,{'Host':'evil.invalid'})]:
   status,_=req(path,auth,headers);assert status==403,(path,label,status);checks.append(f'{path}: {label} -> {status}')
 req('/api/dashboards');time.sleep(3);dash=json.loads(req('/api/dashboards')[1]);(ev/'live-dashboards.json').write_text(json.dumps(dash,indent=2))
 assert [l['status'] for l in dash['links']]==['up','down','unchecked'],dash
 r=fleet['records'];assert next(s for s in r['council']['seats'] if s['seat']=='architect')['use'][0]['model']=='design-model'
 assert next(s for s in r['council']['seats'] if s['seat']=='critic')['use']==[]
 assert next(m for m in r['second_mates'] if m['id']=='dormant')['state']=='dormant'
 assert all(w['state']!='live' for w in r['workers']),r
 assert 'private-account' not in json.dumps(fleet) and 'lab@example.com' not in json.dumps(fleet) and '~' not in json.dumps(fleet)
 assert fleet['quota']['providers'][0]['windows'][0]['percent_remaining']==75,fleet['quota'];assert fleet['quota']['providers'][0]['windows'][1]['percent_remaining']==12;assert any(x['level']=='critical' for x in fleet['quota']['attention'])
 checks.extend(['Council architect resolves design review, ignoring decoy seat-name rule.','Dormant mate stays dormant; absent/unknown endpoints are not counted live.','Private account, e-mail and path are absent from fleet response.','Real quota CLI through localhost TLS emulator: 75% session, 12% weekly remaining and critical warning.','Local links report up/down; external URL stays unchecked.'])
 (ev/'live-checks.txt').write_text('\n'.join(checks)+'\n');print(json.dumps({'ready':True,'url':f'http://127.0.0.1:{p}/?k={secret}','fleet':fleet}),flush=True)
 deadline=time.time()+900
 while not (lab/'stop').exists() and time.time()<deadline:time.sleep(.2)
finally:
 os.killpg(proc.pid,signal.SIGTERM)
 try:proc.wait(timeout=10)
 except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
 log.close();print('daemon stopped, return code '+str(proc.returncode),flush=True)
