import { z } from 'zod';

const id = z.string().min(1).max(150).regex(/^[\w-]+$/);
const date = z.iso.datetime({ offset: true });
const name = z.string().trim().min(1).max(300);
export const boardSchema = z.object({
  id, name, createdAt: date, sortOrder: z.number().int().min(0),
  icon: z.string().min(1).max(50).optional(),
  color: z.number().int().min(0).max(0xffffffff).optional(),
}).strict();
export const subjectSchema = z.object({
  id, name, boardId: id, color: z.number().int().min(0).max(0xffffffff),
  sortOrder: z.number().int().min(0).optional(),
}).strict();
export const taskSchema = z.object({
  id, name, deadline: date, createdAt: date, boardId: id,
  subjectId: id.nullable(), description: z.string().max(20000).nullable(),
  typeIndex: z.number().int().min(0).max(6),
  priorityIndex: z.number().int().min(0).max(2),
  isCompleted: z.boolean(),
  typeId: id.nullable().optional(),
  reminderMinutes: z.number().int().min(0).max(10080).nullable().optional(),
}).strict();
const icon = z.string().min(1).max(50).regex(/^[a-z][a-z0-9_]*$/);
const boardTypeSchema = z.object({
  id, boardId: id, name, icon, sortOrder: z.number().int().min(0),
}).strict();
const typeListSchema = z.object({
  id, name: z.string().trim().min(1).max(50),
  types: z.array(z.object({ name: z.string().trim().min(1).max(50), icon }).strict()).max(25),
}).strict();
export const dataSchema = z.object({
  boards: z.array(boardSchema).min(1).max(300),
  subjects: z.array(subjectSchema).max(3000),
  tasks: z.array(taskSchema).max(10000),
  schemaVersion: z.literal(2).optional(),
  boardTypes: z.array(boardTypeSchema).max(7500).optional(),
  typeLists: z.array(typeListSchema).max(300).optional(),
  notificationPreferences: z.object({
    advanceMinutes: z.number().int().min(1).max(10080),
    atDeadline: z.boolean(),
  }).strict().optional(),
}).strict().superRefine((data, ctx) => {
  for (const kind of ['boards', 'subjects', 'tasks'] as const) {
    if (new Set(data[kind].map(item => item.id)).size !== data[kind].length) {
      ctx.addIssue({ code: 'custom', message: `Duplicate ${kind} identifiers` });
    }
  }
  const boards = new Set(data.boards.map(b => b.id));
  const subjects = new Map(data.subjects.map(s => [s.id, s.boardId]));
  if (data.subjects.some(s => !boards.has(s.boardId)) ||
      data.tasks.some(t => !boards.has(t.boardId) ||
        (t.subjectId !== null && subjects.get(t.subjectId) !== t.boardId))) {
    ctx.addIssue({ code: 'custom', message: 'Invalid board or subject relationship' });
  }
  const version2 = data.schemaVersion === 2;
  if (!version2) {
    if (data.boardTypes !== undefined || data.typeLists !== undefined ||
        data.boards.some(b => b.icon !== undefined || b.color !== undefined) ||
        data.subjects.some(s => s.sortOrder !== undefined) ||
        data.tasks.some(t => t.typeId !== undefined)) {
      ctx.addIssue({ code: 'custom', message: 'Customization requires schema version 2' });
    }
    return;
  }
  if (!data.boardTypes || !data.typeLists ||
      data.boards.some(b => b.icon === undefined || b.color === undefined) ||
      data.subjects.some(s => s.sortOrder === undefined) ||
      data.tasks.some(t => t.typeId === undefined)) {
    ctx.addIssue({ code: 'custom', message: 'Incomplete customization data' });
    return;
  }
  for (const [kind, rows] of [['board types', data.boardTypes], ['type lists', data.typeLists]] as const) {
    if (new Set(rows.map(row => row.id)).size !== rows.length) {
      ctx.addIssue({ code: 'custom', message: `Duplicate ${kind} identifiers` });
    }
  }
  const boardTypes = new Map(data.boardTypes.map(t => [t.id, t.boardId]));
  if (data.boardTypes.some(t => !boards.has(t.boardId)) ||
      data.tasks.some(t => t.typeId !== null && boardTypes.get(t.typeId!) !== t.boardId)) {
    ctx.addIssue({ code: 'custom', message: 'Invalid board or type relationship' });
  }
  const typeCounts = new Map<string, number>();
  for (const type of data.boardTypes) typeCounts.set(type.boardId, (typeCounts.get(type.boardId) ?? 0) + 1);
  if ([...typeCounts.values()].some(count => count > 25)) {
    ctx.addIssue({ code: 'custom', message: 'A board can have at most 25 task types' });
  }
});
export const saveSchema = z.object({
  revision: z.number().int().min(0), operationId: z.uuid(), data: dataSchema,
}).strict();
export const importSchema = saveSchema.extend({ sourceId: z.uuid() });
export type WorkspaceData = z.infer<typeof dataSchema>;
export type Workspace = WorkspaceData & { revision: number };
export type Profile = { id: string; email: string; displayName: string; photoUrl: string | null };

