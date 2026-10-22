import { MongoClient } from 'mongodb';
import { buildApp } from './app.js';
import { configureDns, readConfig } from './config.js';
import { Repository } from './repository.js';

let client: MongoClient | undefined;
try {
  const config = readConfig();
  configureDns(config);
  client = new MongoClient(config.MONGODB_URI, { serverSelectionTimeoutMS: 10000 });
  await client.connect();
  const repo = new Repository(client, config.MONGODB_DB);
  await repo.initialize();
  const app = await buildApp(repo, config);
  app.addHook('onClose', async () => { await client?.close(); });
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => { void app.close(); });
  }
  await app.listen({ host: config.HOST, port: config.PORT });
  console.log(`MicroPlanner API listening on ${config.HOST}:${config.PORT}`);
} catch {
  console.error('API startup failed. Check server.env, Atlas credentials, network access and MongoDB availability. No credentials were logged.');
  await client?.close();
  process.exitCode = 1;
}
