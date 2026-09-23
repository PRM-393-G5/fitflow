import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { configureApp } from './../src/app.setup.js';

describe('App (e2e)', () => {
  let app: INestApplication<App>;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.init();
  });

  afterEach(async () => {
    await app?.close();
  });

  it('GET /api returns the API info', () => {
    return request(app.getHttpServer())
      .get('/api')
      .expect(200)
      .expect({ name: 'FitFlow API', version: '0.1.0' });
  });

  it('serves nothing outside the /api prefix', () => {
    return request(app.getHttpServer()).get('/').expect(404);
  });
});
