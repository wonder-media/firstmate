#!/usr/bin/env bash
# Executable-interface regression for the dashboard daemon, SQLite queue,
# incremental ingest, and the real process-event capture runner. Routing fixtures
# pin argv boundaries without starting a harness or contacting a live home.
# Set FM_BOARD_BROWSER_TEST=1 to add rendered Chrome assertions; without it the
# always-on API, SSE, answer lifecycle, and authoritative answer checks still run.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-board)
export FM_BOARD_TEST_ROOT="$TMP_ROOT" FM_BOARD_TEST_CODE="$ROOT"
PYTHON="${FM_BOARD_PYTHON:-python3}"
"$PYTHON" - <<'PY'
import contextlib,csv,io,json,os,pathlib,re,shutil,signal,socket,sqlite3,subprocess,sys,time,urllib.request,urllib.error
root=pathlib.Path(os.environ['FM_BOARD_TEST_ROOT']).resolve()
assert (root/'.fm-test-fixture').is_file(), 'fixture root is not newly created by fm_test_tmproot'
code=pathlib.Path(os.environ['FM_BOARD_TEST_CODE']).resolve()
fixture=root/'code'; (fixture/'bin').mkdir(parents=True)
for path in (code/'bin').iterdir():
    if path.name not in ('board','fm-board.py','fm-board.sh','fm-procevent-board-answers.sh'):
        (fixture/'bin'/path.name).symlink_to(path,target_is_directory=path.is_dir())
for name in ('fm-board.py','fm-board.sh','fm-procevent-board-answers.sh'):
    shutil.copy2(code/'bin'/name,fixture/'bin'/name)
shutil.copytree(code/'bin/board',fixture/'bin/board',ignore=shutil.ignore_patterns('__pycache__'))
shutil.move(fixture/'bin/board/board-answers-handle.sh',fixture/'bin/board/board-answers-handle-real.sh')
(fixture/'bin/board/board-answers-handle.sh').write_text('#!/bin/bash\nprintf \'%s\\n\' "$*" >> "$FM_BOARD_TEST_ROOT/handler-runs.log"\nexec "$(dirname "$0")/board-answers-handle-real.sh" "$@"\n')
(fixture/'bin/board/board-answers-handle.sh').chmod(0o755)
def handler_runs():
    p=root/'handler-runs.log'
    return len(p.read_text().splitlines()) if p.exists() else 0
page_path=fixture/'bin/board/dashboard.html'
page=page_path.read_text().replace('<script>',"<script>window.__bridgeTest=new URLSearchParams(location.search).has('browser-test')</script><script>",1)
page=page.replace('refresh(true);connect();flush();','refresh(true);if(!window.__bridgeTest)connect();flush();')
page=page.replace('</body>',r'''<script>
if(window.__bridgeTest){
 const finish=result=>{const out=document.createElement('pre');out.id='bridge-test-result';out.textContent=JSON.stringify(result);document.body.append(out);window.stop();for(let id=1;id<1000;id++){clearInterval(id);clearTimeout(id)}};
 let attempts=0;
 const begin=setInterval(async()=>{
  const node=[...document.querySelectorAll('#decision-cards .card')].find(n=>n.querySelector('h3')?.textContent==='Choose for instant');
  const review=[...document.querySelectorAll('#decision-cards .card')].find(n=>n.data?.task_id==='review-label');
  const delivery=[...document.querySelectorAll('#decision-cards .card')].find(n=>n.data?.task_id==='delivery-fail');
  const factual=[...document.querySelectorAll('#decision-cards .card')].find(n=>n.data?.task_id==='factual-rate');
  const failed=[...document.querySelectorAll('#task-cards .card')].find(n=>n.data?.task_id==='external');
  const archived=[...document.querySelectorAll('#archive-cards .card')].find(n=>n.data?.task_id==='owned');
  if(!node||!review||!delivery||!factual||!failed||!archived){if(++attempts>30){clearInterval(begin);finish({error:'cards did not render',missing:{node:!node,review:!review,delivery:!delivery,factual:!factual,failed:!failed,archived:!archived}})}return}
  clearInterval(begin);
  const radios=node.querySelectorAll('input[type=radio]'),note=node.querySelector('textarea'),key=draftKey(node.data);
  const preselected=[...radios].some(r=>r.checked);
  radios[0].click();note.value='Unsaved local draft';note.dispatchEvent(new Event('input',{bubbles:true}));
  const origin=structuredClone(state.decisions.find(d=>d.task_id==='instant'));
  const moved=structuredClone(state),moving=moved.decisions.find(d=>d.task_id==='instant');
  moving.project='CES';moving.origin_id='instant';moving.task_id='instant-decision-choose';paint(moved);
  const holdKey=draftKey(node.data),liveProject=node.querySelector('.badge').textContent,draftAfterMove=JSON.parse(localStorage.getItem(holdKey)),draftLeftBehind=localStorage.getItem(key);
  document.querySelector('#projects button[data-tag="CES"]').click();
  const visibleAfterMove=!node.hidden;
  document.querySelector('#projects button[data-tag="All"]').click();
  const coexist=structuredClone(state);coexist.decisions.push(origin);paint(coexist);
  const originCard=cards.get(identity(origin)),holdRadios=[...node.querySelectorAll('input[type=radio]')],originRadios=[...originCard.querySelectorAll('input[type=radio]')];
  originRadios[1].click();paint(structuredClone(coexist));
  const migration={records:[record(node.data).choice,record(originCard.data).choice],rebuilt:[node.data,originCard.data].map(d=>{const fresh=buildDecision(d);return [fresh.querySelector('input:checked')?.value||null,record(fresh.data).choice]}),
   cards:[...cards.values()].filter(n=>draftIdentity(n.data)===draftIdentity(origin)).length,radioNames:[holdRadios[0].name,originRadios[0].name],
   selected:[holdRadios.find(r=>r.checked)?.value||null,originRadios.find(r=>r.checked)?.value||null],confirm:[node.querySelector('.confirm').textContent,originCard.querySelector('.confirm').textContent],
   checkedOpen:[...cards.values()].filter(n=>!n.hidden&&n.data.state==='open'&&n.querySelector('input:checked')).length,batch:document.querySelector('#submit-drafted').textContent};
  paint(moved);
  await refresh(true);
  const secret=JSON.parse(localStorage.getItem('board-secret'));
  const response=await fetch('/answer',{method:'POST',headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},body:JSON.stringify({home:node.data.home_id,task:node.data.task_id,key:node.data.decision_key,revision:node.data.revision,choice:'B',note:'Other device chose wait',device:'other-device'})});
  if(!response.ok){finish({error:'answer post '+response.status});return}
  await refresh(true);
  let polls=0;
  const observe=setInterval(()=>{
   if(node.querySelector('.decision-state').textContent==='Waiting on you'){if(++polls>30){clearInterval(observe);finish({error:'submitted state did not render',state:node.querySelector('.decision-state').textContent})}return}
   clearInterval(observe);
   const conflicting=structuredClone(state),base=conflicting.decisions.find(d=>d.task_id==='instant');
   conflicting.decisions.push({...base,task_id:'instant-decision-choose',origin_id:'instant'});paint(conflicting);
   const duplicateCards=[...cards.values()].filter(n=>draftIdentity(n.data)===draftIdentity(base)),distinctDuplicateCards=duplicateCards.length;
   const distinctRadioGroups=new Set(duplicateCards.map(n=>n.querySelector('input[type=radio]').name)).size;
   const style=getComputedStyle(failed),descriptionStyle=getComputedStyle(node.querySelector('.consequence')),saved=localStorage.getItem(key);
   finish({viewport:[innerWidth,innerHeight],horizontalOverflow:document.documentElement.scrollWidth>document.documentElement.clientWidth,
    preselected,liveProject,draftAfterMove,draftLeftBehind,visibleAfterMove,migration,distinctDuplicateCards,distinctRadioGroups,selected:[...radios].find(r=>r.checked)?.value,note:note.value,state:node.querySelector('.decision-state').textContent,
    savedDraft:saved,health:document.querySelector('#answer-health').textContent,
    healthHidden:document.querySelector('#answer-health').hidden,dot:document.querySelector('#connection-dot').className,
    failedBorderWidth:style.borderTopWidth,failedBorderColor:style.borderTopColor,
    description:node.querySelector('.consequence').textContent,descriptionSize:descriptionStyle.fontSize,descriptionWeight:descriptionStyle.fontWeight,
    registeredOptions:[...node.querySelectorAll('.option')].map(o=>o.textContent),
    legacyOptions:[...review.querySelectorAll('.option')].map(o=>o.textContent),legacyNotice:review.querySelector('.options-needed')?.textContent,
    factualPreselected:[...factual.querySelectorAll('input[type=radio]')].some(r=>r.checked),factualGuidance:factual.querySelector('.recommend')?.textContent,
    reviewState:review.querySelector('.decision-state').textContent,deliveryState:delivery.querySelector('.decision-state').textContent,
    decisionLifecycle:[...node.querySelectorAll('.lifecycle-actions button:not([hidden])')].map(b=>b.textContent),
    taskLifecycle:[...failed.querySelectorAll('.lifecycle-actions button:not([hidden])')].map(b=>b.textContent),
    archiveLifecycle:[...archived.querySelectorAll('.lifecycle-actions button:not([hidden])')].map(b=>b.textContent),archiveTitle:document.querySelector('#archive-title').textContent});
  },100);
 },100);
}
</script></body>''')
page_path.write_text(page)
(fakebin:=root/'fakebin').mkdir()
home=root/'main'; second=root/'second'
# Deliberately poison the launching session with a different, contained home.
# The boundary guards below refuse BEFORE executing any real process-event
# operation if production leaks these variables, even during failed-test cleanup.
sentinel=root/'non-fixture-home'
for directory in ('state','data','projects'):
    (sentinel/directory).mkdir(parents=True)
    (sentinel/directory/'must-remain').write_text('untouched')
def sentinel_state():
    return {str(p.relative_to(sentinel)):p.read_bytes() for p in sentinel.rglob('*') if p.is_file()}
sentinel_before=sentinel_state()
pe=fixture/'bin/fm-procevent.sh'
pe.unlink()
shutil.copy2(code/'bin/fm-procevent.sh',fixture/'bin/fm-procevent-real.sh')
pe.write_text("""#!PYTHON
import json,os,pathlib,sys
root=pathlib.Path(os.environ['FM_BOARD_TEST_ROOT']).resolve()
home=pathlib.Path(os.environ.get('FM_HOME','/')).resolve()
keys=('FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_PROJECTS_OVERRIDE')
record={'command':sys.argv[1:],'home':str(home),'overrides':{k:os.environ.get(k) for k in keys}}
clean=all(k not in os.environ for k in keys)
# The real sweep owner explicitly binds its recursive retire to this same state.
recursive_retire=(sys.argv[1:2]==['retire'] and os.environ.get('FM_STATE_OVERRIDE')==str(home/'state') and all(k not in os.environ for k in keys[1:]))
record['allowed']=home in (root/'main',root/'second') and (clean or recursive_retire)
with (root/'isolation.jsonl').open('a') as f:f.write(json.dumps(record)+'\\n')
if not record['allowed']:sys.exit('fixture containment refused')
os.execv('/bin/bash',['bash',str(pathlib.Path(__file__).with_name('fm-procevent-real.sh')),*sys.argv[1:]])
""".replace('PYTHON',sys.executable))
pe.chmod(0o755)
for h in (home,second):
    for d in ('state','data','config'):(h/d).mkdir(parents=True)
    (h/'data/backlog.md').write_text('fixture backlog')
    (h/'rows.json').write_text('[]')
    (h/'full-rows.json').write_text('{}')
