import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

/**
 * One refresh token of a session. Only its SHA-256 hash is stored, so a
 * database leak does not hand out sessions. Every token issued by
 * rotation shares the session's `sessionId`; a used token is kept (with
 * `usedAt`) so presenting it again can be detected as theft. Mongo's TTL
 * monitor removes the document once `expiresAt` passes.
 */
@Schema({ timestamps: { createdAt: true, updatedAt: false } })
export class RefreshToken {
  @Prop({ type: Types.ObjectId, required: true, index: true })
  userId: Types.ObjectId;

  @Prop({ required: true, index: true })
  sessionId: string;

  @Prop({ required: true, unique: true })
  tokenHash: string;

  @Prop({ type: Date, default: null })
  usedAt: Date | null;

  @Prop({ required: true, expires: 0 })
  expiresAt: Date;
}

export type RefreshTokenDocument = HydratedDocument<RefreshToken>;

export const RefreshTokenSchema = SchemaFactory.createForClass(RefreshToken);
