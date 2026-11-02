import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertCustomizationChanges, dataSchema, type WorkspaceData } from '../src/domain.js';
import { legacyTypeId, upgradeWorkspace } from '../src/customization-migration.js';

function legacy(): WorkspaceData {
  return {
    boards: [{ id: 'board', name: 'Board', createdAt: '2026-01-01T00:00:00Z', sortOrder: 0 }],
    subjects: [], tasks: [],
  };
}

test('migration is deterministic and validates complete board type relationships', () => {
  const first = upgradeWorkspace(legacy());
  assert.deepEqual(first, upgradeWorkspace(legacy()));
  assert.equal(first.boardTypes![1]!.id, legacyTypeId('board', 2));
  assert.equal(dataSchema.safeParse(first).success, true);
  const invalid = { ...first, tasks: [{ id: 'task', name: 'Task', boardId: 'board', subjectId: null,
    description: null, deadline: '2026-01-01T00:00:00Z', createdAt: '2026-01-01T00:00:00Z',
    typeIndex: 0, typeId: 'missing', priorityIndex: 0, isCompleted: false }] };
  assert.equal(dataSchema.safeParse(invalid).success, false);
});

test('old oversized subject lists and names are preserved but cannot grow or be renamed too long', () => {
  const original = upgradeWorkspace({ ...legacy(), subjects: Array.from({ length: 26 }, (_, i) => ({
    id: `subject-${i}`, boardId: 'board', name: i === 0 ? 'x'.repeat(70) : `Subject ${i}`, color: 0xffabcdef,
  })) });
  assert.doesNotThrow(() => assertCustomizationChanges(original, original));
  const larger = { ...original, subjects: [...original.subjects, {
    id: 'extra', boardId: 'board', name: 'Extra', color: 0xffabcdef, sortOrder: 26,
  }] };
  assert.throws(() => assertCustomizationChanges(larger, original), /25 subjects/);
  const renamed = { ...original, subjects: original.subjects.map((subject, i) =>
    i === 0 ? { ...subject, name: 'y'.repeat(70) } : subject) };
  assert.throws(() => assertCustomizationChanges(renamed, original), /50 characters/);
});
