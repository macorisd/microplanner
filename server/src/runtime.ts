import { MongoClient } from 'mongodb';
import Fastify from 'fastify';
import { buildApp } from './application.js';
import { configureDns, readConfig, type Config } from './config.js';
import { Repository } from './repository.js';

export async function createRuntime(config: Config = readConfig(), factory = Fastify) {
  configureDns(config);
  const client = new MongoClient(config.MONGODB_URI, {
    maxPoolSize: 5, minPoolSize: 0, maxIdleTimeMS: 60000,
    serverSelectionTimeoutMS: 10000, connectTimeoutMS: 10000, waitQueueTimeoutMS: 5000,
  });
  const repo = new Repository(client, config.MONGODB_DB);
  let ready: Promise<void> | undefined;
  const app = await buildApp(repo, config, { factory, prepare: () => {
    // One initialization per warm instance; failed starts may retry next request.
    ready ??= client.connect().then(() => repo.initialize()).catch(() => {
      ready = undefined;
      throw new Error('Database initialization failed');
    });
    return ready;
  } });
  app.addHook('onClose', async () => { await client.close(); });
  return app;
}
