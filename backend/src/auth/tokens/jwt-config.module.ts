import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { EnvironmentVariables } from '../../config/env.validation.js';

export const ACCESS_TOKEN_ISSUER = 'fitflow-api';
export const ACCESS_TOKEN_AUDIENCE = 'fitflow-app';

/**
 * Access-token signing, available app-wide so any module's routes can use
 * JwtAuthGuard without importing AuthModule.
 */
@Global()
@Module({
  imports: [
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<EnvironmentVariables, true>) => ({
        secret: config.get('JWT_ACCESS_SECRET', { infer: true }),
        signOptions: {
          algorithm: 'HS256',
          expiresIn: config.get('ACCESS_TOKEN_TTL_SECONDS', { infer: true }),
          issuer: ACCESS_TOKEN_ISSUER,
          audience: ACCESS_TOKEN_AUDIENCE,
        },
        // Only our access tokens: same secret alone is not enough.
        verifyOptions: {
          algorithms: ['HS256'],
          issuer: ACCESS_TOKEN_ISSUER,
          audience: ACCESS_TOKEN_AUDIENCE,
        },
      }),
    }),
  ],
  exports: [JwtModule],
})
export class JwtConfigModule {}
