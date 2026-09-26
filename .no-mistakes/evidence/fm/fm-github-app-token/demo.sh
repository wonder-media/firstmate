#!/usr/bin/env bash
# End-to-end CLI demo of bin/fm-github-app-token.sh with fake gh/gh-axi and a stubbed GitHub mint endpoint.
set -u
W=$1; H=$W/bin/fm-github-app-token.sh
D=$(mktemp -d); mkdir -p $D/home/config $D/home/state $D/bin $D/secret
cat > $D/bin/gh <<'SH'
#!/usr/bin/env bash
who=captain; [ "${GH_TOKEN:-}" = "${FM_DEMO_PERSONAL:-x}" ] || who="app(${GH_TOKEN:0:8}...)"
echo "[fake gh] $* as=$who"
SH
cat > $D/bin/gh-axi <<'SH'
#!/usr/bin/env bash
if [ "${GH_TOKEN:-}" != "$FM_DEMO_PERSONAL" ]; then
  case "$*" in *other/repo*) printf 'error: Repository "other/repo" not found\ncode: REPO_NOT_FOUND\n'; exit 1;; esac
  case "$*" in *conflict*) echo 'error: Pull request is not mergeable: merge conflict'; exit 1;; esac
fi
echo "[fake gh-axi] $* as=$([ "$GH_TOKEN" = "$FM_DEMO_PERSONAL" ] && echo captain || echo app)"
SH
chmod +x $D/bin/*
export PATH=$D/bin:$PATH FM_HOME=$D/home GH_TOKEN=personal-captain-token FM_DEMO_PERSONAL=personal-captain-token
echo '$ # 1) no pointer file -> unchanged captain behavior'
$H run-safe gh pr view 22
node -e 'const{generateKeyPairSync:g}=require("crypto");const{privateKey:k,publicKey:p}=g("rsa",{modulusLength:2048});require("fs").writeFileSync(process.argv[1]+"/app.pem",k.export({type:"pkcs8",format:"pem"}),{mode:0o600});require("fs").writeFileSync(process.argv[1]+"/pub.pem",p.export({type:"spki",format:"pem"}))' $D/secret
printf '{"app_id":123,"installation_id":456,"private_key_file":"app.pem"}\n' > $D/secret/app.json; chmod 600 $D/secret/app.json
echo "$D/secret/app.json" > $D/home/config/github-app-credentials
cat > $D/stub.js <<JS
const https=require('https'),{EventEmitter}=require('events'),crypto=require('crypto'),fs=require('fs');
https.request=(o,cb)=>{const r=new EventEmitter();r.destroy=()=>{};r.end=()=>{
 const [h,p,s]=o.headers.Authorization.slice(7).split('.');
 const ok=crypto.verify('RSA-SHA256',Buffer.from(h+'.'+p),fs.readFileSync('$D/secret/pub.pem'),Buffer.from(s,'base64url'));
 fs.appendFileSync('$D/mint.log','POST https://'+o.hostname+o.path+' alg='+JSON.parse(Buffer.from(h,'base64url')).alg+' iss='+JSON.parse(Buffer.from(p,'base64url')).iss+' RS256-signature-valid='+ok+'\n');
 const res=new EventEmitter();res.statusCode=ok?201:401;res.setEncoding=()=>{};cb(res);
 res.emit('data',JSON.stringify({token:'ghs_demoInstallationToken0123456789',expires_at:new Date(Date.now()+3600e3).toISOString()}));res.emit('end');};return r;};
JS
echo; echo '$ # 2) pointer set -> helper mints RS256 installation token, runs gh as App'
NODE_OPTIONS="--require $D/stub.js" $H run-safe gh pr view 22
cat $D/mint.log
echo "cache mode: $(stat -f %Lp $D/home/state/github-app-installation-token.json 2>/dev/null || stat -c %a $D/home/state/github-app-installation-token.json)"
echo; echo '$ # 3) second call reuses cache (no new mint)'
NODE_OPTIONS="--require $D/stub.js" $H run-safe gh pr view 22; echo "mint count: $(wc -l < $D/mint.log | tr -d ' ')"
echo; echo '$ # 4) gh-axi merge in repo App cannot reach -> one retry on captain login'
$H run-safe gh-axi pr merge 7 --repo other/repo; echo "rc=$?"
echo; echo '$ # 5) real merge conflict -> real error, no retry'
$H run-safe gh-axi pr merge 8 --repo conflict/repo; echo "rc=$?"
echo; echo '$ # 6) gh project is refused (Projects v2 stays on captain login)'
$H run-safe gh project item-list 1; echo "rc=$?"
echo; echo '$ # 7) broken credentials -> one warning, captain login'
rm $D/home/state/github-app-installation-token.json; echo '{}' > $D/secret/app.json
$H run-safe gh pr view 22; echo "rc=$?"
echo; echo '$ # 8) token material in repo / argv?'
grep -rl ghs_demoInstallationToken $W 2>/dev/null || echo "token not found in worktree"
rm -rf $D
