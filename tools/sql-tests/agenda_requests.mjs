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
  await db.exec(await readFile(new URL('../../supabase/migrations/202610050001_agenda_requests.sql', import.meta.url), 'utf8'));

  const table = 'public.agenda_requests';
  for (const privilege of ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) {
    assert.equal((await db.query('select has_table_privilege($1, $2, $3) as ok', ['anon', table, privilege])).rows[0].ok,
      false, `anon cannot ${privilege}`);
  }
  assert.equal((await db.query("select has_table_privilege('authenticated', $1, 'TRUNCATE') as ok", [table])).rows[0].ok, false);
  for (const column of ['status', 'user_id', 'error', 'completed_at', 'claimed_at']) {
    for (const privilege of ['INSERT', 'UPDATE']) {
      assert.equal((await db.query('select has_column_privilege($1, $2, $3, $4) as ok',
        ['authenticated', table, column, privilege])).rows[0].ok, false, `${privilege} ${column}`);
    }
  }
  for (const fn of ['public.claim_agenda_requests_v1(integer)', 'public.complete_agenda_request_v1(uuid, boolean, text)']) {
    assert.equal((await db.query("select has_function_privilege('anon', $1, 'EXECUTE') as ok", [fn])).rows[0].ok, false);
    assert.equal((await db.query("select has_function_privilege('authenticated', $1, 'EXECUTE') as ok", [fn])).rows[0].ok, true);
  }

  const a = '00000000-0000-4000-8000-0000000000a1';
  const b = '00000000-0000-4000-8000-0000000000b2';
  await db.exec(`insert into auth.users values ('${a}'), ('${b}'); set role authenticated;`);
  const as = (user) => db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  const queue = (kind, key, payload) => db.query(
    `insert into ${table}(kind, instance_key, payload) values ($1, $2, $3::jsonb) returning id, status, user_id`,
    [kind, key, JSON.stringify(payload)]);
  const claim = () => db.query('select id, kind, status from public.claim_agenda_requests_v1(20) order by created_at');
  const complete = (id, ok, message) => db.query('select public.complete_agenda_request_v1($1, $2, $3) as ok', [id, ok, message]);

  await as(a);
  const created = (await queue('create', null, {title: 'Visita', calendar: 'c1'})).rows[0];
  assert.equal(created.status, 'pending');
  assert.equal(created.user_id, a);
  const moved = (await queue('update', '42@1760000000000', {title: 'Spostata'})).rows[0];
  // kind and instance_key must agree.
  await assert.rejects(queue('create', 'x', {}));
  await assert.rejects(queue('delete', null, {}));
  await assert.rejects(queue('rename', 'x', {}));
  // The browser cannot mark its own request done.
  await assert.rejects(db.query(`update ${table} set status = 'done' where id = $1`, [created.id]));
  await assert.rejects(db.query(`insert into ${table}(kind, payload, status) values ('create', '{}', 'done')`));

  // Pending requests can be edited and withdrawn.
  await db.query(`update ${table} set payload = '{"title":"Visita 2"}' where id = $1`, [created.id]);

  // Another user sees nothing and claims nothing.
  await as(b);
  assert.equal((await db.query(`select count(*)::int as n from ${table}`)).rows[0].n, 0);
  assert.equal((await claim()).rows.length, 0);
  assert.equal((await complete(created.id, true, null)).rows[0].ok, false);

  // The phone claims each request exactly once.
  await as(a);
  const first = (await claim()).rows;
  assert.deepEqual(first.map((r) => r.status), ['processing', 'processing']);
  assert.equal((await claim()).rows.length, 0);
  // Claimed requests are frozen for the browser.
  const frozen = await db.query(`update ${table} set payload = '{}' where id = $1 returning id`, [created.id]);
  assert.equal(frozen.rows.length, 0);
  const kept = await db.query(`delete from ${table} where id = $1 returning id`, [created.id]);
  assert.equal(kept.rows.length, 0);

  assert.equal((await complete(created.id, true, null)).rows[0].ok, true);
  assert.equal((await complete(created.id, true, null)).rows[0].ok, false, 'second completion ignored');
  assert.equal((await complete(moved.id, false, 'Evento non più sul telefono')).rows[0].ok, true);
  const states = (await db.query(`select status, error from ${table} order by created_at`)).rows;
  assert.deepEqual(states, [{status: 'done', error: null}, {status: 'failed', error: 'Evento non più sul telefono'}]);
  // Closed requests can be dismissed.
  assert.equal((await db.query(`delete from ${table} where id = $1 returning id`, [moved.id])).rows.length, 1);

  // A request stuck in processing is closed as unknown, never repeated.
  const stuck = (await queue('delete', '7', {})).rows[0];
  await claim();
  await db.exec('reset role');
  await db.query(`update ${table} set claimed_at = now() - interval '31 minutes' where id = $1`, [stuck.id]);
  await db.exec('set role authenticated');
  assert.equal((await claim()).rows.length, 0);
  const closed = (await db.query(`select status, error from ${table} where id = $1`, [stuck.id])).rows[0];
  assert.equal(closed.status, 'failed');
  assert.match(closed.error, /Esito sconosciuto/);

  // Old closed requests are forgotten at the next claim.
  await db.exec('reset role');
  await db.query(`update ${table} set completed_at = now() - interval '15 days'`);
  await db.exec('set role authenticated');
  await claim();
  assert.equal((await db.query(`select count(*)::int as n from ${table}`)).rows[0].n, 0);

  // At most 100 open requests.
  await db.exec('reset role');
  await db.query(`insert into ${table}(user_id, kind, payload) select $1, 'create', '{}' from generate_series(1, 100)`, [a]);
  await db.exec('set role authenticated');
  await assert.rejects(queue('create', null, {}), /too many/);

  // Oversized payloads are refused.
  await as(b);
  await assert.rejects(queue('create', null, {title: 'x'.repeat(9000)}));

  // Without a user the RPCs refuse.
  await db.query("select set_config('request.jwt.claim.sub', '', false)");
  await assert.rejects(claim(), /not authenticated/);
  console.log('Agenda requests SQL: OK');
} finally {
  await db.close();
}
