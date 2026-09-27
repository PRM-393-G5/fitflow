import { plainToInstance } from 'class-transformer';
import {
  IsEnum,
  IsInt,
  IsNotEmpty,
  IsString,
  Max,
  Min,
  validateSync,
} from 'class-validator';

export enum NodeEnv {
  Development = 'development',
  Production = 'production',
  Test = 'test',
}

/** Environment variables the API needs; validated once at startup. */
export class EnvironmentVariables {
  @IsEnum(NodeEnv)
  NODE_ENV: NodeEnv = NodeEnv.Development;

  @IsInt()
  @Min(1)
  @Max(65535)
  PORT: number = 3001;

  @IsString()
  @IsNotEmpty()
  MONGODB_URI: string;

  /**
   * Comma-separated OAuth client IDs accepted as the `aud` of Google ID
   * tokens — the web client ID the app passes as `serverClientId`.
   */
  @IsString()
  @IsNotEmpty()
  GOOGLE_CLIENT_IDS: string;
}

/** Splits a comma-separated variable, dropping blanks. */
export function splitList(value: string): string[] {
  return value
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

/** Fails fast with every invalid variable listed, instead of at first use. */
export function validateEnv(config: Record<string, unknown>) {
  const env = plainToInstance(EnvironmentVariables, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(env);
  if (errors.length > 0) {
    const details = errors
      .flatMap((error) => Object.values(error.constraints ?? {}))
      .join('\n  ');
    throw new Error(`Invalid environment:\n  ${details}`);
  }
  if (splitList(env.GOOGLE_CLIENT_IDS).length === 0) {
    throw new Error(
      'Invalid environment:\n  GOOGLE_CLIENT_IDS must list at least one ID',
    );
  }
  return env;
}
