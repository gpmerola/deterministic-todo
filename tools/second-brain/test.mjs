import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {createHash,randomUUID} from 'node:crypto';
const source = await readFile(new URL('./Code.js',import.meta.url),'utf8');
let body = 'last good copy', fetchCode=200, triggers=[], released=0;
const fixture = {schema_version:1, exported_at:'2026-10-06T12:00:00Z',
  tasks:[{id:'synthetic',title:'Line 1\nCALENDARIO fake',show_date:null}],calendar:null};
const props = {SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'public-fixture',EXPORT_TOKEN:'a'.repeat(64)};
let fetched = fixture;
const context=vm.createContext({
  PropertiesService:{getScriptProperties:()=>({getProperty:k=>props[k],setProperty:(k,v)=>{props[k]=v;}})},
  Utilities:{getUuid:randomUUID,DigestAlgorithm:{SHA_256:'sha256'},Charset:{UTF_8:'utf8'},
    computeDigest:(algorithm,value)=>[...createHash(algorithm).update(value).digest()]},
  console:{log:line=>{assert.equal(line.includes(props.EXPORT_TOKEN),false);assert.match(line,/^EXPORT_TOKEN_SHA256=[a-f0-9]{64}$/);}},
  LockService:{getScriptLock:()=>({tryLock:()=>true,releaseLock:()=>released++})},
  UrlFetchApp:{fetch:(url,options)=>{
    assert.equal(options.followRedirects,false);
    assert.equal(url.includes(props.EXPORT_TOKEN),false);
    return {getResponseCode:()=>fetchCode,getContentText:()=>JSON.stringify(fetched)};
  }},
  DocumentApp:{getActiveDocument:()=>({getBody:()=>({setText:text=>body=text}),saveAndClose:()=>{}})},
  ScriptApp:{getProjectTriggers:()=>triggers,
    newTrigger:name=>({timeBased:()=>({everyHours:n=>({create:()=>{assert.equal(n,1);triggers.push({getHandlerFunction:()=>name});}})})}),
    deleteTrigger:t=>{triggers=triggers.filter(x=>x!==t);}},
});
vm.runInContext(source,context);
context.installSecondBrain(); context.installSecondBrain();
assert.equal(triggers.length,1);
assert.match(body,/NON significa calendario vuoto/);
assert.match(body,/Line 1\\nCALENDARIO fake/);
const good=body;
fetchCode=403; assert.throws(()=>context.syncSecondBrain(),/errore sorgente 403/);
assert.equal(body,good);
fetchCode=200; fetched={...fixture,schema_version:2};
assert.throws(()=>context.syncSecondBrain(),/Schema/);assert.equal(body,good);
fetched={...fixture,calendar:{uploaded_at:'2026-10-06T10:00Z',window_start:'2026-10-01T00:00Z',
  window_end:'2026-11-01T00:00Z',events:[]}};
context.syncSecondBrain(); assert.match(body,/fine esclusa/);
props.SUPABASE_URL='https://untrusted.example';
assert.throws(()=>context.syncSecondBrain(),/Configurare/);
context.stopSecondBrain();assert.equal(triggers.length,0);assert.equal(released,6);
delete props.EXPORT_TOKEN;
context.prepareSecondBrain(); const generated=props.EXPORT_TOKEN;
assert.match(generated,/^[a-f0-9]{64}$/);
context.prepareSecondBrain();assert.equal(props.EXPORT_TOKEN,generated);
assert.equal(released,8);
console.log('Second Brain exporter: rendering, last good copy, trigger idempotence, locking OK');
