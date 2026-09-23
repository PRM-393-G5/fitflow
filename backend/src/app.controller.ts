import { Controller, Get } from '@nestjs/common';
import type { ApiInfo } from './app.service.js';
import { AppService } from './app.service.js';

@Controller()
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get()
  getInfo(): ApiInfo {
    return this.appService.getInfo();
  }
}
