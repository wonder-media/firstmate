import json,pathlib,urllib.request,urllib.error,time
work=pathlib.Path('.test-tmp');info=json.loads((work/'live-info.json').read_text());lab=pathlib.Path(info['lab']);ev=pathlib.Path('~/.no-mistakes/evidence/01M8A0X6STT0FN1DFD4X64E35R')
def req(route,headers=None):
 h={'Authorization':'Bearer '+info['secret']} if headers is None else headers
 try:r=urllib.request.urlopen(urllib.request.Request(f'http://localhost:{info["port"]}'+route,headers=h),timeout=15)
 except urllib.error.HTTPError as e:r=e
 with r:
  raw=r.read();return r.status,json.loads(raw) if raw.startswith(b'{') else raw.decode()
def save(name,obj):(ev/name).write_text(json.dumps(obj,indent=2))
fleet=req('/api/fleet')[1];save('fleet-observed.json',fleet)
assert {m['id']:m['state'] for m in fleet['records']['second_mates']}=={'dormant':'dormant','research':'unknown'}
assert fleet['records']['workers'][0]['state']=='stopped'
assert fleet['records']['council']['seats'][0]['use'][0]['model']=='review-model'
for private in ['private@example.com','user@example.com','secret-account','/private/','worktree','absent-socket']:
 assert private not in json.dumps(fleet),private
checks=[]
for route in ['/api/fleet','/api/dashboards']:
 for name,h in [('no auth',{}),('bad auth',{'Authorization':'Bearer invalid'}),('host',{'Authorization':'Bearer '+info['secret'],'Host':'evil.invalid'}),('origin',{'Authorization':'Bearer '+info['secret'],'Origin':'http://evil.invalid'})]:
  status,_=req(route,h);assert status==403;(checks.append({'route':route,'boundary':name,'status':status}))
save('access-boundaries.json',checks)
for _ in range(30):
 dash=req('/api/dashboards')[1]
 if all(l['status']!='checking' for l in dash['links']):break
 time.sleep(.2)
assert [l['status'] for l in dash['links']]==['up','down','unchecked'];save('dashboard-links.json',dash)
calls=(lab/'quota-calls').read_text().splitlines()
for _ in range(10):req('/api/fleet')
assert (lab/'quota-calls').read_text().splitlines()==calls
print('API guards, stopped/unknown/dormant fleet, council mapping, redaction, links and cache passed',flush=True)
dispatch=lab/'config/crew-dispatch.json';data=json.loads(dispatch.read_text());data['rules'][0]['use'][0]['model']='updated-review-model';dispatch.write_text(json.dumps(data))
for _ in range(100):
 current=req('/api/fleet')[1]
 if current['records']['council']['seats'][0]['use'][0]['model']=='updated-review-model':break
 time.sleep(.2)
else:raise AssertionError('records never refreshed')
save('fleet-refreshed.json',current)
(lab/'quota-fail').touch();print('Waiting for real five-minute quota refresh failure',flush=True)
for _ in range(330):
 current=req('/api/fleet')[1]
 if current['quota']['error']:break
 time.sleep(1)
else:raise AssertionError('failed refresh did not appear')
assert current['quota']['error']=='quota_axi_unreadable'
assert current['quota']['providers']==fleet['quota']['providers']
assert current['quota']['fetched_at']==fleet['quota']['fetched_at']
save('quota-last-good.json',current['quota'])
failedcalls=(lab/'quota-calls').read_text().splitlines()
for _ in range(10):req('/api/fleet')
assert (lab/'quota-calls').read_text().splitlines()==failedcalls
print('Real 300-second refresh retained last good quota and disclosed failure; repeated requests did not retry',flush=True)
