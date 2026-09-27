import { IsString, Length } from 'class-validator';

export class RefreshTokenDto {
  /** Refresh token from the last sign-in or refresh (base64url, 43 chars). */
  @IsString()
  @Length(43, 43)
  refreshToken: string;
}
