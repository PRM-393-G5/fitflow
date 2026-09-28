import {
  Injectable,
  Logger,
  OnModuleInit,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectModel } from '@nestjs/mongoose';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { Model, Types } from 'mongoose';
import { EnvironmentVariables } from '../../config/env.validation.js';
import { UsersService } from '../../users/users.service.js';
import { RefreshToken } from './refresh-token.schema.js';

export interface TokenPair {
  accessToken: string;
  /** Seconds until [accessToken] expires. */
  expiresIn: number;
  refreshToken: string;
}

/** Claims carried by an access token (plus `iss`/`aud`/`exp`). */
export interface AccessTokenPayload {
  sub: string;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * A used refresh token presented again within this window is treated as a
 * client retry (e.g. two refreshes fired at once), not theft.
 */
export const REUSE_GRACE_MS = 10_000;

/**
 * Access tokens are short-lived HS256 JWTs. Refresh tokens are opaque
 * random strings, stored hashed and single-use: each refresh marks the
 * presented token used and issues a new pair in the same session. A used
 * token presented again after [REUSE_GRACE_MS] means it was copied, so the
 * whole session is revoked.
 */
@Injectable()
export class TokensService implements OnModuleInit {
  private readonly logger = new Logger(TokensService.name);
  private readonly accessTtl: number;
  private readonly refreshTtlMs: number;

  constructor(
    private readonly jwt: JwtService,
    @InjectModel(RefreshToken.name)
    private readonly refreshTokens: Model<RefreshToken>,
    private readonly users: UsersService,
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

  /** Opens a new session for [userId]. */
  issue(userId: string): Promise<TokenPair> {
    return this.issueInSession(userId, randomUUID());
  }

  /**
   * Spends [refreshToken] and issues the next pair of its session.
   * Claiming the token is atomic, so of two concurrent calls with the same
   * token only one succeeds.
   */
  async rotate(refreshToken: string): Promise<TokenPair> {
    const tokenHash = hash(refreshToken);
    const now = new Date();
    const claimed = await this.refreshTokens
      .findOneAndUpdate(
        // The TTL monitor runs about once a minute; don't honour a token
        // that has expired but not been swept yet.
        { tokenHash, usedAt: null, expiresAt: { $gt: now } },
        { $set: { usedAt: now } },
      )
      .exec();
    if (!claimed) {
      await this.handleUnusable(tokenHash);
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const userId = claimed.userId.toString();
    if (!(await this.users.findById(userId))) {
      await this.revokeAll(userId);
      throw new UnauthorizedException('Account no longer exists');
    }
    try {
      return await this.issueInSession(userId, claimed.sessionId);
    } catch (error) {
      // Give the token back so a transient failure doesn't end the session.
      await this.refreshTokens
        .updateOne({ _id: claimed._id }, { $set: { usedAt: null } })
        .exec();
      throw error;
    }
  }

  /** Ends the session [refreshToken] belongs to; unknown tokens are ignored. */
  async revoke(refreshToken: string): Promise<void> {
    const token = await this.refreshTokens
      .findOne({ tokenHash: hash(refreshToken) })
      .exec();
    if (token) await this.revokeSession(token.sessionId);
  }

  /** Ends every session of [userId] (account deletion). */
  async revokeAll(userId: string): Promise<void> {
    await this.refreshTokens
      .deleteMany({ userId: new Types.ObjectId(userId) })
      .exec();
  }

  private async issueInSession(
    userId: string,
    sessionId: string,
  ): Promise<TokenPair> {
    const payload: AccessTokenPayload = { sub: userId };
    const accessToken = await this.jwt.signAsync(payload);
    const refreshToken = randomBytes(32).toString('base64url');
    await this.refreshTokens.create({
      userId: new Types.ObjectId(userId),
      sessionId,
      tokenHash: hash(refreshToken),
      expiresAt: new Date(Date.now() + this.refreshTtlMs),
    });
    return { accessToken, expiresIn: this.accessTtl, refreshToken };
  }

  /** A used token replayed after the grace window revokes its session. */
  private async handleUnusable(tokenHash: string): Promise<void> {
    const token = await this.refreshTokens.findOne({ tokenHash }).exec();
    if (!token?.usedAt) return;
    if (Date.now() - token.usedAt.getTime() <= REUSE_GRACE_MS) return;
    this.logger.warn(
      `Refresh token reuse for user ${token.userId.toString()}; revoking session`,
    );
    await this.revokeSession(token.sessionId);
  }

  private async revokeSession(sessionId: string): Promise<void> {
    await this.refreshTokens.deleteMany({ sessionId }).exec();
  }
}

function hash(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
