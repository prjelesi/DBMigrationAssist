import {
  InteractionRequiredAuthError,
  PublicClientApplication,
  type AccountInfo,
} from '@azure/msal-browser';
import { Button, Spinner } from '@fluentui/react-components';
import { useEffect, useState, type ReactNode } from 'react';
import { configureAccessTokenProvider } from '../lib/api';
import { AuthContext } from './AuthContext';
import './AuthProvider.css';

interface RuntimeAuthConfig {
  enabled: boolean;
  tenantId?: string;
  clientId?: string;
  apiScope?: string;
}

export default function AuthProvider({ children }: { children: ReactNode }) {
  const [client, setClient] = useState<PublicClientApplication | null>(null);
  const [config, setConfig] = useState<RuntimeAuthConfig | null>(null);
  const [account, setAccount] = useState<AccountInfo | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'signedOut' | 'error'>('loading');
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;

    async function initializeAuthentication() {
      try {
        const baseUrl = import.meta.env.VITE_API_URL ?? '';
        const response = await fetch(`${baseUrl}/api/auth/config`);
        if (!response.ok) throw new Error('Authentication configuration is unavailable.');

        const runtimeConfig = await response.json() as RuntimeAuthConfig;
        if (cancelled) return;
        setConfig(runtimeConfig);

        if (!runtimeConfig.enabled) {
          configureAccessTokenProvider(null);
          setStatus('ready');
          return;
        }

        if (!runtimeConfig.tenantId || !runtimeConfig.clientId || !runtimeConfig.apiScope) {
          throw new Error('Microsoft Entra authentication is enabled but not fully configured.');
        }

        const msalClient = new PublicClientApplication({
          auth: {
            clientId: runtimeConfig.clientId,
            authority: `https://login.microsoftonline.com/${runtimeConfig.tenantId}`,
            redirectUri: window.location.origin,
            postLogoutRedirectUri: window.location.origin,
          },
          cache: { cacheLocation: 'sessionStorage' },
        });

        await msalClient.initialize();
        const redirectResult = await msalClient.handleRedirectPromise();
        const activeAccount = redirectResult?.account ?? msalClient.getAllAccounts()[0] ?? null;
        if (cancelled) return;

        if (!activeAccount) {
          setClient(msalClient);
          setStatus('signedOut');
          return;
        }

        msalClient.setActiveAccount(activeAccount);
        configureAccessTokenProvider(async () => {
          try {
            const result = await msalClient.acquireTokenSilent({
              account: activeAccount,
              scopes: [runtimeConfig.apiScope!],
            });
            return result.accessToken;
          } catch (tokenError) {
            if (tokenError instanceof InteractionRequiredAuthError) {
              await msalClient.acquireTokenRedirect({ scopes: [runtimeConfig.apiScope!] });
              return null;
            }
            throw tokenError;
          }
        });
        setClient(msalClient);
        setAccount(activeAccount);
        setStatus('ready');
      } catch (authenticationError) {
        if (cancelled) return;
        setError(authenticationError instanceof Error ? authenticationError.message : 'Authentication failed.');
        setStatus('error');
      }
    }

    void initializeAuthentication();
    return () => {
      cancelled = true;
      configureAccessTokenProvider(null);
    };
  }, []);

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
          <p>Sign in with your organization account to open the assessment workspace.</p>
          <Button
            appearance="primary"
            onClick={() => void client?.loginRedirect({ scopes: [config!.apiScope!] })}
          >
            Sign in with Microsoft
          </Button>
        </div>
      </div>
    );
  }

  return (
    <AuthContext.Provider value={{
      account,
      authenticationEnabled: config?.enabled ?? false,
      signOut: async () => {
        configureAccessTokenProvider(null);
        if (client) await client.logoutRedirect({ account: account ?? undefined });
      },
    }}>
      {children}
    </AuthContext.Provider>
  );
}