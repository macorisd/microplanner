import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { MongoClient, type ClientSession, type Collection } from 'mongodb';
import { ApiError, assertBoardNames, assertCustomizationChanges, assertUniqueNames, assertWorkspaceSize, dataSchema, type Profile, type Workspace, type WorkspaceData } from './domain.js';
import { upgradeWorkspace } from './customization-migration.js';

type User = Profile & { _id: string; googleSub: string; revision: number; operations: string[]; workspaceSchemaVersion?: number; notificationPreferences?: WorkspaceData['notificationPreferences']; sessionWrite?: string };
type Session = { _id: string; ownerId: string; expiresAt: Date };
type Owned<T> = T & { _id: string; ownerId: string };
type OperationReceipt = {
  _id: string; ownerId: string; operationId: string; digest: string; committedAt: Date;
};
type Challenge = {
  _id: string; nonce: string; codeChallenge: string; redirectUri: string; expiresAt: Date;
  ownerId?: string; sessionId?: string;
};
type DeletionGrant = { _id: string; ownerId: string; sessionId: string; expiresAt: Date };
const workspaceCollections = ['boards', 'subjects', 'tasks', 'boardTypes', 'typeLists'] as const;
const hash = (value: string) => createHash('sha256').update(value).digest('hex');

export class Repository {
  readonly db;
  private readonly users: Collection<User>;
  private readonly sessions: Collection<Session>;
  private readonly challenges: Collection<Challenge>;
  constructor(readonly client: MongoClient, database: string) {
    this.db = client.db(database);
    this.users = this.db.collection<User>('users');
    this.sessions = this.db.collection<Session>('sessions');
    this.challenges = this.db.collection<Challenge>('oauthChallenges');
  }

  async initialize() {
    await this.users.createIndex({ googleSub: 1 }, { unique: true });
    await this.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    await this.sessions.createIndex({ ownerId: 1 });
    await this.challenges.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    await this.challenges.createIndex({ ownerId: 1 });
    await this.db.collection<DeletionGrant>('deletionGrants').createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    await this.db.collection<DeletionGrant>('deletionGrants').createIndex({ ownerId: 1 });
    await this.db.collection('imports').createIndex({ ownerId: 1 });
    await this.db.collection('requestLimits').createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
    await this.db.collection<OperationReceipt>('operationReceipts')
      .createIndex({ ownerId: 1, operationId: 1 }, { unique: true });
    for (const kind of workspaceCollections) {
      await this.db.collection(kind).createIndex({ ownerId: 1, id: 1 }, { unique: true });
      await this.db.collection(kind).createIndex({ ownerId: 1, boardId: 1 });
    }
  }

  async allowRequest(key: string, max: number, now = Date.now()) {
    // Hash IPs and share fixed-minute counters across cold starts and instances.
    const bucket = Math.floor(now / 60000);
    const collection = this.db.collection<{ _id: string; count: number; expiresAt: Date }>('requestLimits');
    const filter = { _id: `${bucket}:${hash(key)}` };
    const update = { $inc: { count: 1 }, $setOnInsert: { expiresAt: new Date((bucket + 2) * 60000) } };
    let row;
    try {
      row = await collection.findOneAndUpdate(filter, update, { upsert: true, returnDocument: 'after' });
    } catch (error) {
      if (!(error instanceof Error && 'code' in error && error.code === 11000)) throw error;
      row = await collection.findOneAndUpdate(filter, { $inc: { count: 1 } }, { returnDocument: 'after' });
    }
    return row !== null && row.count <= max;
  }

  private collection<K extends 'boards' | 'subjects' | 'tasks' | 'boardTypes' | 'typeLists'>(kind: K) {
    return this.db.collection<Owned<NonNullable<WorkspaceData[K]>[number]>>(kind);
  }

  private profile(user: User): Profile {
    return { id: user.id, email: user.email, displayName: user.displayName, photoUrl: user.photoUrl };
  }

