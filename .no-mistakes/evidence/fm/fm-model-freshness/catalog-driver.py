import os,json,subprocess,datetime,pathlib
root=pathlib.Path.cwd(); home=root/'.validation/codex'; home.mkdir(exist_ok=True)
env=dict(os.environ,CODEX_HOME=str(home),HOME=str(root/'.h/user'))
def run(args):
 p=subprocess.run(args,env=env,text=True,capture_output=True,timeout=20)
 assert p.returncode==0,(args,p.stderr)
 return p
bundle=json.loads(run(['codex','debug','models','--bundled']).stdout)
print('CLI:',run(['codex','--version']).stdout.strip())
print('Bundled listed models:',json.dumps([m['slug'] for m in bundle['models'] if m['visibility']=='list']))
fresh=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def check(name,pin,expected,cache,mode='upgrade',notice=None):
 f=home/'models_cache.json'
 if cache is None: f.unlink(missing_ok=True)
 elif isinstance(cache,str): f.write_text(cache)
 else: f.write_text(json.dumps(cache))
 args=['bash','bin/fm-model-freshness.sh','codex',pin,'--launch',name,mode]
 p=run(args)
 print('\n$', ' '.join(args));print('stdout:',p.stdout.strip());print('stderr:',p.stderr.strip())
 assert p.stdout.strip()==expected,(name,expected,p.stdout)
 assert len(p.stderr.splitlines())<=1
 if notice: assert notice in p.stderr
check('bundled-sol','gpt-6-sol','gpt-6.1-sol',{'fetched_at':fresh,'models':[]},notice='for this launch')
check('bundled-astra','gpt-5-astra','gpt-6-astra',{'fetched_at':fresh,'models':[]},notice='for this launch')
entries=[{'slug':x,'visibility':v} for x,v in [('gpt-6.9-sol','list'),('gpt-6.10-sol','list'),('gpt-99-sol','hide'),('gpt-999-astra','list')]]
check('fresh-higher-cache','gpt-6.1-sol','gpt-6.10-sol',{'fetched_at':fresh,'models':entries})
check('explicit-pin','gpt-6.1-sol','gpt-6.1-sol',{'fetched_at':fresh,'models':entries},'advisory','Keeping the explicit model pin')
for name,cache,notice in [('stale',{'fetched_at':'2000-01-01T00:00:00Z','models':entries},'cache age is'),('undated',{'models':entries},'cache age is'),('missing',None,'could not be read or parsed'),('malformed','{bad','could not be read or parsed')]:
 check(name,'gpt-6-sol','gpt-6.1-sol',cache,notice=notice)
check('no-downgrade','gpt-999-sol','gpt-999-sol',{'fetched_at':fresh,'models':entries})
print('\nAll real CLI comparisons met independently specified model and one-line notice expectations.')