script='''#!PYTHON
import csv,json,os,pathlib,sys,time
h=pathlib.Path(os.environ['FM_HOME']); name=pathlib.Path(sys.argv[0]).name
fixture_root=pathlib.Path(os.environ['FM_BOARD_TEST_ROOT']).resolve()
assert h.resolve() in (fixture_root/'main',fixture_root/'second')
assert all(k not in os.environ for k in ('FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_PROJECTS_OVERRIDE'))
with (h/'calls.jsonl').open('a') as f:f.write(json.dumps([name,sys.argv[1:]])+'\\n')
if (h/'delay').exists():time.sleep(float((h/'delay').read_text()))
if (h/'fail').exists():sys.exit(1)
if name=='fm-send.sh' and (h/'fail-send').exists():sys.exit(1)
if name=='fm-control.sh' and (h/'fail-control').exists():sys.exit(1)
if name=='tasks-axi':
 rows=json.loads((h/'rows.json').read_text())
 if sys.argv[1]=='show':
  tid=sys.argv[2];r=next(row for row in rows if row[0]==tid);full=json.loads((h/'full-rows.json').read_text()).get(tid,{})
  print('task:')
  for field,index in (('title',4),('hold_reason',6),('body',9)):
   print(f'  {field}: {json.dumps(full.get(field,(r+[""]*10)[index]))}')
  print(f'  state: {r[1]}\\n  held: {"yes" if r[5]!="-" and r[1]!="done" else "no"}\\n  hold_kind: {r[5]}')
 elif sys.argv[1] in ('hold','unhold','done'):
  command,tid=sys.argv[1:3];r=next(row for row in rows if row[0]==tid)
  if command=='hold':
   assert r[5]=='-',('fixture refuses to replace an existing hold',r)
   r[5]=sys.argv[sys.argv.index('--kind')+1];r[6]=sys.argv[sys.argv.index('--reason')+1]
  elif command=='unhold':r[5]=r[6]='-'
  else:r[1]='done'
  (h/'rows.json').write_text(json.dumps(rows));(h/'data/backlog.md').write_text(json.dumps(rows));print(json.dumps({'id':tid,'state':r[1]}))
 else:
  assert 'body' not in sys.argv[sys.argv.index('--fields')+1].split(','),sys.argv
  state=sys.argv[sys.argv.index('--state')+1];print('tasks[0]{id,state,kind,repo,title,hold_kind,hold_reason,blocked,blocked_by}:')
  for r in rows:
   if state==r[1] or state=='held' and r[5]!='-':
    import io
    line=io.StringIO();csv.writer(line,lineterminator='').writerow(r[:9]);print('  '+line.getvalue())
elif name=='fm-crew-state.sh':print('state: parked · source: pane · fixture')
elif name=='fm-fleet-snapshot.sh':print(json.dumps({'tasks':[]}))
elif name in ('fm-send.sh','fm-decision-hold.sh','fm-control.sh'):
 if name=='fm-control.sh':
  if sys.argv[2]=='relaunch':
   with (h/f'state/{sys.argv[1]}.meta').open('a') as f:f.write('control_relaunch_tx=fixture\\n')
 elif name=='fm-decision-hold.sh' and sys.argv[1]=='decline':
  origin,key=sys.argv[2:4];decision=pathlib.Path(sys.argv[sys.argv.index('--decision-file')+1]).read_text()
  rows=json.loads((h/'rows.json').read_text());r=next(row for row in rows if row[0]==f'{origin}-decision-{key}')
  assert r[1]=='queued' and r[5]=='captain',('decline needs an active captain hold',r)
  r[1]='done';(h/'rows.json').write_text(json.dumps(rows));(h/'data/backlog.md').write_text(json.dumps(rows))
  with (h/'declines.jsonl').open('a') as f:f.write(json.dumps([origin,key,decision])+'\\n')
 elif name=='fm-decision-hold.sh':
  with (h/'hold-input').open('a') as f:f.write(sys.stdin.read())
  with (h/'deliveries.jsonl').open('a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
 else:
  with (h/'deliveries.jsonl').open('a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
'''.replace('PYTHON',sys.executable)
for name in ('tasks-axi','fm-crew-state.sh','fm-fleet-snapshot.sh','fm-send.sh','fm-decision-hold.sh','fm-control.sh'):
    dest=(fakebin if name=='tasks-axi' else fixture/'bin')/name
    if dest.is_symlink():dest.unlink()
    dest.write_text(script);dest.chmod(0o755)
with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
secret='fixture-secret-24-characters-minimum'
config=home/'config/board.json';config.write_text(json.dumps({'homes':[{'id':'Main','path':str(home)},{'id':'Second','path':str(second)}],'lan_host':'localhost','port':port,'secret':secret,'repo_tags':{'wonderok':'WOK','ces':'CES','vendor/qualified-only':'MF','org-a/shared':'WOK','org-b/shared':'MF'}}))
env=dict(os.environ)
for key in ('FM_HOME','FM_BOARD_CONFIG','FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_PROJECTS_OVERRIDE'):
    env.pop(key,None)
env.update(FM_HOME=str(home),FM_BOARD_CONFIG=str(config),FM_BOARD_PYTHON=sys.executable,
           FM_PROCEVENT_CLAIM_ROOT=str(root/'claims'),PATH=str(fakebin)+os.pathsep+os.environ['PATH'])
poisoned_env=dict(env,FM_STATE_OVERRIDE=str(sentinel/'state'),FM_DATA_OVERRIDE=str(sentinel/'data'),FM_PROJECTS_OVERRIDE=str(sentinel/'projects'))
cli=fixture/'bin/fm-board.sh';daemon=None;out=(root/'daemon.log').open('wb')
def fixture_boundary(candidate_env=env,candidate_config=config):
    def descendant(path,label):
        resolved=pathlib.Path(path).resolve()
        try:relative=resolved.relative_to(root)
        except ValueError:raise AssertionError(f'{label} escaped fixture root: {resolved}')
        assert relative.parts, f'{label} must be a strict fixture-root descendant'
        return resolved
    fixture_home=descendant(candidate_env['FM_HOME'],'FM_HOME')
    assert all(k not in candidate_env for k in ('FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_PROJECTS_OVERRIDE'))
    fixture_config=descendant(candidate_config,'config')
    fixture_db=descendant(fixture_home/'state/board.sqlite','database')
    assert fixture_config==pathlib.Path(candidate_env['FM_BOARD_CONFIG']).resolve()
    configured=json.loads(fixture_config.read_text())
    for source in configured['homes']:
        descendant(source['path'],f"configured home {source['id']}")
    assert fixture_db==home.resolve()/'state/board.sqlite'
    return fixture_home,fixture_config,fixture_db
