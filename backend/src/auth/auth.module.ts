import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { OAuth2Client } from 'google-auth-library';
import { UsersModule } from '../users/users.module.js';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { GoogleVerifier } from './google-verifier.service.js';
import {
  RefreshToken,
  RefreshTokenSchema,
} from './tokens/refresh-token.schema.js';
import { TokensService } from './tokens/tokens.service.js';

@Module({
  imports: [
    UsersModule,
    MongooseModule.forFeature([
      { name: RefreshToken.name, schema: RefreshTokenSchema },
    ]),
  ],
  controllers: [AuthController],
  providers: [
    { provide: OAuth2Client, useFactory: () => new OAuth2Client() },
    GoogleVerifier,
    TokensService,
    AuthService,
  ],
  exports: [TokensService],
})
export class AuthModule {}
