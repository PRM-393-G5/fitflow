import { Injectable } from '@nestjs/common';
import { UserProfile, UsersService } from '../users/users.service.js';
import { GoogleVerifier } from './google-verifier.service.js';
import { TokenPair, TokensService } from './tokens/tokens.service.js';

export interface SignInResult extends TokenPair {
  user: UserProfile;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly google: GoogleVerifier,
    private readonly users: UsersService,
    private readonly tokens: TokensService,
  ) {}

  /**
   * Verifies the Google ID token, finds or creates the account and opens
   * a session (access + refresh token).
   */
  async signInWithGoogle(idToken: string): Promise<SignInResult> {
    const profile = await this.google.verify(idToken);
    const user = await this.users.upsertFromGoogle(profile);
    const tokens = await this.tokens.issue(user.id as string);
    return { ...tokens, user: UsersService.toProfile(user) };
  }

  refresh(refreshToken: string): Promise<TokenPair> {
    return this.tokens.rotate(refreshToken);
  }

  logout(refreshToken: string): Promise<void> {
    return this.tokens.revoke(refreshToken);
  }
}
