import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { isValidObjectId, Model, mongo } from 'mongoose';
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
export class UsersService {
  constructor(@InjectModel(User.name) private readonly users: Model<User>) {}

  /**
   * Finds the account for a Google identity, creating it on first sign-in.
   * Name, email and photo are refreshed from Google on every sign-in.
   */
  async upsertFromGoogle(profile: GoogleProfile): Promise<UserDocument> {
    const upsert = () =>
      this.users
        .findOneAndUpdate(
          { googleSub: profile.sub },
          {
            $set: {
              email: profile.email,
              name: profile.name,
              photoUrl: profile.photoUrl,
            },
          },
          { upsert: true, returnDocument: 'after', setDefaultsOnInsert: true },
        )
        .orFail();
    try {
      return await upsert();
    } catch (error) {
      // Two first sign-ins raced to insert; the other one won — update it.
      if (error instanceof mongo.MongoServerError && error.code === 11000) {
        return upsert();
      }
      throw error;
    }
  }

  /** The user with [id], or null when absent or [id] is malformed. */
  async findById(id: string): Promise<UserDocument | null> {
    if (!isValidObjectId(id)) return null;
    return this.users.findById(id).exec();
  }

  /** Deletes the account document; true when it existed. */
  async remove(id: string): Promise<boolean> {
    if (!isValidObjectId(id)) return false;
    const result = await this.users.deleteOne({ _id: id }).exec();
    return result.deletedCount === 1;
  }

  static toProfile(user: UserDocument): UserProfile {
    return {
      id: user.id as string,
      email: user.email,
      name: user.name ?? null,
      photoUrl: user.photoUrl ?? null,
    };
  }
}
