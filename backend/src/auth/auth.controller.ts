import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import type { SignInResult } from './auth.service.js';
import { GoogleSignInDto } from './dto/google-sign-in.dto.js';
import { RefreshTokenDto } from './dto/refresh-token.dto.js';
import type { TokenPair } from './tokens/tokens.service.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('google')
  @HttpCode(HttpStatus.OK)
  signInWithGoogle(@Body() body: GoogleSignInDto): Promise<SignInResult> {
    return this.auth.signInWithGoogle(body.idToken);
  }

  /** Exchanges a refresh token for a new pair; the old one stops working. */
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() body: RefreshTokenDto): Promise<TokenPair> {
    return this.auth.refresh(body.refreshToken);
  }

  /** Ends the session of the given refresh token. */
  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  logout(@Body() body: RefreshTokenDto): Promise<void> {
    return this.auth.logout(body.refreshToken);
  }
}
