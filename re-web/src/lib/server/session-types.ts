export type PublicUser = {
  id: string;
  username: string;
  role: string;
  fullName: string;
  designation?: string | null;
  branch?: string | null;
  /** This browser's own session version, read from its access token (see session.ts). */
  sessionVersion?: number | null;
};
