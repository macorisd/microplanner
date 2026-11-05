import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertUniqueNames, type WorkspaceData } from '../src/domain.js';
import { upgradeWorkspace } from '../src/customization-migration.js';

const fixture = (): WorkspaceData => upgradeWorkspace({
  boards: [
    { id: 'one', name: 'First', sortOrder: 0, createdAt: '2026-01-01T00:00:00Z' },
    { id: 'two', name: 'Second', sortOrder: 1, createdAt: '2026-01-01T00:00:00Z' },
  ],
  subjects: [
    { id: 'math', name: 'Math', color: 1, boardId: 'one' },
    { id: 'math-two', name: 'Math', color: 2, boardId: 'two' },
  ], tasks: [],
});

test('boards and board-local categories reject normalized duplicate names regardless of appearance', () => {
  const old = fixture();
  assert.doesNotThrow(() => assertUniqueNames(old));
  assert.throws(() => assertUniqueNames({ ...old, boards: old.boards.map(b => ({ ...b, name: ' first ' })) }, old), /board.*already exists/);
  assert.throws(() => assertUniqueNames({ ...old, subjects: [...old.subjects,
    { ...old.subjects[0]!, id: 'duplicate', name: ' MATH ', color: 9 }] }, old), /subject.*already exists/);
  const type = old.boardTypes![0]!;
  assert.throws(() => assertUniqueNames({ ...old, boardTypes: [...old.boardTypes!,
    { ...type, id: 'duplicate-type', name: type.name.toUpperCase(), icon: 'code' }] }, old), /task type.*already exists/);
  const list = old.typeLists![0]!;
  assert.throws(() => assertUniqueNames({ ...old, typeLists: [{ ...list,
    types: [list.types[0]!, { ...list.types[0]!, name: ` ${list.types[0]!.name.toUpperCase()} ` }] }] }, old), /task type.*already exists/);
});

test('legacy collisions allow unrelated edits and cleanup without allowing more duplicates', () => {
  const old = fixture();
  old.subjects.push({ ...old.subjects[0]!, id: 'legacy', name: 'math' });
  assert.doesNotThrow(() => assertUniqueNames(old, old));
  const edited = { ...old, subjects: old.subjects.map(s => ({ ...s, color: 5 })) };
  assert.doesNotThrow(() => assertUniqueNames(edited, old));
  assert.throws(() => assertUniqueNames({ ...old, subjects: old.subjects.map(s =>
    s.id === 'legacy' ? { ...s, id: 'replacement' } : s) }, old), /already exists/);
  assert.throws(() => assertUniqueNames({ ...old, subjects: [...old.subjects,
    { ...old.subjects[0]!, id: 'third' }] }, old), /already exists/);
  assert.doesNotThrow(() => assertUniqueNames({ ...old,
    subjects: old.subjects.filter(s => s.id !== 'legacy') }, old));
});
