import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
try {
  await db.exec(`
    create role authenticated; create role anon;
    create schema auth;
    alter default privileges in schema public grant all on tables to anon, authenticated;
    alter default privileges in schema public grant all on functions to anon, authenticated;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
    $$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
  `);
  for (const name of ['202608040001_initial', '202608040002_todoist_import', '202608080001_references', '202608310001_purge_trash', '202609110001_safe_purge', '202609110002_ledger_privileges', '202609110003_task_fingerprints']) {
    await db.exec(await readFile(new URL(`../../supabase/migrations/${name}.sql`, import.meta.url), 'utf8'));
  }
  for (const role of ['anon', 'authenticated']) {
    for (const privilege of ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) {
      assert.equal((await db.query('select has_table_privilege($1, $2, $3) as allowed',
        [role, 'public.purged_entities', privilege])).rows[0].allowed, false, `${role} cannot ${privilege} ledger`);
    }
  }
  assert.equal((await db.query("select has_table_privilege('authenticated','public.purged_entities','SELECT') as allowed")).rows[0].allowed, true);
  assert.equal((await db.query("select has_table_privilege('anon','public.purged_entities','SELECT') as allowed")).rows[0].allowed, false);
  for (const name of ['guard_purged_entity', 'remember_purged_entity', 'purge_trash', 'purge_trash_v2']) {
    assert.equal((await db.query('select has_function_privilege($1, $2, $3) as allowed',
      ['anon', `public.${name}()`, 'EXECUTE'])).rows[0].allowed, false, `anon cannot execute ${name}`);
    assert.equal((await db.query('select has_function_privilege($1, $2, $3) as allowed',
      ['authenticated', `public.${name}()`, 'EXECUTE'])).rows[0].allowed,
      name.startsWith('purge_trash'), `authenticated can execute only the purge RPCs`);
  }
  // Supabase grants are normally supplied by the platform.
  await db.exec(`grant select, insert, update on public.tasks, public.projects, public.project_sections, public.sync_operations to authenticated;
    insert into auth.users values ('00000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-000000000002');
    set role authenticated;
    select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);`);
  const owner = '00000000-0000-4000-8000-000000000001';
  const taskId = '00000000-0000-4000-8000-000000000010';
  const projectId = '00000000-0000-4000-8000-000000000020';
  const sectionId = '00000000-0000-4000-8000-000000000030';
  const task = {id: taskId, user_id: owner, title: 'Synthetic private text', status: 'available', position: 1024, created_at: 1, updated_at: 1, logical_version: 1, device_id: owner, deleted_at: 1};
  const insertTask = () => db.query(`select public.merge_task($1::jsonb)`, [JSON.stringify(task)]);
  await insertTask();
  const fingerprint = async () => ({rows: (await db.query('select public.todo_task_fingerprints_v1() as result')).rows[0].result});
  const expectedDigest = createHash('sha256').update(`${taskId}:1:${owner};`).digest('hex');
  assert.deepEqual((await fingerprint()).rows, [{bucket: '00', fingerprint: expectedDigest}]);
  assert.equal((await db.query("select has_function_privilege('anon','public.todo_task_fingerprints_v1()','EXECUTE') as allowed")).rows[0].allowed, false);
  await db.exec('begin;');
  await db.query('update public.tasks set logical_version = 2 where id = $1', [taskId]);
  assert.notEqual((await fingerprint()).rows[0].fingerprint, expectedDigest, 'version change affects digest');
  await db.exec('rollback;');
  assert.equal((await fingerprint()).rows[0].fingerprint, expectedDigest, 'rollback restores digest');
  await db.query(`insert into public.projects(id,user_id,name,position,is_archived,logical_version,device_id) values($1,$2,'Synthetic project',1024,true,1,$2)`, [projectId, owner]);
  await db.query(`insert into public.project_sections(id,user_id,project_id,name,position,is_archived,logical_version,device_id) values($1,$2,$3,'Synthetic section',1024,true,1,$2)`, [sectionId,owner,projectId]);
  await db.exec('begin; select public.purge_trash_v2(); rollback;');
  assert.equal((await db.query('select * from public.purged_entities')).rows.length, 0, 'rollback removes ledger');
  assert.equal((await db.query('select * from public.tasks')).rows.length, 1, 'rollback preserves task');
  const purged = (await db.query('select public.purge_trash_v2() as result')).rows[0].result;
  assert.deepEqual(purged, {tasks: 1, sections: 1, projects: 1});
  assert.deepEqual((await fingerprint()).rows, [], 'purge removes bucket');
  const ledger = (await db.query('select * from public.purged_entities')).rows;
  assert.equal(ledger.length, 3);
  assert.ok(!JSON.stringify(ledger).includes('Synthetic'), 'ledger has no content');
  task.deleted_at = null; task.logical_version = 999;
  await assert.rejects(insertTask, /todo_entity_purged/, 'old merge RPC cannot resurrect a UUID');
  await assert.rejects(() => db.query(`insert into public.projects(id,user_id,name,position,logical_version,device_id) values($1,$2,'Old project',1024,999,$2)`, [projectId,owner]), /todo_entity_purged/);
  await assert.rejects(() => db.query(`insert into public.project_sections(id,user_id,project_id,name,position,logical_version,device_id) values($1,$2,$3,'Old section',1024,999,$2)`, [sectionId,owner,projectId]), /todo_entity_purged/);
  await assert.rejects(() => db.query('delete from public.purged_entities'), /permission denied/);
  assert.deepEqual((await db.query('select public.purge_trash() as result')).rows[0].result, {tasks: 0, sections: 0, projects: 0}, 'legacy RPC remains idempotent');
  await db.exec(`select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false)`);
  assert.equal((await db.query('select * from public.purged_entities')).rows.length, 0, 'RLS isolates ledger');
  await db.exec("select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false)");
  task.id = 'ff000000-0000-4000-8000-000000000001';
  await insertTask();
  await db.exec("select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false)");
  assert.deepEqual((await fingerprint()).rows, [], 'fingerprints isolate account metadata');
  await db.exec('reset role;');
  await db.query('delete from auth.users where id = $1', [owner]);
  assert.equal((await db.query('select * from public.purged_entities')).rows.length, 0, 'account deletion clears ledger');
  console.log('Safe purge: migrations, rollback, task/project/section resurrection, RLS, inherited privileges/TRUNCATE, content minimization, replay and account deletion passed.');
} finally { await db.close(); }
