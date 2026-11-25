import os,pathlib,json,socket,subprocess,time,urllib.request,signal
root=pathlib.Path.cwd(); work=root/'.test-tmp'; lab=work/'live-home'; evidence=pathlib.Path('~/.no-mistakes/evidence/01M8A0X6STT0FN1DFD4X64E35R')
subprocess.run(['bin/fm-lab-home.sh','create',str(lab)],check=True)
for d in ['user','tools','tmp']: (lab/d).mkdir()
(lab/'data/backlog.md').write_text('# Backlog\n\n## In flight\n\n## Queued\n\n## Done\n')
(lab/'config/backlog-backend').write_text('manual\n')
(lab/'data/secondmates.md').write_text('- research - Owns synthetic research scope. (home: /private/example)\n- dormant - Owns synthetic dormant scope.\n')
(lab/'state/dormant.meta').write_text('kind=secondmate\nharness=codex\nmodel=example-model\neffort=high\nbackend=tmux\nwindow=fm-lab-nonexistent\n')
(lab/'state/dormant.dormant').touch()
(lab/'state/parked-worker.meta').write_text('kind=ship\nharness=claude\nmodel=example-worker\neffort=high\nbackend=tmux\nwindow=fm-lab-nonexistent\nproject=/private/clones/hub\nworktree=/private/hidden\n')
(lab/'state/parked-worker.status').write_text('paused: secret user@example.com /private/hidden\n')
(lab/'config/crew-dispatch.json').write_text(json.dumps({'rules':[{'when':'design review','why':'Synthetic review; user@example.com /private/secret/path','use':[{'harness':'codex','model':'review-model','effort':'high','account':'secret-account'},{'harness':'claude','model':'alternate-model'}]}],'default':{'harness':'codex','model':'default-model'}}))
(lab/'config/council.json').write_text(json.dumps({'seats':{'architect':'design review','ux':'missing'},'default_roster':['architect'],'caps':{'max_rounds':3}}))
quota={'providers':[{'provider':'Synthetic A','plan':'local fixture','state':{'status':'fresh'},'accountKeys':['private@example.com'],'windows':[{'id':'session','percentRemaining':88,'resetsAt':'2099-01-01T00:00:00Z'},{'id':'week','percentRemaining':12,'resetsAt':'2099-01-02T00:00:00Z'}],'quotaSemantics':{'effectiveAvailability':[{'scope':'all_models','status':'known','effectivePercentRemaining':12,'runway':{'status':'projected_exhaustion'},'selection':{'spendPriority':3.5}}]}},{'provider':'Synthetic B','state':{'status':'auth_required','error':'credential_unavailable'},'windows':[]}]}
(lab/'quota.json').write_text(json.dumps(quota))
q=lab/'tools/quota-axi';q.write_text('#!'+os.sys.executable+'\nimport pathlib,time,sys\np=pathlib.Path('+repr(str(lab))+')\nwith (p/"quota-calls").open("a") as f:f.write(str(time.time())+"\\n")\nif (p/"quota-fail").exists():print("invalid quota output");sys.exit(1)\nprint((p/"quota.json").read_text())\n');q.chmod(0o755)
def port():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
p=port(); closed=port();secret='local-synthetic-bridge-secret-2026'
config={'homes':[{'id':'Lab','path':str(lab)}],'lan_host':'localhost','port':p,'secret':secret,'links':[{'title':'Bridge lab','url':f'http://localhost:{p}/','description':'Local running Bridge','group':'Local'},{'title':'Stopped dashboard','url':f'http://localhost:{closed}/','group':'Local'},{'title':'External example','url':'https://example.invalid/dashboard','group':'Hosted'}]}
(lab/'config/board.json').write_text(json.dumps(config))
env={k:v for k,v in os.environ.items() if not k.startswith(('FM_','HERDR_','TASKS_AXI_')) and k not in ('TMUX','TMUX_PANE')}
env.update(HOME=str(lab/'user'),FM_HOME=str(lab),TMPDIR=str(lab/'tmp'),TMUX=str(lab/'absent-socket')+',0,0',PATH=str(lab/'tools')+os.pathsep+os.environ['PATH'],FM_PROCEVENT_CLAIM_ROOT=str(lab/'claims'))
log=(evidence/'live-daemon.log').open('w');proc=subprocess.Popen(['bin/fm-board.sh','serve'],env=env,stdout=log,stderr=log)
try:
 for _ in range(100):
  if proc.poll() is not None:raise RuntimeError('daemon exited '+str(proc.returncode))
  try:
   req=urllib.request.Request(f'http://localhost:{p}/api/fleet',headers={'Authorization':'Bearer '+secret})
   with urllib.request.urlopen(req) as r:data=json.load(r)
   if data['quota']['fetched_at']:break
  except OSError:pass
  time.sleep(.2)
 else:raise RuntimeError('readiness timeout')
 (work/'live-info.json').write_text(json.dumps({'url':f'http://localhost:{p}/?k={secret}','port':p,'secret':secret,'lab':str(lab)}))
 (evidence/'fleet-initial.json').write_text(json.dumps(data,indent=2))
 print('READY '+str(p),flush=True)
 deadline=time.monotonic()+1000
 while not (work/'live-done').exists() and time.monotonic()<deadline:
  assert proc.poll() is None
  time.sleep(.5)
finally:
 proc.terminate();rc=proc.wait(timeout=120);print('daemon exit',rc,flush=True)
 cleanup=subprocess.run(['bin/fm-procevent.sh','sweep-home'],env=env,capture_output=True,text=True,timeout=45)
 print('cleanup',cleanup.returncode,cleanup.stdout,cleanup.stderr,flush=True)
 log.close()
 assert rc==0 and cleanup.returncode==0
