import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// Synthetic data only: no real calendar content.
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
    grant usage on schema public to authenticated, anon;
  `);
  await db.exec(await readFile(new URL('../../supabase/migrations/202610050002_agenda_backup.sql', import.meta.url), 'utf8'));

  for (const role of ['anon', 'authenticated']) {
    for (const privilege of ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) {
      assert.equal((await db.query('select has_table_privilege($1, $2, $3) as ok',
        [role, 'public.agenda_backups', privilege])).rows[0].ok, false, `${role} cannot ${privilege}`);
    }
    assert.equal((await db.query("select has_function_privilege($1, 'public.save_agenda_backup_v1(jsonb,text,text)', 'EXECUTE') as ok",
      [role])).rows[0].ok, role === 'authenticated', `${role} RPC execute`);
  }
  assert.equal((await db.query("select has_table_privilege('anon','public.agenda_backups','SELECT') as ok")).rows[0].ok, false);

  const a = '00000000-0000-4000-8000-0000000000a1';
  const b = '00000000-0000-4000-8000-0000000000b2';
  await db.exec(`insert into auth.users values ('${a}'), ('${b}'); set role authenticated;`);
  const as = (user) => db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  const save = async (events, hash, base) => (await db.query(
    'select public.save_agenda_backup_v1($1::jsonb, $2, $3) as status',
    [JSON.stringify({device_id: 'phone', events}), hash, base])).rows[0].status;
  const stored = async () => (await db.query('select hash, payload from public.agenda_backups')).rows;

  await as(a);
  assert.equal(await save([{title: 'Uno'}], 'h1', null), 'saved');
  assert.equal(await save([{title: 'Uno'}], 'h1', null), 'unchanged');
  // The phone that wrote h1 moves it forward.
  assert.equal(await save([{title: 'Uno'}, {title: 'Due'}], 'h2', 'h1'), 'saved');
  // A new empty phone (no base) and an old phone (stale base) cannot
  // overwrite it.
  assert.equal(await save([], 'h0', null), 'conflict');
  assert.equal(await save([{title: 'Vecchio'}], 'h9', 'h1'), 'conflict');
  assert.equal((await stored())[0].hash, 'h2');
  assert.equal((await stored())[0].payload.events.length, 2);

  // Each user sees only their own backup.
  await as(b);
  assert.equal((await stored()).length, 0);
  assert.equal(await save([{title: 'B'}], 'hb', null), 'saved');
  await as(a);
  assert.deepEqual((await stored()).map((r) => r.hash), ['h2']);

  // Direct writes are refused even for the owner.
  await assert.rejects(db.query(`update public.agenda_backups set hash = 'x'`));
  await assert.rejects(db.query('delete from public.agenda_backups'));
  await assert.rejects(db.query('select public.save_agenda_backup_v1($1::jsonb, $2, null)', ['[]', 'h']), /invalid backup/);

  await db.query("select set_config('request.jwt.claim.sub', '', false)");
  await assert.rejects(save([], 'x', null), /not authenticated/);
  console.log('Agenda backup SQL: OK');
} finally {
  await db.close();
}
