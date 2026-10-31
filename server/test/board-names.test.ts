import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertBoardNames, type WorkspaceData } from '../src/domain.js';

const data = (name: string): WorkspaceData => ({
  boards: [{ id: 'board', name, sortOrder: 0, createdAt: '2026-01-01T00:00:00Z' }],
  subjects: [], tasks: [],
});
test('board names accept 50 units and reject new or renamed names over the limit', () => {
  assert.doesNotThrow(() => assertBoardNames(data('a'.repeat(50))));
  assert.throws(() => assertBoardNames(data('a'.repeat(51))), /at most 50/);
  assert.throws(() => assertBoardNames(data('b'.repeat(51)), data('a'.repeat(51))), /at most 50/);
  assert.doesNotThrow(() => assertBoardNames(data('a'.repeat(100)), data('a'.repeat(100))));
  assert.doesNotThrow(() => assertBoardNames(data('Shorter'), data('a'.repeat(100))));
  assert.throws(() => assertBoardNames(data('\u{1f600}'.repeat(26))), /at most 50/);
});
