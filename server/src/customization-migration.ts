import { createHash } from 'node:crypto';
import { type WorkspaceData } from './domain.js';

const academic = [
  { name: 'Homework', icon: 'book' },
  { name: 'Test', icon: 'quiz' },
  { name: 'Presentation', icon: 'presentation' },
  { name: 'Project', icon: 'folder' },
  { name: 'Reading', icon: 'reading' },
  { name: 'Other', icon: 'more' },
];

const initialLists = [
  { id: 'default-academic', name: 'Academic tasks', types: academic },
  { id: 'default-software', name: 'Software development', types: [
    { name: 'Feature', icon: 'code' }, { name: 'Bug', icon: 'bug' },
    { name: 'Refactor', icon: 'build' }, { name: 'Testing', icon: 'test' },
    { name: 'Documentation', icon: 'document' }, { name: 'Review', icon: 'search' },
  ] },
  { id: 'default-work', name: 'Work', types: [
    { name: 'Meeting', icon: 'meeting' }, { name: 'Report', icon: 'document' },
    { name: 'Research', icon: 'search' }, { name: 'Planning', icon: 'calendar' },
    { name: 'Follow-up', icon: 'check' }, { name: 'Other', icon: 'more' },
  ] },
  { id: 'default-personal', name: 'Personal life', types: [
    { name: 'Errand', icon: 'shopping' }, { name: 'Appointment', icon: 'calendar' },
    { name: 'Household', icon: 'home' }, { name: 'Health', icon: 'health' },
    { name: 'Finance', icon: 'money' }, { name: 'Other', icon: 'more' },
  ] },
  { id: 'default-creative', name: 'Creative projects', types: [
    { name: 'Idea', icon: 'idea' }, { name: 'Research', icon: 'search' },
    { name: 'Draft', icon: 'edit' }, { name: 'Design', icon: 'art' },
    { name: 'Review', icon: 'search' }, { name: 'Finalize', icon: 'check' },
  ] },
];

/** Stable across independent upgrades on different devices, including long IDs. */
export function legacyTypeId(boardId: string, index: number) {
  return `bt-${createHash('sha256').update(`${boardId}:${index}`).digest('hex')}`;
}

/** Upgrade a legacy snapshot in memory; callers persist it atomically. */
export function upgradeWorkspace(data: WorkspaceData): WorkspaceData {
  if (data.schemaVersion === 2) return data;
  const orders = new Map<string, number>();
  return {
    schemaVersion: 2,
    boards: data.boards.map(board => ({ ...board, icon: 'board', color: 0xff7986cb })),
    subjects: data.subjects.map(subject => {
      const order = orders.get(subject.boardId) ?? 0;
      orders.set(subject.boardId, order + 1);
      return { ...subject, sortOrder: order };
    }),
    tasks: data.tasks.map(task => ({
      ...task,
      typeId: task.typeIndex === 0 ? null : legacyTypeId(task.boardId, task.typeIndex),
    })),
    boardTypes: data.boards.flatMap(board => academic.map((type, index) => ({
      ...type, id: legacyTypeId(board.id, index + 1), boardId: board.id, sortOrder: index,
    }))),
    typeLists: initialLists.map(list => ({
      ...list, types: list.types.map(type => ({ ...type })),
    })),
  };
}