// Leave headroom for the transport envelope below Vercel's 4.5 MB payload limit.
export const MAX_WORKSPACE_BYTES = 4_000_000;
export function assertWorkspaceSize(workspace: Workspace) {
  if (Buffer.byteLength(JSON.stringify(workspace)) > MAX_WORKSPACE_BYTES) {
    throw new ApiError(413, 'too_large', 'The workspace is too large. Reduce its size before saving.');
  }
}

export class ApiError extends Error {
  constructor(public statusCode: number, public code: string, message: string) { super(message); }
}

// Existing longer names remain readable; only creating/renaming is restricted.
export function assertBoardNames(data: WorkspaceData, previous?: Pick<WorkspaceData, 'boards'>) {
  const old = new Map(previous?.boards.map(board => [board.id, board.name]));
  if (data.boards.some(board => board.name.length > 50 && old.get(board.id) !== board.name)) {
    throw new ApiError(400, 'invalid_board_name', 'Board names must use at most 50 characters.');
  }
}

/** Name uniqueness is scoped to the account, board or reusable type list.
 * Keep legacy collisions usable only for the same entries and normalized names. */
export function assertUniqueNames(data: WorkspaceData, previous?: WorkspaceData) {
  type Row = readonly [scope: string, id: string, name: string];
  const counts = (rows: Row[]) => {
    const result = new Map<string, number>();
    for (const [scope, , name] of rows) {
      const key = JSON.stringify([scope, name.trim().toLowerCase()]);
      result.set(key, (result.get(key) ?? 0) + 1);
    }
    return result;
  };
  const check = (rows: Row[], oldRows: Row[], kind: string) => {
    const old = counts(oldRows);
    const oldEntries = new Set(oldRows.map(([scope, id, name]) => JSON.stringify([scope, id, name.trim().toLowerCase()])));
    const introduced = new Set(rows.filter(([scope, id, name]) =>
      !oldEntries.has(JSON.stringify([scope, id, name.trim().toLowerCase()])))
      .map(([scope, , name]) => JSON.stringify([scope, name.trim().toLowerCase()])));
    for (const [key, count] of counts(rows)) {
      if (count > 1 && (count > (old.get(key) ?? 0) || introduced.has(key))) {
        throw new ApiError(400, 'duplicate_name', `A ${kind} with this name already exists.`);
      }
    }
  };
  check(data.boards.map(b => ['', b.id, b.name]), previous?.boards.map(b => ['', b.id, b.name]) ?? [], 'board');
  check(data.subjects.map(s => [s.boardId, s.id, s.name]), previous?.subjects.map(s => [s.boardId, s.id, s.name]) ?? [], 'subject');
  check((data.boardTypes ?? []).map(t => [t.boardId, t.id, t.name]),
    (previous?.boardTypes ?? []).map(t => [t.boardId, t.id, t.name]), 'task type');
  check((data.typeLists ?? []).flatMap(l => l.types.map(t => [l.id, t.name.trim().toLowerCase(), t.name] as const)),
    (previous?.typeLists ?? []).flatMap(l => l.types.map(t => [l.id, t.name.trim().toLowerCase(), t.name] as const)), 'task type');
}

/** Grandfather existing long names and over-limit subject lists without loss. */
export function assertCustomizationChanges(data: WorkspaceData, previous: WorkspaceData, importing = false) {
  if (data.schemaVersion !== 2) return;
  const oldNames = new Map(previous.subjects.map(subject => [subject.id, subject.name]));
  const oldBoards = new Set(previous.boards.map(board => board.id));
  const oldCounts = new Map<string, number>();
  const newCounts = new Map<string, number>();
  for (const subject of previous.subjects) oldCounts.set(subject.boardId, (oldCounts.get(subject.boardId) ?? 0) + 1);
  for (const subject of data.subjects) {
    const fromImport = importing && !oldBoards.has(subject.boardId);
    if (subject.name.length > 50 && oldNames.get(subject.id) !== subject.name && !fromImport) {
      throw new ApiError(400, 'invalid_subject_name', 'Subject names must use at most 50 characters.');
    }
    newCounts.set(subject.boardId, (newCounts.get(subject.boardId) ?? 0) + 1);
  }
  for (const [boardId, count] of newCounts) {
    if (!(importing && !oldBoards.has(boardId)) && count > Math.max(25, oldCounts.get(boardId) ?? 0)) {
      throw new ApiError(400, 'too_many_subjects', 'A board can have at most 25 subjects.');
    }
  }
  const oldTypes = new Map((previous.boardTypes ?? []).map(type => [type.id, type.name]));
  if ((data.boardTypes ?? []).some(type => type.name.length > 50 && oldTypes.get(type.id) !== type.name)) {
    throw new ApiError(400, 'invalid_type_name', 'Task type names must use at most 50 characters.');
  }
}
