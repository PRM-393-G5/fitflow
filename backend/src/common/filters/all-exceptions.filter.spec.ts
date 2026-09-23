import {
  ArgumentsHost,
  BadRequestException,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { Error as MongooseError, mongo } from 'mongoose';
import { AllExceptionsFilter } from './all-exceptions.filter.js';

function run(exception: unknown) {
  const json = vi.fn();
  const status = vi.fn(() => ({ json }));
  const host = {
    switchToHttp: () => ({
      getRequest: () => ({ method: 'GET', originalUrl: '/api/x' }),
      getResponse: () => ({ status }),
    }),
  } as unknown as ArgumentsHost;
  new AllExceptionsFilter().catch(exception, host);
  return { status: status.mock.calls[0][0], body: json.mock.calls[0][0] };
}

describe('AllExceptionsFilter', () => {
  beforeEach(() => {
    vi.spyOn(Logger.prototype, 'error').mockImplementation(() => {});
  });

  it('keeps the status and message of HTTP exceptions', () => {
    const { status, body } = run(new NotFoundException('No such workout'));
    expect(status).toBe(404);
    expect(body).toMatchObject({
      statusCode: 404,
      error: 'NOT_FOUND',
      message: 'No such workout',
      path: '/api/x',
    });
  });

  it('passes validation messages through as a list', () => {
    const { body } = run(new BadRequestException(['name should not be empty']));
    expect(body.message).toEqual(['name should not be empty']);
  });

  it('maps a Mongo duplicate key error to 409', () => {
    const error = new mongo.MongoServerError({
      message: 'E11000',
      code: 11000,
    });
    expect(run(error).status).toBe(409);
  });

  it('maps a Mongoose cast error to 400', () => {
    const error = new MongooseError.CastError('ObjectId', 'abc', '_id');
    expect(run(error).status).toBe(400);
  });

  it('hides unexpected errors behind a generic 500', () => {
    const { status, body } = run(new Error('secret connection string'));
    expect(status).toBe(500);
    expect(body.message).toBe('Internal server error');
  });
});
