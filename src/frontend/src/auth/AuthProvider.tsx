import { Button, Field, Input, Spinner } from '@fluentui/react-components';
import { useEffect, useState, type ReactNode } from 'react';
import { clearAntiforgeryToken, getAntiforgeryToken } from '../lib/api';
import { AuthContext, type AppUser } from './AuthContext';
import './AuthProvider.css';

const baseUrl = import.meta.env.VITE_API_URL ?? '';

export default function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'signedOut' | 'error'>('loading');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    let cancelled = false;

    async function loadSession() {
      try {
        const response = await fetch(`${baseUrl}/api/auth/session`, {
          credentials: 'include',
        });
        if (cancelled) return;
        if (response.status === 401) {
          setStatus('signedOut');
          return;
        }
        if (!response.ok) throw new Error('The authentication service is unavailable.');
        setUser(await response.json() as AppUser);
        setStatus('ready');
      } catch (authenticationError) {
        if (cancelled) return;
        setError(authenticationError instanceof Error ? authenticationError.message : 'Authentication failed.');
        setStatus('error');
      }
    }

    void loadSession();
    return () => { cancelled = true; };
  }, []);

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError('');
    const data = new FormData(event.currentTarget);

    try {
      const token = await getAntiforgeryToken();
      const response = await fetch(`${baseUrl}/api/auth/login`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': token },
        body: JSON.stringify({ email: data.get('email'), password: data.get('password') }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null) as { message?: string } | null;
        throw new Error(body?.message ?? 'Sign in failed.');
      }
      clearAntiforgeryToken();
      setUser(await response.json() as AppUser);
      setStatus('ready');
    } catch (authenticationError) {
      setError(authenticationError instanceof Error ? authenticationError.message : 'Sign in failed.');
    } finally {
      setSubmitting(false);
    }
  }

  if (status === 'loading') {
    return <div className="auth-state"><Spinner label="Checking your session" /></div>;
  }

  if (status === 'error') {
    return (
      <div className="auth-state">
        <div className="auth-panel">
          <h1>Sign-in unavailable</h1>
          <p>{error}</p>
          <Button appearance="primary" onClick={() => window.location.reload()}>Try again</Button>
        </div>
      </div>
    );
  }

  if (status === 'signedOut') {
    return (
      <div className="auth-state">
        <div className="auth-panel">
          <div className="auth-mark">DB</div>
          <h1>DB Migration Assist</h1>
          <p>Sign in to open the assessment workspace.</p>
          <form className="auth-form" onSubmit={event => void signIn(event)}>
            <Field label="Email" required>
              <Input name="email" type="email" autoComplete="username" required autoFocus />
            </Field>
            <Field label="Password" required>
              <Input name="password" type="password" autoComplete="current-password" required />
            </Field>
            {error && <div className="auth-error" role="alert">{error}</div>}
            <Button appearance="primary" type="submit" disabled={submitting}>
              {submitting ? 'Signing in...' : 'Sign in'}
            </Button>
          </form>
        </div>
      </div>
    );
  }

  if (!user) return null;

  return (
    <AuthContext.Provider value={{
      user,
      signOut: async () => {
        const token = await getAntiforgeryToken();
        await fetch(`${baseUrl}/api/auth/logout`, {
          method: 'POST',
          credentials: 'include',
          headers: { 'X-CSRF-TOKEN': token },
        });
        clearAntiforgeryToken();
        setUser(null);
        setStatus('signedOut');
      },
    }}>
      {children}
    </AuthContext.Provider>
  );
}