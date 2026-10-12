import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// Postgres side of the v2 fingerprint contract. The same synthetic fixture is
// signed by SQLite and the Dart reference in test/task_fingerprints_v2_test.dart.
const fixture = JSON.parse(await readFile(new URL('../../test/fixtures/task_fingerprint_v2.json', import.meta.url), 'utf8'));
const db = new PGlite();
try {
  await db.exec(`
    create role authenticated; create role anon;
    create schema auth;
    alter default privileges in schema public grant all on functions to anon, authenticated;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
    $$;
    grant usage on schema auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
  `);
  for (const name of ['202608040001_initial', '202608040002_todoist_import', '202608080001_references', '202608310001_purge_trash', '202609110001_safe_purge', '202609110002_ledger_privileges', '202609110003_task_fingerprints', '202609110004_sync_overview', '202610120001_task_fingerprints_v2']) {
    await db.exec(await readFile(new URL(`../../supabase/migrations/${name}.sql`, import.meta.url), 'utf8'));
  }
  const owner = '00000000-0000-4000-8000-000000000001';
  const other = '00000000-0000-4000-8000-000000000002';
  await db.query('insert into auth.users values ($1), ($2)', [owner, other]);
  for (const row of fixture.rows) {
    await db.query('insert into public.tasks select * from jsonb_populate_record(null::public.tasks, $1::jsonb)', [JSON.stringify({...row, user_id: owner})]);
  }
  for (const name of ['todo_task_fingerprints_v2', 'todo_sync_overview_v2']) {
    assert.equal((await db.query('select has_function_privilege($1, $2, $3) as allowed', ['anon', `public.${name}()`, 'EXECUTE'])).rows[0].allowed, false, `anon cannot execute ${name}`);
    assert.equal((await db.query('select has_function_privilege($1, $2, $3) as allowed', ['authenticated', `public.${name}()`, 'EXECUTE'])).rows[0].allowed, true);
  }
  await db.exec(`grant select, update on public.tasks, public.projects, public.project_sections to authenticated; set role authenticated;
    select set_config('request.jwt.claim.sub','${owner}',false);`);
  const v2 = async () => (await db.query('select public.todo_task_fingerprints_v2() as result')).rows[0].result;
  const overview = async () => (await db.query('select public.todo_sync_overview_v2() as result')).rows[0].result;
  const v1Overview = (await db.query('select public.todo_sync_overview_v1() as result')).rows[0].result;
  assert.deepEqual(await v2(), fixture.expected, 'Postgres matches the shared fixture digests');
  const both = await overview();
  assert.equal(both.schema, 2);
  assert.deepEqual(both.tasks, fixture.expected);
  for (const table of ['projects', 'project_sections', 'purged_entities']) assert.equal(both[table], v1Overview[table]);
  // «hinge»: content cleared at an equal version changes only its bucket.
  await db.exec('begin;');
  await db.query(`update public.tasks set show_date = '2026-10-13', recurrence = 'every day' where id = $1`, [fixture.rows[3].id]);
  const changed = await v2();
  assert.equal(changed[0].fingerprint, fixture.expected[0].fingerprint, 'other buckets unchanged');
  assert.notEqual(changed[1].fingerprint, fixture.expected[1].fingerprint, 'equal-version content change is visible');
  assert.deepEqual((await db.query('select public.todo_task_fingerprints_v1() as result')).rows[0].result.map(r => r.bucket), ['a1', 'f2']);
  await db.exec('rollback;');
  // Null and empty string must not collide.
  await db.exec('begin;');
  await db.query(`update public.tasks set notes = '' where id = $1`, [fixture.rows[0].id]);
  assert.notEqual((await v2())[0].fingerprint, fixture.expected[0].fingerprint, 'empty notes differ from null');
  await db.exec('rollback;');
  assert.ok(!JSON.stringify(both).includes('Synthetic'), 'no content leaves the server');
  await db.exec(`select set_config('request.jwt.claim.sub','${other}',false)`);
  assert.deepEqual(await v2(), [], 'v2 isolates account metadata');
  console.log('Task fingerprints v2: shared fixture, overview v2, equal-version content change, null/empty distinction, privileges and RLS passed.');
} finally { await db.close(); }
