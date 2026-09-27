import { Body, Controller, HttpCode, HttpStatus, Post } from '@nestjs/common';
import { AuthService } from './auth.service.js';
import type { SignInResult } from './auth.service.js';
import { GoogleSignInDto } from './dto/google-sign-in.dto.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('google')
  @HttpCode(HttpStatus.OK)
  signInWithGoogle(@Body() body: GoogleSignInDto): Promise<SignInResult> {
    return this.auth.signInWithGoogle(body.idToken);
  }
}