fixture_boundary()
def command(*args,ok=True,timeout=30):
    fixture_boundary()
    p=subprocess.run([str(cli),*map(str,args)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=timeout)
    if ok and p.returncode:raise AssertionError(p.stderr.decode()+p.stdout.decode())
    if not ok:assert p.returncode!=0,(args,p.stdout)
    return p

def sql(query,args=()):
    with sqlite3.connect(home/'state/board.sqlite',timeout=5) as c:
        c.row_factory=sqlite3.Row
        return [dict(r) for r in c.execute(query,args)]

def mutate(query,args=()):
    with sqlite3.connect(home/'state/board.sqlite',timeout=5) as c:c.execute(query,args)

def rev():return int(sql("select value from meta where key='rev'")[0]['value'])
def request(path='/api/state',body=None,auth=True,extra=None):
    headers={'Authorization':'Bearer '+secret} if auth else {}
    headers.update(extra or {})
    req=urllib.request.Request(f'http://localhost:{port}'+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
    try:r=urllib.request.urlopen(req,timeout=10)
    except urllib.error.HTTPError as e:r=e
    with r:
        data=r.read();return r.status,json.loads(data) if data and data[:1] in (b'{',b'[') else data,r.headers

def wait(test,seconds=15):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        try:
            v=test()
            if v:return v
        except (OSError,urllib.error.URLError,sqlite3.OperationalError):pass
        time.sleep(.1)
    raise AssertionError('condition did not become true')

def start():
    global daemon
    fixture_boundary()
    daemon=subprocess.Popen([str(cli),'serve'],env=env,stdout=out,stderr=out)
    wait(lambda:request('/healthz')[1].get('ok') and request('/healthz')[1]['last_snapshot_ms'].get('Main') is not None,20)

def stop(kill=False):
    global daemon
    if daemon and daemon.poll() is None:
        daemon.kill() if kill else daemon.terminate()
        daemon.wait(timeout=30)
    daemon=None

def meta(h,tid,status='working: fixture',repo='wonderok'):
    (h/f'state/{tid}.meta').write_text('kind=task\nproject='+repo+'\n')
    (h/f'state/{tid}.status').write_text(status+'\n')
def decision(tid,key='choose',project='WOK'):
    return json.loads(command('decision','Main',tid,key,'--project',project,'--title','Choose for '+tid,
        '--description','This decides whether the change ships now or waits for another check.',
        '--option','A: Ship it','--option','B: Wait','--rec','A','--why','Small reversible change').stdout)
def answer(tid,key='choose',choice='A',note='a note',revision=1):return dict(home='Main',task=tid,key=key,revision=revision,choice=choice,note=note)
def lifecycle(hid,tid,revision,action,rid):return dict(home=hid,task=tid,revision=revision,action=action,request_id=rid,device='fixture')
def accelerate(ids):
    for aid in ids:mutate('update answers set ready_at=0 where answer_id=?',(aid,))
def accelerate_lifecycle(ids):
    for rid in ids:mutate('update lifecycle_requests set ready_at=0 where request_id=?',(rid,))
def calls(h,name):
    p=h/'calls.jsonl'
    return [r for r in map(json.loads,p.read_text().splitlines()) if r[0]==name] if p.exists() else []
def passed(t):print('ok - '+t,flush=True)
# A phase-1 (user_version=1) database with the original column order and
# question formats, holding open decisions the upgrade must not re-revision.
legacy_asked='2026-09-01T00:00:00+00:00'
with sqlite3.connect(home/'state/board.sqlite') as c:
    c.executescript('''CREATE TABLE schema_version(version INTEGER NOT NULL);INSERT INTO schema_version VALUES(1);
        CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);INSERT INTO meta VALUES('rev','7');INSERT INTO meta VALUES('generated_at','');
        CREATE TABLE decisions(home_id TEXT,task_id TEXT,decision_key TEXT,
            revision INTEGER,question TEXT,options TEXT,recommendation TEXT,why TEXT,
            source TEXT,state TEXT,asked_at TEXT,closed_at TEXT,project TEXT,
            origin_id TEXT,registered INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(home_id,task_id,decision_key,revision));
        PRAGMA user_version=1;''')
    c.executemany('INSERT INTO decisions VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
        ('Main','alpha','choose',1,'Which release?','[]','','','worker','open',legacy_asked,None,'WOK','',0),
        ('Main','origin-decision-budget','budget',1,'Budget approval: Set the budget','[]','','','hold','open',legacy_asked,None,'CES','origin',1),
        ('Main','v1-registered','pick',1,'DECIDE D1: Pick a color',json.dumps([{'value':'A','label':'Red'},{'value':'B','label':'Blue'}]),'A','Red is faster','firstmate','open',legacy_asked,None,'WOK','',1)])
try:
    for sub in ('serve','ingest','decision','live','answered','refresh','arm-answers','backup'):
        command(sub,'--help');command(sub,'--invalid',ok=False)
    command('--help');command('decision','Main','../bad','key',ok=False)
    refused=subprocess.run([str(pe),'sweep-home'],env=poisoned_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    assert refused.returncode and b'fixture containment refused' in refused.stderr
    assert sentinel_state()==sentinel_before
    handler=fixture/'bin/board/board-answers-handle.sh'
    assert subprocess.run([str(handler),'--help'],env=env,stdout=subprocess.PIPE).returncode==0
    old=fakebin/'oldpython';old.write_text('#!/bin/sh\nexit 1\n');old.chmod(0o755)
    guarded=subprocess.run([str(handler),'route'],env=dict(env,FM_BOARD_PYTHON=str(old)),
                           stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    assert guarded.returncode!=0 and b'3.14' in guarded.stderr,guarded
    passed('every subcommand validates arguments and supports --help')
    meta(home,'alpha','needs-decision [key=choose]: Which release?')
    meta(home,'lifecycle','needs-decision [key=one]: Choose the first path\nneeds-decision [key=two]: Choose the second path')
    meta(second,'beta')
    long_title=('DECIDE D2: Wonderok Postgres to Vultr Managed (EWR) - $36 Startup NVMe recommendation '
                'with enough additional context to exceed one hundred and sixty characters while remaining understandable')
    marker=f'\\n... (truncated, {len(long_title)} chars total - use show long-decision --full to see complete text)'
    long_body='This is the complete plain-English body for the long decision. '+('More context. '*20)
    rows=[['alpha','in_flight','ship','wonder-media/wonderok','Release alpha','-','-','no','none'],
          ['lifecycle','in_flight','ship','wonder-media/wonderok','Lifecycle fixture','-','-','no','none'],
          ['origin-decision-budget','queued','captain','example/ces','Budget approval','captain','Set the budget','no','none'],
          ['long-decision','queued','captain','wonderok',long_title[:78]+marker,'captain','Choose where the database will live.','no','none'],
          ['blocked-decision-no','queued','captain','ces','Blocked hold','captain','Wait','yes','missing'],
          ['external','in_flight','ship','ces','External wait','external','Supplier','no','none'],
          ['inherit-origin','in_flight','ship','wonderok','Origin work','-','-','no','none'],
          ['inherit-origin-decision-scope','queued','captain','','Choose scope','captain','Choose the bounded scope.','no','none'],
          ['qualified-leaf','in_flight','ship','qualified-only','Qualified alias leaf','-','-','no','none'],
          ['ambiguous-exact','in_flight','ship','org-a/shared','Exact shared alias','-','-','no','none'],
          ['ambiguous-unlisted','in_flight','ship','org-c/shared','Ambiguous shared leaf','-','-','no','none'],
          ['ambiguous-unlisted-decision-pick','queued','captain','','Pick a vendor','captain','Pick the vendor for the shared work.','no','none'],
          ['stale-origin','in_flight','ship','wonderok','Stale origin work','-','-','no','none'],
          ['stale-origin-decision-merge','queued','captain','','Merge now?','captain','Choose whether to merge now.','no','none']]
    (home/'rows.json').write_text(json.dumps(rows))
    (home/'full-rows.json').write_text(json.dumps({'long-decision':{'title':long_title,'body':long_body,'hold_reason':'Choose where the database will live.'}}))
    command('ingest','--once');before=rev()
    assert sql("select title from tasks where task_id='alpha'")[0]['title']=='Release alpha'
    assert len(sql("select * from decisions where source='hold'"))==5
    assert sql("select * from decisions where task_id='alpha'")[0]['decision_key']=='choose'
    shows=[call[1] for call in calls(home,'tasks-axi') if call[1][:1]==['show']]
    assert shows==[['show','long-decision','--full']],shows
    assert sql('pragma user_version')[0]['user_version']==3 and sql('select version from schema_version')[0]['version']==3
    assert [col['name'] for col in sql('pragma table_info(decisions)')][-1]=='description'
    assert before>7
    for tid,question,description in (('alpha','Release alpha','Which release?'),('origin-decision-budget','Budget approval','Set the budget'),
                                     ('v1-registered','Pick a color','Your choice decides what happens next for this task.')):
        rows_for=sql('select * from decisions where task_id=?',(tid,))
        assert len(rows_for)==1 and rows_for[0]['revision']==1 and rows_for[0]['state']=='open',rows_for
        assert rows_for[0]['question']==question and rows_for[0]['description']==description,rows_for
    assert json.loads(sql("select options from decisions where task_id='v1-registered'")[0]['options'])[0]['label']=='Red'
    long_row=sql("select * from decisions where task_id='long-decision'")[0]
    assert long_row['question']=='Wonderok Postgres to Vultr Managed (EWR)' and long_row['description']=='Choose where the database will live.',long_row
    assert 'truncated' not in json.dumps(sql("select payload from backlog"))
    projects={row['task_id']:row['project'] for row in sql('select task_id,project from tasks')}
    assert projects['alpha']=='WOK' and projects['origin-decision-budget']=='CES',projects
    assert projects['qualified-leaf']=='MF' and projects['ambiguous-exact']=='WOK' and projects['ambiguous-unlisted']=='FM',projects
    inherited=sql("select * from decisions where task_id='inherit-origin-decision-scope'")[0]
    assert inherited['project']=='WOK' and inherited['origin_id']=='inherit-origin',inherited
    assert projects['inherit-origin-decision-scope']=='WOK',projects
    legacy_hold=sql("select * from decisions where task_id='stale-origin-decision-merge'")[0]
    assert legacy_hold['state']=='open' and legacy_hold['options']=='[]',legacy_hold
    mutate('''insert into decisions(home_id,task_id,decision_key,revision,question,description,options,recommendation,why,
        source,state,asked_at,closed_at,project,origin_id,registered) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        ('Main','stale-origin','merge',1,'Merge now?','This decides whether the branch lands today.',
         json.dumps([{'value':'A','label':'Merge now'},{'value':'B','label':'Wait for review'}]),'B','Review lowers the risk.',
         'firstmate','open',legacy_asked,None,'WOK','',1))
    command('ingest','--once')
    merged=sql("select * from decisions where task_id='stale-origin-decision-merge' order by revision desc")
    assert merged[0]['state']=='open' and merged[0]['registered']==1 and merged[0]['recommendation']=='B' and merged[0]['origin_id']=='stale-origin',merged[0]
    assert merged[0]['revision']==2 and merged[1]['state']=='closed' and merged[1]['revision']==1,merged
    assert sql("select state from decisions where task_id='stale-origin'")==[{'state':'closed'}]
    before=rev();command('ingest','--once');assert rev()==before
    assert {e['project'] for e in sql("select project from events where task_id='inherit-origin-decision-scope'")}=={'WOK'}
    assert projects['ambiguous-unlisted-decision-pick']=='FM' and sql("select project from decisions where task_id='ambiguous-unlisted-decision-pick'")[0]['project']=='FM'
    picked=json.loads(command('decision','Main','ambiguous-unlisted','pick','--project','WOK','--title','Pick a vendor',
        '--option','A: Vendor one','--option','B: Vendor two','--rec','A','--why','Vendor one is already approved.').stdout)
    assert picked['task']=='ambiguous-unlisted-decision-pick',picked
    command('ingest','--once')
    explicit=sql("select * from decisions where task_id='ambiguous-unlisted-decision-pick' order by revision desc")[0]
    assert explicit['project']=='WOK' and explicit['state']=='open' and explicit['revision']==picked['revision'],explicit
    projects={row['task_id']:row['project'] for row in sql('select task_id,project from tasks')}
    assert projects['ambiguous-unlisted-decision-pick']=='WOK' and projects['ambiguous-unlisted']=='WOK',projects
    assert {e['project'] for e in sql("select project from events where task_id in ('ambiguous-unlisted','ambiguous-unlisted-decision-pick')")}=={'WOK'}
    canonical=json.loads(command('decision','Main','inherit-origin','scope','--project','FM','--title','Choose scope',
        '--description','This decides the bounded scope.','--option','A: Small scope','--option','B: Broad scope',
        '--rec','A','--why','The smaller scope is easier to verify.').stdout)
    assert canonical['task']=='inherit-origin-decision-scope',canonical
    assert not sql("select * from decisions where task_id='inherit-origin'")
    canonical_row=sql("select * from decisions where task_id='inherit-origin-decision-scope' order by revision desc")[0]
    assert canonical_row['project']=='FM'
    command('ingest','--once')
    reconciled=sql("select * from decisions where task_id='inherit-origin-decision-scope' order by revision desc")[0]
    assert reconciled['project']=='WOK' and reconciled['revision']==canonical_row['revision'] and reconciled['state']=='open',reconciled
    late=json.loads(command('decision','Main','late-origin','route','--project','WOK','--title','Choose the route',
        '--description','This decides which route is used.','--option','A: Direct','--option','B: Staged',
        '--rec','B','--why','The staged route is easier to verify.').stdout)
    assert late['task']=='late-origin',late
    rows.append(['late-origin-decision-route','queued','captain','wonder-media/wonderok','Choose the route',
        'captain','This decides which route is used.','no','none'])
    (home/'rows.json').write_text(json.dumps(rows));(home/'data/backlog.md').write_text('fixture backlog with late hold')
    command('ingest','--once')
    late_hold=sql("select * from decisions where task_id='late-origin-decision-route' order by revision desc")[0]
    late_origin=sql("select * from decisions where task_id='late-origin' order by revision desc")[0]
    assert late_hold['registered']==1 and late_hold['origin_id']=='late-origin' and late_hold['state']=='open',late_hold
    assert late_origin['state']=='closed' and late_origin['revision']==late['revision'],late_origin
    def late_actionable(actionable):
        rows[-1][7:9]=['no','none'] if actionable else ['yes','missing']
        (home/'rows.json').write_text(json.dumps(rows));(home/'data/backlog.md').write_text('fixture backlog late hold actionable '+str(actionable))
        command('ingest','--once')
        return sql("select * from decisions where task_id='late-origin-decision-route' order by revision desc")[0]
    blocked_hold=late_actionable(False)
    assert blocked_hold['state']=='closed' and blocked_hold['revision']==late_hold['revision'],blocked_hold
    rerouted=json.loads(command('decision','Main','late-origin','route','--project','WOK','--title','Choose the route',
        '--option','A: Direct','--option','B: Staged','--option','C: Manual','--rec','C','--why','Manual routing is reversible.').stdout)
    assert rerouted['task']=='late-origin',rerouted
    assert late_actionable(False)['state']=='closed'
    absorbed=late_actionable(True)
    assert absorbed['state']=='open' and absorbed['registered']==1 and absorbed['recommendation']=='C',absorbed
    assert absorbed['revision']==blocked_hold['revision']+1 and len(json.loads(absorbed['options']))==3,absorbed
    assert sql("select state from decisions where task_id='late-origin' order by revision desc")[0]['state']=='closed'
    assert late_actionable(False)['state']=='closed'
    reopened=late_actionable(True)
    assert reopened['state']=='open' and reopened['revision']==absorbed['revision']+1,reopened
    assert (reopened['question'],reopened['options'],reopened['recommendation'],reopened['why'])==(absorbed['question'],absorbed['options'],absorbed['recommendation'],absorbed['why']),reopened
    assert len(sql("select * from decisions where task_id='late-origin-decision-route'"))==reopened['revision']
    passed('qualified aliases, ambiguity, hold inheritance, canonical registration, and in-place project reconciliation')
    passed('closed registered hold reopens with its content; registration never targets a closed hold')
    passed('v1 database migrates in place: old column order, same revisions, ELI5 text for every open decision')
    before=rev()
    assert sql("select * from tasks where home_id='Second' and task_id='beta'")
    assert not calls(home,'fm-fleet-snapshot.sh'),calls(home,'fm-fleet-snapshot.sh')
    command('ingest','--once');assert rev()==before
    (home/'state/alpha.status').touch();command('ingest','--once');assert rev()==before
    (home/'state/.last-watcher-beat').touch();command('ingest','--once');assert rev()==before
    passed('fixture homes, actionable holds, keyed decisions; no timestamp churn or hot snapshots')
    (second/'state/beta.meta').unlink();command('ingest','--once','--home','Second')
    assert sql("select deleted_at from tasks where task_id='beta'")[0]['deleted_at']
    assert rev()==before+1
    passed('vanished meta tombstones once')
    before=rev();decision('alpha');assert rev()==before+1
    row=sql("select * from decisions where task_id='alpha' order by revision desc")[0]
    assert json.loads(row['options'])[0]['label']=='Ship it' and row['recommendation']=='A'
    assert row['description']=='This decides whether the change ships now or waits for another check.'
    decision('alpha');assert rev()==before+1
    command('decision','Main','bad-options','few','--project','WOK','--title','Too few',
            '--description','This should be rejected.','--option','A: Alone',ok=False)
    factual=json.loads(command('decision','Main','factual-rate','rate','--project','MF','--title','Confirm the current rate',
            '--description','This records the factual rate after checking the source.','--option','A: 2.5%',
            '--option','B: 2.9%','--option','C: Another rate','--why','Verify the current schedule before choosing.').stdout)
    factual_row=sql("select * from decisions where task_id='factual-rate' and revision=?",(factual['revision'],))[0]
    assert factual_row['recommendation']=='' and factual_row['why']=='Verify the current schedule before choosing.',factual_row
    passed('decision CLI creates 2-3 options, description, and recommendation idempotently')
    # Single flight across CLI processes, preserving last-good state on timeout.
    # A hold whose origin meta vanishes after the manifest snapshot must not abort the home.
    meta(home,'vanish',repo='');rows.append(['vanish-decision-keep','queued','captain','','Keep the branch?','captain','Choose whether to keep it.','no','none'])
    (home/'rows.json').write_text(json.dumps(rows));(home/'data/backlog.md').write_text('fixture backlog with vanishing origin')
    command('ingest','--once')
    assert sql("select project from decisions where task_id='vanish-decision-keep'")==[{'project':'FM'}]
    (home/'delay').write_text('12');(home/'state/alpha.status').touch()
    fixture_boundary()
    slow=subprocess.Popen([str(cli),'ingest','--once','--home','Main'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    time.sleep(.5);n=len(calls(home,'fm-crew-state.sh'));(home/'state/vanish.meta').unlink()
    command('ingest','--once','--home','Main');assert len(calls(home,'fm-crew-state.sh'))==n
    _,err=slow.communicate(timeout=20);assert slow.returncode!=0 and b'timeout' in err
    assert sql("select title from tasks where task_id='alpha'")[0]['title']=='Release alpha'
    assert 'timeout' in sql("select last_error from ingest_runs where home_id='Main'")[0]['last_error']
    assert sql("select state from decisions where task_id='vanish-decision-keep'")==[{'state':'open'}]
    (home/'delay').unlink();rows.pop()
    (home/'rows.json').write_text(json.dumps(rows));(home/'data/backlog.md').write_text('fixture backlog without vanishing origin')
    command('ingest','--once')
    assert sql("select state from decisions where task_id='vanish-decision-keep'")==[{'state':'closed'}]
    assert sql("select deleted_at from tasks where task_id='vanish'")[0]['deleted_at']
    passed('single-flight and bounded subprocess failure keep last-good rows; a vanished origin meta is tolerated')
    start();assert calls(home,'fm-fleet-snapshot.sh')
    status,health,_=request('/healthz');assert status==200 and health['answers_armed']
    assert set(('ok','ingest_age_s','last_snapshot_ms','sse_clients','db_ok','outbox_backlog','answers_armed','answers_error'))<=health.keys()
    assert health['answers_error'] is None
    _,payload,h=request();assert request(extra={'If-None-Match':h['ETag']})[0]==304
    visible_route=[d for d in payload['decisions'] if d['home_id']=='Main' and d['decision_key']=='route']
    assert [(d['task_id'],d['origin_id']) for d in visible_route]==[('late-origin-decision-route','late-origin')],visible_route
    long_card=next(d for d in payload['decisions'] if d['task_id']=='long-decision')
    assert long_card['question']=='Wonderok Postgres to Vultr Managed (EWR)',long_card
    assert long_card['description']=='Choose where the database will live.'
    assert 'truncated' not in json.dumps(payload)
    _,_,ph=request('/api/state?project=CES');assert ph['ETag']!=h['ETag']
    assert request('/api/state?project=CES',extra={'If-None-Match':h['ETag']})[0]==200
    assert request('/api/state?project=CES',extra={'If-None-Match':ph['ETag']})[0]==304
    assert request(auth=False)[0]==403
    assert request('/api/state',extra={'Origin':'http://evil.test'})[0]==403
    assert request('/../config/board.json')[0]==404
    assert request('/')[0]==200
    assert request('/answer',answer('alpha',revision=row['revision']),auth=False)[0]==403
    assert request('/answer',answer('alpha',revision=99))[0]==409
    passed('health, Bearer authentication, Host/Origin boundary, explicit routes, ETag, stale revision')
    # SSE uses a real streaming socket; new status appears without reload.
    req=urllib.request.Request(f'http://localhost:{port}/events',headers={'Authorization':'Bearer '+secret})
    stream=urllib.request.urlopen(req,timeout=15)
    event=b''
    while b'\n\n' not in event:event+=stream.readline()
    assert b'event: changed' in event and b'"rev"' in event
    meta(home,'pushed','needs-decision [key=deploy]: Pick a deploy window')
    wait(lambda:any(d['task_id']=='pushed' for d in request()[1]['decisions']),10)
    deadline=time.monotonic()+10
    while True:
        seen=b''
        while b'\n\n' not in seen:seen+=stream.readline()
        if b'event: changed' in seen:break
        assert time.monotonic()<deadline,'SSE changed event missing'
    # Registration pushes immediately through the loopback-only reload route.
    started=time.monotonic();result=decision('instant')
    while True:
        pushed=b''
        while b'\n\n' not in pushed:pushed+=stream.readline()
        data=next((line[6:] for line in pushed.splitlines() if line.startswith(b'data: ')),b'{}')
        if json.loads(data).get('rev')==rev():break
    assert time.monotonic()-started<1.5,'registration did not push promptly'
    assert request('/internal/reload',{},auth=False)[0]==403
    stream.close();passed('changed SSE carries rev, status arrives within ten seconds, registration pushes immediately')
    # Task lifecycle is queued once per underlying task, even when several
    # decision cards expose the same Hold and Discard actions.
    lifecycle_cards=[d for d in request()[1]['decisions'] if d['task_id']=='lifecycle']
    assert {d['decision_key'] for d in lifecycle_cards}=={'one','two'} and {d['lifecycle_task_id'] for d in lifecycle_cards}=={'lifecycle'}
    answer_post=request('/answer',answer('lifecycle',key='one',choice='custom',note='Preserve this answer',revision=next(d for d in lifecycle_cards if d['decision_key']=='one')['revision']))
    assert answer_post[0]==200,answer_post
    preserved_answer=answer_post[1]['answers'][0]['answer_id']
    mutate('update answers set ready_at=? where answer_id=?',(time.time()+3600,preserved_answer))
    hold_one='11111111-1111-4111-8111-111111111111'
    queued=request('/lifecycle',lifecycle('Main','lifecycle',0,'hold',hold_one));assert queued[0]==200,queued
    assert queued[1]['lifecycle']['pending_action']=='hold'
    assert request('/lifecycle',{'action':'undo','request_id':hold_one})[0]==200
    after_undo=next(d for d in request()[1]['decisions'] if d['task_id']=='lifecycle')['lifecycle']
    assert after_undo['state']=='active' and after_undo['revision']==2 and not after_undo['pending_request_id'],after_undo
    hold_two='22222222-2222-4222-8222-222222222222'
    queued=request('/lifecycle',lifecycle('Main','lifecycle',after_undo['revision'],'hold',hold_two));assert queued[0]==200,queued
    duplicate=request('/lifecycle',lifecycle('Main','lifecycle',after_undo['revision'],'hold','33333333-3333-4333-8333-333333333333'))
    assert duplicate[0]==200 and duplicate[1]['request']['request_id']==hold_two,duplicate
    stale=request('/lifecycle',lifecycle('Main','lifecycle',0,'discard','44444444-4444-4444-8444-444444444444'))
    assert stale[0]==409,stale
    pending_cards=[d for d in request()[1]['decisions'] if d['task_id']=='lifecycle']
    assert len(pending_cards)==2 and {d['lifecycle']['pending_request_id'] for d in pending_cards}=={hold_two}
    accelerate_lifecycle([hold_two])
    wait(lambda:sql('select state from lifecycle_requests where request_id=?',(hold_two,))[0]['state']=='completed')
    held_state=request()[1]
    assert not any(d['task_id']=='lifecycle' for d in held_state['decisions']) and not any(t['task_id']=='lifecycle' for t in held_state['tasks'])
    archived=next(t for t in held_state['archive'] if t['task_id']=='lifecycle')
    assert archived['lifecycle']['state']=='held' and archived['lifecycle']['error'] is None,archived
    assert sql('select state from decisions where task_id=?',('lifecycle',))==[{'state':'queued'},{'state':'open'}]
    assert sql('select cancelled_at from answers where answer_id=?',(preserved_answer,))[0]['cancelled_at'] is None
    assert len([c for c in calls(home,'tasks-axi') if c[1][:2]==['hold','lifecycle']])==1
    assert len([c for c in calls(home,'fm-control.sh') if c[1]==['lifecycle','exit']])==1
    def delivered(tid):
        p=home/'deliveries.jsonl'
        return [d for d in map(json.loads,p.read_text().splitlines()) if d[0]==tid] if p.exists() else []
    accelerate([preserved_answer])
    gated=subprocess.run([str(handler),'route','--config',str(config)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    assert gated.returncode==0 and json.loads(gated.stdout)['routed']==0 and json.loads(gated.stdout)['exceptions']==[],(gated.stdout,gated.stderr)
    time.sleep(1.5)
    assert sql('select routing_at,consumed_at,error from answers where answer_id=?',(preserved_answer,))==[{'routing_at':None,'consumed_at':None,'error':None}]
    assert not delivered('lifecycle')
    stop(kill=True);start()
    archived=next(t for t in request()[1]['archive'] if t['task_id']=='lifecycle')
    resume='55555555-5555-4555-8555-555555555555'
    resumed=request('/lifecycle',lifecycle('Main','lifecycle',archived['lifecycle']['revision'],'resume',resume));assert resumed[0]==200,resumed
    accelerate_lifecycle([resume]);wait(lambda:sql('select state from lifecycle_requests where request_id=?',(resume,))[0]['state']=='completed')
    resumed_state=request()[1]
    resumed_cards=[d for d in resumed_state['decisions'] if d['task_id']=='lifecycle']
    assert len(resumed_cards)==2 and next(d for d in resumed_cards if d['decision_key']=='one')['answer']['answer_id']==preserved_answer
    assert not any(t['task_id']=='lifecycle' for t in resumed_state['archive'])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(preserved_answer,))[0]['consumed_at'])
    assert delivered('lifecycle')==[['lifecycle','--resolve-key','one','Preserve this answer']],delivered('lifecycle')
    second_answer=request('/answer',answer('lifecycle',key='two',choice='custom',note='Still queued',revision=next(d for d in resumed_cards if d['decision_key']=='two')['revision']))[1]['answers'][0]['answer_id']
    mutate('update answers set ready_at=? where answer_id=?',(time.time()+3600,second_answer))
    relaunches=[c[1] for c in calls(home,'fm-control.sh') if c[1][:2]==['lifecycle','relaunch']]
    assert len(relaunches)==1 and relaunches[0][2]=='--note' and resume in relaunches[0][3],relaunches
    assert len([c for c in calls(home,'tasks-axi') if c[1][:2]==['unhold','lifecycle']])==1
    assert next(r for r in json.loads((home/'rows.json').read_text()) if r[0]=='lifecycle')[5]=='-'
    discard='66666666-6666-4666-8666-666666666666'
    lifecycle_revision=resumed_cards[0]['lifecycle']['revision']
    discarded=request('/lifecycle',lifecycle('Main','lifecycle',lifecycle_revision,'discard',discard));assert discarded[0]==200,discarded
    accelerate_lifecycle([discard]);wait(lambda:sql('select state from lifecycle_requests where request_id=?',(discard,))[0]['state']=='completed')
    discarded_state=request()[1]
    assert not any(d['task_id']=='lifecycle' for d in discarded_state['decisions'])
    assert not any(t['task_id']=='lifecycle' for t in discarded_state['tasks']+discarded_state['archive'])
    assert sql("select decision_key,state from decisions where task_id=? and state!='closed'",('lifecycle',))==[{'decision_key':'one','state':'consumed'}]
    assert sql('select cancelled_at from answers where answer_id=?',(second_answer,))[0]['cancelled_at']
    assert sql('select cancelled_at from answers where answer_id=?',(preserved_answer,))[0]['cancelled_at'] is None
    assert len([c for c in calls(home,'tasks-axi') if c[1][:2]==['done','lifecycle']])==1
    assert len([c for c in calls(home,'fm-control.sh') if c[1]==['lifecycle','exit']])==2
    stop(kill=True);start()
    assert not any(d['task_id']=='lifecycle' for d in request()[1]['decisions'])
    passed('Hold/archive/resume and Discard persist across restart, preserve answers until discard, and dedupe stale multi-card actions')
    # A secondmate-owned task is mutated only in that configured home. A
    # control-plane failure stays visible in Archive and a retry converges.
    meta(second,'owned','needs-decision [key=scope]: Choose scope',repo='ces')
    (second/'rows.json').write_text(json.dumps([['owned','in_flight','ship','ces','Secondmate-owned task','-','-','no','none']]))
    command('ingest','--once','--home','Second')
    owned=wait(lambda:next((d for d in request()[1]['decisions'] if d['home_id']=='Second' and d['task_id']=='owned'),None))
    (second/'fail-control').write_text('1')
    owner_hold='77777777-7777-4777-8777-777777777777'
    assert request('/lifecycle',lifecycle('Second','owned',owned['lifecycle']['revision'],'hold',owner_hold))[0]==200
    accelerate_lifecycle([owner_hold]);wait(lambda:sql('select state from lifecycle_requests where request_id=?',(owner_hold,))[0]['state']=='failed')
    failed_archive=next(t for t in request()[1]['archive'] if t['home_id']=='Second' and t['task_id']=='owned')
    assert failed_archive['lifecycle']['state']=='held' and 'fm-control.sh' in failed_archive['lifecycle']['error'],failed_archive
    # The failure reaches the owner as one request-scoped packet on the
    # board-answers seam, distinct from any answer, and is acknowledged only
    # after the failed step completes; a queued or undone retry keeps the error.
    log=home/'state/board-inbox/answers.jsonl'
    packet=wait(lambda:log.exists() and next((r for r in map(json.loads,log.read_text().splitlines()) if r.get('request_id')==owner_hold),None))
    assert packet['home']=='Second' and packet['task']=='owned' and packet['lifecycle']=='hold' and 'fm-control.sh' in packet['error'],packet
    assert not {'answer_id','choice','key'}&set(packet)
    result=wait(lambda:next((p for p in (home/'state/procevent-inbox').glob('*.result') if owner_hold in p.read_text()),None))
    source_id,seq=result.name[:-len('.result')].rsplit('.',1)
    def handle_result():return subprocess.run([str(fixture/'bin/fm-procevent-board-answers.sh'),'handle',source_id,seq,str(result)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    unresolved=handle_result();report=json.loads(unresolved.stdout)
    assert unresolved.returncode==1 and [a['request_id'] for a in report['answers']]==[owner_hold] and 'fm-control.sh' in report['answers'][0]['error'],(unresolved.stdout,unresolved.stderr)
    undone_retry='abababab-abab-4bab-8bab-abababababab'
    queued_retry=request('/lifecycle',lifecycle('Second','owned',failed_archive['lifecycle']['revision'],'hold',undone_retry))
    assert queued_retry[0]==200 and queued_retry[1]['lifecycle']['pending_action']=='hold' and 'fm-control.sh' in queued_retry[1]['lifecycle']['error'],queued_retry
    assert request('/lifecycle',{'action':'undo','request_id':undone_retry})[0]==200
    failed_archive=next(t for t in request()[1]['archive'] if t['home_id']=='Second' and t['task_id']=='owned')
    assert failed_archive['lifecycle']['state']=='held' and 'fm-control.sh' in failed_archive['lifecycle']['error'] and not failed_archive['lifecycle']['pending_request_id'],failed_archive
    assert handle_result().returncode==1
    (second/'fail-control').unlink()
    retry='88888888-8888-4888-8888-888888888888'
    assert request('/lifecycle',lifecycle('Second','owned',failed_archive['lifecycle']['revision'],'hold',retry))[0]==200
    accelerate_lifecycle([retry]);wait(lambda:sql('select state from lifecycle_requests where request_id=?',(retry,))[0]['state']=='completed')
    owner_archive=next(t for t in request()[1]['archive'] if t['home_id']=='Second' and t['task_id']=='owned')
    assert owner_archive['lifecycle']['error'] is None
    handled=handle_result()
    assert handled.returncode==0 and json.loads(handled.stdout)['schema']=='board-answers.handled.v1',(handled.stdout,handled.stderr)
    assert [r for r in map(json.loads,log.read_text().splitlines()) if r.get('request_id')==owner_hold]==[packet]
    assert len([c for c in calls(second,'tasks-axi') if c[1][:2]==['hold','owned']])==1
    assert len([c for c in calls(second,'fm-control.sh') if c[1]==['owned','exit']])==2
    assert not [c for c in calls(home,'tasks-axi') if c[1][:2] in (['hold','owned'],['done','owned'])]
    passed('secondmate lifecycle routes to the owning home and exposes control failure until an idempotent retry succeeds')
    # A pre-existing captain or external hold is never replaced or released by
    # Bridge; Discard closes captain decisions through their owner script.
    def lifecycle_done(rid,state='completed'):
        accelerate_lifecycle([rid]);wait(lambda:sql('select state from lifecycle_requests where request_id=?',(rid,))[0]['state']==state)
    def backlog_row(tid):return next(r for r in json.loads((home/'rows.json').read_text()) if r[0]==tid)
    def set_backlog(full,note):
        (home/'rows.json').write_text(json.dumps(full));(home/'data/backlog.md').write_text(note);command('ingest','--once','--home','Main')
    def external(tid,note,state=None,hold=None):
        full=json.loads((home/'rows.json').read_text());r=next(x for x in full if x[0]==tid)
        if state:r[1]=state
        if hold:r[5],r[6]=hold
        set_backlog(full,note)
    gates=[['gate-decision-scope','queued','captain','wonderok','Scope approval','captain','Pick the scope','no','none'],
           ['known','in_flight','ship','wonderok','Known worker','-','-','no','none'],
           ['known-decision-go','queued','captain','wonderok','Go decision','captain','Go or wait','no','none'],
           ['orphan-decision-pick','queued','captain','wonderok','Pick a size','captain','Pick the size','no','none'],
           ['vendor','in_flight','ship','wonderok','Vendor window','external','Waiting for the vendor','no','none']]
    meta(home,'vendor','working: fixture');meta(home,'known','working: fixture');set_backlog(json.loads((home/'rows.json').read_text())+gates,'fixture backlog with gates')
    gate=wait(lambda:next((d for d in request()[1]['decisions'] if d['task_id']=='gate-decision-scope'),None))
    assert gate['lifecycle_task_id']=='gate-decision-scope' and gate['question']=='Scope approval' and gate['description']=='Pick the scope',gate
    gate_hold='99999999-9999-4999-8999-999999999999'
    assert request('/lifecycle',lifecycle('Main','gate-decision-scope',gate['lifecycle']['revision'],'hold',gate_hold))[0]==200
    lifecycle_done(gate_hold)
    assert backlog_row('gate-decision-scope')[5:7]==['captain','Pick the scope']
    assert not [c for c in calls(home,'tasks-axi') if c[1][0] in ('hold','unhold','done') and c[1][1]=='gate-decision-scope']
    gate_archive=next(t for t in request()[1]['archive'] if t['task_id']=='gate-decision-scope')
    assert gate_archive['lifecycle']['state']=='held' and not any(d['task_id']=='gate-decision-scope' for d in request()[1]['decisions'])
    time.sleep(6)
    assert next(t for t in request()[1]['archive'] if t['task_id']=='gate-decision-scope')['lifecycle']['state']=='held'
    gate_resume='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    assert request('/lifecycle',lifecycle('Main','gate-decision-scope',gate_archive['lifecycle']['revision'],'resume',gate_resume))[0]==200
    lifecycle_done(gate_resume)
    gate=wait(lambda:next((d for d in request()[1]['decisions'] if d['task_id']=='gate-decision-scope'),None))
    assert gate['question']=='Scope approval' and gate['description']=='Pick the scope' and gate['state']=='open',gate
    assert backlog_row('gate-decision-scope')[5:7]==['captain','Pick the scope']
    assert not [c for c in calls(home,'tasks-axi') if c[1][0] in ('hold','unhold','done') and c[1][1]=='gate-decision-scope']
    gate_discard='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    assert request('/lifecycle',lifecycle('Main','gate-decision-scope',gate['lifecycle']['revision'],'discard',gate_discard))[0]==200
    lifecycle_done(gate_discard)
    declines=[json.loads(l) for l in (home/'declines.jsonl').read_text().splitlines()]
    assert [d[:2] for d in declines]==[['gate','scope']] and gate_discard in declines[0][2] and 'gate-decision-scope' in declines[0][2],declines
    assert (home/'state/board-inbox/lifecycle'/f'{gate_discard}.decision').read_text()==declines[0][2]
    assert backlog_row('gate-decision-scope')[1]=='done' and not [c for c in calls(home,'tasks-axi') if c[1][:2]==['done','gate-decision-scope']]
    assert {r['state'] for r in sql("select state from decisions where task_id='gate-decision-scope'")}=={'closed'}
    assert not any(d['task_id']=='gate-decision-scope' for d in request()[1]['decisions']) and not any(t['task_id']=='gate-decision-scope' for t in request()[1]['archive'])
    # A hold card whose origin is a listed worker shares the origin's lifecycle:
    # one request archives both rows, and the hold task never resurfaces alone.
    known_decision=next(d for d in request()[1]['decisions'] if d['task_id']=='known-decision-go')
    assert known_decision['lifecycle_task_id']=='known',known_decision
    known_tasks={t['task_id']:t['lifecycle_task_id'] for t in request()[1]['tasks'] if t['task_id'].startswith('known')}
    assert known_tasks=={'known':'known','known-decision-go':'known'},known_tasks
    known_hold='efefefef-efef-4fef-8fef-efefefefefef'
    assert request('/lifecycle',lifecycle('Main','known',known_decision['lifecycle']['revision'],'hold',known_hold))[0]==200
    same=request('/lifecycle',lifecycle('Main','known-decision-go',known_decision['lifecycle']['revision'],'hold','efefefef-efef-4fef-8fef-000000000000'))
    assert same[0]==200 and same[1]['request']['request_id']==known_hold and same[1]['request']['task_id']=='known',same
    lifecycle_done(known_hold)
    held=request()[1]
    assert not [t for t in held['tasks'] if t['task_id'].startswith('known')] and not [d for d in held['decisions'] if d['task_id']=='known-decision-go']
    assert [t['task_id'] for t in held['archive'] if t['task_id'].startswith('known')]==['known']
    assert sql("select task_id from task_lifecycle where task_id like 'known%'")==[{'task_id':'known'}]
    assert backlog_row('known-decision-go')[5:7]==['captain','Go or wait'] and backlog_row('known')[5]=='parked'
    known_resume='efefefef-efef-4fef-8fef-111111111111'
    assert request('/lifecycle',lifecycle('Main','known',next(t for t in held['archive'] if t['task_id']=='known')['lifecycle']['revision'],'resume',known_resume))[0]==200
    lifecycle_done(known_resume)
    back=request()[1]
    assert {t['task_id'] for t in back['tasks'] if t['task_id'].startswith('known')}=={'known','known-decision-go'} and any(d['task_id']=='known-decision-go' for d in back['decisions'])
    # A held hold-card whose origin has no task row keeps its ready answer
    # unrouted without spinning the routing handler, then routes it after Resume.
    orphan=next(d for d in request()[1]['decisions'] if d['task_id']=='orphan-decision-pick')
    assert orphan['lifecycle_task_id']=='orphan-decision-pick',orphan
    orphan_answer=request('/answer',answer('orphan-decision-pick',key='pick',choice='custom',note='Pick the small one',revision=orphan['revision']))[1]['answers'][0]['answer_id']
    orphan_hold='cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd'
    assert request('/lifecycle',lifecycle('Main','orphan-decision-pick',orphan['lifecycle']['revision'],'hold',orphan_hold))[0]==200
    lifecycle_done(orphan_hold)
    accelerate([orphan_answer]);time.sleep(0.6);runs=handler_runs()
    gated=subprocess.run([str(handler),'route','--config',str(config)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    assert gated.returncode==0 and json.loads(gated.stdout)['routed']==0 and json.loads(gated.stdout)['exceptions']==[],(gated.stdout,gated.stderr)
    time.sleep(2.5)
    assert handler_runs()==runs+1,(runs,handler_runs())
    assert sql('select routing_at,consumed_at,cancelled_at from answers where answer_id=?',(orphan_answer,))==[{'routing_at':None,'consumed_at':None,'cancelled_at':None}]
    assert not [d for d in delivered('answers') if d[1]=='orphan']
    orphan_archive=next(t for t in request()[1]['archive'] if t['task_id']=='orphan-decision-pick')
    orphan_resume='cdcdcdcd-cdcd-4dcd-8dcd-dededededede'
    assert request('/lifecycle',lifecycle('Main','orphan-decision-pick',orphan_archive['lifecycle']['revision'],'resume',orphan_resume))[0]==200
    lifecycle_done(orphan_resume)
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(orphan_answer,))[0]['consumed_at'])
    assert [d for d in delivered('answers') if d[1]=='orphan']==[['answers','orphan','--source',f'board:{orphan_answer}']]
    assert 'pick\tPick the small one\tCaptain dashboard' in (home/'hold-input').read_text().splitlines()
    vendor=next(t for t in request()[1]['tasks'] if t['task_id']=='vendor')
    vendor_hold='cccccccc-cccc-4ccc-8ccc-cccccccccccc'
    assert request('/lifecycle',lifecycle('Main','vendor',vendor['lifecycle']['revision'],'hold',vendor_hold))[0]==200
    lifecycle_done(vendor_hold)
    assert backlog_row('vendor')[5:7]==['external','Waiting for the vendor'] and len([c for c in calls(home,'fm-control.sh') if c[1]==['vendor','exit']])==1
    assert not [c for c in calls(home,'tasks-axi') if c[1][0] in ('hold','unhold') and c[1][1]=='vendor']
    with (home/'state/vendor.meta').open('a') as f:f.write('control_relaunch_tx=firstmate\n')
    vendor_archive=next(t for t in request()[1]['archive'] if t['task_id']=='vendor')
    vendor_resume='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
    assert request('/lifecycle',lifecycle('Main','vendor',vendor_archive['lifecycle']['revision'],'resume',vendor_resume))[0]==200
    lifecycle_done(vendor_resume,'failed')
    vendor_archive=next(t for t in request()[1]['archive'] if t['task_id']=='vendor')
    assert vendor_archive['lifecycle']['state']=='held' and 'changed since Bridge stopped it' in vendor_archive['lifecycle']['error'],vendor_archive
    assert not any(t['task_id']=='vendor' for t in request()[1]['tasks'])
    assert not [c for c in calls(home,'fm-control.sh') if c[1][:2]==['vendor','relaunch']]
    assert backlog_row('vendor')[5:7]==['external','Waiting for the vendor'] and not [c for c in calls(home,'tasks-axi') if c[1][:2]==['unhold','vendor']]
    (home/'fail-control').write_text('1')
    vendor_discard='dddddddd-dddd-4ddd-8ddd-eeeeeeeeeeee'
    assert request('/lifecycle',lifecycle('Main','vendor',vendor_archive['lifecycle']['revision'],'discard',vendor_discard))[0]==200
    lifecycle_done(vendor_discard,'failed')
    stuck_discard=next(t for t in request()[1]['archive'] if t['task_id']=='vendor')
    assert stuck_discard['lifecycle']['state']=='discarded' and 'fm-control.sh' in stuck_discard['lifecycle']['error'] and backlog_row('vendor')[1]=='done',stuck_discard
    external('vendor','fixture backlog after failed vendor discard')
    time.sleep(6)
    stuck_discard=next(t for t in request()[1]['archive'] if t['task_id']=='vendor')
    assert 'fm-control.sh' in stuck_discard['lifecycle']['error'],stuck_discard
    (home/'fail-control').unlink()
    vendor_retry='dddddddd-dddd-4ddd-8ddd-ffffffffffff'
    assert request('/lifecycle',lifecycle('Main','vendor',stuck_discard['lifecycle']['revision'],'discard',vendor_retry))[0]==200
    lifecycle_done(vendor_retry)
    assert not any(t['task_id']=='vendor' for t in request()[1]['archive']+request()[1]['tasks'])
    assert len([c for c in calls(home,'fm-control.sh') if c[1]==['vendor','exit']])==3
    passed('Hold and Resume preserve pre-existing holds, a changed worker record blocks Resume, and a failed Discard stop stays visible until a retry succeeds')
    # tasks-axi stays authoritative: external reopen, release, and completion
    # reconcile the Archive on ingest, and a failed relaunch never claims active.
    assert backlog_row('lifecycle')[1]=='done' and sql("select state from task_lifecycle where task_id='lifecycle'")==[{'state':'discarded'}]
    external('lifecycle','fixture backlog reopened lifecycle',state='in_flight',hold=('-','-'))
    wait(lambda:any(t['task_id']=='lifecycle' for t in request()[1]['tasks']))
    lifecycle_row=sql("select * from task_lifecycle where task_id='lifecycle'")[0]
    assert lifecycle_row['state']=='active' and lifecycle_row['error'] is None,lifecycle_row
    wait(lambda:len([d for d in request()[1]['decisions'] if d['task_id']=='lifecycle'])==2)
    rehold='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
    assert request('/lifecycle',lifecycle('Main','lifecycle',lifecycle_row['revision'],'hold',rehold))[0]==200
    lifecycle_done(rehold)
    assert backlog_row('lifecycle')[5:7]==['parked','Held in Bridge Archive']
    external('lifecycle','fixture backlog released lifecycle',hold=('-','-'))
    wait(lambda:not any(t['task_id']=='lifecycle' for t in request()[1]['archive']))
    assert sql("select state,bridge_hold,stopped_meta from task_lifecycle where task_id='lifecycle'")==[{'state':'active','bridge_hold':0,'stopped_meta':None}]
    assert len([d for d in request()[1]['decisions'] if d['task_id']=='lifecycle'])==2
    revision=sql("select revision from task_lifecycle where task_id='lifecycle'")[0]['revision']
    rehold='ffffffff-ffff-4fff-8fff-ffffffffffff'
    assert request('/lifecycle',lifecycle('Main','lifecycle',revision,'hold',rehold))[0]==200
    lifecycle_done(rehold)
    (home/'fail-control').write_text('1')
    failed_resume='12121212-1212-4121-8121-121212121212'
    revision=sql("select revision from task_lifecycle where task_id='lifecycle'")[0]['revision']
    assert request('/lifecycle',lifecycle('Main','lifecycle',revision,'resume',failed_resume))[0]==200
    lifecycle_done(failed_resume,'failed')
    stuck=next(t for t in request()[1]['archive'] if t['task_id']=='lifecycle')
    assert stuck['lifecycle']['state']=='held' and 'fm-control.sh' in stuck['lifecycle']['error'],stuck
    assert backlog_row('lifecycle')[5]=='parked' and not any(t['task_id']=='lifecycle' for t in request()[1]['tasks'])
    (home/'fail-control').unlink()
    retry_resume='13131313-1313-4131-8131-131313131313'
    assert request('/lifecycle',lifecycle('Main','lifecycle',stuck['lifecycle']['revision'],'resume',retry_resume))[0]==200
    lifecycle_done(retry_resume)
    assert next(t for t in request()[1]['tasks'] if t['task_id']=='lifecycle')['lifecycle']['state']=='active' and backlog_row('lifecycle')[5]=='-'
    assert len([c for c in calls(home,'fm-control.sh') if c[1][:2]==['lifecycle','relaunch']])==3
    revision=sql("select revision from task_lifecycle where task_id='lifecycle'")[0]['revision']
    rehold='14141414-1414-4141-8141-141414141414'
    assert request('/lifecycle',lifecycle('Main','lifecycle',revision,'hold',rehold))[0]==200
    lifecycle_done(rehold)
    external('lifecycle','fixture backlog finished lifecycle',state='done',hold=('-','-'))
    wait(lambda:not sql("select 1 from task_lifecycle where task_id='lifecycle'"))
    assert not any(t['task_id']=='lifecycle' for t in request()[1]['archive'])
    assert any(t['task_id']=='lifecycle' for t in request()[1]['tasks'])
    stale_hold='15151515-1515-4151-8151-151515151515';holds_before=len([c for c in calls(home,'tasks-axi') if c[1][:2]==['hold','lifecycle']])
    finished=request('/lifecycle',lifecycle('Main','lifecycle',0,'hold',stale_hold))
    assert finished[0]==409 and 'already complete' in finished[1]['error'],finished
    time.sleep(1)
    assert not sql('select 1 from lifecycle_requests where request_id=?',(stale_hold,)) and not sql("select 1 from task_lifecycle where task_id='lifecycle'")
    assert len([c for c in calls(home,'tasks-axi') if c[1][:2]==['hold','lifecycle']])==holds_before and any(t['task_id']=='lifecycle' for t in request()[1]['tasks'])
    for stale in ('lifecycle','vendor','known'):(home/f'state/{stale}.meta').unlink();(home/f'state/{stale}.status').unlink()
    set_backlog(rows,'fixture backlog after lifecycle')
    passed('ingest reconciles held and discarded work with tasks-axi, and a failed relaunch stays held until a retry succeeds')
    # Queue is durable before handler starts; restart does not lose or duplicate.
    code_,posted,_=request('/answer',answer('alpha',revision=row['revision']));assert code_==200,posted
    aid=posted['answers'][0]['answer_id'];assert request('/answer',answer('alpha',revision=row['revision']))[1]['answers'][0]['answer_id']==aid
    queued=next(d for d in request()[1]['decisions'] if d['task_id']=='alpha' and d['revision']==row['revision'])
    assert queued['state']=='queued' and queued['answer']['choice']=='A' and queued['answer']['note']=='a note',queued
    assert sql('select state from decisions where task_id=? and revision=?',('alpha',row['revision']))[0]['state']=='queued'
    assert request('/answer',{'action':'undo','answer_id':aid})[0]==200
    aid=request('/answer',answer('alpha',revision=row['revision']))[1]['answers'][0]['answer_id']
    stop(kill=True);start();accelerate([aid])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(aid,))[0]['consumed_at'])
    delivered=[d for d in map(json.loads,(home/'deliveries.jsonl').read_text().splitlines()) if d[0]=='alpha']
    assert len(delivered)==1 and delivered[0][:3]==['alpha','--resolve-key','choose'] and '(note: a note)' in delivered[0][-1]
    log=home/'state/board-inbox/answers.jsonl'
    assert not [r for r in map(json.loads,log.read_text().splitlines()) if 'answer_id' in r] if log.exists() else True
    command('answered',aid);passed('authoritative queued payload, undo, dedupe, crash replay, routing, and consumption')
    # A known keyed legacy answer goes to its worker, including its note.
    meta(home,'keyed-legacy','needs-decision [key=reason]: Explain your choice')
    wait(lambda:any(d['task_id']=='keyed-legacy' for d in request()[1]['decisions']))
    r=request('/answer',answer('keyed-legacy',key='reason',choice='custom',note='Keep the current copy'))
    kid=r[1]['answers'][0]['answer_id'];accelerate([kid])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(kid,))[0]['consumed_at'])
    meta(home,'options-please','needs-decision [key=alternatives]: Need options')
    wait(lambda:any(d['task_id']=='options-please' for d in request()[1]['decisions']))
    r=request('/answer',answer('options-please',key='alternatives',choice='request-options',note=''))
    oid=r[1]['answers'][0]['answer_id'];accelerate([oid])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(oid,))[0]['consumed_at'])
    deliveries=list(map(json.loads,(home/'deliveries.jsonl').read_text().splitlines()))
    assert deliveries[-2]==['keyed-legacy','--resolve-key','reason','Keep the current copy'],deliveries[-2]
    assert deliveries[-1]==['options-please',"Captain requested structured options for decision alternatives: register 2-3 distinct alternatives with `bin/fm-board.sh decision Main options-please alternatives --option '...' --rec VALUE --why '...'` and stop; for an unknown factual input, omit --rec and use --why for the recommended verification step."]
    passed('keyed legacy note routes directly; concrete-options request is one exact fixed steer')
    # Three legacy answers are exceptions: one atomic JSONL burst, one source fire.
    for i in range(3):meta(home,f'legacy{i}',f'needs-decision: Explain choice {i}')
    wait(lambda:len([d for d in request()[1]['decisions'] if d['task_id'].startswith('legacy')])==3)
    log=home/'state/board-inbox/answers.jsonl';cursor=home/'state/board-inbox/answers.cursor'
    wait(lambda:cursor.exists() and json.loads(cursor.read_text())['offset']==log.stat().st_size)
    prior_lines=len(log.read_text().splitlines());prior_results=len(list((home/'state/procevent-inbox').glob('*.result')))
    batch=[answer(f'legacy{i}',key='default',choice='custom',note='Please inspect') for i in range(3)]
    response=request('/answers',{'answers':batch});assert response[0]==200,response
    aids=[a['answer_id'] for a in response[1]['answers']];accelerate(aids)
    wait(lambda:len(log.read_text().splitlines())==prior_lines+3)
    wait(lambda:len(list((home/'state/procevent-inbox').glob('*.result')))==prior_results+1)
    time.sleep(1)
    assert len(list((home/'state/procevent-inbox').glob('*.result')))==prior_results+1
    exported=list(map(json.loads,log.read_text().splitlines()[prior_lines:]))
    assert {a['answer_id'] for a in exported}==set(aids)
    assert all(set(('ts','home','task','choice','note','key','answer_id'))<=a.keys() for a in exported)
    # Restore the exact crash-after-publication state; restart must not append duplicates.
    stop();mutate('update answers set exported_at=NULL where error IS NOT NULL');start()
    wait(lambda:all(a['exported_at'] for a in sql('select * from answers where error IS NOT NULL')))
    assert len(log.read_text().splitlines())==prior_lines+3
    for a in aids:command('answered',a)
    passed('batch exceptions produce one JSONL burst/source fire; publication crash replay is idempotent')
    # A backlog hold invokes the authoritative keyed-answer intake.
    held=next(d for d in request()[1]['decisions'] if d['task_id']=='origin-decision-budget')
    r=request('/answer',answer(held['task_id'],key='budget',choice='custom',note='Use the small budget',revision=held['revision']))
    assert r[0]==200,r
    hid=r[1]['answers'][0]['answer_id']
    def ingested_after(previous):
        wait(lambda:sql("select last_ok from ingest_runs where home_id='Main'")[0]['last_ok']!=previous)
        run_=sql("select last_ok,last_error from ingest_runs where home_id='Main'")[0]
        assert run_['last_error'] is None,run_
        return run_['last_ok']
    last_ok=sql("select last_ok from ingest_runs where home_id='Main'")[0]['last_ok']
    blocked=command('decision','Main','origin','budget','--project','CES','--title','Budget approval',
            '--option','A: Approve','--option','B: Reject','--rec','A','--why','Approval unblocks the work.',ok=False)
    assert b'outstanding answer' in blocked.stderr+blocked.stdout,blocked.stderr
    assert not sql("select * from decisions where task_id='origin'")
    last_ok=ingested_after(last_ok)
    assert sql("select state from decisions where task_id='origin-decision-budget' order by revision desc")[0]['state']=='queued'
    accelerate([hid])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(hid,))[0]['consumed_at'])
    assert any(line.startswith('budget\tUse the small budget\t') for line in (home/'hold-input').read_text().splitlines())
    ingested_after(last_ok)
    consumed_hold=sql("select * from decisions where task_id='origin-decision-budget' order by revision desc")[0]
    assert consumed_hold['state']=='consumed' and consumed_hold['revision']==held['revision'],consumed_hold
    passed('backlog hold routes through fm-decision-hold answers')
    passed('registration conflicts with an answered hold; ingest keeps running and never supersedes it')
    # An answer without a note delivers the option wording alone.
    decision('nonote')
    wait(lambda:any(d['task_id']=='nonote' for d in request()[1]['decisions']))
    r=request('/answer',answer('nonote',choice='A',note=''))
    assert r[0]==200,r
    nid=r[1]['answers'][0]['answer_id'];accelerate([nid])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(nid,))[0]['consumed_at'])
    sent=list(map(json.loads,(home/'deliveries.jsonl').read_text().splitlines()))[-1]
    assert sent==['nonote','--resolve-key','choose','Ship it'],sent
    # A registered option may hold newlines or tabs; the hold intake needs one line.
    command('decision','Main',held['task_id'],'budget','--project','CES','--title','Budget approval',
            '--option','A: Approve\nwith\tconditions','--option','B: Reject','--rec','A','--why','Conditions preserve the safety boundary.')
    fresh=next(d for d in request()[1]['decisions'] if d['task_id']==held['task_id'])
    lines=len((home/'hold-input').read_text().splitlines())
    r=request('/answer',answer(held['task_id'],key='budget',choice='A',note='',revision=fresh['revision']))
    assert r[0]==200,r
    tid_=r[1]['answers'][0]['answer_id'];accelerate([tid_])
    wait(lambda:sql('select consumed_at from answers where answer_id=?',(tid_,))[0]['consumed_at'])
    written=(home/'hold-input').read_text().splitlines()
    assert len(written)==lines+1,written
    assert written[-1]=='budget\tApprove with conditions\tCaptain dashboard',written[-1]
    passed('empty notes add no suffix and hold answers stay one field-safe line')
    # Exceptions that need judgment are not delivery failures. A real worker
    # send failure is surfaced separately and firstmate is notified in both cases.
    meta(home,'review-label','needs-decision: Close this item?')
    wait(lambda:any(d['task_id']=='review-label' for d in request()[1]['decisions']))
    r=request('/answer',answer('review-label',key='default',choice='custom',note='Close this'))
    review_id=r[1]['answers'][0]['answer_id'];accelerate([review_id])
    wait(lambda:sql('select error from answers where answer_id=?',(review_id,))[0]['error'])
    review_card=next(d for d in request()[1]['decisions'] if d['task_id']=='review-label')
    assert review_card['answer']['delivery_class']=='review',review_card
    decision('delivery-fail',key='ship')
    (home/'fail-send').write_text('1')
    r=request('/answer',answer('delivery-fail',key='ship',choice='A',note=''))
    delivery_id=r[1]['answers'][0]['answer_id'];accelerate([delivery_id])
    wait(lambda:sql('select error from answers where answer_id=?',(delivery_id,))[0]['error'])
    (home/'fail-send').unlink()
    delivery_card=next(d for d in request()[1]['decisions'] if d['task_id']=='delivery-fail')
    assert delivery_card['answer']['delivery_class']=='delivery-failed',delivery_card
    assert sql('select routing_at from answers where answer_id=?',(review_id,))[0]['routing_at'] is None
    assert sql('select routing_at from answers where answer_id=?',(delivery_id,))[0]['routing_at']
    known={failed_id:sql('select error from answers where answer_id=?',(failed_id,))[0]['error'] for failed_id in (review_id,delivery_id)}
    for failed_id in known:mutate('update answers set error=? where answer_id=?',('KeyError: unexpected',failed_id))
    classes={d['task_id']:d['answer']['delivery_class'] for d in request()[1]['decisions'] if d['task_id'] in ('review-label','delivery-fail')}
    assert classes=={'review-label':'review','delivery-fail':'delivery-failed'},classes
    for failed_id,error in known.items():mutate('update answers set error=? where answer_id=?',(error,failed_id))
    passed('answer exceptions distinguish firstmate review from a true worker delivery failure')
    assert not sql("select * from events where kind='live'")
    command('live','Main','alpha','--url','javascript:bad','--env','production',ok=False)
    command('live','Main','alpha','--url','https://example.com','--env','production',ok=False)
    command('live','Main','alpha','--url','https://example.com','--env','production','--evidence','',ok=False)
    assert not sql("select * from events where kind='live'")
    command('live','Main','alpha','--url','https://example.com','--env','production','--evidence','Verified response')
    live=sql("select * from events where kind='live'")
    assert len(live)==1 and live[0]['verified_at'] and live[0]['evidence']=='Verified response'
    passed('daemon and runner subprocess environments reject inherited path overrides')
    stop()
    # A dead runner must not re-arm every tick, and a live external owner is armed.
    guard='''
import importlib.util,os
spec=importlib.util.spec_from_file_location('fm_board',os.environ['FM_BOARD_CHECK_MODULE'])
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
b=m.Board(os.environ['FM_BOARD_CONFIG'])
calls=[]
b.arm=lambda:calls.append(1)
b.source_owner=lambda:'live'
for _ in range(20):b.maintain_arm()
assert not calls and b.armed_now(),'a live external owner is armed without churn'
b.source_owner=lambda:'none'
b.arm_next=0
for _ in range(20):b.maintain_arm()
assert len(calls)==1 and not b.armed_now(),calls
for _ in range(15):
 b.arm_next=0;b.maintain_arm()
assert len(calls)==16 and b.arm_delay==60,(calls,b.arm_delay)
# A freshly booted host (CI VM) has a monotonic clock far below the 900 s
# reconcile interval; the first pass must still be a full reconcile.
m.time.monotonic=lambda:120.0
seen=[]
def ingest(only=None,reconcile=False):seen.append(reconcile);b.stop.set()
b.ingest=ingest
b.dirty.set();b.ingest_loop()
assert seen==[True],seen
assert b.stale_after==120
b.age=lambda value:100
assert not any(h['stale'] for h in b.version()['homes']) and all(v==100 for v in b.health()['ingest_age_s'].values())
b.stale_after=90
assert all(h['stale'] for h in b.version()['homes']) and not b.health()['ok']
import json,pathlib,tempfile
for bad in (0,86401,'120',12.5):
    with tempfile.NamedTemporaryFile('w',suffix='.json',dir=pathlib.Path(os.environ['FM_BOARD_CONFIG']).parent,delete=False) as f:
        json.dump(dict(json.loads(pathlib.Path(os.environ['FM_BOARD_CONFIG']).read_text()),stale_after_s=bad),f)
    try:
        m.Board(f.name)
    except m.Invalid as e:
        assert 'stale_after_s' in str(e),e
    else:
        raise AssertionError(bad)
    finally:
        os.unlink(f.name)
'''
    fixture_boundary()
    check=subprocess.run([sys.executable,'-c',guard],env=dict(env,FM_BOARD_CHECK_MODULE=str(fixture/'bin/fm-board.py')),
                         stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
    assert check.returncode==0,check.stderr.decode()
    passed('re-arming backs off, a live external owner is armed, fresh boot reconciles, stale_after_s is validated and honored')
    for _ in range(8):backup=json.loads(command('backup').stdout)['backup']
    assert len(list((home/'state/backups').glob('board-*.sqlite')))==7
    expected=rev()
    for suffix in ('','-wal','-shm'):
        p=pathlib.Path(str(home/'state/board.sqlite')+suffix)
        if p.exists():p.unlink()
    shutil.copy2(backup,home/'state/board.sqlite');assert rev()==expected
    command('ingest','--once');passed('verified live registration and VACUUM backup restore')
    # The replaced private source used a plain integer cursor and records with
    # no UUID. Preserve those records as exceptions while exporting new rows.
    cursor=home/'state/board-inbox/answers.cursor'
    # A broken cursor is a source failure: no captured result, no wake, only an
    # honest /healthz reason until the cursor is repaired; then the source re-arms.
    start()
    wait(lambda:json.loads(cursor.read_text())['offset']==log.stat().st_size,30)
    good=cursor.read_text();results=len(list((home/'state/procevent-inbox').glob('*.result')))
    req=urllib.request.Request(f'http://localhost:{port}/events',headers={'Authorization':'Bearer '+secret})
    source_stream=urllib.request.urlopen(req,timeout=15)
    initial=b''
    while b'\n\n' not in initial:initial+=source_stream.readline()
    cursor.write_text(str(len(log.read_bytes())+10))
    wait(lambda:request('/healthz')[1]['answers_armed'] is False and 'cursor' in (request('/healthz')[1]['answers_error'] or ''))
    _,broken,_=request()
    assert broken['answers_armed'] is False and 'cursor' in broken['answers_error']
    deadline=time.monotonic()+30
    while True:
        pushed=b''
        while b'\n\n' not in pushed:pushed+=source_stream.readline()
        data=next((line[6:] for line in pushed.splitlines() if line.startswith(b'data: ')),b'{}')
        pulse=json.loads(data)
        if pulse.get('answers_armed') is False and 'cursor' in (pulse.get('answers_error') or ''):break
        assert time.monotonic()<deadline,pulse
    source_stream.close()
    mutate("update tasks set current_state='failed' where task_id='external'")
    chrome=next((p for p in (shutil.which('google-chrome'),shutil.which('google-chrome-stable'),shutil.which('chromium'),shutil.which('chromium-browser'),'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome') if p and pathlib.Path(p).is_file()),None)
    if os.environ.get('FM_BOARD_EXTERNAL_BROWSER')=='1':
        proof=root/'external-browser-complete'
        print('external-browser-fixture '+json.dumps({'url':f'http://localhost:{port}/?k={secret}',
            'root':str(root),'complete':str(proof)}),flush=True)
        deadline=time.monotonic()+900
        while not proof.exists() and time.monotonic()<deadline:
            assert daemon.poll() is None,'synthetic browser daemon exited'
            time.sleep(.2)
        assert proof.exists(),'external browser proof timed out'
        passed('external browser proof completed against the synthetic fixture')
    elif os.environ.get('FM_BOARD_BROWSER_TEST')=='1' and chrome:
        sizes=[('operator',os.environ['FM_BOARD_BROWSER_SIZE'])] if os.environ.get('FM_BOARD_BROWSER_SIZE') else [('desktop','1440,1000'),('phone','390,844')]
        for label,browser_size in sizes:
            assert re.fullmatch(r'[1-9][0-9]{1,3},[1-9][0-9]{1,3}',browser_size),browser_size
            rendered=subprocess.run([chrome,'--headless=new','--disable-gpu','--no-sandbox','--timeout=8000','--virtual-time-budget=4000',
                '--window-size='+browser_size,'--user-data-dir='+str(root/f'chrome-profile-{label}'),'--dump-dom',f'http://localhost:{port}/?k={secret}&browser-test=1'],
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
            assert rendered.returncode==0,rendered.stderr.decode()[-1000:]
            import html
            match=re.search(rb'<pre id="bridge-test-result">(.*?)</pre>',rendered.stdout,re.S)
            assert match,rendered.stdout[-2000:]
            observed=json.loads(html.unescape(match.group(1).decode()))
            assert observed.get('error') is None,observed
            assert observed['horizontalOverflow'] is False,observed
            assert observed['preselected'] is False,observed
            assert observed['liveProject']=='CES' and observed['visibleAfterMove'],observed
            assert observed['draftAfterMove']=={'choice':'A','note':'Unsaved local draft'} and observed['draftLeftBehind'] is None,observed
            migration=observed['migration']
            assert migration['cards']==2 and len(set(migration['radioNames']))==2,observed
            assert migration['selected']==['A','B'] and migration['confirm']==['Confirm: Ship it','Confirm: Wait'],observed
            assert migration['checkedOpen']==2 and migration['batch'].startswith('Submit drafted (2 of '),observed
            assert migration['records']==['A','B'] and migration['rebuilt']==[['A','A'],['B','B']],observed
            assert observed['distinctDuplicateCards']==2 and observed['distinctRadioGroups']==2,observed
            assert observed['selected']=='B' and observed['note']=='Other device chose wait',observed
            assert observed['savedDraft'] is None,observed
            assert observed['state'].startswith('Queued') and observed['health'].startswith('Answers: '),observed
            assert observed['description']=='This decides whether the change ships now or waits for another check.',observed
            assert observed['descriptionSize']=='14px' and observed['descriptionWeight']=='400',observed
            assert observed['registeredOptions'][0].startswith('Ship itRecommended · Small reversible change'),observed
            assert observed['legacyOptions']==['Write my own answer','Ask firstmate for 2-3 concrete options'],observed
            assert observed['legacyNotice']=='Concrete options and a recommendation are still being prepared.',observed
            assert observed['factualPreselected'] is False,observed
            assert observed['factualGuidance']=='Recommended next step · Verify the current schedule before choosing.',observed
            assert observed['reviewState']=='Sent to firstmate to review',observed
            assert observed['deliveryState']=='Could not deliver - firstmate notified',observed
            assert observed['decisionLifecycle']==['Hold','Discard'] and observed['taskLifecycle']==['Hold','Discard'],observed
            assert observed['archiveLifecycle']==['Discard','Resume'] and observed['archiveTitle']=='Archive',observed
            assert not observed['healthHidden'] and 'red' in observed['dot'].split(),observed
            assert observed['failedBorderWidth']=='3px' and observed['failedBorderColor']!='rgba(0, 0, 0, 0)',observed
            browser_answer=sql("select answer_id from answers where task_id='instant' and cancelled_at IS NULL")[0]['answer_id']
            assert request('/answer',{'action':'undo','answer_id':browser_answer})[0]==200
            passed(f'rendered {label} {browser_size}: failed styling, source health, authoritative answer, lifecycle actions, and submitted draft clearing')
    elif os.environ.get('FM_BOARD_BROWSER_TEST')=='1':
        print('skip: no chrome',flush=True)
    else:
        print('skip: browser check disabled; set FM_BOARD_BROWSER_TEST=1',flush=True)
    time.sleep(3)
    assert len(list((home/'state/procevent-inbox').glob('*.result')))==results
    assert 'answers source: legacy cursor' in (home/'state/logs/board.log').read_text()
    cursor.write_text(good)
    wait(lambda:request('/healthz')[1]['answers_armed'] and request('/healthz')[1]['answers_error'] is None,45)
    assert len(list((home/'state/procevent-inbox').glob('*.result')))==results
    stop()
    passed('source failure reaches API state and SSE without a captured result')
    cursor.write_text(str(json.loads(cursor.read_text())['offset']))
    prior_lines=len(log.read_text().splitlines())
    with log.open('a') as f:f.write(json.dumps({'ts':'legacy','home':'Main','task':'old','choice':'custom','note':'Older answer'})+'\n')
    ino=log.stat().st_ino
    start()
    wait(lambda:len(list((home/'state/procevent-inbox').glob('*.result')))==results+1)
    wait(lambda:isinstance(json.loads(cursor.read_text()),dict))
    r=request('/answer',{'action':'correction','answer_id':aid,'note':'Review this correction'})
    assert r[0]==200,r
    cid=sql("select answer_id from answers where action='correction'")[0]['answer_id'];accelerate([cid])
    wait(lambda:sql('select exported_at from answers where answer_id=?',(cid,))[0]['exported_at'])
    assert len(log.read_text().splitlines())==prior_lines+2 and log.stat().st_ino==ino
    passed('legacy integer cursor and id-less lines migrate without losing or blocking answers')
except Exception:
    for log in (root/'daemon.log',home/'state/logs/board.log',home/'state/logs/board-answers.log'):
        if log.exists():print(log.name+': '+log.read_text()[-1800:],file=sys.stderr)
    raise
finally:
    stop()
    cleanup_env=dict(env)
    for key in ('FM_STATE_OVERRIDE','FM_DATA_OVERRIDE','FM_PROJECTS_OVERRIDE'):
        cleanup_env.pop(key,None)
    assert pathlib.Path(cleanup_env['FM_HOME']).resolve()==home
    cleanup=subprocess.run([str(pe),'sweep-home'],env=cleanup_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    assert cleanup.returncode==0,cleanup.stderr.decode()
    audit=[json.loads(line) for line in (root/'isolation.jsonl').read_text().splitlines()]
    executed=[record for record in audit if record['allowed']]
    assert any(r['command'][0]=='start' for r in executed)
    assert any(r['command'][0]=='register' for r in executed)
    sweeps=[r for r in executed if r['command'][0]=='sweep-home']
    assert len(sweeps)==1 and sweeps[0]['home']==str(home)
    assert all(all(v is None for v in r['overrides'].values()) for r in executed if r['command'][0]!='retire')
    assert all(r['overrides']['FM_STATE_OVERRIDE']==str(home/'state') for r in executed if r['command'][0]=='retire')
    assert sentinel_state()==sentinel_before
    out.close()
    passed('all cleanup uses only fixture FM_HOME; all three path overrides stripped; sentinel unchanged')
PY
pass 'dashboard integration suite'
