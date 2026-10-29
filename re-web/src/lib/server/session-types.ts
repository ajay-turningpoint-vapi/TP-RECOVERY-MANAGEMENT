export type PublicUser = {
  id: string;
  username: string;
  role: string;
  fullName: string;
  designation?: string | null;
  branch?: string | null;
};
