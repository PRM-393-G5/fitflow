import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Schema as MongooseSchema } from 'mongoose';

/**
 * A FitFlow account, keyed by the Google account's stable `sub` claim.
 * `meta` holds the last-write-wins profile blob the app syncs (profile,
 * schedule, onboarding, weekly goal); `metaUpdatedAt` is its client
 * timestamp in epoch milliseconds (0 = never pushed).
 *
 * `meta` is a Mixed path: Mongoose does not track in-place edits to it, so
 * always write it with an atomic `$set` update, never `user.meta.x = …;
 * user.save()`.
 */
@Schema({ timestamps: true })
export class User {
  @Prop({ required: true, unique: true })
  googleSub: string;

  @Prop({ required: true, lowercase: true, trim: true })
  email: string;

  @Prop({ type: String, default: null })
  name: string | null;

  @Prop({ type: String, default: null })
  photoUrl: string | null;

  @Prop({ type: MongooseSchema.Types.Mixed, default: () => ({}) })
  meta: Record<string, unknown>;

  @Prop({ default: 0 })
  metaUpdatedAt: number;

  createdAt: Date;
  updatedAt: Date;
}

export type UserDocument = HydratedDocument<User>;

export const UserSchema = SchemaFactory.createForClass(User);
