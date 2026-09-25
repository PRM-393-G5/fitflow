import { Injectable, OnModuleInit } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { isObjectIdOrHexString, Model, mongo } from 'mongoose';
import { User, UserDocument } from './schemas/user.schema.js';

/** Identity fields taken from a verified Google ID token. */
export interface GoogleProfile {
  sub: string;
  email: string;
  name?: string;
  photoUrl?: string;
}

/** What the API exposes about a user. */
export interface UserProfile {
  id: string;
  email: string;
  name: string | null;
  photoUrl: string | null;
}

@Injectable()
export class UsersService implements OnModuleInit {
  constructor(@InjectModel(User.name) private readonly users: Model<User>) {}

  /**
   * Builds the unique googleSub index before the app serves requests —
   * autoIndex runs in the background, and without the index two racing
   * first sign-ins would create duplicate accounts. Fails startup if the
   * index cannot be built (e.g. duplicates already exist).
   */
  async onModuleInit() {
    await this.users.createIndexes();
  }

  /**
   * Finds the account for a Google identity, creating it on first sign-in.
   * Name, email and photo are refreshed from Google on every sign-in.
   */
  async upsertFromGoogle(profile: GoogleProfile): Promise<UserDocument> {
    if (!profile.sub || !profile.email) {
      throw new Error('Google profile needs both sub and email');
    }
    const upsert = () =>
      this.users
        .findOneAndUpdate(
          { googleSub: profile.sub },
          {
            $set: {
              email: profile.email,
              // null (not undefined, which Mongoose drops) so a name or
              // photo removed on Google is cleared here too.
              name: profile.name ?? null,
              photoUrl: profile.photoUrl ?? null,
            },
          },
          {
            upsert: true,
            returnDocument: 'after',
            setDefaultsOnInsert: true,
            runValidators: true,
          },
        )
        .orFail();
    try {
      return await upsert();
    } catch (error) {
      // Two first sign-ins raced to insert; the other one won — update it.
      if (
        error instanceof mongo.MongoServerError &&
        error.code === 11000 &&
        error.keyPattern?.googleSub !== undefined
      ) {
        return upsert();
      }
      throw error;
    }
  }

  /** The user with [id], or null when absent or [id] is malformed. */
  async findById(id: string): Promise<UserDocument | null> {
    if (!isObjectIdOrHexString(id)) return null;
    return this.users.findById(id).exec();
  }

  /** Deletes the account document; true when it existed. */
  async remove(id: string): Promise<boolean> {
    if (!isObjectIdOrHexString(id)) return false;
    const result = await this.users.deleteOne({ _id: id }).exec();
    return result.deletedCount === 1;
  }

  static toProfile(user: UserDocument): UserProfile {
    return {
      id: user.id as string,
      email: user.email,
      name: user.name,
      photoUrl: user.photoUrl,
    };
  }
}
