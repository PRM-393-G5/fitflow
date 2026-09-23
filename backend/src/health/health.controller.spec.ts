import { ServiceUnavailableException } from '@nestjs/common';
import type { Connection } from 'mongoose';
import { HealthController } from './health.controller.js';

function fakeConnection(readyState: number, ping: () => Promise<unknown>) {
  return {
    readyState,
    db: { admin: () => ({ ping }) },
  } as unknown as Connection;
}

describe('HealthController', () => {
  it('reports ok when the database answers a ping', async () => {
    const controller = new HealthController(
      fakeConnection(1, () => Promise.resolve({ ok: 1 })),
    );
    await expect(controller.check()).resolves.toEqual({
      status: 'ok',
      database: 'up',
    });
  });

  it('returns 503 when the ping fails', async () => {
    const controller = new HealthController(
      fakeConnection(1, () => Promise.reject(new Error('down'))),
    );
    await expect(controller.check()).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('returns 503 when the connection is not open', async () => {
    const controller = new HealthController(
      fakeConnection(0, () => Promise.resolve({ ok: 1 })),
    );
    await expect(controller.check()).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
