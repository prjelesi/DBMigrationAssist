import { createContext, useContext } from 'react';

export interface AppUser {
  userId: string;
  email: string;
  displayName: string;
  role: string;
}

export interface AuthContextValue {
  user: AppUser;
  signOut: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside AuthProvider.');
  return context;
}