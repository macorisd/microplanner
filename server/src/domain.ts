import { z } from 'zod';

const id = z.string().min(1).max(150).regex(/^[\w-]+$/);
const date = z.iso.datetime({ offset: true });
const name = z.string().trim().min(1).max(300);
export const boardSchema = z.object({
  id, name, createdAt: date, sortOrder: z.number().int().min(0),
}).strict();
export const subjectSchema = z.object({
  id, name, boardId: id, color: z.number().int().min(0).max(0xffffffff),
}).strict();
export const taskSchema = z.object({
  id, name, deadline: date, createdAt: date, boardId: id,
  subjectId: id.nullable(), description: z.string().max(20000).nullable(),
  typeIndex: z.number().int().min(0).max(6),
  priorityIndex: z.number().int().min(0).max(2),
  isCompleted: z.boolean(),
}).strict();
export const dataSchema = z.object({
  boards: z.array(boardSchema).min(1).max(300),
  subjects: z.array(subjectSchema).max(3000),
  tasks: z.array(taskSchema).max(10000),
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
