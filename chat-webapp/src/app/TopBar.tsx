'use client';
import { AppBar, IconButton, Toolbar, Typography } from "@mui/material";
import LogoutIcon from '@mui/icons-material/Logout';
import { useAppDispatch } from "@/store";
import { invalidateToken } from "@/services/auth";
import { appPath } from "@/lib/app-path";

interface TopBarProps {
    title: React.ReactNode;
    leftAction?: React.ReactNode;
    rightAction?: React.ReactNode;
}

/**
 * Persistent top navigation bar shown across the authenticated app (collections,
 * agents, and chat session pages) so users can always sign out regardless of
 * where they are in the app.
 */
export default function TopBar({ title, leftAction, rightAction }: TopBarProps) {
    const dispatch = useAppDispatch();

    const signOut = async () => {
        let logoutUrl = appPath('/');
        try {
            const response = await fetch(appPath('/auth/logout'), { method: 'POST', cache: 'no-store' });
            const body = await response.json() as { logoutUrl?: string | null };
            logoutUrl = body.logoutUrl || appPath('/');
        } finally {
            // Clear both Redux and its localStorage persistence before leaving —
            // a full navigation makes AuthWrapper recheck the SSO session cookie.
            localStorage.removeItem('auth');
            dispatch(invalidateToken());
            window.location.assign(logoutUrl);
        }
    };

    return (
        <AppBar>
            <Toolbar>
                {leftAction}
                <Typography sx={{ flexGrow: 1 }}>
                    {title}
                </Typography>
                {rightAction}
                <IconButton size="large" aria-label="Sign out" onClick={signOut}>
                    <LogoutIcon />
                </IconButton>
            </Toolbar>
        </AppBar>
    );
}
