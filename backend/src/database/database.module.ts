import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { EnvironmentVariables } from '../config/env.validation.js';

/** Single MongoDB connection for the app, configured from MONGODB_URI. */
@Module({
  imports: [
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<EnvironmentVariables, true>) => ({
        uri: config.get('MONGODB_URI', { infer: true }),
        // While Mongo is down, fail queries within 5 s instead of queueing
        // them (Mongoose buffering) or waiting on the driver indefinitely.
        bufferCommands: false,
        serverSelectionTimeoutMS: 5000,
        // Give up at startup after ~10 s rather than the default 9 retries.
        retryAttempts: 1,
        retryDelay: 1000,
      }),
    }),
  ],
})
export class DatabaseModule {}
