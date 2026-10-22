import { z } from 'zod';
import dns from 'node:dns';
import { isIP } from 'node:net';

export const windowsClientId = '853649790752-s8t10u7gj5u3b4m8gd0paqhsabshv131.apps.googleusercontent.com';
export const webClientId = '853649790752-vm13udq65n5ul6o3vferd10a8gora651.apps.googleusercontent.com';

const environment = z.object({
  MONGODB_URI: z.string().startsWith('mongodb'),
  MONGODB_DB: z.string().regex(/^[\w-]+$/),
  HOST: z.string().default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1024).max(65535).default(3000),
  GOOGLE_WINDOWS_CLIENT_ID: z.string().default(windowsClientId),
  GOOGLE_WEB_CLIENT_ID: z.string().default(webClientId),
  GOOGLE_WINDOWS_CLIENT_SECRET: z.string().optional(),
  MONGODB_DNS_SERVERS: z.string().refine(value => value.split(',').every(ip => isIP(ip.trim()) > 0)).optional(),
});

export type Config = z.infer<typeof environment>;

export function readConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = environment.safeParse(env);
  if (!parsed.success) {
    // Do not include input values, which may contain database credentials.
    throw new Error(`Invalid environment variables: ${parsed.error.issues.map(i => i.path.join('.')).join(', ')}`);
  }
  return parsed.data;
}

export function configureDns(config: Config) {
  // Process-local override for networks whose default resolver refuses SRV/TXT queries.
  if (config.MONGODB_DNS_SERVERS) dns.setServers(config.MONGODB_DNS_SERVERS.split(',').map(ip => ip.trim()));
}
