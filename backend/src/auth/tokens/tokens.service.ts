import {
  Injectable,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectModel } from '@nestjs/mongoose';
import { createHash, randomBytes } from 'node:crypto';
import { Model, Types } from 'mongoose';
import { EnvironmentVariables } from '../../config/env.validation.js';
import { RefreshToken } from './refresh-token.schema.js';

export interface TokenPair {
  accessToken: string;
  /** Seconds until [accessToken] expires. */
  expiresIn: number;
  refreshToken: string;
}

/** Claims carried by an access token. */
export interface AccessTokenPayload {
  sub: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Access tokens are short-lived HS256 JWTs. Refresh tokens are opaque
 * random strings, stored hashed, single-use: each refresh consumes the
 * presented token and issues a new pair (rotation).
 */
@Injectable()
export class TokensService implements OnModuleInit {
  private readonly accessTtl: number;
  private readonly refreshTtlMs: number;

  constructor(
    private readonly jwt: JwtService,
    @InjectModel(RefreshToken.name)
    private readonly refreshTokens: Model<RefreshToken>,
    config: ConfigService<EnvironmentVariables, true>,
  ) {
    this.accessTtl = config.get('ACCESS_TOKEN_TTL_SECONDS', { infer: true });
    this.refreshTtlMs =
      config.get('REFRESH_TOKEN_TTL_DAYS', { infer: true }) * DAY_MS;
  }

  /** The unique-hash and TTL indexes must exist before tokens are issued. */
  async onModuleInit() {
    await this.refreshTokens.createIndexes();
  }

  async issue(userId: string): Promise<TokenPair> {
    const payload: AccessTokenPayload = { sub: userId };
    const accessToken = await this.jwt.signAsync(payload);
    const refreshToken = randomBytes(32).toString('base64url');
    await this.refreshTokens.create({
      userId: new Types.ObjectId(userId),
      tokenHash: hash(refreshToken),
      expiresAt: new Date(Date.now() + this.refreshTtlMs),
    });
    return { accessToken, expiresIn: this.accessTtl, refreshToken };
  }

  /**
   * Consumes [refreshToken] and issues a new pair. Atomic: when the same
   * token is presented twice concurrently only one call succeeds.
   */
  async rotate(refreshToken: string): Promise<TokenPair> {
    const consumed = await this.refreshTokens
      .findOneAndDelete({
        tokenHash: hash(refreshToken),
        // The TTL monitor runs about once a minute; don't honour a token
        // that has expired but not been swept yet.
        expiresAt: { $gt: new Date() },
      })
      .exec();
    if (!consumed) {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
    return this.issue(consumed.userId.toString());
  }

  /** Ends the session of [refreshToken]; unknown tokens are ignored. */
  async revoke(refreshToken: string): Promise<void> {
    await this.refreshTokens
      .deleteOne({ tokenHash: hash(refreshToken) })
      .exec();
  }

  /** Ends every session of [userId] (account deletion). */
  async revokeAll(userId: string): Promise<void> {
    await this.refreshTokens
      .deleteMany({ userId: new Types.ObjectId(userId) })
      .exec();
  }
}

function hash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
