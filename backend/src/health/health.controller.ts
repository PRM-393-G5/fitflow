import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { InjectConnection } from '@nestjs/mongoose';
import type { Connection } from 'mongoose';

/** Longest the database ping may take before the API reports it down. */
export const PING_TIMEOUT_MS = 2000;

export interface HealthStatus {
  status: 'ok';
  database: 'up';
}

/** Liveness + database reachability, for monitoring and the app's checks. */
@Controller('health')
export class HealthController {
  constructor(@InjectConnection() private readonly connection: Connection) {}

  @Get()
  async check(): Promise<HealthStatus> {
    const db = this.connection.db;
    try {
      if (this.connection.readyState !== 1 || !db) throw new Error('closed');
      await withTimeout(db.admin().ping(), PING_TIMEOUT_MS);
    } catch {
      throw new ServiceUnavailableException('Database unreachable');
    }
    return { status: 'ok', database: 'up' };
  }
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error('timeout')), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}
