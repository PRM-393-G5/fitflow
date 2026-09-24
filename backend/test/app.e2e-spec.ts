import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.setup.js';

describe('App (e2e)', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  afterAll(async () => {
    await app?.close();
  });

  it('GET /api returns the API info', () => {
    return request(app.getHttpServer())
      .get('/api')
      .expect(200)
      .expect({ name: 'FitFlow API', version: '0.1.0' });
  });

  it('GET /api/health reports the database as up', () => {
    return request(app.getHttpServer())
      .get('/api/health')
      .expect(200)
      .expect({ status: 'ok', database: 'up' });
  });

  it('answers malformed JSON with a 400 error body', async () => {
    const res = await request(app.getHttpServer())
      .post('/api')
      .set('Content-Type', 'application/json')
      .send('{bad json')
      .expect(400);
    expect(res.body).toMatchObject({ statusCode: 400, error: 'Bad Request' });
  });

  it('serves nothing outside the /api prefix', () => {
    return request(app.getHttpServer()).get('/').expect(404);
  });

  it('returns the shared error body for unknown routes', async () => {
    const res = await request(app.getHttpServer()).get('/api/nope').expect(404);
    expect(res.body).toMatchObject({
      statusCode: 404,
      error: 'Not Found',
      path: '/api/nope',
    });
  });
});
