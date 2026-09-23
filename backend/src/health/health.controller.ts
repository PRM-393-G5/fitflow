import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { InjectConnection } from '@nestjs/mongoose';
import type { Connection } from 'mongoose';

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
      await db.admin().ping();
    } catch {
      throw new ServiceUnavailableException('Database unreachable');
    }
    return { status: 'ok', database: 'up' };
  }
}
