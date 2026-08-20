'use client';
import { useAppDispatch, useAppSelector } from "@/store";
import { useEffect, useMemo, useRef } from "react";
import { useJwt } from "react-jwt";
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
    const { decodedToken, isExpired } = useJwt<DecodedToken>(access_token ?? '');
    const [refreshToken] = useRefreshTokenMutation();

    const isAuthenticated = useMemo(() => {
        return decodedToken && !isExpired;
    }, [decodedToken, isExpired]);

    const dispatch = useAppDispatch();

    useEffect(() => {
        const checkExpiration = async () => {
            if (!decodedToken) return;

            const exp = decodedToken.exp;
            if (!exp) return;

            const currentTime = Date.now() / 1000;
            const tokenIsExpired = exp < currentTime;
            const timeUntilExpiry = exp - currentTime;

            console.log('Checking token expiry...', {
                tokenIsExpired,
                exp,
                currentTime,
                timeUntilExpiry,
                isRefreshing: isRefreshingRef.current
            });

            // Refresh token if it expires in less than 1 minute (60 seconds)
            if (!tokenIsExpired && timeUntilExpiry < 60 && refresh_token && !isRefreshingRef.current) {
                isRefreshingRef.current = true;
                console.log('Refreshing token...');
                try {
                    await refreshToken({ refresh_token }).unwrap();
                    console.log('Token refreshed successfully');
                } catch (error) {
                    console.error('Failed to refresh token:', error);
                    dispatch(invalidateToken());
                    router.replace(appPath('/'));
                } finally {
                    isRefreshingRef.current = false;
                }
            } else if (tokenIsExpired) {
                console.log('Token expired, logging out');
                dispatch(invalidateToken());
                router.replace(appPath('/'));
            }
        };

        const interval = setInterval(checkExpiration, 60000);
        return () => clearInterval(interval);
    }, [dispatch, decodedToken, refresh_token, refreshToken, router, isRefreshingRef])

    return (
        isAuthenticated ? children : <LoginPage />
    )
}
