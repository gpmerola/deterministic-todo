import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

// Synthetic data only: no real task content.
const migration = await readFile(
  new URL('../../supabase/migrations/202611190001_todo_cloud_backups.sql', import.meta.url),
  'utf8',
);

// The migration must be additive: nothing existing is dropped or altered,
// apart from enabling RLS on the table it creates itself.
const statements = migration.replace(/--.*$/gm, '').replace(/\$\$[\s\S]*?\$\$/g, '$$$$');
assert.doesNotMatch(statements, /\bdrop\b/i, 'no drop');
assert.doesNotMatch(statements, /\btruncate\s+(table\s+)?public\./i, 'no truncate');
const alters = statements.match(/\balter\s+\w+\s+[\w.]+[^;]*/gi) ?? [];
assert.deepEqual(alters.map((s) => s.replace(/\s+/g, ' ').trim()), [
  'alter table public.todo_cloud_backups enable row level security',
]);

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
  await db.exec(migration);

  const signature = 'public.save_todo_cloud_backup_v1(text,text,text,integer,text)';
  for (const role of ['anon', 'authenticated']) {
    for (const privilege of ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE']) {
      assert.equal((await db.query('select has_table_privilege($1, $2, $3) as ok',
        [role, 'public.todo_cloud_backups', privilege])).rows[0].ok, false, `${role} cannot ${privilege}`);
    }
    assert.equal((await db.query('select has_function_privilege($1, $2, \'EXECUTE\') as ok',
      [role, signature])).rows[0].ok, role === 'authenticated', `${role} RPC execute`);
  }
  assert.equal((await db.query("select has_table_privilege('anon','public.todo_cloud_backups','SELECT') as ok")).rows[0].ok, false);

  const a = '00000000-0000-4000-8000-0000000000a1';
  const b = '00000000-0000-4000-8000-0000000000b2';
  await db.exec(`insert into auth.users values ('${a}'), ('${b}'); set role authenticated;`);
  const as = (user) => db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  const hash = (n) => n.toString(16).padStart(64, '0');
  const save = async (n, {encoding = 'gzip-base64', size = 10, device = 'phone', content = `c${n}`} = {}) =>
    (await db.query('select public.save_todo_cloud_backup_v1($1, $2, $3, $4, $5) as status',
      [content, typeof n === 'string' ? n : hash(n), encoding, size, device])).rows[0].status;
  const hashes = async () => (await db.query(
    'select content_hash from public.todo_cloud_backups order by seq desc')).rows
    .map((r) => r.content_hash);

  await as(a);
  assert.equal(await save(1), 'saved');
  assert.equal(await save(1), 'unchanged', 'same content as the newest copy');
  assert.equal(await save(2), 'saved');
  // A copy equal to an older one (not the newest) is a new state: saved.
  assert.equal(await save(1), 'saved');
  assert.deepEqual(await hashes(), [hash(1), hash(2), hash(1)]);

  // Only the newest 14 copies remain, oldest removed first.
  for (let n = 3; n <= 20; n++) assert.equal(await save(n), 'saved');
  const kept = await hashes();
  assert.equal(kept.length, 14);
  assert.deepEqual(kept, Array.from({length: 14}, (_, i) => hash(20 - i)));

  // Each user sees and prunes only their own copies.
  await as(b);
  assert.deepEqual(await hashes(), []);
  for (let n = 100; n < 116; n++) assert.equal(await save(n), 'saved');
  assert.equal((await hashes()).length, 14);
  await as(a);
  assert.deepEqual(await hashes(), kept, 'b pruning never touches a');

  // Direct writes are refused even for the owner.
  await assert.rejects(db.query(`update public.todo_cloud_backups set device_id = 'x'`));
  await assert.rejects(db.query('delete from public.todo_cloud_backups'));
  await assert.rejects(db.query(
    `insert into public.todo_cloud_backups (user_id, device_id, content_hash, encoding, size_bytes, content)
     values ('${a}', 'x', '${hash(1)}', 'gzip-base64', 1, 'x')`));

  // Malformed input is rejected before anything is written.
  await assert.rejects(save('not-a-hash'), /invalid backup/);
  await assert.rejects(save(30, {encoding: 'json'}), /invalid backup/);
  await assert.rejects(save(31, {size: 0}), /invalid backup/);
  await assert.rejects(save(32, {content: ''}), /invalid backup/);
  await assert.rejects(save(33, {device: 'x'.repeat(129)}), /invalid backup/);
  assert.deepEqual(await hashes(), kept);

  await db.query("select set_config('request.jwt.claim.sub', '', false)");
  await assert.rejects(save(40), /not authenticated/);
  console.log('Todo cloud backups SQL: OK');
} finally {
  await db.close();
}
