'use client';
import { useAppDispatch, useAppSelector } from "@/store";
import { useEffect, useMemo, useRef, useState } from "react";
import { decodeToken, isExpired as isTokenExpired } from "react-jwt";
import LoginPage from "./LoginPage";
import { invalidateToken, useRefreshTokenMutation } from "@/services/auth";
import { useRouter } from "next/navigation";
import { appPath } from "@/lib/app-path";

interface DecodedToken {
    exp?: number;
    iat?: number;
    sub?: string;
    [key: string]: unknown;
}

export default function AuthWrapper({ children }: { children: React.ReactNode }) {
    const access_token = useAppSelector(state => state.auth.access_token);
    const refresh_token = useAppSelector(state => state.auth.refresh_token);
    const isRefreshingRef = useRef(false);

    return <TokenValidator access_token={access_token} refresh_token={refresh_token} isRefreshingRef={isRefreshingRef}>{children}</TokenValidator>;
}

function TokenValidator({ children, access_token, refresh_token, isRefreshingRef }: { children: React.ReactNode, access_token: string | null, refresh_token: string | null, isRefreshingRef: React.MutableRefObject<boolean> }) {

    const router = useRouter();
    // Decode synchronously (react-jwt's `useJwt` hook decodes in its own
    // internal effect, which lags one render behind a freshly-set
    // `access_token` — that lag let `isAuthenticated` stay `false` for one
    // render right after sign-in, which could flash the login page back in
    // under an already-changed URL). Decoding directly here keeps
    // `isAuthenticated` in sync with `access_token` in the same render.
    const decodedToken = useMemo<DecodedToken | null>(() => {
        if (!access_token) return null;
        return decodeToken<DecodedToken>(access_token);
    }, [access_token]);
    const isExpired = useMemo(() => {
        return access_token ? isTokenExpired(access_token) : true;
    }, [access_token]);
    const [refreshToken] = useRefreshTokenMutation();
    // `ssoAuthenticated` starts `null` (not yet known) so we never render
    // LoginPage on a false negative while the very first session check is
    // still in flight — only an explicit `false` result does that.
    const [ssoAuthenticated, setSsoAuthenticated] = useState<boolean | null>(null);

    const isAuthenticated = useMemo(() => {
        return Boolean(decodedToken) && !isExpired;
    }, [decodedToken, isExpired]);

    const dispatch = useAppDispatch();

    // Check the HTTP-only SSO session cookie once per app load. SSO tokens
    // remain server-side; device-code tokens continue to use Redux.
    useEffect(() => {
        if (isAuthenticated) return;
        let cancelled = false;

        fetch(appPath("/auth/session"), { cache: "no-store" })
            .then((response) => response.json())
            .then((data: { authenticated?: boolean }) => {
                if (!cancelled) setSsoAuthenticated(Boolean(data.authenticated));
            })
            .catch(() => {
                if (!cancelled) setSsoAuthenticated(false);
            });

        return () => { cancelled = true; };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        const checkExpiration = async () => {
            if (!decodedToken) return;

            const exp = decodedToken.exp;
            if (!exp) return;

            const currentTime = Date.now() / 1000;
            const tokenIsExpired = exp < currentTime;
            const timeUntilExpiry = exp - currentTime;

            // Refresh token if it expires in less than 1 minute (60 seconds)
            if (!tokenIsExpired && timeUntilExpiry < 60 && refresh_token && !isRefreshingRef.current) {
                isRefreshingRef.current = true;
                try {
                    await refreshToken({ refresh_token }).unwrap();
                } catch (error) {
                    console.error('Failed to refresh token:', error);
                    dispatch(invalidateToken());
                    router.replace(appPath('/'));
                } finally {
                    isRefreshingRef.current = false;
                }
            } else if (tokenIsExpired) {
                dispatch(invalidateToken());
                router.replace(appPath('/'));
            }
        };

        const interval = setInterval(checkExpiration, 60000);
        return () => clearInterval(interval);
    }, [dispatch, decodedToken, refresh_token, refreshToken, router, isRefreshingRef])

    if (isAuthenticated || ssoAuthenticated) return children;
    // Still waiting on the one-time session check — render nothing rather
    // than flashing the login page for a valid session.
    if (ssoAuthenticated === null) return null;
    return <LoginPage />;
}
