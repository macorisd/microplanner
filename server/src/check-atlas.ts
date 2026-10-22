import { MongoClient } from 'mongodb';
import { configureDns, readConfig } from './config.js';
import { randomUUID } from 'node:crypto';

let client: MongoClient | undefined;
try {
  const config = readConfig();
  configureDns(config);
  client = new MongoClient(config.MONGODB_URI, { serverSelectionTimeoutMS: 10000 });
  await client.connect();
  await client.db(config.MONGODB_DB).command({ ping: 1 });
  console.log('Atlas: authenticated connection and database ping succeeded.');
  if (process.argv.includes('--write')) {
    // Use only a fresh verification collection; never touch application records.
    const collection = client.db(config.MONGODB_DB).collection(`__microplanner_verify_${randomUUID().replaceAll('-', '')}`);
    await collection.createIndex({ probe: 1 }, { unique: true });
    try {
      const rollback = new Error('intentional rollback');
      try {
        await client.withSession(session => session.withTransaction(async () => {
          await collection.insertOne({ probe: 'rolled_back' }, { session });
          throw rollback;
        }));
      } catch (error) { if (error !== rollback) throw error; }
      if (await collection.countDocuments({}) !== 0) throw new Error('Rollback failed');
      await client.withSession(session => session.withTransaction(async () => {
        await collection.insertOne({ probe: 'committed' }, { session });
      }));
      if (!await collection.findOne({ probe: 'committed' })) throw new Error('Commit failed');
      console.log('Atlas: database write, transaction commit and rollback succeeded.');
    } finally {
      await collection.drop();
      console.log('Atlas: temporary verification collection removed.');
    }
  }
} catch (error) {
  console.error('Atlas: connection failed. Check credentials, network and the IP access list.');
  if (error instanceof Error) {
    const code = (error as Error & { code?: string | number }).code;
    console.error(`Category: ${error.name}; code: ${typeof code === 'string' || typeof code === 'number' ? code : 'not provided'}`);
  }
  process.exitCode = 1;
} finally {
  await client?.close();
}
