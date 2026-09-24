import {
  ArgumentsHost,
  BadRequestException,
  HttpException,
  Logger,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Error as MongooseError, mongo } from 'mongoose';
import { AllExceptionsFilter, reasonPhrase } from './all-exceptions.filter.js';

function run(exception: unknown, headersSent = false) {
  const json = vi.fn();
  const end = vi.fn();
  const status = vi.fn(() => ({ json }));
  const host = {
    switchToHttp: () => ({
      getRequest: () => ({ method: 'GET', originalUrl: '/api/x' }),
      getResponse: () => ({ status, end, headersSent }),
    }),
  } as unknown as ArgumentsHost;
  new AllExceptionsFilter().catch(exception, host);
  return {
    status: status.mock.calls[0]?.[0],
    body: json.mock.calls[0]?.[0],
    end,
  };
}

describe('AllExceptionsFilter', () => {
  let logError: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logError = vi.spyOn(Logger.prototype, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('keeps the status, message and reason phrase of HTTP exceptions', () => {
    const { status, body } = run(new NotFoundException('No such workout'));
    expect(status).toBe(404);
    expect(body).toMatchObject({
      statusCode: 404,
      error: 'Not Found',
      message: 'No such workout',
      path: '/api/x',
    });
  });

  it('passes validation messages through as a list', () => {
    const { body } = run(new BadRequestException(['name should not be empty']));
    expect(body.message).toEqual(['name should not be empty']);
    expect(body.error).toBe('Bad Request');
  });

  it('keeps a custom error field', () => {
    const { body } = run(
      new HttpException({ message: 'x', error: 'TokenExpired' }, 401),
    );
    expect(body.error).toBe('TokenExpired');
  });

  it('does not log intentional 5xx HTTP exceptions', () => {
    expect(run(new ServiceUnavailableException()).status).toBe(503);
    expect(logError).not.toHaveBeenCalled();
  });

  it('maps a Mongo duplicate key error to 409', () => {
    const error = new mongo.MongoServerError({
      message: 'E11000',
      code: 11000,
    });
    expect(run(error).status).toBe(409);
  });

  it('maps a Mongoose cast error to 400 without model internals', () => {
    const error = new MongooseError.CastError('ObjectId', 'abc', '_id');
    const { status, body } = run(error);
    expect(status).toBe(400);
    expect(body.message).toBe('Invalid value for _id');
  });

  it('keeps the 4xx status of middleware errors such as bad JSON', () => {
    const error = Object.assign(new SyntaxError('Unexpected token'), {
      status: 400,
    });
    const { status, body } = run(error);
    expect(status).toBe(400);
    expect(body.message).toBe('Bad Request');
    expect(logError).not.toHaveBeenCalled();
  });

  it('hides unexpected errors behind a logged generic 500', () => {
    const { status, body } = run(new Error('secret connection string'));
    expect(status).toBe(500);
    expect(body.message).toBe('Internal server error');
    expect(logError).toHaveBeenCalledOnce();
  });

  it('only ends the response when headers were already sent', () => {
    const { status, end } = run(new Error('mid-stream'), true);
    expect(status).toBeUndefined();
    expect(end).toHaveBeenCalledOnce();
  });

  it('formats reason phrases like Nest', () => {
    expect(reasonPhrase(422)).toBe('Unprocessable Entity');
    expect(reasonPhrase(999)).toBe('Error');
  });
});
