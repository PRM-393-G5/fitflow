import { IsJWT } from 'class-validator';

export class GoogleSignInDto {
  /** ID token returned by Google Sign-In on the device. */
  @IsJWT()
  idToken: string;
}