  async login(google: { sub: string; email: string; name?: string; picture?: string }) {
    const observed = await this.users.findOne({ googleSub: google.sub });
    const token = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    const profile = {
      email: google.email, displayName: google.name ?? google.email, photoUrl: google.picture ?? null,
    };
    const issue = (ownerId?: string) => this.client.withSession(session => session.withTransaction(async () => {
      let user: User;
      if (ownerId) {
        const updated = await this.users.findOneAndUpdate(
          { _id: ownerId }, { $set: { ...profile, sessionWrite: hash(token) } },
          { session, returnDocument: 'after' },
        );
        if (!updated) throw new ApiError(409, 'account_changed', 'The account changed. Start sign-in again.');
        user = updated;
      } else {
        const id = randomUUID();
        user = { _id: id, id, googleSub: google.sub, ...profile, revision: 0, operations: [] };
        await this.users.insertOne(user, { session });
        await this.collection('boards').insertOne({
          _id: randomUUID(), ownerId: id, id: 'default-board',
          name: 'Board 1', createdAt: new Date().toISOString(), sortOrder: 0,
        }, { session });
      }
      await this.sessions.insertOne({ _id: hash(token), ownerId: user.id, expiresAt }, { session });
      return { token, expiresAt: expiresAt.toISOString(), user: this.profile(user) };
    }));
    try {
      return await issue(observed?.id);
    } catch (error) {
      if (observed || !(error instanceof Error && 'code' in error && error.code === 11000)) throw error;
      const created = await this.users.findOne({ googleSub: google.sub });
      if (!created) throw new ApiError(409, 'account_changed', 'The account changed. Start sign-in again.');
      return issue(created.id);
    }
  }

