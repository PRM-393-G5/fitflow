import {
  Controller,
  Get,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser } from '../auth/current-user.decorator.js';
import { JwtAuthGuard } from '../auth/jwt-auth.guard.js';
import type { AuthUser } from '../auth/jwt-auth.guard.js';
import { UsersService } from './users.service.js';
import type { UserProfile } from './users.service.js';

@Controller('me')
@UseGuards(JwtAuthGuard)
export class MeController {
  constructor(private readonly users: UsersService) {}

  /** Profile of the signed-in user; 401 if the account no longer exists. */
  @Get()
  async profile(@CurrentUser() caller: AuthUser): Promise<UserProfile> {
    const user = await this.users.findById(caller.userId);
    if (!user) throw new UnauthorizedException('Account no longer exists');
    return UsersService.toProfile(user);
  }
}
