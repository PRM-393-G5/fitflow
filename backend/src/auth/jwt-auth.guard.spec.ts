import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { JwtAuthGuard } from './jwt-auth.guard.js';

const jwt = new JwtService({
  secret: 'unit-test-secret-unit-test-secret',
  signOptions: { expiresIn: 60 },
});

function contextWith(authorization?: string) {
  const request: Record<string, unknown> = {
    headers: authorization ? { authorization } : {},
  };
  const context = {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { context, request };
}

describe('JwtAuthGuard', () => {
  const guard = new JwtAuthGuard(jwt);

  it('attaches the caller for a valid bearer token', async () => {
    const token = await jwt.signAsync({ sub: 'user-1' });
    const { context, request } = contextWith(`Bearer ${token}`);
    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.user).toEqual({ userId: 'user-1' });
  });

  it.each([undefined, 'Basic abc', 'Bearer', 'Bearer not-a-jwt'])(
    'rejects authorization header %s',
    async (header) => {
      await expect(
        guard.canActivate(contextWith(header).context),
      ).rejects.toBeInstanceOf(UnauthorizedException);
    },
  );

  it('rejects a token signed with another secret', async () => {
    const forged = await new JwtService({
      secret: 'another-secret-another-secret-xx',
    }).signAsync({ sub: 'user-1' });
    await expect(
      guard.canActivate(contextWith(`Bearer ${forged}`).context),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an expired token', async () => {
    const expired = await jwt.signAsync({ sub: 'user-1' }, { expiresIn: -1 });
    await expect(
      guard.canActivate(contextWith(`Bearer ${expired}`).context),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
