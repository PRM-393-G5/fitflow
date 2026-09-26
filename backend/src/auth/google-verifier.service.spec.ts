import { UnauthorizedException } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import type { OAuth2Client, TokenPayload } from 'google-auth-library';
import { GoogleVerifier } from './google-verifier.service.js';

function verifierWith(verifyIdToken: OAuth2Client['verifyIdToken']) {
  const config = {
    get: () => 'web-client, other-client',
  } as unknown as ConfigService;
  return new GoogleVerifier(
    config as never,
    {
      verifyIdToken,
    } as unknown as OAuth2Client,
  );
}

function ticket(payload: Partial<TokenPayload>) {
  return vi.fn().mockResolvedValue({ getPayload: () => payload });
}

describe('GoogleVerifier', () => {
  const verified: Partial<TokenPayload> = {
    sub: 'google-1',
    email: 'a@example.com',
    email_verified: true,
    name: 'A',
    picture: 'https://example.com/a.png',
  };

  it('returns the profile of a valid token, checking every audience', async () => {
    const verify = ticket(verified);
    await expect(verifierWith(verify).verify('token')).resolves.toEqual({
      sub: 'google-1',
      email: 'a@example.com',
      name: 'A',
      photoUrl: 'https://example.com/a.png',
    });
    expect(verify).toHaveBeenCalledWith({
      idToken: 'token',
      audience: ['web-client', 'other-client'],
    });
  });

  it('rejects a token that fails verification with 401', async () => {
    const verify = vi.fn().mockRejectedValue(new Error('Wrong recipient'));
    await expect(verifierWith(verify).verify('bad')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects an unverified email', async () => {
    const verify = ticket({ ...verified, email_verified: false });
    await expect(verifierWith(verify).verify('t')).rejects.toThrow(
      /not verified/,
    );
  });

  it('rejects a token without email', async () => {
    const verify = ticket({ ...verified, email: undefined });
    await expect(verifierWith(verify).verify('t')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
