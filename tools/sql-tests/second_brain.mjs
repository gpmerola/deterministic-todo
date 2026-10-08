import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

const db = new PGlite();
try {
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql as $$select null::uuid$$;
    alter default privileges in schema public grant all on tables to anon, authenticated;
    alter default privileges in schema public grant all on functions to anon, authenticated;`);
  for (const name of ['202608040001_initial', '202610040001_agenda_mirror', '202610060001_second_brain_export']) {
    await db.exec(await readFile(new URL(`../../supabase/migrations/${name}.sql`, import.meta.url), 'utf8'));
  }
  const a = '00000000-0000-4000-8000-000000000001';
  const b = '00000000-0000-4000-8000-000000000002';
  const token = 'a'.repeat(64); // Synthetic, never a production credential.
  await db.query('insert into auth.users values ($1),($2)', [a, b]);
  for (const [owner, id, status, deleted] of [[a,a,'available',null], [b,b,'available',null],
    [a,'00000000-0000-4000-8000-000000000003','completed',null],
    [a,'00000000-0000-4000-8000-000000000004','available',1]]) {
    await db.query(`insert into public.tasks(id,user_id,title,notes,status,position,created_at,updated_at,
      deleted_at,logical_version,device_id) values ($1,$2,'Synthetic','DO NOT EXPORT',$3,0,1,1,$4,1,$2)`,
      [id, owner, status, deleted]);
  }
  await db.query(`insert into public.second_brain_export_grants(user_id,token_hash,expires_at)
    values ($1,sha256(convert_to($2,'UTF8')),now()+interval '1 day')`, [a,token]);
  await db.exec('set role anon');
  const call = () => db.query('select public.second_brain_export_v1() as snapshot');
  const header = value => db.query("select set_config('request.headers',$1,false)",
    [JSON.stringify({'x-second-brain-token':value})]);
  await assert.rejects(call(), /not authorized/);
  await header('b'.repeat(64)); await assert.rejects(call(), /not authorized/);
  await header(token);
  const first = (await call()).rows[0].snapshot;
  assert.equal(first.tasks.length, 1); assert.equal(first.tasks[0].id,a);
  assert.equal(first.calendar,null);
  assert.equal(JSON.stringify(first).includes('DO NOT EXPORT'),false);
  await assert.rejects(db.query('select * from public.second_brain_export_grants'));
  await assert.rejects(db.query('delete from public.second_brain_export_grants'));
  await db.exec('reset role');
  await db.query(`insert into public.agenda_snapshots(user_id,device_id,window_start,window_end)
    values ($1,'synthetic','2026-10-01','2026-11-01')`,[a]);
  await db.query(`insert into public.agenda_events(user_id,instance_key,calendar_keys,title,starts_at,ends_at,
    all_day,start_date,end_date,meeting_url) values
    ($1,'one','[]','Synthetic all-day','2026-10-07','2026-10-09',true,'2026-10-07','2026-10-09','PRIVATE')`,[a]);
  await db.exec('set role authenticated');
  await assert.rejects(db.query('select * from public.second_brain_export_grants'));
  const second = (await call()).rows[0].snapshot;
  assert.equal(second.calendar.events[0].end_date,'2026-10-09');
  assert.equal(second.calendar.events[0].meeting_url,undefined);
  await db.exec(`reset role; update public.second_brain_export_grants set expires_at=now()-interval '1 second'; set role anon`);
  await assert.rejects(call(), /not authorized/);
  await db.exec('reset role; delete from public.second_brain_export_grants; set role anon');
  await assert.rejects(call(), /not authorized/);
  console.log('Second Brain SQL: isolation, projection, expiration, revocation OK');
} finally { await db.close(); }
