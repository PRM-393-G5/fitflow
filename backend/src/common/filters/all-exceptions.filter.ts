import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { Error as MongooseError, mongo } from 'mongoose';

/** Shape of every error response the API sends. */
export interface ErrorBody {
  statusCode: number;
  error: string;
  message: string | string[];
  path: string;
  timestamp: string;
}

interface Resolved {
  statusCode: number;
  message: string | string[];
  /** Overrides the reason phrase (HttpException `{error}`). */
  error?: string;
  /** Unexpected failure: log it with its stack. */
  unexpected?: boolean;
}

/** `NOT_FOUND` → `Not Found`, matching Nest's built-in reason phrases. */
export function reasonPhrase(statusCode: number): string {
  const name = HttpStatus[statusCode] as string | undefined;
  if (!name) return 'Error';
  return name
    .toLowerCase()
    .split('_')
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(' ');
}

/**
 * Turns any thrown error into an [ErrorBody]. Known database errors map to
 * client errors (duplicate key → 409, bad id / schema violation → 400)
 * without echoing model internals; errors that carry a 4xx status (e.g.
 * malformed JSON from the body parser) keep it; anything else is logged
 * and reported as a bare 500.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const http = host.switchToHttp();
    const request = http.getRequest<Request>();
    const response = http.getResponse<Response>();

    const resolved = this.resolve(exception);
    if (resolved.unexpected) {
      this.logger.error(
        `${request.method} ${request.originalUrl}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }
    // Part of the response already went out; all we can do is end it.
    if (response.headersSent) {
      response.end();
      return;
    }

    const body: ErrorBody = {
      statusCode: resolved.statusCode,
      error: resolved.error ?? reasonPhrase(resolved.statusCode),
      message: resolved.message,
      path: request.originalUrl,
      timestamp: new Date().toISOString(),
    };
    response.status(resolved.statusCode).json(body);
  }

  private resolve(exception: unknown): Resolved {
    if (exception instanceof HttpException) {
      const res = exception.getResponse();
      if (typeof res === 'object' && res !== null) {
        const { message, error } = res as {
          message?: string | string[];
          error?: string;
        };
        return {
          statusCode: exception.getStatus(),
          message: message ?? exception.message,
          error,
        };
      }
      return { statusCode: exception.getStatus(), message: exception.message };
    }
    if (
      exception instanceof mongo.MongoServerError &&
      exception.code === 11000
    ) {
      return { statusCode: HttpStatus.CONFLICT, message: 'Duplicate key' };
    }
    if (exception instanceof MongooseError.CastError) {
      return {
        statusCode: HttpStatus.BAD_REQUEST,
        message: `Invalid value for ${exception.path}`,
      };
    }
    if (exception instanceof MongooseError.ValidationError) {
      return {
        statusCode: HttpStatus.BAD_REQUEST,
        message: Object.keys(exception.errors).map(
          (path) => `${path} is invalid`,
        ),
      };
    }
    const status = clientErrorStatus(exception);
    if (status !== undefined) {
      return { statusCode: status, message: reasonPhrase(status) };
    }
    return {
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
      unexpected: true,
    };
  }
}

/** 4xx status set by Express middleware errors (body-parser and friends). */
function clientErrorStatus(exception: unknown): number | undefined {
  if (typeof exception !== 'object' || exception === null) return undefined;
  const { status, statusCode } = exception as {
    status?: unknown;
    statusCode?: unknown;
  };
  const code = typeof status === 'number' ? status : statusCode;
  return typeof code === 'number' && code >= 400 && code < 500
    ? code
    : undefined;
}
