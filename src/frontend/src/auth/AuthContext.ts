import { createContext, useContext } from 'react';
import type { AccountInfo } from '@azure/msal-browser';

export interface AuthContextValue {
  account: AccountInfo | null;
  authenticationEnabled: boolean;
  signOut: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextValue | null>(null);

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used inside AuthProvider.');
  return context;
}