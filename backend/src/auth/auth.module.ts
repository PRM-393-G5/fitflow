import { Module } from '@nestjs/common';
import { OAuth2Client } from 'google-auth-library';
import { UsersModule } from '../users/users.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { GoogleVerifier } from './google-verifier.service.js';

@Module({
  imports: [UsersModule],
  controllers: [AuthController],
  providers: [
    { provide: OAuth2Client, useFactory: () => new OAuth2Client() },
    GoogleVerifier,
    AuthService,
  ],
})
export class AuthModule {}
