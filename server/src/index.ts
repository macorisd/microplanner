import { createRuntime } from './runtime.js';
import { readConfig } from './config.js';

const config = readConfig();
const app = await createRuntime(config);
if (!config.VERCEL) {
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.once(signal, () => { void app.close(); });
  }
}
try {
  await app.listen({ host: config.VERCEL ? '0.0.0.0' : config.HOST, port: config.PORT });
  console.log('microplanner API started');
} catch {
  console.error('API startup failed. Check the server configuration.');
  await app.close();
  process.exitCode = 1;
}
