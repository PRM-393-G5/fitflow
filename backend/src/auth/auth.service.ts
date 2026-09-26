import { Injectable } from '@nestjs/common';
import { UserProfile, UsersService } from '../users/users.service.js';
import { GoogleVerifier } from './google-verifier.service.js';

export interface SignInResult {
  user: UserProfile;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly google: GoogleVerifier,
    private readonly users: UsersService,
  ) {}

  /** Verifies the Google ID token and finds or creates the account. */
  async signInWithGoogle(idToken: string): Promise<SignInResult> {
    const profile = await this.google.verify(idToken);
    const user = await this.users.upsertFromGoogle(profile);
    return { user: UsersService.toProfile(user) };
  }
}
