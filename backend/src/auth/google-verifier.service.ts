import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { EnvironmentVariables, splitList } from '../config/env.validation.js';
import type { GoogleProfile } from '../users/users.service.js';

/**
 * Verifies Google ID tokens sent by the app after Google Sign-In: checks
 * the signature against Google's keys, expiry, issuer and that the
 * audience is one of GOOGLE_CLIENT_IDS. Only verified emails are accepted.
 */
@Injectable()
export class GoogleVerifier {
  private readonly audience: string[];

  constructor(
    config: ConfigService<EnvironmentVariables, true>,
    private readonly client: OAuth2Client,
  ) {
    this.audience = splitList(config.get('GOOGLE_CLIENT_IDS', { infer: true }));
  }

  /** The Google identity in [idToken]; 401 when it does not verify. */
  async verify(idToken: string): Promise<GoogleProfile> {
    let payload;
    try {
      const ticket = await this.client.verifyIdToken({
        idToken,
        audience: this.audience,
      });
      payload = ticket.getPayload();
    } catch {
      throw new UnauthorizedException('Invalid Google ID token');
    }
    if (!payload?.sub || !payload.email || payload.email_verified !== true) {
      throw new UnauthorizedException('Google account email is not verified');
    }
    return {
      sub: payload.sub,
      email: payload.email,
      name: payload.name,
      photoUrl: payload.picture,
    };
  }
}