  async authenticate(token: string) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
    const session = await this.sessions.findOne({ _id: hash(token), expiresAt: { $gt: new Date() } });
    if (!session) return null;
    const user = await this.users.findOne({ _id: session.ownerId });
    return user ? { user: this.profile(user), expiresAt: session.expiresAt.toISOString() } : null;
  }
  async logout(token: string) { await this.sessions.deleteOne({ _id: hash(token) }); }

  async accountExists(ownerId: string) {
    return (await this.users.findOne(
      { _id: ownerId }, { projection: { _id: 1 }, readConcern: { level: 'majority' } },
    )) !== null;
  }

  // Touch the account in transactions that issue owner-bound state. This serializes
  // them with deletion even when the profile has not changed.
  private async activeSession(ownerId: string, sessionId: string, session: ClientSession) {
    const active = await this.sessions.findOne({
      _id: sessionId, ownerId, expiresAt: { $gt: new Date() },
    }, { session });
    if (!active) throw new ApiError(401, 'unauthorized', 'Your session expired. Please sign in again.');
  }

  async authorizeDeletion(ownerId: string, token: string, subject: string) {
    const grant = randomBytes(32).toString('base64url');
    const sessionId = hash(token);
    await this.client.withSession(session => session.withTransaction(async () => {
      await this.activeSession(ownerId, sessionId, session);
      const user = await this.users.findOneAndUpdate(
        { _id: ownerId, googleSub: subject }, { $set: { sessionWrite: hash(grant) } },
        { session },
      );
      if (!user) throw new ApiError(403, 'account_mismatch', 'Choose the Google account shown in Settings.');
      const grants = this.db.collection<DeletionGrant>('deletionGrants');
      await grants.deleteMany({ ownerId, sessionId }, { session });
      await grants.insertOne({
        _id: hash(grant), ownerId, sessionId, expiresAt: new Date(Date.now() + 5 * 60 * 1000),
      }, { session });
    }));
    return { grant };
  }

  async deleteAccount(ownerId: string, token: string, grant: string) {
    const sessionId = hash(token);
    return this.client.withSession(session => session.withTransaction(async () => {
      await this.activeSession(ownerId, sessionId, session);
      // Serialize even a rejected retry with a previous deletion that might
      // still be committing, so the client can distinguish rollback from loss.
      const account = await this.users.updateOne(
        { _id: ownerId }, { $set: { sessionWrite: randomUUID() } }, { session },
      );
      if (!account.matchedCount) throw new ApiError(401, 'unauthorized', 'Please sign in again.');
      const verified = await this.db.collection<DeletionGrant>('deletionGrants').findOne({
        _id: hash(grant), ownerId, sessionId, expiresAt: { $gt: new Date() },
      }, { session });
      if (!verified) throw new ApiError(403, 'deletion_not_authorized', 'Verify your Google account again to delete it.');
      const { deletedCount } = await this.users.deleteOne({ _id: ownerId }, { session });
      if (deletedCount !== 1) throw new ApiError(401, 'unauthorized', 'Your session expired. Please sign in again.');
      for (const kind of workspaceCollections) {
        await this.collection(kind).deleteMany({ ownerId }, { session });
      }
      for (const name of ['sessions', 'operationReceipts', 'imports', 'oauthChallenges', 'deletionGrants']) {
        await this.db.collection(name).deleteMany({ ownerId }, { session });
      }
      return { status: 'deleted' };
    }, { writeConcern: { w: 'majority' } }));
  }

  async challenge(redirectUri: string, codeChallenge: string, deletion?: { ownerId: string; token: string }) {
    const challenge: Challenge = {
      _id: randomUUID(), nonce: randomBytes(32).toString('base64url'), redirectUri,
      codeChallenge, expiresAt: new Date(Date.now() + 5 * 60 * 1000),
    };
    if (!deletion) {
      await this.challenges.insertOne(challenge);
    } else {
      const { ownerId, token } = deletion;
      const sessionId = hash(token);
      Object.assign(challenge, { ownerId, sessionId });
      await this.client.withSession(session => session.withTransaction(async () => {
        await this.activeSession(ownerId, sessionId, session);
        const result = await this.users.updateOne(
          { _id: ownerId }, { $set: { sessionWrite: challenge._id } }, { session },
        );
        if (!result.matchedCount) throw new ApiError(401, 'unauthorized', 'Please sign in again.');
        await this.challenges.insertOne(challenge, { session });
      }));
    }
    return challenge;
  }

  async consumeChallenge(challengeId: string, verifier: string, deletion?: { ownerId: string; token: string }) {
    const challenge = await this.challenges.findOneAndDelete({
      _id: challengeId, codeChallenge: createHash('sha256').update(verifier).digest('base64url'),
      expiresAt: { $gt: new Date() },
      ...(deletion
        ? { ownerId: deletion.ownerId, sessionId: hash(deletion.token) }
        : { ownerId: { $exists: false } }),
    });
    if (!challenge) throw new ApiError(401, 'invalid_challenge', 'Sign-in expired. Please try again.');
    return challenge;
  }

  private async read(ownerId: string, session: ClientSession): Promise<Workspace> {
    const user = await this.users.findOne({ _id: ownerId }, { session });
    if (!user) throw new ApiError(401, 'unauthorized', 'Please sign in again.');
    const result = { revision: user.revision } as Workspace;
    if (user.notificationPreferences) result.notificationPreferences = user.notificationPreferences;
    // Operations in one transaction must remain sequential (MongoDB driver rule).
    for (const kind of ['boards', 'subjects', 'tasks'] as const) {
      const rows = await this.collection(kind).find({ ownerId }, {
        session, projection: { _id: 0, ownerId: 0 },
      }).toArray();
      Object.assign(result, { [kind]: rows });
    }
    if (user.workspaceSchemaVersion === 2) {
      result.schemaVersion = 2;
      result.boardTypes = await this.collection('boardTypes').find({ ownerId }, {
        session, projection: { _id: 0, ownerId: 0 },
      }).toArray();
      result.typeLists = await this.collection('typeLists').find({ ownerId }, {
        session, projection: { _id: 0, ownerId: 0 },
      }).toArray();
      result.boardTypes.sort((a, b) => a.sortOrder - b.sortOrder || a.id.localeCompare(b.id));
      result.subjects.sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0) || a.id.localeCompare(b.id));
    }
    result.boards.sort((a, b) => a.sortOrder - b.sortOrder || a.createdAt.localeCompare(b.createdAt));
    assertWorkspaceSize(result);
    return result;
  }
  async workspace(ownerId: string) {
    return this.client.withSession(session => session.withTransaction(
      () => this.read(ownerId, session), { readConcern: { level: 'snapshot' } },
    ));
  }

  async save(ownerId: string, revision: number, operationId: string, data: WorkspaceData, sourceId?: string) {
    return this.client.withSession(session => session.withTransaction(async () => {
      const user = await this.users.findOne({ _id: ownerId }, { session });
      if (!user) throw new ApiError(401, 'unauthorized', 'Please sign in again.');
      const receipts = this.db.collection<OperationReceipt>('operationReceipts');
      const receiptId = hash(`${ownerId}:${operationId}`);
      const digest = hash(JSON.stringify({ revision, data, sourceId: sourceId ?? null }));
      const operationReceipt = await receipts.findOne({ _id: receiptId, ownerId }, { session });
      if (operationReceipt) {
        if (operationReceipt.digest !== digest) {
          throw new ApiError(409, 'operation_id_reused', 'This operation identifier was already used.');
        }
        return this.read(ownerId, session);
      }
      if (sourceId) {
        const receipt = await this.db.collection<{ _id: string; ownerId: string }>('imports')
          .findOne({ _id: sourceId }, { session });
        if (receipt?.ownerId === ownerId) return this.read(ownerId, session);
        if (receipt) throw new ApiError(409, 'already_imported', 'These local data were imported to another account.');
      }
      if (user.operations.includes(operationId)) return this.read(ownerId, session);
      if (user.revision !== revision) {
        throw new ApiError(409, 'revision_conflict', 'Another device changed your data. Reload and try again.');
      }
      if (!sourceId && user.workspaceSchemaVersion === 2 && data.schemaVersion !== 2) {
        throw new ApiError(409, 'client_upgrade_required', 'Update microplanner before editing this workspace.');
      }
      let next = data;
      if (sourceId) {
        let existing = await this.read(ownerId, session);
        const imported = user.workspaceSchemaVersion === 2 || data.schemaVersion === 2
          ? upgradeWorkspace(data) : data;
        if (imported.schemaVersion === 2) existing = { ...upgradeWorkspace(existing), revision: existing.revision };
        const boardIds = new Map(imported.boards.map(b => [b.id, randomUUID()]));
        const subjectIds = new Map(imported.subjects.map(s => [s.id, randomUUID()]));
        const typeIds = new Map((imported.boardTypes ?? []).map(t => [t.id, randomUUID()]));
        next = {
          boards: [...existing.boards, ...imported.boards.map((b, i) => ({
            ...b, id: boardIds.get(b.id)!, sortOrder: existing.boards.length + i,
          }))],
          subjects: [...existing.subjects, ...imported.subjects.map(s => ({
            ...s, id: subjectIds.get(s.id)!, boardId: boardIds.get(s.boardId)!,
          }))],
          tasks: [...existing.tasks, ...imported.tasks.map(t => ({
            ...t, id: randomUUID(), boardId: boardIds.get(t.boardId)!,
            subjectId: t.subjectId === null ? null : subjectIds.get(t.subjectId)!,
            ...(imported.schemaVersion === 2 ? { typeId: t.typeId == null ? null : typeIds.get(t.typeId)! } : {}),
          }))],
          ...(imported.schemaVersion === 2 ? {
            schemaVersion: 2 as const,
            boardTypes: [...(existing.boardTypes ?? []), ...(imported.boardTypes ?? []).map(t => ({
              ...t, id: typeIds.get(t.id)!, boardId: boardIds.get(t.boardId)!,
            }))],
            typeLists: existing.typeLists ?? [],
          } : {}),
        };
        // The receipt and all imported entities commit together or not at all.
        await this.db.collection<{ _id: string; ownerId: string }>('imports')
          .insertOne({ _id: sourceId, ownerId }, { session });
      }
      dataSchema.parse(next);
      const previous = await this.read(ownerId, session);
      const savedTasks = new Map(previous.tasks.map(task => [task.id, task]));
      // Omission by an older client preserves new data; null explicitly inherits.
      next = {
        ...next,
        ...(next.notificationPreferences === undefined && previous.notificationPreferences
          ? { notificationPreferences: previous.notificationPreferences } : {}),
        tasks: next.tasks.map(task => {
          const saved = savedTasks.get(task.id);
          return task.reminderMinutes === undefined && saved?.reminderMinutes !== undefined
            ? { ...task, reminderMinutes: saved.reminderMinutes } : task;
        }),
      };
      assertBoardNames(next, previous);
      assertWorkspaceSize({ ...next, revision: revision + 1 });
      assertUniqueNames(next, previous);
      if (next.schemaVersion === 2) {
        assertCustomizationChanges(next, previous, sourceId !== undefined);
      }
      // The receipt and data are committed together, so a delayed retry remains
      // idempotent even after the legacy 50-operation history rolls over.
      await receipts.insertOne({
        _id: receiptId, ownerId, operationId, digest, committedAt: new Date(),
      }, { session });
      const updated = await this.users.updateOne({ _id: ownerId, revision }, {
        $inc: { revision: 1 }, $push: { operations: { $each: [operationId], $slice: -50 } },
        $set: {
          ...(next.schemaVersion === 2 ? { workspaceSchemaVersion: 2 } : {}),
          ...(next.notificationPreferences ? { notificationPreferences: next.notificationPreferences } : {}),
        },
      }, { session });
      if (updated.modifiedCount !== 1) throw new ApiError(409, 'revision_conflict', 'Reload and try again.');
      for (const kind of ['boards', 'subjects', 'tasks'] as const) {
        await this.collection(kind).deleteMany({ ownerId }, { session });
        if (next[kind].length) {
          // A workspace save is atomic and always scoped to the authenticated owner.
          await this.db.collection<{ _id: string; ownerId: string }>(kind).insertMany(next[kind].map(row => ({
            ...row, _id: randomUUID(), ownerId,
          })), { session });
        }
      }
      if (next.schemaVersion === 2) {
        for (const kind of ['boardTypes', 'typeLists'] as const) {
          await this.collection(kind).deleteMany({ ownerId }, { session });
          const rows = next[kind] ?? [];
          if (rows.length) await this.db.collection<{ _id: string; ownerId: string }>(kind).insertMany(
            rows.map(row => ({ ...row, _id: randomUUID(), ownerId })), { session },
          );
        }
      }
      return { ...next, revision: revision + 1 };
    }, { readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' } }));
  }
}
