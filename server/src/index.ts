import Fastify from 'fastify';
import { createRuntime } from './runtime.js';
import { readConfig } from './config.js';

const config = readConfig();
const app = await createRuntime(config, Fastify);
if (!config.VERCEL) {
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => { void app.close(); });
  }
}
// Finish module evaluation so Vercel's listener adapter can finish bootstrapping.
void app.listen({ host: config.VERCEL ? '0.0.0.0' : config.HOST, port: config.PORT }).then(() => {
  console.log('microplanner API started');
}).catch(async () => {
  console.error('API startup failed. Check the server configuration.');
  await app.close();
  process.exitCode = 1;
});
