import { Injectable } from '@nestjs/common';

export interface ApiInfo {
  name: string;
  version: string;
}

@Injectable()
export class AppService {
  getInfo(): ApiInfo {
    return { name: 'FitFlow API', version: '0.1.0' };
  }
}
