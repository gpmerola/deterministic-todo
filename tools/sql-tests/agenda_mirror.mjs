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
  await db.exec(await readFile(new URL('../../supabase/migrations/202610040001_agenda_mirror.sql', import.meta.url), 'utf8'));

  for (const role of ['anon', 'authenticated']) {
    for (const table of ['public.agenda_events', 'public.agenda_snapshots']) {
      for (const privilege of ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) {
        assert.equal((await db.query('select has_table_privilege($1, $2, $3) as ok',
          [role, table, privilege])).rows[0].ok, false, `${role} cannot ${privilege} ${table}`);
      }
    }
    assert.equal((await db.query("select has_function_privilege($1, 'public.replace_agenda_snapshot_v1(jsonb)', 'EXECUTE') as ok",
      [role])).rows[0].ok, role === 'authenticated', `${role} RPC execute`);
  }
  assert.equal((await db.query("select has_table_privilege('anon','public.agenda_events','SELECT') as ok")).rows[0].ok, false);

  const a = '00000000-0000-4000-8000-0000000000a1';
  const b = '00000000-0000-4000-8000-0000000000b2';
  await db.exec(`insert into auth.users values ('${a}'), ('${b}'); set role authenticated;`);
  const as = (user) => db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  const snapshot = (titles) => JSON.stringify({
    device_id: 'device', zone_label: 'Europe/London · UTC+1',
    window_start: '2026-09-04T00:00:00Z', window_end: '2027-01-02T00:00:00Z',
    calendars: [{key: 'c1', name: 'Personale', color: '#039BE5'}],
    task_links: ['task:t1'],
    events: titles.map((title, i) => ({
      instance_key: `e${i}`, calendar_keys: ['c1'], title,
      starts_at: '2026-10-08T14:30:00Z', ends_at: '2026-10-08T15:30:00Z',
      all_day: false, meeting_provider: 'Teams', meeting_url: 'https://teams.microsoft.com/l/meetup-join/x',
    })).concat([{instance_key: 'allday', calendar_keys: ['c1'], title: 'Congresso',
      starts_at: '2026-11-11T23:00:00Z', ends_at: '2026-11-14T00:00:00Z', all_day: true,
      start_date: '2026-11-12', end_date: '2026-11-14'}]),
  });
  const rpc = (json) => db.query('select public.replace_agenda_snapshot_v1($1::jsonb)', [json]);

  await as(a);
  await rpc(snapshot(['Riunione A1', 'Riunione A2']));
  await as(b);
  await rpc(snapshot(['Riunione B1']));

  // Each user sees only their own rows.
  await as(a);
  const mine = (await db.query('select title from public.agenda_events order by instance_key')).rows.map((r) => r.title);
  assert.deepEqual(mine, ['Congresso', 'Riunione A1', 'Riunione A2']);
  const allDay = (await db.query("select start_date::text, end_date::text from public.agenda_events where instance_key = 'allday'")).rows[0];
  assert.deepEqual(allDay, {start_date: '2026-11-12', end_date: '2026-11-14'});
  assert.equal((await db.query('select count(*)::int as n from public.agenda_snapshots')).rows[0].n, 1);

  // A new snapshot replaces the old one entirely.
  await rpc(snapshot(['Solo questa']));
  assert.deepEqual((await db.query('select title from public.agenda_events order by instance_key')).rows.map((r) => r.title),
    ['Congresso', 'Solo questa']);
  await as(b);
  assert.deepEqual((await db.query('select title from public.agenda_events order by instance_key')).rows.map((r) => r.title),
    ['Congresso', 'Riunione B1']);

  // Direct writes are refused even for the owner.
  await assert.rejects(db.query(`insert into public.agenda_events(user_id, instance_key, calendar_keys, title, starts_at, ends_at)
    values ('${b}', 'x', '[]', 'x', now(), now())`));
  await assert.rejects(db.query('delete from public.agenda_events'));

  // Without a user the RPC refuses.
  await db.query("select set_config('request.jwt.claim.sub', '', false)");
  await assert.rejects(rpc(snapshot(['anon'])), /not authenticated/);
  console.log('Agenda mirror SQL: OK');
} finally {
  await db.close();
}
